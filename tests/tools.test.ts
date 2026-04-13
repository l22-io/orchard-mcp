import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { registerCalendarTools } from "../src/tools/calendar.js";
import { registerMailTools } from "../src/tools/mail.js";
import { registerReminderTools } from "../src/tools/reminders.js";
import { registerSystemTools } from "../src/tools/system.js";
import { registerFileTools } from "../src/tools/files.js";
import { registerNumbersTools } from "../src/tools/numbers.js";
import { registerPagesTools } from "../src/tools/pages.js";
import { registerKeynoteTools } from "../src/tools/keynote.js";

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
  // Numbers (10)
  "numbers.search",
  "numbers.read",
  "numbers.write",
  "numbers.create",
  "numbers.list_sheets",
  "numbers.add_sheet",
  "numbers.remove_sheet",
  "numbers.get_formulas",
  "numbers.export",
  "numbers.info",
  // Pages (9)
  "pages.search",
  "pages.read",
  "pages.write",
  "pages.create",
  "pages.find_replace",
  "pages.insert_table",
  "pages.list_sections",
  "pages.export",
  "pages.info",
  // Keynote (11)
  "keynote.search",
  "keynote.read",
  "keynote.create",
  "keynote.add_slide",
  "keynote.edit_slide",
  "keynote.remove_slide",
  "keynote.reorder_slides",
  "keynote.list_slides",
  "keynote.list_themes",
  "keynote.export",
  "keynote.info",
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
    registerNumbersTools(server);
    registerPagesTools(server);
    registerKeynoteTools(server);
  });

  it("registers exactly 58 tools", () => {
    const tools = (server as any)._registeredTools as Record<string, unknown>;
    const names = Object.keys(tools);
    assert.equal(names.length, 58, `Expected 58 tools, got ${names.length}: ${names.join(", ")}`);
  });

  for (const name of EXPECTED_TOOLS) {
    it(`registers "${name}"`, () => {
      const tools = (server as any)._registeredTools as Record<string, unknown>;
      assert.ok(name in tools, `Tool "${name}" not registered`);
    });
  }
});
