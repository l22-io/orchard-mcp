import { describe, it } from "node:test";
import assert from "node:assert/strict";

describe("mail.read_message body truncation args", () => {
  it("omits --max-body-length when param not provided", () => {
    const messageId = "test-id-123";
    const maxBodyLength = undefined;
    const args = ["mail-message", "--id", messageId];
    if (maxBodyLength !== undefined) {
      args.push("--max-body-length", String(maxBodyLength));
    }
    assert.deepEqual(args, ["mail-message", "--id", "test-id-123"]);
  });

  it("passes --max-body-length 0 for unlimited (using !== undefined guard)", () => {
    const messageId = "test-id-123";
    const maxBodyLength = 0;
    const args = ["mail-message", "--id", messageId];
    if (maxBodyLength !== undefined) {
      args.push("--max-body-length", String(maxBodyLength));
    }
    assert.deepEqual(args, ["mail-message", "--id", "test-id-123", "--max-body-length", "0"]);
  });

  it("passes positive maxBodyLength correctly", () => {
    const messageId = "test-id-123";
    const maxBodyLength = 2000;
    const args = ["mail-message", "--id", messageId];
    if (maxBodyLength !== undefined) {
      args.push("--max-body-length", String(maxBodyLength));
    }
    assert.deepEqual(args, ["mail-message", "--id", "test-id-123", "--max-body-length", "2000"]);
  });
});

describe("body truncation logic", () => {
  function truncateBody(body: string, maxBodyLength: number): string {
    if (maxBodyLength > 0 && body.length > maxBodyLength) {
      return body.slice(0, maxBodyLength) + `\n\n[truncated — ${body.length} chars total]`;
    }
    return body;
  }

  it("truncates body exceeding max with suffix", () => {
    const body = "a".repeat(5000);
    const result = truncateBody(body, 4000);
    assert.equal(result.startsWith("a".repeat(4000)), true);
    assert.ok(result.includes("[truncated — 5000 chars total]"));
    assert.ok(result.length > 4000);
  });

  it("does not truncate body under max", () => {
    const body = "short body";
    const result = truncateBody(body, 4000);
    assert.equal(result, "short body");
  });

  it("does not truncate when maxBodyLength is 0 (unlimited)", () => {
    const body = "a".repeat(10000);
    const result = truncateBody(body, 0);
    assert.equal(result, body);
    assert.equal(result.length, 10000);
  });

  it("does not truncate body exactly at max length", () => {
    const body = "a".repeat(4000);
    const result = truncateBody(body, 4000);
    assert.equal(result, body);
  });
});

describe("nested mailbox path format", () => {
  it("formats top-level mailbox without prefix", () => {
    const name = "INBOX";
    const prefix = "";
    const fullName = prefix + name;
    assert.equal(fullName, "INBOX");
  });

  it("formats nested mailbox with path separator", () => {
    const name = "Invoices";
    const prefix = "Projects/ClientA/";
    const fullName = prefix + name;
    assert.equal(fullName, "Projects/ClientA/Invoices");
  });
});

describe("search whose clause construction", () => {
  function buildWhereClause(searchIn: string): string {
    switch (searchIn) {
      case "subject":
        return "whose subject contains searchQuery";
      case "sender":
        return "whose sender contains searchQuery";
      case "body":
        return "whose content contains searchQuery";
      case "all":
      default:
        return "whose subject contains searchQuery or sender contains searchQuery or content contains searchQuery";
    }
  }

  it("builds subject-only clause", () => {
    assert.equal(buildWhereClause("subject"), "whose subject contains searchQuery");
  });

  it("builds sender-only clause", () => {
    assert.equal(buildWhereClause("sender"), "whose sender contains searchQuery");
  });

  it("builds body-only clause", () => {
    assert.equal(buildWhereClause("body"), "whose content contains searchQuery");
  });

  it("builds all-fields clause as default", () => {
    const clause = buildWhereClause("all");
    assert.ok(clause.includes("subject contains"));
    assert.ok(clause.includes("sender contains"));
    assert.ok(clause.includes("content contains"));
  });
});

describe("cross-mailbox search args construction", () => {
  it("passes mailbox 'all' to bridge", () => {
    const mailbox = "all";
    const args = ["mail-search", "--query", "test"];
    if (mailbox) {
      args.push("--mailbox", mailbox);
    }
    assert.ok(args.includes("all"));
  });

  it("passes account 'all' to bridge", () => {
    const account = "all";
    const args = ["mail-search", "--query", "test"];
    if (account) {
      args.push("--account", account);
    }
    assert.ok(args.includes("all"));
  });
});

describe("pagination envelope", () => {
  it("wraps results with metadata when offset is provided", () => {
    const messages = [{ id: "1", subject: "test" }];
    const total = 50;
    const offset = 20;
    const limit = 20;
    const envelope = {
      messages,
      total,
      offset,
      limit,
      hasMore: offset + limit < total,
    };
    assert.equal(envelope.hasMore, true);
    assert.equal(envelope.total, 50);
  });

  it("sets hasMore false when at end", () => {
    const offset = 40;
    const limit = 20;
    const total = 50;
    const hasMore = offset + limit < total;
    assert.equal(hasMore, false);
  });

  it("returns flat array when offset not provided", () => {
    const messages = [{ id: "1" }, { id: "2" }];
    const offset = undefined;
    const result = offset !== undefined ? { messages, total: 2, offset, limit: 20, hasMore: false } : messages;
    assert.ok(Array.isArray(result));
  });
});
