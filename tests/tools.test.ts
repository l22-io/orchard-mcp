import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { registerCalendarTools } from "../src/tools/calendar.js";
import { registerMailTools } from "../src/tools/mail.js";
import { registerReminderTools } from "../src/tools/reminders.js";
import { registerSystemTools } from "../src/tools/system.js";
import { registerFileTools } from "../src/tools/files.js";

const EXPECTED_TOOLS = [
  // Calendar (4)
  "calendar.list_calendars",
  "calendar.list_events",
  "calendar.today",
  "calendar.search",
  // Mail (7)
  "mail.list_accounts",
  "mail.unread_summary",
  "mail.search",
  "mail.read_message",
  "mail.create_draft",
  "mail.flagged",
  "mail.save_attachment",
  // Reminders (8)
  "reminders.list_lists",
  "reminders.list_reminders",
  "reminders.today",
  "reminders.create_list",
  "reminders.create_reminder",
  "reminders.complete_reminder",
  "reminders.delete_reminder",
  "reminders.delete_list",
  // Files (8)
  "files.list",
  "files.info",
  "files.search",
  "files.read",
  "files.move",
  "files.copy",
  "files.create_folder",
  "files.trash",
  // System (1)
  "system.doctor",
];

describe("tool registration", () => {
  let server: McpServer;

  before(() => {
    server = new McpServer({ name: "orchard-mcp", version: "0.3.0" });
    registerCalendarTools(server);
    registerMailTools(server);
    registerReminderTools(server);
    registerSystemTools(server);
    registerFileTools(server);
  });

  it("registers exactly 28 tools", () => {
    const tools = (server as any)._registeredTools as Record<string, unknown>;
    const names = Object.keys(tools);
    assert.equal(names.length, 28, `Expected 28 tools, got ${names.length}: ${names.join(", ")}`);
  });

  for (const name of EXPECTED_TOOLS) {
    it(`registers "${name}"`, () => {
      const tools = (server as any)._registeredTools as Record<string, unknown>;
      assert.ok(name in tools, `Tool "${name}" not registered`);
    });
  }
});
