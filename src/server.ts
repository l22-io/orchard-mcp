import { createRequire } from "node:module";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
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

const require = createRequire(import.meta.url);
const packageJson = require("../package.json") as { version: string };
const FRONTEND_TOOL_NAME_PATTERN = /^[a-zA-Z0-9_-]{1,64}$/;

export function toFrontendToolName(name: string): string {
  const frontendName = name.replaceAll(".", "_");
  if (!FRONTEND_TOOL_NAME_PATTERN.test(frontendName)) {
    throw new Error(
      `Tool name "${name}" maps to invalid frontend tool name "${frontendName}". ` +
        "Tool names must match /^[a-zA-Z0-9_-]{1,64}$/."
    );
  }
  return frontendName;
}

function useFrontendToolNames(server: McpServer): void {
  const originalTool = server.tool.bind(server) as (
    name: string,
    ...rest: unknown[]
  ) => unknown;

  (server as unknown as { tool: (name: string, ...rest: unknown[]) => unknown }).tool = (
    name,
    ...rest
  ) => originalTool(toFrontendToolName(name), ...rest);
}

export function createOrchardServer(): McpServer {
  const server = new McpServer({
    name: "orchard-mcp",
    version: packageJson.version,
  });
  useFrontendToolNames(server);

  registerCalendarTools(server);
  registerMailTools(server);
  registerReminderTools(server);
  registerSystemTools(server);
  registerFileTools(server);
  registerNumbersTools(server);
  registerPagesTools(server);
  registerKeynoteTools(server);
  registerNotesTools(server);
  registerContactsTools(server);

  return server;
}
