import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { bridgeData } from "../bridge.js";

export function registerReminderTools(server: McpServer): void {
  server.tool(
    "reminders.list_lists",
    "List all Apple Reminders lists with account name, color, and modification status.",
    {},
    async () => {
      const data = await bridgeData(["reminder-lists"]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "reminders.list_reminders",
    "List reminders from a specific list or all lists. Supports filters: incomplete (default), completed, overdue, dueToday, all.",
    {
      list: z
        .string()
        .optional()
        .describe("Filter to a specific reminder list name"),
      filter: z
        .enum(["incomplete", "completed", "overdue", "dueToday", "all"])
        .optional()
        .describe("Filter reminders by status (default: incomplete)"),
      limit: z
        .number()
        .optional()
        .describe("Max reminders to return (default: 50)"),
    },
    async ({ list, filter, limit }) => {
      const args = ["reminders"];
      if (list) {
        args.push("--list", list);
      }
      if (filter) {
        args.push("--filter", filter);
      }
      if (limit !== undefined) {
        args.push("--limit", String(limit));
      }
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "reminders.today",
    "Get incomplete reminders due today plus any overdue reminders across all lists.",
    {},
    async () => {
      const data = await bridgeData(["reminders-today"]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
