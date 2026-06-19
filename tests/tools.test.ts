import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { createOrchardServer } from "../src/server.js";

const FRONTEND_TOOL_NAME_PATTERN = /^[a-zA-Z0-9_-]{1,64}$/;

const EXPECTED_TOOLS = [
  // Calendar (4)
  "calendar_list_calendars",
  "calendar_list_events",
  "calendar_today",
  "calendar_search",
  // Mail (7)
  "mail_list_accounts",
  "mail_unread_summary",
  "mail_search",
  "mail_read_message",
  "mail_create_draft",
  "mail_flagged",
  "mail_save_attachment",
  // Reminders (8)
  "reminders_list_lists",
  "reminders_list_reminders",
  "reminders_today",
  "reminders_create_list",
  "reminders_create_reminder",
  "reminders_complete_reminder",
  "reminders_delete_reminder",
  "reminders_delete_list",
  // Files (8)
  "files_list",
  "files_info",
  "files_search",
  "files_read",
  "files_move",
  "files_copy",
  "files_create_folder",
  "files_trash",
  // System (1)
  "system_doctor",
  // Numbers (10)
  "numbers_search",
  "numbers_read",
  "numbers_write",
  "numbers_create",
  "numbers_list_sheets",
  "numbers_add_sheet",
  "numbers_remove_sheet",
  "numbers_get_formulas",
  "numbers_export",
  "numbers_info",
  // Pages (9)
  "pages_search",
  "pages_read",
  "pages_write",
  "pages_create",
  "pages_find_replace",
  "pages_insert_table",
  "pages_list_sections",
  "pages_export",
  "pages_info",
  // Keynote (11)
  "keynote_search",
  "keynote_read",
  "keynote_create",
  "keynote_add_slide",
  "keynote_edit_slide",
  "keynote_remove_slide",
  "keynote_reorder_slides",
  "keynote_list_slides",
  "keynote_list_themes",
  "keynote_export",
  "keynote_info",
  // Notes (4)
  "notes_list_folders",
  "notes_list_notes",
  "notes_search",
  "notes_read_note",
  // Contacts (3)
  "contacts_list_groups",
  "contacts_search",
  "contacts_read_contact",
];

describe("tool registration", () => {
  let server: McpServer;

  before(() => {
    server = createOrchardServer();
  });

  it("registers exactly 65 tools", () => {
    const tools = (server as any)._registeredTools as Record<string, unknown>;
    const names = Object.keys(tools);
    assert.equal(names.length, 65, `Expected 65 tools, got ${names.length}: ${names.join(", ")}`);
  });

  it("uses Claude Desktop Chat-compatible tool names", () => {
    const tools = (server as any)._registeredTools as Record<string, unknown>;
    for (const name of Object.keys(tools)) {
      assert.match(name, FRONTEND_TOOL_NAME_PATTERN);
    }
  });

  for (const name of EXPECTED_TOOLS) {
    it(`registers "${name}"`, () => {
      const tools = (server as any)._registeredTools as Record<string, unknown>;
      assert.ok(name in tools, `Tool "${name}" not registered`);
    });
  }
});
