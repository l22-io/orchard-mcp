#!/usr/bin/env node

// Handle `orchard-mcp setup` subcommand before starting MCP server.
if (process.argv[2] === "setup") {
  const { runSetup } = await import("./setup.js");
  await runSetup(process.argv.includes("--non-interactive"));
  process.exit(0);
}

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { registerCalendarTools } from "./tools/calendar.js";
import { registerMailTools } from "./tools/mail.js";
import { registerReminderTools } from "./tools/reminders.js";
import { registerSystemTools } from "./tools/system.js";
import { registerFileTools } from "./tools/files.js";

const server = new McpServer({
  name: "orchard-mcp",
  version: "0.3.0",
});

registerCalendarTools(server);
registerMailTools(server);
registerReminderTools(server);
registerSystemTools(server);
registerFileTools(server);

const transport = new StdioServerTransport();
await server.connect(transport);

// Reason: stderr only -- stdout is reserved for JSON-RPC in stdio transport.
console.error("[orchard-mcp] Server started via stdio transport.");
