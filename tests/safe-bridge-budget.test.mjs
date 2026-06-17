import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const repoRoot = new URL("../", import.meta.url);

function readRepoFile(path) {
  return readFileSync(new URL(path, repoRoot), "utf8");
}

describe("safeBridgeData timeout budgeting", () => {
  it("allows extra wall-clock budget for direct-to-app fallback retries", () => {
    const safetySource = readRepoFile("src/safety.ts");

    assert.match(safetySource, /const BRIDGE_TIMEOUT_ATTEMPTS = 2;/);
    assert.match(
      safetySource,
      /runWithOperationProfile\([\s\S]*timeoutMs:\s*profile\.timeoutMs\s*\*\s*BRIDGE_TIMEOUT_ATTEMPTS/s
    );
  });
});
