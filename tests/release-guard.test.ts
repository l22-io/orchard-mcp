import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const repoRoot = new URL("../", import.meta.url);

function readRepoFile(path: string): string {
  return readFileSync(new URL(path, repoRoot), "utf8");
}

describe("release publish guard", () => {
  it("runs before package build/publish packaging", () => {
    const packageJson = JSON.parse(readRepoFile("package.json")) as {
      scripts: Record<string, string>;
    };

    assert.match(
      packageJson.scripts.prepublishOnly,
      /^bash scripts\/prepublish-guard\.sh && npm run build:ts && bash scripts\/prepublish\.sh$/
    );
  });

  it("prevents publishing from stale branches or duplicate npm versions", () => {
    const script = readRepoFile("scripts/prepublish-guard.sh");

    assert.match(script, /git branch --show-current/);
    assert.match(script, /\$CURRENT_BRANCH" != "main"/);
    assert.match(script, /git diff --quiet/);
    assert.match(script, /git diff --cached --quiet/);
    assert.match(script, /git fetch --quiet origin main/);
    assert.match(script, /git merge-base --is-ancestor HEAD origin\/main/);
    assert.match(script, /git merge-base --is-ancestor origin\/main HEAD/);
    assert.match(script, /npm view "\$PACKAGE_NAME@\$PACKAGE_VERSION" version/);
    assert.match(script, /already exists on npm/);
  });
});
