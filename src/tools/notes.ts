import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { bridgeData } from "../bridge.js";

export function registerNotesTools(server: McpServer): void {
  server.tool(
    "notes.list_folders",
    "List all Notes folders grouped by account with note counts. Requires Notes.app to be running and Automation permission.",
    {},
    async () => {
      const data = await bridgeData(["notes-folders"]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "notes.list_notes",
    "List notes, optionally filtered by folder/account. Returns headers only (id, title, modified, folder). Requires Notes.app to be running.",
    {
      folder: z
        .string()
        .optional()
        .describe("Folder name to filter by"),
      account: z
        .string()
        .optional()
        .describe("Account name (use with folder when the folder name is ambiguous)"),
      limit: z
        .number()
        .int()
        .min(1)
        .max(200)
        .optional()
        .describe("Max results to return (default: 50, max: 200)"),
    },
    async ({ folder, account, limit }) => {
      const args = ["notes-list"];
      if (folder) args.push("--folder", folder);
      if (account) args.push("--account", account);
      if (limit) args.push("--limit", String(limit));
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "notes.search",
    "Search notes by title, body, or both. Returns headers only. Requires Notes.app to be running.",
    {
      query: z.string().describe("Search query"),
      searchIn: z
        .enum(["title", "body", "all"])
        .optional()
        .describe("Fields to search (default: all)"),
      limit: z
        .number()
        .int()
        .min(1)
        .max(200)
        .optional()
        .describe("Max results (default: 20, max: 200)"),
    },
    async ({ query, searchIn, limit }) => {
      const args = ["notes-search", "--query", query];
      if (searchIn) args.push("--search-in", searchIn);
      if (limit) args.push("--limit", String(limit));
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "notes.read_note",
    "Read a note's full plain-text body by ID (from notes.list_notes or notes.search). Returns title, body, timestamps, and folder.",
    {
      id: z.string().describe("Note ID"),
      maxBodyLength: z
        .number()
        .int()
        .min(0)
        .max(1_000_000)
        .optional()
        .describe("Max body characters (default: 8000, 0 = unlimited)"),
    },
    async ({ id, maxBodyLength }) => {
      const args = ["notes-read", "--id", id];
      if (maxBodyLength !== undefined) {
        args.push("--max-body-length", String(maxBodyLength));
      }
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
