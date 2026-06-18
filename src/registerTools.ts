import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { OrchardConfig, ModuleName } from "./config.js";
import { registerCalendarTools } from "./tools/calendar.js";
import { registerMailTools } from "./tools/mail.js";
import { registerReminderTools } from "./tools/reminders.js";
import { registerSystemTools } from "./tools/system.js";
import { registerFileTools } from "./tools/files.js";
import { registerNumbersTools } from "./tools/numbers.js";
import { registerPagesTools } from "./tools/pages.js";
import { registerKeynoteTools } from "./tools/keynote.js";
import { registerNotesTools } from "./tools/notes.js";
import { registerContactsTools } from "./tools/contacts.js";

type ToolRegistrar = (server: McpServer, config: OrchardConfig) => void;

const MODULE_REGISTRARS: Record<ModuleName, ToolRegistrar> = {
  calendar: registerCalendarTools,
  mail: registerMailTools,
  reminders: registerReminderTools,
  system: registerSystemTools,
  files: registerFileTools,
  numbers: registerNumbersTools,
  pages: registerPagesTools,
  keynote: registerKeynoteTools,
  notes: registerNotesTools,
  contacts: registerContactsTools,
};

export function registerEnabledTools(server: McpServer, config: OrchardConfig): void {
  for (const name of config.enabledModules) {
    MODULE_REGISTRARS[name](server, config);
  }
}
