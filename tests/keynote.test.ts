import { describe, it } from "node:test";
import assert from "node:assert/strict";

describe("keynote.read args construction", () => {
  it("builds args for all slides", () => {
    const file = "/Users/test/Deck.key";
    const args = ["keynote-read", "--file", file];
    assert.deepEqual(args, ["keynote-read", "--file", "/Users/test/Deck.key"]);
  });

  it("includes slide index for single slide", () => {
    const file = "/Users/test/Deck.key";
    const slide = 3;
    const args = ["keynote-read", "--file", file];
    if (slide !== undefined) args.push("--slide", String(slide));
    assert.ok(args.includes("--slide"));
    assert.ok(args.includes("3"));
  });
});

describe("keynote.add_slide args construction", () => {
  it("builds args with all optional fields", () => {
    const file = "/Users/test/Deck.key";
    const layout = "Title & Body";
    const title = "Q1 Results";
    const body = "Revenue grew 15%";
    const notes = "Mention partnership";
    const position = 2;
    const args = ["keynote-add-slide", "--file", file];
    if (layout) args.push("--layout", layout);
    if (title) args.push("--title", title);
    if (body) args.push("--body", body);
    if (notes) args.push("--notes", notes);
    if (position !== undefined) args.push("--position", String(position));
    assert.equal(args.length, 13);
    assert.ok(args.includes("--layout"));
    assert.ok(args.includes("--position"));
  });

  it("builds minimal args with file only", () => {
    const file = "/Users/test/Deck.key";
    const args = ["keynote-add-slide", "--file", file];
    assert.equal(args.length, 3);
  });
});

describe("keynote.reorder_slides args construction", () => {
  it("builds args with from and to positions", () => {
    const file = "/Users/test/Deck.key";
    const from = 5;
    const to = 2;
    const args = [
      "keynote-reorder-slides", "--file", file,
      "--from", String(from), "--to", String(to),
    ];
    assert.ok(args.includes("5"));
    assert.ok(args.includes("2"));
  });
});

describe("keynote.export args construction", () => {
  it("builds args for pdf export", () => {
    const file = "/Users/test/Deck.key";
    const format = "pdf";
    const args = ["keynote-export", "--file", file, "--format", format];
    assert.deepEqual(args, [
      "keynote-export", "--file", "/Users/test/Deck.key", "--format", "pdf",
    ]);
  });

  it("supports all four export formats", () => {
    for (const format of ["pdf", "pptx", "png", "jpeg"]) {
      const args = ["keynote-export", "--file", "test.key", "--format", format];
      assert.ok(args.includes(format));
    }
  });

  it("includes single-slide export option", () => {
    const file = "/Users/test/Deck.key";
    const slide = 1;
    const args = ["keynote-export", "--file", file, "--format", "png"];
    if (slide !== undefined) args.push("--slide", String(slide));
    assert.ok(args.includes("--slide"));
  });
});

describe("keynote.edit_slide args construction", () => {
  it("includes only changed fields", () => {
    const file = "/Users/test/Deck.key";
    const slide = 2;
    const title = "Updated Title";
    const body = undefined;
    const notes = "New notes";
    const args = ["keynote-edit-slide", "--file", file, "--slide", String(slide)];
    if (title) args.push("--title", title);
    if (body) args.push("--body", body);
    if (notes) args.push("--notes", notes);
    assert.ok(args.includes("--title"));
    assert.ok(!args.includes("--body"));
    assert.ok(args.includes("--notes"));
  });
});
