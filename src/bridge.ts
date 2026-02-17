import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);

// Reason: Resolve the Swift binary path relative to this file's location.
// In development: swift/.build/release/apple-bridge
// In npm package: swift/.build/release/apple-bridge (shipped alongside)
const __dirname = dirname(fileURLToPath(import.meta.url));

function getBridgePath(): string {
  // Reason: Allow override via env var for custom installations.
  if (process.env.APPLE_BRIDGE_BIN) {
    return process.env.APPLE_BRIDGE_BIN;
  }
  // Default: relative to project root (one level up from build/)
  return resolve(__dirname, "..", "swift", ".build", "release", "apple-bridge");
}

export interface BridgeResponse {
  status: "ok" | "error";
  data?: unknown;
  error?: string;
}

/**
 * Execute an apple-bridge subcommand and return parsed JSON.
 * Throws on non-zero exit or JSON parse failure.
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
    return parsed;
  } catch (err: unknown) {
    const msg =
      err instanceof Error ? err.message : "Unknown error calling apple-bridge";
    return { status: "error", error: msg };
  }
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
