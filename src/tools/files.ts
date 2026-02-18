import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { bridgeData } from "../bridge.js";

export function registerFileTools(server: McpServer): void {
  server.tool(
    "files.list",
    "List directory contents with metadata (name, size, dates, type). Paths relative to home directory.",
    {
      path: z
        .string()
        .optional()
        .describe("Directory path relative to ~ (default: home directory)"),
      recursive: z
        .boolean()
        .optional()
        .describe("List recursively (default: false)"),
      depth: z
        .number()
        .optional()
        .describe("Max recursion depth when recursive (default: 3)"),
    },
    async ({ path, recursive, depth }) => {
      const args = ["file-list"];
      if (path) args.push("--path", path);
      if (recursive) args.push("--recursive");
      if (depth !== undefined) args.push("--depth", String(depth));
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "files.info",
    "Get detailed metadata for a file or folder, including Spotlight attributes (content type, dimensions, authors, page count).",
    {
      path: z
        .string()
        .describe(
          "File path relative to ~ or absolute (must be under home directory)"
        ),
    },
    async ({ path }) => {
      const data = await bridgeData(["file-info", "--path", path]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "files.search",
    "Search files using macOS Spotlight. Searches file names and content across indexed volumes. Scoped to home directory.",
    {
      query: z
        .string()
        .describe(
          "Search query (Spotlight syntax, e.g. 'budget 2026' or 'kMDItemAuthor == \"John\"')"
        ),
      kind: z
        .enum([
          "folder",
          "image",
          "pdf",
          "document",
          "audio",
          "video",
          "presentation",
          "spreadsheet",
        ])
        .optional()
        .describe("Filter by file kind"),
      scope: z
        .string()
        .optional()
        .describe(
          "Subdirectory to search within (default: entire home directory)"
        ),
    },
    async ({ query, kind, scope }) => {
      const args = ["file-search", "--query", query];
      if (kind) args.push("--kind", kind);
      if (scope) args.push("--scope", scope);
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "files.read",
    "Read and extract text from a file. Handles plain text, PDF (via PDFKit), images (via OCR), and documents (.docx, .rtf, .pages via textutil). Text capped at 1MB.",
    {
      path: z
        .string()
        .describe(
          "File path relative to ~ or absolute (must be under home directory)"
        ),
    },
    async ({ path }) => {
      const data = await bridgeData(["file-read", "--path", path]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "files.move",
    "Move or rename files and folders. Supports batch operations for mass renaming. All paths must be under home directory.",
    {
      operations: z
        .array(
          z.object({
            source: z.string().describe("Source path"),
            destination: z.string().describe("Destination path"),
          })
        )
        .describe("Array of move operations ({source, destination} pairs)"),
    },
    async ({ operations }) => {
      const data = await bridgeData([
        "file-move",
        "--items",
        JSON.stringify(operations),
      ]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "files.copy",
    "Copy a file or folder to a new location. Both paths must be under home directory.",
    {
      source: z.string().describe("Source file or folder path"),
      destination: z.string().describe("Destination path"),
    },
    async ({ source, destination }) => {
      const data = await bridgeData([
        "file-copy",
        "--source",
        source,
        "--dest",
        destination,
      ]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "files.create_folder",
    "Create a new directory with intermediate directories. Path must be under home directory.",
    {
      path: z.string().describe("Directory path to create"),
    },
    async ({ path }) => {
      const data = await bridgeData(["file-create-folder", "--path", path]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "files.trash",
    "Move a file or folder to the Trash (reversible delete). Path must be under home directory.",
    {
      path: z.string().describe("File or folder path to move to Trash"),
    },
    async ({ path }) => {
      const data = await bridgeData(["file-trash", "--path", path]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
