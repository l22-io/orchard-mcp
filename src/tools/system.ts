import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { OrchardConfig } from "../config.js";
import { OPERATION_PROFILES, safeBridgeData } from "../safety.js";

export function registerSystemTools(server: McpServer, _config: OrchardConfig): void {
  server.tool(
    "system.doctor",
    "Check orchard-mcp permissions status, list accessible Calendar accounts, Mail accounts, and Reminders status. Run this first to diagnose access issues.",
    {},
    async () => {
      const data = await safeBridgeData(
        ["doctor"],
        OPERATION_PROFILES.systemDoctor
      );
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
