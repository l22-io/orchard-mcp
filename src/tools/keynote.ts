import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { bridgeData } from "../bridge.js";

export function registerKeynoteTools(server: McpServer): void {
  server.tool(
    "keynote.search",
    "Search for Keynote presentation files by name.",
    {
      query: z.string().max(500).describe("Search term to match against file names"),
      limit: z
        .number()
        .int()
        .min(1)
        .max(100)
        .optional()
        .describe("Maximum number of results to return"),
    },
    async ({ query, limit }) => {
      const args = ["keynote-search", "--query", query];
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
    "keynote.read",
    "Read slide content from a Keynote presentation (title, body, notes, layout, skipped status).",
    {
      file: z.string().max(1024).describe("Path to the Keynote file"),
      slide: z
        .number()
        .int()
        .min(1)
        .optional()
        .describe("Slide index to read (1-based). Omit to read all slides."),
    },
    async ({ file, slide }) => {
      const args = ["keynote-read", "--file", file];
      if (slide !== undefined) {
        args.push("--slide", String(slide));
      }
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "keynote.create",
    "Create a new Keynote presentation. Optionally specify a theme.",
    {
      file: z.string().max(1024).describe("Path for the new Keynote file"),
      theme: z
        .string()
        .max(10_000)
        .optional()
        .describe("Theme name to use for the presentation"),
    },
    async ({ file, theme }) => {
      const args = ["keynote-create", "--file", file];
      if (theme) args.push("--theme", theme);
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "keynote.add_slide",
    "Add a new slide to a Keynote presentation with optional layout, title, body, notes, and position.",
    {
      file: z.string().max(1024).describe("Path to the Keynote file"),
      layout: z
        .string()
        .max(10_000)
        .optional()
        .describe("Slide layout name (from the theme)"),
      title: z.string().max(10_000).optional().describe("Slide title text"),
      body: z.string().max(10_000).optional().describe("Slide body text"),
      notes: z.string().max(10_000).optional().describe("Presenter notes"),
      position: z
        .number()
        .int()
        .min(1)
        .optional()
        .describe("Insert after this slide index (1-based). Omit to add at end."),
    },
    async ({ file, layout, title, body, notes, position }) => {
      const args = ["keynote-add-slide", "--file", file];
      if (layout) args.push("--layout", layout);
      if (title) args.push("--title", title);
      if (body) args.push("--body", body);
      if (notes) args.push("--notes", notes);
      if (position !== undefined) args.push("--position", String(position));
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "keynote.edit_slide",
    "Edit an existing slide's title, body, or presenter notes.",
    {
      file: z.string().max(1024).describe("Path to the Keynote file"),
      slide: z.number().int().min(1).describe("Slide index to edit (1-based)"),
      title: z.string().max(10_000).optional().describe("New title text"),
      body: z.string().max(10_000).optional().describe("New body text"),
      notes: z.string().max(10_000).optional().describe("New presenter notes"),
    },
    async ({ file, slide, title, body, notes }) => {
      const args = [
        "keynote-edit-slide",
        "--file",
        file,
        "--slide",
        String(slide),
      ];
      if (title) args.push("--title", title);
      if (body) args.push("--body", body);
      if (notes) args.push("--notes", notes);
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "keynote.remove_slide",
    "Delete a slide from a Keynote presentation.",
    {
      file: z.string().max(1024).describe("Path to the Keynote file"),
      slide: z.number().int().min(1).describe("Slide index to remove (1-based)"),
    },
    async ({ file, slide }) => {
      const data = await bridgeData([
        "keynote-remove-slide",
        "--file",
        file,
        "--slide",
        String(slide),
      ]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "keynote.reorder_slides",
    "Move a slide from one position to another in a Keynote presentation.",
    {
      file: z.string().max(1024).describe("Path to the Keynote file"),
      from: z.number().int().min(1).describe("Current slide index (1-based)"),
      to: z.number().int().min(1).describe("Target slide index (1-based)"),
    },
    async ({ file, from, to }) => {
      const data = await bridgeData([
        "keynote-reorder-slides",
        "--file",
        file,
        "--from",
        String(from),
        "--to",
        String(to),
      ]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "keynote.list_slides",
    "List all slides in a Keynote presentation with their content and metadata.",
    {
      file: z.string().max(1024).describe("Path to the Keynote file"),
    },
    async ({ file }) => {
      const data = await bridgeData(["keynote-list-slides", "--file", file]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "keynote.list_themes",
    "List all available Keynote themes.",
    {},
    async () => {
      const data = await bridgeData(["keynote-list-themes"]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "keynote.export",
    "Export a Keynote presentation to PDF, PowerPoint, PNG, or JPEG.",
    {
      file: z.string().max(1024).describe("Path to the Keynote file"),
      format: z
        .enum(["pdf", "pptx", "png", "jpeg"])
        .describe("Export format: pdf, pptx, png, or jpeg"),
      dest: z
        .string()
        .max(1024)
        .optional()
        .describe("Output file or directory path (defaults to same directory as input)"),
      slide: z
        .number()
        .int()
        .min(1)
        .optional()
        .describe("Export only this slide index (1-based, for image formats)"),
    },
    async ({ file, format, dest, slide }) => {
      const args = ["keynote-export", "--file", file, "--format", format];
      if (dest) args.push("--dest", dest);
      if (slide !== undefined) args.push("--slide", String(slide));
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "keynote.info",
    "Get metadata about a Keynote presentation (name, slide count, theme).",
    {
      file: z.string().max(1024).describe("Path to the Keynote file"),
    },
    async ({ file }) => {
      const data = await bridgeData(["keynote-info", "--file", file]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
