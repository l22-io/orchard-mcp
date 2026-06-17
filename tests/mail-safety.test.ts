import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  appendMailLocatorArgs,
  requireMailLocator,
} from "../src/mailSafety.js";

const repoRoot = new URL("../", import.meta.url);

function readRepoFile(path: string): string {
  return readFileSync(new URL(path, repoRoot), "utf8");
}

function swiftFunctionBody(name: string): string {
  const source = readRepoFile("swift/Sources/AppleBridge/Mail.swift");
  const start = source.indexOf(`static func ${name}`);
  assert.notEqual(start, -1, `${name} should exist`);
  const next = source.indexOf("\n    ///", start + 1);
  return source.slice(start, next === -1 ? source.length : next);
}

describe("mail locator safety", () => {
  it("requires account and mailbox before saving an attachment", () => {
    assert.throws(
      () => requireMailLocator("mail.save_attachment", {}),
      /requires account and mailbox/
    );
    assert.throws(
      () => requireMailLocator("mail.save_attachment", { account: "Proton" }),
      /requires account and mailbox/
    );
    assert.doesNotThrow(() =>
      requireMailLocator("mail.save_attachment", {
        account: "Proton",
        mailbox: "INBOX",
      })
    );
  });

  it("passes account and mailbox locators through to the Swift bridge", () => {
    const args = ["mail-save-attachment", "--id", "abc", "--index", "0"];
    appendMailLocatorArgs(args, { account: "Proton", mailbox: "INBOX" });
    assert.deepEqual(args, [
      "mail-save-attachment",
      "--id",
      "abc",
      "--index",
      "0",
      "--account",
      "Proton",
      "--mailbox",
      "INBOX",
    ]);
  });

  it("does not let message lookup fall back to every mailbox of every account", () => {
    assert.doesNotMatch(swiftFunctionBody("readMessage"), /repeat with acct in every account/);
    assert.doesNotMatch(swiftFunctionBody("saveAttachment"), /repeat with acct in every account/);
  });

  it("keeps account listing bounded and metadata-only", () => {
    const body = swiftFunctionBody("listAccounts");

    assert.match(body, /set mailboxLimit to 50/);
    assert.doesNotMatch(body, /on listMailboxes/);
    assert.doesNotMatch(body, /unread count of mbox/);
  });
});
