#!/usr/bin/env node

// Handle `orchard-mcp setup` subcommand before starting MCP server.
if (process.argv[2] === "setup") {
  const { runSetup } = await import("./setup.js");
  await runSetup(process.argv.includes("--non-interactive"));
  process.exit(0);
}

import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { createOrchardServer } from "./server.js";

const server = createOrchardServer();
const transport = new StdioServerTransport();
await server.connect(transport);

// Reason: stderr only -- stdout is reserved for JSON-RPC in stdio transport.
console.error("[orchard-mcp] Server started via stdio transport.");
