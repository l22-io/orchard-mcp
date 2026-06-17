import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  runWithOperationProfile,
  type OperationProfile,
} from "../src/safety.js";

describe("operation safety scheduler", () => {
  const mailProfile: OperationProfile = {
    name: "test.mail",
    lane: "mail",
    timeoutMs: 1_000,
    queueTimeoutMs: 1_000,
  };

  it("serializes operations that share a host-app lane", async () => {
    const events: string[] = [];

    const first = runWithOperationProfile(mailProfile, async () => {
      events.push("first:start");
      await new Promise((resolve) => setTimeout(resolve, 50));
      events.push("first:end");
      return "first";
    });

    const second = runWithOperationProfile(mailProfile, async () => {
      events.push("second:start");
      events.push("second:end");
      return "second";
    });

    assert.deepEqual(await Promise.all([first, second]), ["first", "second"]);
    assert.deepEqual(events, [
      "first:start",
      "first:end",
      "second:start",
      "second:end",
    ]);
  });

  it("fails fast when a host-app lane stays busy past the queue budget", async () => {
    const blockingProfile: OperationProfile = {
      ...mailProfile,
      queueTimeoutMs: 5,
    };

    let secondStarted = false;
    const first = runWithOperationProfile(blockingProfile, async () => {
      await new Promise((resolve) => setTimeout(resolve, 50));
      return "first";
    });

    await assert.rejects(
      runWithOperationProfile(blockingProfile, async () => {
        secondStarted = true;
        return "second";
      }),
      /busy with another orchard-mcp operation/
    );
    assert.equal(secondStarted, false);
    assert.equal(await first, "first");
  });
});
