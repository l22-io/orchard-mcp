import { spawn } from "node:child_process";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { readFile, unlink, access, stat } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { tmpdir } from "node:os";

// Reason: Resolve the Swift binary path relative to this file's location.
// In development and npm package installs, use the signed .app bundle copy.
const __dirname = dirname(fileURLToPath(import.meta.url));

// Emit a one-time warning when binary path overrides are active: these env
// vars grant arbitrary executables the TCC permissions granted to apple-bridge.
let overrideWarned = false;
function warnOverrideOnce(): void {
  if (overrideWarned) return;
  overrideWarned = true;
  if (process.env.APPLE_BRIDGE_BIN) {
    console.error(
      `[orchard-mcp] WARNING: APPLE_BRIDGE_BIN override active ("${process.env.APPLE_BRIDGE_BIN}"). ` +
      `This binary inherits all granted TCC permissions — ensure the path is trusted.`
    );
  }
  if (process.env.APPLE_BRIDGE_APP) {
    console.error(
      `[orchard-mcp] WARNING: APPLE_BRIDGE_APP override active ("${process.env.APPLE_BRIDGE_APP}"). ` +
      `This .app bundle inherits all granted TCC permissions — ensure the path is trusted.`
    );
  }
}

function getBridgePath(): string {
  // Reason: Allow override via env var for custom installations.
  if (process.env.APPLE_BRIDGE_BIN) {
    warnOverrideOnce();
    return process.env.APPLE_BRIDGE_BIN;
  }
  // Default: use the binary inside the .app bundle (one level up from build/)
  return resolve(__dirname, "..", "swift", ".build", "AppleBridge.app", "Contents", "MacOS", "apple-bridge");
}

function getAppBundlePath(): string {
  if (process.env.APPLE_BRIDGE_APP) {
    warnOverrideOnce();
    return process.env.APPLE_BRIDGE_APP;
  }
  return resolve(__dirname, "..", "swift", ".build", "AppleBridge.app");
}

export interface BridgeResponse {
  status: "ok" | "error";
  data?: unknown;
  error?: string;
}

export interface BridgeOptions {
  /**
   * Per-call timeout in milliseconds. Defaults to 30_000.
   * Long-running operations (e.g. mail content searches, large file reads)
   * should pass a larger value. When the timeout fires the entire child
   * process group is killed via SIGTERM (then SIGKILL) — this is required
   * for tools that spawn osascript grandchildren, which would otherwise
   * be orphaned and keep Mail.app / Notes.app wedged on Apple Events.
   */
  timeoutMs?: number;
  /**
   * Maximum stdout/output-file bytes accepted from apple-bridge.
   * Defaults to 10 MiB. Tool families with large native/app responses should
   * lower this through the safety layer so one call cannot monopolize memory
   * or flood the MCP client.
   */
  maxOutputBytes?: number;
}

const DEFAULT_TIMEOUT_MS = 30_000;
const DEFAULT_MAX_OUTPUT_BYTES = 10 * 1024 * 1024;
const SIGKILL_GRACE_MS = 2_000;

/**
 * Execute an apple-bridge subcommand and return parsed JSON.
 * Tries direct execution first; falls back to .app bundle mode
 * (via `open`) when direct execution returns a permission error.
 */
export async function callBridge(
  args: string[],
  opts: BridgeOptions = {}
): Promise<BridgeResponse> {
  const bin = getBridgePath();
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const maxOutputBytes = opts.maxOutputBytes ?? DEFAULT_MAX_OUTPUT_BYTES;
  const direct = await runBridgeProcess(bin, args, timeoutMs, maxOutputBytes);

  if (direct.status === "error" || direct.parsed == null) {
    if (direct.spawnError) {
      return { status: "error", error: direct.spawnError };
    }
    if (direct.timedOut) {
      return {
        status: "error",
        error: `apple-bridge timed out after ${timeoutMs}ms`,
      };
    }
  }

  if (direct.parsed) {
    const parsed = direct.parsed;
    // If the command returned a permission error, retry via .app bundle
    if (
      parsed.status === "error" &&
      typeof parsed.error === "string" &&
      parsed.error.includes("access denied")
    ) {
      return callBridgeViaApp(args, timeoutMs, maxOutputBytes);
    }
    return parsed;
  }

  return { status: "error", error: direct.spawnError ?? "apple-bridge returned no output" };
}

