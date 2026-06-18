import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { filterReminders } from "../ageFilters.js";
import { OrchardConfig } from "../config.js";
import { OPERATION_PROFILES, safeBridgeData } from "../safety.js";

function formatRemindersResponse(
  data: unknown,
  remindersMaxAgeDays: number | undefined
): string {
  const reminders = Array.isArray(data) ? data : [];
  const filtered = filterReminders(reminders, remindersMaxAgeDays);
  return JSON.stringify(filtered, null, 2);
}

export function registerReminderTools(server: McpServer, config: OrchardConfig): void {
  server.tool(
    "reminders.list_lists",
    "List all Apple Reminders lists with account name, color, and modification status.",
    {},
    async () => {
      const data = await safeBridgeData(
        ["reminder-lists"],
        OPERATION_PROFILES.remindersRead
      );
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
        .int()
        .min(1)
        .max(200)
        .optional()
        .describe("Max reminders to return (default: 50, max: 200)"),
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
      const data = await safeBridgeData(args, OPERATION_PROFILES.remindersRead);
      return {
        content: [
          {
            type: "text",
            text: formatRemindersResponse(data, config.remindersMaxAgeDays),
          },
        ],
      };
    }
  );

  server.tool(
    "reminders.today",
    "Get incomplete reminders due today plus any overdue reminders across all lists.",
    {},
    async () => {
      const data = await safeBridgeData(
        ["reminders-today"],
        OPERATION_PROFILES.remindersRead
      );
      return {
        content: [
          {
            type: "text",
            text: formatRemindersResponse(data, config.remindersMaxAgeDays),
          },
        ],
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
      const data = await safeBridgeData(
        ["reminder-create-list", "--name", name],
        OPERATION_PROFILES.remindersWrite
      );
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
      const data = await safeBridgeData(args, OPERATION_PROFILES.remindersWrite);
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
      const data = await safeBridgeData(
        ["reminder-complete", "--id", id],
        OPERATION_PROFILES.remindersWrite
      );
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
      const data = await safeBridgeData(
        ["reminder-delete", "--id", id],
        OPERATION_PROFILES.remindersWrite
      );
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
      const data = await safeBridgeData(args, OPERATION_PROFILES.remindersWrite);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
