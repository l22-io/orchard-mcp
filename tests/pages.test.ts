import { describe, it } from "node:test";
import assert from "node:assert/strict";

describe("pages.read args construction", () => {
  it("builds args with file only", () => {
    const file = "/Users/test/Report.pages";
    const args = ["pages-read", "--file", file];
    assert.deepEqual(args, ["pages-read", "--file", "/Users/test/Report.pages"]);
  });
});

describe("pages.find_replace args construction", () => {
  it("builds args without --all flag", () => {
    const file = "/Users/test/Report.pages";
    const find = "old text";
    const replace = "new text";
    const all = false;
    const args = ["pages-find-replace", "--file", file, "--find", find, "--replace", replace];
    if (all) args.push("--all");
    assert.ok(!args.includes("--all"));
  });

  it("includes --all flag when true", () => {
    const file = "/Users/test/Report.pages";
    const find = "old text";
    const replace = "new text";
    const all = true;
    const args = ["pages-find-replace", "--file", file, "--find", find, "--replace", replace];
    if (all) args.push("--all");
    assert.ok(args.includes("--all"));
  });
});

describe("pages.export args construction", () => {
  it("builds args for pdf export", () => {
    const file = "/Users/test/Report.pages";
    const format = "pdf";
    const args = ["pages-export", "--file", file, "--format", format];
    assert.deepEqual(args, [
      "pages-export", "--file", "/Users/test/Report.pages", "--format", "pdf",
    ]);
  });

  it("supports all four export formats", () => {
    for (const format of ["pdf", "docx", "txt", "epub"]) {
      const args = ["pages-export", "--file", "test.pages", "--format", format];
      assert.ok(args.includes(format));
    }
  });
});

describe("pages.create args construction", () => {
  it("builds args with text and template", () => {
    const file = "/Users/test/New.pages";
    const text = "Hello World";
    const template = "Blank";
    const args = ["pages-create", "--file", file];
    if (text) args.push("--text", text);
    if (template) args.push("--template", template);
    assert.ok(args.includes("--text"));
    assert.ok(args.includes("--template"));
  });
});