interface DirectResult {
  status: "ok" | "error";
  parsed?: BridgeResponse;
  timedOut?: boolean;
  spawnError?: string;
}

/**
 * Spawn apple-bridge in its own process group so we can SIGTERM the entire
 * group on timeout. Required because Swift's Foundation.Process does not
 * cascade signals to its child osascript processes — without this, a
 * cancelled/timed-out mail search leaves osascript orphaned and Mail.app
 * locked on Apple Events for as long as the script keeps iterating.
 */
function runBridgeProcess(
  bin: string,
  args: string[],
  timeoutMs: number,
  maxOutputBytes: number
): Promise<DirectResult> {
  return new Promise((resolvePromise) => {
    let child;
    try {
      child = spawn(bin, args, {
        detached: true, // own process group; -pid kills the whole tree
        stdio: ["ignore", "pipe", "pipe"],
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Failed to spawn apple-bridge";
      resolvePromise({ status: "error", spawnError: msg });
      return;
    }

    const pid = child.pid;
    if (!pid) {
      resolvePromise({ status: "error", spawnError: "apple-bridge spawn returned no pid" });
      return;
    }

    const chunks: Buffer[] = [];
    const errChunks: Buffer[] = [];
    let totalBytes = 0;
    let settled = false;
    let timedOut = false;
    let killEscalated = false;
    let sigkillTimer: NodeJS.Timeout | null = null;

    const killGroup = (signal: NodeJS.Signals) => {
      try {
        process.kill(-pid, signal);
      } catch {
        // Group may already be gone; nothing to do.
      }
    };

    // Reason: Swift's apple-bridge has no SIGTERM handler and dies on the first
    // signal, which causes Node's "close" event to fire almost immediately.
    // If we cleared sigkillTimer at that point, any osascript grandchild
    // wedged in an Apple Event RPC to Mail.app / Notes.app would be orphaned
    // (PPID=1) and continue to hold Mail.app's event queue hostage. So once
    // we have committed to escalating, the SIGKILL must fire regardless of
    // when the bridge process itself closes.
    const escalateKill = () => {
      if (killEscalated) return;
      killEscalated = true;
      killGroup("SIGTERM");
      sigkillTimer = setTimeout(() => killGroup("SIGKILL"), SIGKILL_GRACE_MS);
      sigkillTimer.unref();
    };

    const settle = (result: DirectResult) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (!killEscalated && sigkillTimer) clearTimeout(sigkillTimer);
      // When escalation is in flight, leave the SIGKILL timer alone so it
      // can reap any grandchildren the bridge spawned (see escalateKill).
      resolvePromise(result);
    };

    const timer = setTimeout(() => {
      timedOut = true;
      escalateKill();
    }, timeoutMs);

    child.stdout?.on("data", (d: Buffer) => {
      totalBytes += d.length;
      if (totalBytes > maxOutputBytes) {
        escalateKill();
        settle({
          status: "error",
          spawnError: `apple-bridge output exceeded ${maxOutputBytes} bytes`,
        });
        return;
      }
      chunks.push(d);
    });

    child.stderr?.on("data", (d: Buffer) => {
      errChunks.push(d);
    });

    child.on("error", (err) => {
      settle({ status: "error", spawnError: err.message });
    });

    child.on("close", () => {
      const stderr = Buffer.concat(errChunks).toString("utf8").trim();
      if (stderr) {
        console.error(`[apple-bridge stderr] ${stderr}`);
      }
      if (timedOut) {
        settle({ status: "error", timedOut: true });
        return;
      }
      const stdout = Buffer.concat(chunks).toString("utf8");
      try {
        const parsed = JSON.parse(stdout) as BridgeResponse;
        settle({ status: "ok", parsed });
      } catch (err) {
        const msg = err instanceof Error ? err.message : "JSON parse failed";
        settle({
          status: "error",
          spawnError: `apple-bridge returned invalid JSON: ${msg}`,
        });
      }
    });
  });
}

/**
 * Launch apple-bridge via .app bundle using `open`, with output written to
 * a temp file. Required on macOS Sequoia where CLI tools cannot obtain
 * TCC permissions (e.g. Reminders) without an .app bundle context.
 */
async function callBridgeViaApp(
  args: string[],
  timeoutMs: number,
  maxOutputBytes: number
): Promise<BridgeResponse> {
  const appPath = getAppBundlePath();
  const outputFile = resolve(tmpdir(), `apple-bridge-${randomUUID()}.json`);

  try {
    // Verify .app bundle exists
    await access(appPath);
  } catch {
    return {
      status: "error",
      error: `AppleBridge.app not found at ${appPath}. Build with: swift build -c release then create the .app bundle.`,
    };
  }

  return new Promise((resolvePromise) => {
    const child = spawn("open", [
      "-W", "-n", "-a", appPath,
      "--args", ...args, "--output", outputFile,
    ]);

    const timeout = setTimeout(() => {
      child.kill();
      void killAppFallbackProcesses(outputFile, "SIGTERM").then(() => {
        setTimeout(() => {
          void killAppFallbackProcesses(outputFile, "SIGKILL");
        }, SIGKILL_GRACE_MS).unref();
      });
      resolvePromise({
        status: "error",
        error: `apple-bridge .app bundle timed out after ${timeoutMs}ms`,
      });
    }, timeoutMs);

    child.on("close", async () => {
      clearTimeout(timeout);
      try {
        const info = await stat(outputFile);
        if (info.size > maxOutputBytes) {
          await unlink(outputFile).catch(() => {});
          resolvePromise({
            status: "error",
            error: `apple-bridge output exceeded ${maxOutputBytes} bytes`,
          });
          return;
        }
        const data = await readFile(outputFile, "utf-8");
        await unlink(outputFile).catch(() => {});
        const parsed = JSON.parse(data) as BridgeResponse;
        resolvePromise(parsed);
      } catch (err) {
        await unlink(outputFile).catch(() => {});
        const msg =
          err instanceof Error
            ? err.message
            : "Failed to read .app bundle output";
        resolvePromise({ status: "error", error: msg });
      }
    });

    child.on("error", (err) => {
      clearTimeout(timeout);
      resolvePromise({
        status: "error",
        error: `Failed to launch .app bundle: ${err.message}`,
      });
    });
  });
}

function killAppFallbackProcesses(
  outputFile: string,
  signal: NodeJS.Signals
): Promise<void> {
  return new Promise((resolvePromise) => {
    const pgrep = spawn("/usr/bin/pgrep", ["-f", outputFile], {
      stdio: ["ignore", "pipe", "ignore"],
    });
    const chunks: Buffer[] = [];
    pgrep.stdout?.on("data", (chunk: Buffer) => chunks.push(chunk));
    pgrep.on("error", () => resolvePromise());
    pgrep.on("close", () => {
      const pids = Buffer.concat(chunks)
        .toString("utf8")
        .split(/\s+/)
        .map((raw) => parseInt(raw, 10))
        .filter((pid) => Number.isFinite(pid) && pid > 0 && pid !== process.pid);

      for (const pid of pids) {
        try {
          process.kill(pid, signal);
        } catch {
          // The fallback app process may have exited between pgrep and kill.
        }
      }
      resolvePromise();
    });
  });
}

/**
 * Convenience: call bridge, check status, return data or throw.
 */
export async function bridgeData(
  args: string[],
  opts?: BridgeOptions
): Promise<unknown> {
  const result = await callBridge(args, opts);
  if (result.status === "error") {
    throw new Error(result.error ?? "apple-bridge returned an error");
  }
  return result.data;
}
