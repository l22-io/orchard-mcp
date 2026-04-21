import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { readFile, unlink, access } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { tmpdir } from "node:os";

const execFileAsync = promisify(execFile);

// Reason: Resolve the Swift binary path relative to this file's location.
// In development: swift/.build/release/apple-bridge
// In npm package: swift/.build/release/apple-bridge (shipped alongside)
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

/**
 * Execute an apple-bridge subcommand and return parsed JSON.
 * Tries direct execution first; falls back to .app bundle mode
 * (via `open`) when direct execution returns a permission error.
 */
export async function callBridge(
  args: string[]
): Promise<BridgeResponse> {
  const bin = getBridgePath();
  try {
    const { stdout, stderr } = await execFileAsync(bin, args, {
      timeout: 30_000,
      maxBuffer: 10 * 1024 * 1024,
    });

    if (stderr) {
      // Reason: stderr is used for Swift warnings/diagnostics, log but don't fail.
      console.error(`[apple-bridge stderr] ${stderr.trim()}`);
    }

    const parsed = JSON.parse(stdout) as BridgeResponse;

    // If the command returned a permission error, retry via .app bundle
    if (
      parsed.status === "error" &&
      typeof parsed.error === "string" &&
      parsed.error.includes("access denied")
    ) {
      return callBridgeViaApp(args);
    }

    return parsed;
  } catch (err: unknown) {
    const msg =
      err instanceof Error ? err.message : "Unknown error calling apple-bridge";
    return { status: "error", error: msg };
  }
}

/**
 * Launch apple-bridge via .app bundle using `open`, with output written to
 * a temp file. Required on macOS Sequoia where CLI tools cannot obtain
 * TCC permissions (e.g. Reminders) without an .app bundle context.
 */
async function callBridgeViaApp(
  args: string[]
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
      resolvePromise({
        status: "error",
        error: "apple-bridge .app bundle timed out after 30s",
      });
    }, 30_000);

    child.on("close", async () => {
      clearTimeout(timeout);
      try {
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

/**
 * Convenience: call bridge, check status, return data or throw.
 */
export async function bridgeData(args: string[]): Promise<unknown> {
  const result = await callBridge(args);
  if (result.status === "error") {
    throw new Error(result.error ?? "apple-bridge returned an error");
  }
  return result.data;
}
