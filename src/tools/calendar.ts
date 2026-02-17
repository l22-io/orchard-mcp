import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { bridgeData } from "../bridge.js";

export function registerCalendarTools(server: McpServer): void {
  server.tool(
    "calendar.list_calendars",
    "List all Apple Calendar calendars with account name, type, color, and read-only status.",
    {},
    async () => {
      const data = await bridgeData(["calendars"]);
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
      const args = ["events", "--start", start, "--end", end];
      if (calendarId) {
        args.push("--calendar", calendarId);
      }
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
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

      const data = await bridgeData(["events", "--start", start, "--end", end]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
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
      const data = await bridgeData([
        "search",
        query,
        "--start",
        start,
        "--end",
        end,
      ]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
