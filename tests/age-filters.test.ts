import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  cutoffDate,
  filterCalendarEvents,
  filterReminders,
  isCalendarRangeFullyBeforeCutoff,
} from "../src/ageFilters.js";

const NOW = new Date("2026-06-18T15:00:00");

describe("age filters", () => {
  it("computes cutoff as start of today minus maxAgeDays", () => {
    const cutoff = cutoffDate(30, NOW);
    const expected = new Date(NOW.getFullYear(), NOW.getMonth(), NOW.getDate());
    expected.setDate(expected.getDate() - 30);
    assert.equal(cutoff.getTime(), expected.getTime());
  });

  it("returns false when maxAgeDays is undefined", () => {
    assert.equal(
      isCalendarRangeFullyBeforeCutoff("2020-01-01", "2020-01-02", undefined, NOW),
      false
    );
  });

  it("detects calendar ranges fully before the cutoff", () => {
    assert.equal(
      isCalendarRangeFullyBeforeCutoff("2020-01-01", "2020-01-02", 30, NOW),
      true
    );
    assert.equal(
      isCalendarRangeFullyBeforeCutoff("2026-06-01", "2026-06-18", 30, NOW),
      false
    );
  });

  it("filters calendar events by end date", () => {
    const events = [
      { id: "old", end: "2020-01-01T10:00:00Z" },
      { id: "recent", end: "2026-06-18T10:00:00Z" },
      { id: "future", end: "2026-07-01T10:00:00Z" },
    ];

    const filtered = filterCalendarEvents(events, 30, NOW);
    assert.deepEqual(
      filtered.map((event) => event.id),
      ["recent", "future"]
    );
  });

  it("keeps calendar events when maxAgeDays is undefined", () => {
    const events = [{ id: "old", end: "2020-01-01T10:00:00Z" }];
    assert.deepEqual(filterCalendarEvents(events, undefined, NOW), events);
  });

  it("filters old completed reminders but keeps incomplete overdue items", () => {
    const reminders = [
      {
        id: "old-completed",
        isCompleted: true,
        completionDate: "2020-01-01T10:00:00Z",
      },
      {
        id: "recent-completed",
        isCompleted: true,
        completionDate: "2026-06-10T10:00:00Z",
      },
      {
        id: "overdue-incomplete",
        isCompleted: false,
        dueDate: "2020-01-01T10:00:00Z",
      },
      {
        id: "undated-incomplete",
        isCompleted: false,
      },
      {
        id: "completed-no-date",
        isCompleted: true,
      },
    ];

    const filtered = filterReminders(reminders, 30, NOW);
    assert.deepEqual(
      filtered.map((reminder) => reminder.id),
      [
        "recent-completed",
        "overdue-incomplete",
        "undated-incomplete",
        "completed-no-date",
      ]
    );
  });
});
