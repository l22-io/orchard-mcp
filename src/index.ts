#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { registerCalendarTools } from "./tools/calendar.js";
import { registerSystemTools } from "./tools/system.js";

const server = new McpServer({
  name: "apple-mcp",
  version: "0.1.0",
});

registerCalendarTools(server);
registerSystemTools(server);

const transport = new StdioServerTransport();
await server.connect(transport);

// Reason: stderr only -- stdout is reserved for JSON-RPC in stdio transport.
console.error("[apple-mcp] Server started via stdio transport.");
