import { describe, it, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, writeFile, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import type { BridgeOptions, BridgeResponse } from "../src/bridge.js";

describe("bridge JSON contract", () => {
  it("parses ok response", () => {
    const raw = '{"status":"ok","data":{"calendars":[]}}';
    const parsed: BridgeResponse = JSON.parse(raw);
    assert.equal(parsed.status, "ok");
    assert.deepEqual(parsed.data, { calendars: [] });
    assert.equal(parsed.error, undefined);
  });

  it("parses error response", () => {
    const raw = '{"status":"error","error":"access denied"}';
    const parsed: BridgeResponse = JSON.parse(raw);
    assert.equal(parsed.status, "error");
    assert.equal(parsed.error, "access denied");
    assert.equal(parsed.data, undefined);
  });

  it("rejects invalid JSON", () => {
    assert.throws(() => JSON.parse("not json"), SyntaxError);
  });

  it("handles empty data field", () => {
    const raw = '{"status":"ok","data":null}';
    const parsed: BridgeResponse = JSON.parse(raw);
    assert.equal(parsed.status, "ok");
    assert.equal(parsed.data, null);
  });
});

describe("BridgeOptions shape", () => {
  it("accepts timeoutMs override", () => {
    const opts: BridgeOptions = { timeoutMs: 120_000 };
    assert.equal(opts.timeoutMs, 120_000);
  });

  it("accepts maxOutputBytes override", () => {
    const opts: BridgeOptions = { maxOutputBytes: 1024 };
    assert.equal(opts.maxOutputBytes, 1024);
  });

  it("allows empty options (uses default timeout)", () => {
    const opts: BridgeOptions = {};
    assert.equal(opts.timeoutMs, undefined);
    assert.equal(opts.maxOutputBytes, undefined);
  });
});

// Regression test for the v0.6.1 gap that re-froze Mail.app: when the bridge
// timeout fires, SIGTERM is sent to the process group, and SIGKILL is
// scheduled 2s later. The Swift bridge has no SIGTERM handler and dies
// immediately, which previously caused settle() to clear the SIGKILL timer
// before it fired — orphaning any osascript grandchild that was blocked on
// an Apple Event to Mail.app/Notes.app. The fix keeps the SIGKILL alive
// once escalation has begun so the whole group is reaped.
describe("bridge timeout: SIGKILL reaches grandchildren after parent exits on SIGTERM", () => {
  let tmpDir: string;
  let stubBin: string;
  let pidFile: string;
  let savedEnvBin: string | undefined;

  before(async () => {
    tmpDir = await mkdtemp(resolve(tmpdir(), "orchard-bridge-test-"));
    stubBin = resolve(tmpDir, "stub-bridge.sh");
    pidFile = resolve(tmpDir, "grandchild.pid");
    // Stub bridge: fork a stubborn grandchild that genuinely ignores SIGTERM
    // (perl's $SIG{TERM}="IGNORE" maps to SIG_IGN, which the kernel honors —
    // unlike bash's `trap '' TERM`, which only protects the bash process and
    // not its `sleep` child) and record its PID, then sleep so the bridge
    // itself remains alive until the test-side timeout fires. Models the
    // production case where Swift dies fast on SIGTERM but osascript is
    // wedged in a Mach RPC to Mail.app/Notes.app.
    const perlOneLiner =
      `$SIG{TERM}="IGNORE"; open(F,">","${pidFile}") or die; ` +
      `print F $$; close(F); sleep 30;`;
    // Detach the grandchild's stdio (`</dev/null >/dev/null 2>&1`) so it does
    // NOT inherit the bridge's stdout/stderr pipe ends. Production matches:
    // Swift's Foundation.Process gives osascript its own Pipe() so when Swift
    // dies, Node sees the bridge's pipes close immediately. Without detaching
    // here, the test would never reach the buggy code path because the close
    // event would be gated on perl exiting.
    const script = [
      "#!/bin/bash",
      `/usr/bin/perl -e '${perlOneLiner}' </dev/null >/dev/null 2>&1 &`,
      "sleep 30",
    ].join("\n") + "\n";
    await writeFile(stubBin, script, { mode: 0o755 });
    savedEnvBin = process.env.APPLE_BRIDGE_BIN;
    process.env.APPLE_BRIDGE_BIN = stubBin;
  });

  after(async () => {
    if (savedEnvBin === undefined) delete process.env.APPLE_BRIDGE_BIN;
    else process.env.APPLE_BRIDGE_BIN = savedEnvBin;
    await rm(tmpDir, { recursive: true, force: true });
  });

  it("SIGKILLs a SIGTERM-ignoring grandchild after the parent has already exited", async () => {
    const { callBridge } = await import("../src/bridge.js");

    const result = await callBridge(["doctor"], { timeoutMs: 500 });
    assert.equal(result.status, "error");

    let grandPid: number | undefined;
    for (let i = 0; i < 40; i++) {
      try {
        const raw = await readFile(pidFile, "utf8");
        const n = parseInt(raw.trim(), 10);
        if (Number.isFinite(n) && n > 0) { grandPid = n; break; }
      } catch { /* file may not exist yet */ }
      await new Promise((r) => setTimeout(r, 50));
    }
    assert.ok(grandPid, "stub grandchild should have recorded its PID");

    // SIGKILL grace is 2s; wait a bit longer so it has time to fire and reap.
    await new Promise((r) => setTimeout(r, 3000));

    let alive = false;
    try { process.kill(grandPid!, 0); alive = true; } catch { /* ESRCH -> dead */ }
    if (alive) {
      // Defensive cleanup so a failing test doesn't leak a 30s sleeper.
      try { process.kill(grandPid!, "SIGKILL"); } catch { /* */ }
    }
    assert.equal(alive, false, `grandchild ${grandPid} should have been SIGKILLed once the bridge timed out`);
  });
});
