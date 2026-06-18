import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import {
  filterCalendarEvents,
  isCalendarRangeFullyBeforeCutoff,
} from "../ageFilters.js";
import { OrchardConfig } from "../config.js";
import { assertIsoDateRangeWithinDays } from "../resourceGuards.js";
import { OPERATION_PROFILES, safeBridgeData } from "../safety.js";

const MAX_CALENDAR_RANGE_DAYS = 31;

function formatEventsResponse(
  data: unknown,
  calendarMaxAgeDays: number | undefined
): string {
  const events = Array.isArray(data) ? data : [];
  const filtered = filterCalendarEvents(events, calendarMaxAgeDays);
  return JSON.stringify(filtered, null, 2);
}

export function registerCalendarTools(server: McpServer, config: OrchardConfig): void {
  server.tool(
    "calendar.list_calendars",
    "List all Apple Calendar calendars with account name, type, color, and read-only status.",
    {},
    async () => {
      const data = await safeBridgeData(["calendars"], OPERATION_PROFILES.calendarRead);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "calendar.list_events",
    "List calendar events in a date range. Recurring events are properly expanded. Optionally filter by calendar ID.",
    {
      start: z
        .string()
        .describe("Start date in ISO 8601 format (e.g. 2026-02-17 or 2026-02-17T00:00:00Z)"),
      end: z
        .string()
        .describe("End date in ISO 8601 format"),
      calendarId: z
        .string()
        .optional()
        .describe("Optional calendar ID to filter by (from calendar.list_calendars)"),
    },
    async ({ start, end, calendarId }) => {
      assertIsoDateRangeWithinDays(
        start,
        end,
        MAX_CALENDAR_RANGE_DAYS,
        "calendar.list_events"
      );
      if (isCalendarRangeFullyBeforeCutoff(start, end, config.calendarMaxAgeDays)) {
        return {
          content: [{ type: "text", text: JSON.stringify([], null, 2) }],
        };
      }
      const args = ["events", "--start", start, "--end", end];
      if (calendarId) {
        args.push("--calendar", calendarId);
      }
      const data = await safeBridgeData(args, OPERATION_PROFILES.calendarRead);
      return {
        content: [
          {
            type: "text",
            text: formatEventsResponse(data, config.calendarMaxAgeDays),
          },
        ],
      };
    }
  );

  server.tool(
    "calendar.today",
    "Get all calendar events for today across all calendars.",
    {},
    async () => {
      // Reason: Build today's date range in local timezone for the bridge.
      const now = new Date();
      const startOfDay = new Date(
        now.getFullYear(),
        now.getMonth(),
        now.getDate()
      );
      const endOfDay = new Date(
        now.getFullYear(),
        now.getMonth(),
        now.getDate() + 1
      );
      const start = startOfDay.toISOString();
      const end = endOfDay.toISOString();

      const data = await safeBridgeData(
        ["events", "--start", start, "--end", end],
        OPERATION_PROFILES.calendarRead
      );
      return {
        content: [
          {
            type: "text",
            text: formatEventsResponse(data, config.calendarMaxAgeDays),
          },
        ],
      };
    }
  );

  server.tool(
    "calendar.search",
    "Search calendar events by title, notes, or location within a date range.",
    {
      query: z.string().describe("Search term to match against event title, notes, or location"),
      start: z.string().describe("Start date in ISO 8601 format"),
      end: z.string().describe("End date in ISO 8601 format"),
    },
    async ({ query, start, end }) => {
      assertIsoDateRangeWithinDays(
        start,
        end,
        MAX_CALENDAR_RANGE_DAYS,
        "calendar.search"
      );
      if (isCalendarRangeFullyBeforeCutoff(start, end, config.calendarMaxAgeDays)) {
        return {
          content: [{ type: "text", text: JSON.stringify([], null, 2) }],
        };
      }
      const data = await safeBridgeData([
        "search",
        query,
        "--start",
        start,
        "--end",
        end,
      ], OPERATION_PROFILES.calendarRead);
      return {
        content: [
          {
            type: "text",
            text: formatEventsResponse(data, config.calendarMaxAgeDays),
          },
        ],
      };
    }
  );

  server.tool(
    "calendar.create_event",
    "Create a new calendar event. Use calendar.list_calendars to find a writable calendar ID.",
    {
      title: z.string().describe("Event title"),
      start: z
        .string()
        .describe("Start date in ISO 8601 format (e.g. 2026-02-17 or 2026-02-17T10:00:00Z)"),
      end: z
        .string()
        .describe("End date in ISO 8601 format; must be on or after start"),
      calendarId: z
        .string()
        .optional()
        .describe("Optional calendar ID (from calendar.list_calendars); defaults to system default"),
      isAllDay: z
        .boolean()
        .optional()
        .describe("Create as an all-day event (default: false)"),
      location: z.string().optional().describe("Event location"),
      notes: z.string().optional().describe("Event notes"),
      url: z.string().optional().describe("Event URL"),
    },
    async ({ title, start, end, calendarId, isAllDay, location, notes, url }) => {
      const args = ["event-create", "--title", title, "--start", start, "--end", end];
      if (calendarId) {
        args.push("--calendar", calendarId);
      }
      if (isAllDay) {
        args.push("--all-day");
      }
      if (location) {
        args.push("--location", location);
      }
      if (notes) {
        args.push("--notes", notes);
      }
      if (url) {
        args.push("--url", url);
      }
      const data = await safeBridgeData(args, OPERATION_PROFILES.calendarWrite);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
