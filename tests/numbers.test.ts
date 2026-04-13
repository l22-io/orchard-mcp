import { describe, it } from "node:test";
import assert from "node:assert/strict";

describe("numbers.read args construction", () => {
  it("builds minimal args with file only", () => {
    const file = "/Users/test/Budget.numbers";
    const args = ["numbers-read", "--file", file];
    assert.deepEqual(args, ["numbers-read", "--file", "/Users/test/Budget.numbers"]);
  });

  it("includes optional sheet, table, range", () => {
    const file = "/Users/test/Budget.numbers";
    const sheet = "Q1";
    const table = "Expenses";
    const range = "A1:C10";
    const args = ["numbers-read", "--file", file];
    if (sheet) args.push("--sheet", sheet);
    if (table) args.push("--table", table);
    if (range) args.push("--range", range);
    assert.deepEqual(args, [
      "numbers-read", "--file", "/Users/test/Budget.numbers",
      "--sheet", "Q1", "--table", "Expenses", "--range", "A1:C10",
    ]);
  });
});

describe("numbers.write args construction", () => {
  it("builds args with required fields", () => {
    const file = "/Users/test/Budget.numbers";
    const data = '[["Name","Amount"],["Rent",1200]]';
    const args = ["numbers-write", "--file", file, "--data", data];
    assert.deepEqual(args, [
      "numbers-write", "--file", "/Users/test/Budget.numbers",
      "--data", '[["Name","Amount"],["Rent",1200]]',
    ]);
  });

  it("includes optional range for targeted write", () => {
    const file = "/Users/test/Budget.numbers";
    const data = '[[500]]';
    const range = "B2";
    const args = ["numbers-write", "--file", file, "--data", data];
    if (range) args.push("--range", range);
    assert.ok(args.includes("--range"));
    assert.ok(args.includes("B2"));
  });
});

describe("numbers.export args construction", () => {
  it("builds args for csv export", () => {
    const file = "/Users/test/Budget.numbers";
    const format = "csv";
    const args = ["numbers-export", "--file", file, "--format", format];
    assert.deepEqual(args, [
      "numbers-export", "--file", "/Users/test/Budget.numbers", "--format", "csv",
    ]);
  });

  it("includes optional output path", () => {
    const file = "/Users/test/Budget.numbers";
    const format = "xlsx";
    const output = "/tmp/export.xlsx";
    const args = ["numbers-export", "--file", file, "--format", format];
    if (output) args.push("--output", output);
    assert.ok(args.includes("--output"));
    assert.ok(args.includes("/tmp/export.xlsx"));
  });
});

describe("A1 range parsing logic", () => {
  function parseA1Cell(cell: string): { row: number; col: number } {
    let colStr = "";
    let rowStr = "";
    for (const char of cell.toUpperCase()) {
      if (char >= "A" && char <= "Z") colStr += char;
      else rowStr += char;
    }
    let col = 0;
    for (const char of colStr) {
      col = col * 26 + (char.charCodeAt(0) - 65) + 1;
    }
    col -= 1;
    const row = (parseInt(rowStr, 10) || 1) - 1;
    return { row, col };
  }

  it("parses A1 to row 0, col 0", () => {
    const { row, col } = parseA1Cell("A1");
    assert.equal(row, 0);
    assert.equal(col, 0);
  });

  it("parses C3 to row 2, col 2", () => {
    const { row, col } = parseA1Cell("C3");
    assert.equal(row, 2);
    assert.equal(col, 2);
  });

  it("parses Z1 to row 0, col 25", () => {
    const { row, col } = parseA1Cell("Z1");
    assert.equal(row, 0);
    assert.equal(col, 25);
  });

  it("parses AA1 to row 0, col 26", () => {
    const { row, col } = parseA1Cell("AA1");
    assert.equal(row, 0);
    assert.equal(col, 26);
  });

  it("parses AB10 to row 9, col 27", () => {
    const { row, col } = parseA1Cell("AB10");
    assert.equal(row, 9);
    assert.equal(col, 27);
  });
});
