import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { bridgeData } from "../bridge.js";

export function registerMailTools(server: McpServer): void {
  server.tool(
    "mail.list_accounts",
    "List all Apple Mail accounts with their mailboxes and unread counts. Requires Mail.app to be running.",
    {},
    async () => {
      const data = await bridgeData(["mail-accounts"]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "mail.unread_summary",
    "Get unread email summary across all accounts: unread count per account and recent unread message subjects/senders. Requires Mail.app to be running.",
    {
      limit: z
        .number()
        .optional()
        .describe(
          "Max unread messages to return per account (default: 10)"
        ),
    },
    async ({ limit }) => {
      const args = ["mail-unread"];
      if (limit) {
        args.push("--limit", String(limit));
      }
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "mail.search",
    "Search email messages by subject or sender text. Returns headers only (no body) for performance. Requires Mail.app to be running.",
    {
      query: z
        .string()
        .describe("Search term to match against message subject or sender"),
      account: z
        .string()
        .optional()
        .describe("Optional account name to filter by"),
      mailbox: z
        .string()
        .optional()
        .describe("Mailbox to search in (default: inbox)"),
      limit: z
        .number()
        .optional()
        .describe("Max results to return (default: 20)"),
    },
    async ({ query, account, mailbox, limit }) => {
      const args = ["mail-search", "--query", query];
      if (account) {
        args.push("--account", account);
      }
      if (mailbox) {
        args.push("--mailbox", mailbox);
      }
      if (limit) {
        args.push("--limit", String(limit));
      }
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "mail.read_message",
    "Get the full content of an email message by its message ID (from mail.search or mail.unread_summary). Returns subject, sender, date, body, to, cc, and attachments (name, MIME type, index for use with mail.save_attachment).",
    {
      messageId: z
        .string()
        .describe("Message ID (from mail.search or mail.unread_summary results)"),
    },
    async ({ messageId }) => {
      const data = await bridgeData(["mail-message", "--id", messageId]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "mail.create_draft",
    "Create a draft email in Mail.app. Opens a compose window for user review before sending. Requires Mail.app to be running.",
    {
      to: z
        .string()
        .describe("Recipient email addresses (comma-separated for multiple)"),
      subject: z.string().describe("Email subject line"),
      body: z.string().describe("Email body text"),
      cc: z
        .string()
        .optional()
        .describe("CC email addresses (comma-separated for multiple)"),
      bcc: z
        .string()
        .optional()
        .describe("BCC email addresses (comma-separated for multiple)"),
      account: z
        .string()
        .optional()
        .describe(
          "Sender email address (from mail.list_accounts). Uses default account if omitted."
        ),
    },
    async ({ to, subject, body, cc, bcc, account }) => {
      const args = [
        "mail-create-draft",
        "--to",
        to,
        "--subject",
        subject,
        "--body",
        body,
      ];
      if (cc) {
        args.push("--cc", cc);
      }
      if (bcc) {
        args.push("--bcc", bcc);
      }
      if (account) {
        args.push("--account", account);
      }
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "mail.flagged",
    "List flagged (starred) email messages across all accounts. Returns message headers. Requires Mail.app to be running.",
    {
      limit: z
        .number()
        .optional()
        .describe("Max results to return (default: 20)"),
    },
    async ({ limit }) => {
      const args = ["mail-flagged"];
      if (limit) {
        args.push("--limit", String(limit));
      }
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "mail.save_attachment",
    "Save an email attachment to disk. Use mail.read_message first to see available attachments and their indices. Returns the saved file path. Requires Mail.app to be running.",
    {
      messageId: z
        .string()
        .describe("Message ID (from mail.search or mail.read_message results)"),
      index: z
        .number()
        .describe("Attachment index (0-based, from mail.read_message attachments array)"),
      path: z
        .string()
        .optional()
        .describe("Output directory (default: /tmp/orchard-mcp-attachments)"),
    },
    async ({ messageId, index, path }) => {
      const args = [
        "mail-save-attachment",
        "--id",
        messageId,
        "--index",
        String(index),
      ];
      if (path) {
        args.push("--path", path);
      }
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
