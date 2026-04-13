import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { bridgeData } from "../bridge.js";

export function registerPagesTools(server: McpServer): void {
  server.tool(
    "pages.search",
    "Search for Pages document files by name or content.",
    {
      query: z.string().describe("Search term to match against file names or content"),
      limit: z
        .number()
        .optional()
        .describe("Maximum number of results to return"),
    },
    async ({ query, limit }) => {
      const args = ["pages-search", "--query", query];
      if (limit !== undefined) {
        args.push("--limit", String(limit));
      }
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "pages.read",
    "Read the body text from a Pages document.",
    {
      file: z.string().describe("Path to the Pages file"),
    },
    async ({ file }) => {
      const data = await bridgeData(["pages-read", "--file", file]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "pages.write",
    "Set the body text of a Pages document.",
    {
      file: z.string().describe("Path to the Pages file"),
      text: z.string().describe("Text to write as the document body"),
    },
    async ({ file, text }) => {
      const data = await bridgeData([
        "pages-write",
        "--file",
        file,
        "--text",
        text,
      ]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "pages.create",
    "Create a new Pages document. Optionally provide initial text or a template.",
    {
      file: z.string().describe("Path for the new Pages file"),
      text: z
        .string()
        .optional()
        .describe("Initial body text for the document"),
      template: z
        .string()
        .optional()
        .describe("Template name or path to use"),
    },
    async ({ file, text, template }) => {
      const args = ["pages-create", "--file", file];
      if (text) args.push("--text", text);
      if (template) args.push("--template", template);
      const result = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
      };
    }
  );

  server.tool(
    "pages.find_replace",
    "Find and replace text in a Pages document.",
    {
      file: z.string().describe("Path to the Pages file"),
      find: z.string().describe("Text to search for"),
      replace: z.string().describe("Replacement text"),
      all: z
        .boolean()
        .optional()
        .describe("Replace all occurrences (default: false, replaces first only)"),
    },
    async ({ file, find, replace, all }) => {
      const args = [
        "pages-find-replace",
        "--file",
        file,
        "--find",
        find,
        "--replace",
        replace,
      ];
      if (all) args.push("--all");
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "pages.insert_table",
    "Insert a table into a Pages document from JSON data.",
    {
      file: z.string().describe("Path to the Pages file"),
      data: z
        .string()
        .describe("Table data as JSON array of arrays (e.g. [[\"Name\",\"Age\"],[\"Alice\",30]])"),
      position: z
        .string()
        .optional()
        .describe("Insert position (beginning or end)"),
    },
    async ({ file, data: tableData, position }) => {
      const args = ["pages-insert-table", "--file", file, "--data", tableData];
      if (position) args.push("--position", position);
      const result = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
      };
    }
  );

  server.tool(
    "pages.list_sections",
    "List sections in a Pages document with preview text and word counts.",
    {
      file: z.string().describe("Path to the Pages file"),
    },
    async ({ file }) => {
      const data = await bridgeData(["pages-list-sections", "--file", file]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "pages.export",
    "Export a Pages document to another format (PDF, Word, TXT, or EPUB).",
    {
      file: z.string().describe("Path to the Pages file"),
      format: z
        .enum(["pdf", "docx", "txt", "epub"])
        .describe("Export format: pdf, docx, txt, or epub"),
      output: z
        .string()
        .optional()
        .describe("Output file path (defaults to same directory as input)"),
    },
    async ({ file, format, output }) => {
      const args = ["pages-export", "--file", file, "--format", format];
      if (output) args.push("--output", output);
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "pages.info",
    "Get metadata about a Pages document (name, word count, page count).",
    {
      file: z.string().describe("Path to the Pages file"),
    },
    async ({ file }) => {
      const data = await bridgeData(["pages-info", "--file", file]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
