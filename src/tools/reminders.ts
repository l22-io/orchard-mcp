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

  server.tool(
    "reminders.create_list",
    "Create a new reminder list.",
    {
      name: z.string().describe("Name for the new list"),
    },
    async ({ name }) => {
      const data = await bridgeData(["reminder-create-list", "--name", name]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "reminders.create_reminder",
    "Create a new reminder in a list.",
    {
      list: z.string().describe("List name to add the reminder to"),
      title: z.string().describe("Reminder title"),
      due: z
        .string()
        .optional()
        .describe("Due date (ISO 8601, e.g. 2026-02-18 or 2026-02-18T10:00:00Z)"),
      priority: z
        .number()
        .optional()
        .describe("Priority: 0=none, 1=high, 5=medium, 9=low (default: 0)"),
      notes: z.string().optional().describe("Notes for the reminder"),
    },
    async ({ list, title, due, priority, notes }) => {
      const args = ["reminder-create", "--list", list, "--title", title];
      if (due) {
        args.push("--due", due);
      }
      if (priority !== undefined) {
        args.push("--priority", String(priority));
      }
      if (notes) {
        args.push("--notes", notes);
      }
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "reminders.complete_reminder",
    "Mark a reminder as completed.",
    {
      id: z.string().describe("Reminder ID (from reminders.list_reminders output)"),
    },
    async ({ id }) => {
      const data = await bridgeData(["reminder-complete", "--id", id]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "reminders.delete_reminder",
    "Delete a reminder.",
    {
      id: z.string().describe("Reminder ID (from reminders.list_reminders output)"),
    },
    async ({ id }) => {
      const data = await bridgeData(["reminder-delete", "--id", id]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "reminders.delete_list",
    "Delete a reminder list. Fails if the list has reminders unless force is true.",
    {
      id: z.string().describe("List ID (from reminders.list_lists output)"),
      force: z
        .boolean()
        .optional()
        .describe("Delete even if the list has reminders (default: false)"),
    },
    async ({ id, force }) => {
      const args = ["reminder-delete-list", "--id", id];
      if (force) {
        args.push("--force");
      }
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
