import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  assertBatchSize,
  assertIsoDateRangeWithinDays,
  normalizeNotesSearchIn,
  requireKeynoteSlideForImageExport,
  requireNumbersRange,
} from "../src/resourceGuards.js";

const repoRoot = new URL("../", import.meta.url);

function readRepoFile(path: string): string {
  return readFileSync(new URL(path, repoRoot), "utf8");
}

describe("resource guardrails", () => {
  it("refuses calendar ranges that are too broad", () => {
    assert.doesNotThrow(() =>
      assertIsoDateRangeWithinDays(
        "2026-06-01T00:00:00Z",
        "2026-06-08T00:00:00Z",
        31,
        "calendar.list_events"
      )
    );
    assert.throws(
      () =>
        assertIsoDateRangeWithinDays(
          "2026-01-01T00:00:00Z",
          "2026-04-15T00:00:00Z",
          31,
          "calendar.list_events"
        ),
      /calendar.list_events refuses date ranges over 31 days/
    );
  });

  it("makes Notes title search the safe default and refuses broad body scans", () => {
    assert.equal(normalizeNotesSearchIn(undefined), "title");
    assert.equal(normalizeNotesSearchIn("title"), "title");
    assert.throws(() => normalizeNotesSearchIn("body"), /Notes body search is disabled/);
    assert.throws(() => normalizeNotesSearchIn("all"), /Notes body search is disabled/);
  });

  it("requires a Numbers cell range before reading table cells or formulas", () => {
    assert.throws(
      () => requireNumbersRange("numbers.read", undefined),
      /numbers.read requires a cell range/
    );
    assert.doesNotThrow(() => requireNumbersRange("numbers.read", "A1:C20"));
  });

  it("requires a slide index before exporting Keynote slide images", () => {
    assert.doesNotThrow(() => requireKeynoteSlideForImageExport("pdf", undefined));
    assert.doesNotThrow(() => requireKeynoteSlideForImageExport("png", 3));
    assert.throws(
      () => requireKeynoteSlideForImageExport("jpeg", undefined),
      /requires a slide index/
    );
  });

  it("refuses oversized file-operation batches", () => {
    assert.doesNotThrow(() => assertBatchSize("files.move", 10, 50));
    assert.throws(
      () => assertBatchSize("files.move", 51, 50),
      /files.move accepts at most 50 items/
    );
  });

  it("keeps file extraction and Spotlight subprocesses behind native budgets", () => {
    const filesSwift = readRepoFile("swift/Sources/AppleBridge/Files.swift");

    assert.match(filesSwift, /processTimeout/);
    assert.match(filesSwift, /runProcess/);
    assert.match(filesSwift, /maxListItems/);
    assert.match(filesSwift, /maxPDFPages/);
    assert.match(filesSwift, /maxOCRImageBytes/);
    assert.match(filesSwift, /maxTextutilBytes/);
  });

  it("caps Contacts phone substring fallback scans", () => {
    const contactsSwift = readRepoFile("swift/Sources/AppleBridge/Contacts.swift");

    assert.match(contactsSwift, /maxPhoneSubstringContactsScanned/);
    assert.match(contactsSwift, /stop.pointee = true/);
  });

  it("keeps native Calendar and Reminders queries capped for direct bridge users", () => {
    const calendarSwift = readRepoFile("swift/Sources/AppleBridge/Calendar.swift");
    const remindersSwift = readRepoFile("swift/Sources/AppleBridge/Reminders.swift");

    assert.match(calendarSwift, /maxCalendarRangeDays/);
    assert.match(calendarSwift, /maxCalendarResults/);
    assert.match(remindersSwift, /maxReminderResults/);
  });
});
