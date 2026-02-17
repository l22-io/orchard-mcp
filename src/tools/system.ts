import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { bridgeData } from "../bridge.js";

export function registerSystemTools(server: McpServer): void {
  server.tool(
    "system.doctor",
    "Check apple-mcp permissions status, list accessible Calendar accounts, Mail accounts, and Reminders status. Run this first to diagnose access issues.",
    {},
    async () => {
      const data = await bridgeData(["doctor"]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
