import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { bridgeData } from "../bridge.js";

export function registerNumbersTools(server: McpServer): void {
  server.tool(
    "numbers.search",
    "Search for Numbers spreadsheet files by name or content.",
    {
      query: z.string().describe("Search term to match against file names or content"),
      limit: z
        .number()
        .optional()
        .describe("Maximum number of results to return"),
    },
    async ({ query, limit }) => {
      const args = ["numbers-search", "--query", query];
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
    "numbers.read",
    "Read data from a Numbers spreadsheet. Optionally specify sheet, table, and cell range.",
    {
      file: z.string().describe("Path to the Numbers file"),
      sheet: z.string().optional().describe("Sheet name to read from"),
      table: z.string().optional().describe("Table name to read from"),
      range: z.string().optional().describe("Cell range to read (e.g. A1:C10)"),
    },
    async ({ file, sheet, table, range }) => {
      const args = ["numbers-read", "--file", file];
      if (sheet) args.push("--sheet", sheet);
      if (table) args.push("--table", table);
      if (range) args.push("--range", range);
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "numbers.write",
    "Write data to a Numbers spreadsheet. Optionally specify sheet, table, and cell range.",
    {
      file: z.string().describe("Path to the Numbers file"),
      data: z.string().describe("Data to write (JSON-encoded rows/columns)"),
      sheet: z.string().optional().describe("Sheet name to write to"),
      table: z.string().optional().describe("Table name to write to"),
      range: z.string().optional().describe("Cell range to write to (e.g. A1)"),
    },
    async ({ file, data: writeData, sheet, table, range }) => {
      const args = ["numbers-write", "--file", file, "--data", writeData];
      if (sheet) args.push("--sheet", sheet);
      if (table) args.push("--table", table);
      if (range) args.push("--range", range);
      const result = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
      };
    }
  );

  server.tool(
    "numbers.create",
    "Create a new Numbers spreadsheet. Optionally provide initial data or a template.",
    {
      file: z.string().describe("Path for the new Numbers file"),
      data: z
        .string()
        .optional()
        .describe("Initial data to populate (JSON-encoded rows/columns)"),
      template: z
        .string()
        .optional()
        .describe("Template name or path to use"),
    },
    async ({ file, data: initialData, template }) => {
      const args = ["numbers-create", "--file", file];
      if (initialData) args.push("--data", initialData);
      if (template) args.push("--template", template);
      const result = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
      };
    }
  );

  server.tool(
    "numbers.list_sheets",
    "List all sheets in a Numbers spreadsheet.",
    {
      file: z.string().describe("Path to the Numbers file"),
    },
    async ({ file }) => {
      const data = await bridgeData(["numbers-list-sheets", "--file", file]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "numbers.add_sheet",
    "Add a new sheet to a Numbers spreadsheet.",
    {
      file: z.string().describe("Path to the Numbers file"),
      name: z.string().describe("Name for the new sheet"),
    },
    async ({ file, name }) => {
      const data = await bridgeData([
        "numbers-add-sheet",
        "--file",
        file,
        "--name",
        name,
      ]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "numbers.remove_sheet",
    "Remove a sheet from a Numbers spreadsheet.",
    {
      file: z.string().describe("Path to the Numbers file"),
      name: z.string().describe("Name of the sheet to remove"),
    },
    async ({ file, name }) => {
      const data = await bridgeData([
        "numbers-remove-sheet",
        "--file",
        file,
        "--name",
        name,
      ]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "numbers.get_formulas",
    "Get formulas from cells in a Numbers spreadsheet. Optionally specify sheet, table, and range.",
    {
      file: z.string().describe("Path to the Numbers file"),
      sheet: z.string().optional().describe("Sheet name"),
      table: z.string().optional().describe("Table name"),
      range: z.string().optional().describe("Cell range (e.g. A1:C10)"),
    },
    async ({ file, sheet, table, range }) => {
      const args = ["numbers-get-formulas", "--file", file];
      if (sheet) args.push("--sheet", sheet);
      if (table) args.push("--table", table);
      if (range) args.push("--range", range);
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "numbers.export",
    "Export a Numbers spreadsheet to another format (CSV, PDF, or XLSX).",
    {
      file: z.string().describe("Path to the Numbers file"),
      format: z
        .enum(["csv", "pdf", "xlsx"])
        .describe("Export format: csv, pdf, or xlsx"),
      output: z
        .string()
        .optional()
        .describe("Output file path (defaults to same directory as input)"),
    },
    async ({ file, format, output }) => {
      const args = ["numbers-export", "--file", file, "--format", format];
      if (output) args.push("--output", output);
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "numbers.info",
    "Get metadata and summary information about a Numbers spreadsheet.",
    {
      file: z.string().describe("Path to the Numbers file"),
    },
    async ({ file }) => {
      const data = await bridgeData(["numbers-info", "--file", file]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
