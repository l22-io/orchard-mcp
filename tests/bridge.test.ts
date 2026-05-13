import { describe, it } from "node:test";
import assert from "node:assert/strict";
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

  it("allows empty options (uses default timeout)", () => {
    const opts: BridgeOptions = {};
    assert.equal(opts.timeoutMs, undefined);
  });
});
