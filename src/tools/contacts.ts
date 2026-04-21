import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { bridgeData } from "../bridge.js";

export function registerContactsTools(server: McpServer): void {
  server.tool(
    "contacts.list_groups",
    "List all contact groups with member counts. Requires Contacts access.",
    {},
    async () => {
      const data = await bridgeData(["contacts-groups"]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "contacts.search",
    "Search contacts by name, email, or phone number. Phone queries (starting with + or a digit) match full numbers via the Contacts framework predicate and partial numbers via a digits-only substring scan — spaces, dashes, and parentheses are ignored in the comparison. Email queries should contain @. Returns summaries; use contacts.read_contact for full details.",
    {
      query: z.string().describe("Name, email, or phone query"),
      limit: z
        .number()
        .int()
        .min(1)
        .max(200)
        .optional()
        .describe("Max results (default: 20, max: 200)"),
    },
    async ({ query, limit }) => {
      const args = ["contacts-search", "--query", query];
      if (limit) args.push("--limit", String(limit));
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "contacts.read_contact",
    "Read full details for a contact by ID (from contacts.search). Includes emails, phones, postal addresses, URLs, birthday, and job info. Note: the 'notes' field on contacts requires a restricted Apple entitlement and is not returned.",
    {
      id: z.string().describe("Contact identifier"),
    },
    async ({ id }) => {
      const data = await bridgeData(["contacts-read", "--id", id]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
