#!/usr/bin/env node

import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const packageJson = require("../package.json") as { version: string };

// Handle `orchard-mcp setup` subcommand before starting MCP server.
if (process.argv[2] === "setup") {
  const { runSetup } = await import("./setup.js");
  await runSetup(process.argv.includes("--non-interactive"));
  process.exit(0);
}

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { failConfig, loadConfig, logConfig } from "./config.js";
import { registerEnabledTools } from "./registerTools.js";

let config;
try {
  config = loadConfig();
} catch (error) {
  failConfig(error);
}

logConfig(config);

const server = new McpServer({
  name: "orchard-mcp",
  version: packageJson.version,
});

registerEnabledTools(server, config);

const transport = new StdioServerTransport();
await server.connect(transport);

// Reason: stderr only -- stdout is reserved for JSON-RPC in stdio transport.
console.error("[orchard-mcp] Server started via stdio transport.");
