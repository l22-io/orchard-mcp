import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { appendMailLocatorArgs, requireMailLocator } from "../mailSafety.js";
import { OPERATION_PROFILES, safeBridgeData } from "../safety.js";

export function registerMailTools(server: McpServer): void {
  server.tool(
    "mail.list_accounts",
    "List all Apple Mail accounts with their mailboxes and unread counts. Requires Mail.app to be running.",
    {},
    async () => {
      const data = await safeBridgeData(
        ["mail-accounts"],
        OPERATION_PROFILES.mailMetadata
      );
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
        .int()
        .min(1)
        .max(200)
        .optional()
        .describe(
          "Max unread messages to return per account (default: 10, max: 200)"
        ),
    },
    async ({ limit }) => {
      const args = ["mail-unread"];
      if (limit) {
        args.push("--limit", String(limit));
      }
      const data = await safeBridgeData(args, OPERATION_PROFILES.mailScan);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "mail.search",
    "Search email messages by subject, sender, body, or all fields (default: all). Returns headers only (no body). " +
      "SCOPE RULE: body or all-fields search across mailbox='all' AND no specific account is REFUSED — it can lock " +
      "Mail.app for minutes. Narrow the scope: pick a specific account, a specific mailbox, or set searchIn to " +
      "'subject' or 'sender' before using mailbox='all'.",
    {
      query: z
        .string()
        .describe("Search term to match against message fields (controlled by searchIn)"),
      account: z
        .string()
        .optional()
        .describe("Optional account name to filter by"),
      mailbox: z
        .string()
        .optional()
        .describe("Mailbox to search in (default: inbox). Use 'all' to search all mailboxes (requires a specific account when searchIn includes body)."),
      searchIn: z
        .enum(["subject", "sender", "body", "all"])
        .optional()
        .describe("Fields to search: subject, sender, body, or all (default: all). Use 'subject' or 'sender' when searching across mailbox='all' without an account filter."),
      limit: z
        .number()
        .int()
        .min(1)
        .max(200)
        .optional()
        .describe("Max results to return (default: 20, max: 200)"),
      offset: z
        .number()
        .int()
        .min(0)
        .optional()
        .describe(
          "Number of results to skip (default: 0). Use with limit for pagination. When provided, response includes total count and hasMore flag."
        ),
    },
    async ({ query, account, mailbox, searchIn, limit, offset }) => {
      const args = ["mail-search", "--query", query];
      if (account) {
        args.push("--account", account);
      }
      if (mailbox) {
        args.push("--mailbox", mailbox);
      }
      if (searchIn) {
        args.push("--search-in", searchIn);
      }
      if (limit) {
        args.push("--limit", String(limit));
      }
      if (offset !== undefined) {
        args.push("--offset", String(offset));
      }
      const data = await safeBridgeData(args, OPERATION_PROFILES.mailScan);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "mail.read_message",
    "Get the full content of an email message by its message ID (from mail.search or mail.unread_summary). Pass account and mailbox from the search result when available so Mail.app can open the message without scanning every mailbox. Returns subject, sender, date, body, to, cc, and attachments (name, MIME type, index for use with mail.save_attachment).",
    {
      messageId: z
        .string()
        .describe("Message ID (from mail.search or mail.unread_summary results)"),
      account: z
        .string()
        .optional()
        .describe("Mail account name from the message search/list result"),
      mailbox: z
        .string()
        .optional()
        .describe("Mailbox name/path from the message search/list result"),
      maxBodyLength: z
        .number()
        .int()
        .min(0)
        .max(1_000_000)
        .optional()
        .describe("Max body characters to return (default: 4000, max: 1_000_000). Use 0 for unlimited."),
    },
    async ({ messageId, account, mailbox, maxBodyLength }) => {
      const args = ["mail-message", "--id", messageId];
      appendMailLocatorArgs(args, { account, mailbox });
      if (maxBodyLength !== undefined) {
        args.push("--max-body-length", String(maxBodyLength));
      }
      const data = await safeBridgeData(args, OPERATION_PROFILES.mailMetadata);
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
      const data = await safeBridgeData(args, OPERATION_PROFILES.mailWrite);
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
        .int()
        .min(1)
        .max(200)
        .optional()
        .describe("Max results to return (default: 20, max: 200)"),
      offset: z
        .number()
        .int()
        .min(0)
        .optional()
        .describe(
          "Number of results to skip (default: 0). Use with limit for pagination. When provided, response includes total count and hasMore flag."
        ),
    },
    async ({ limit, offset }) => {
      const args = ["mail-flagged"];
      if (limit) {
        args.push("--limit", String(limit));
      }
      if (offset !== undefined) {
        args.push("--offset", String(offset));
      }
      const data = await safeBridgeData(args, OPERATION_PROFILES.mailScan);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "mail.save_attachment",
    "Save an email attachment to disk. Requires account and mailbox from the message search/list result so Mail.app does not scan every mailbox by message ID. Use mail.read_message first to see available attachments and their indices. Returns the saved file path. Requires Mail.app to be running.",
    {
      messageId: z
        .string()
        .describe("Message ID (from mail.search or mail.read_message results)"),
      account: z
        .string()
        .optional()
        .describe("Mail account name from the message search/list result"),
      mailbox: z
        .string()
        .optional()
        .describe("Mailbox name/path from the message search/list result"),
      index: z
        .number()
        .int()
        .min(0)
        .describe("Attachment index (0-based, from mail.read_message attachments array)"),
      path: z
        .string()
        .optional()
        .describe("Output directory (default: /tmp/orchard-mcp-attachments)"),
    },
    async ({ messageId, account, mailbox, index, path }) => {
      requireMailLocator("mail.save_attachment", { account, mailbox });
      const args = [
        "mail-save-attachment",
        "--id",
        messageId,
        "--index",
        String(index),
      ];
      appendMailLocatorArgs(args, { account, mailbox });
      if (path) {
        args.push("--path", path);
      }
      const data = await safeBridgeData(args, OPERATION_PROFILES.mailWrite);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
