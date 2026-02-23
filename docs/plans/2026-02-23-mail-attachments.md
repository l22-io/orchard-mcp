# Mail Attachments Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Surface attachment metadata in mail listing tools and add a tool to save attachments to disk.

**Architecture:** Extend existing AppleScript-based mail bridge. Add `count of mail attachments` to listing scripts, full attachment enumeration to readMessage, and a new `saveAttachment` method that uses AppleScript's `save` command to write attachments to `/tmp/apple-mcp-attachments/`.

**Tech Stack:** Swift (ArgumentParser, AppleScript via osascript), TypeScript (MCP SDK, Zod)

---

### Task 1: Add attachment count to mail-search

**Files:**
- Modify: `swift/Sources/AppleBridge/Mail.swift` (search method, ~line 98-135; parseMessageList, ~line 375-392)

**Step 1: Update search AppleScript to include attachment count**

In the `search()` method, add attachment count retrieval to the message loop. Change the `repeat with i` block to also get `count of mail attachments of msg` and append it as an additional `|||`-delimited field:

```swift
set end of resultList to msgId & "|||" & msgSubject & "|||" & msgSender & "|||" & msgDate & "|||" & (msgRead as string) & "|||" & (msgFlagged as string) & "|||" & ((count of mail attachments of msg) as string)
```

**Step 2: Update parseMessageList to extract attachment fields**

Add attachment parsing after the existing fields:

```swift
if fields.count > 6 {
    let count = Int(fields[6].trimmingCharacters(in: .whitespaces)) ?? 0
    msg["attachmentCount"] = count
    msg["hasAttachments"] = count > 0
}
```

**Step 3: Build and verify**

```bash
cd swift && swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Sources/AppleBridge/Info.plist
./swift/.build/release/apple-bridge mail-search --query "test" --limit 3
```

Expected: Each message in output includes `attachmentCount` and `hasAttachments` fields.

**Step 4: Commit**

```bash
git add swift/Sources/AppleBridge/Mail.swift
git commit -m "feat(mail): add attachment count to search results"
```

---

### Task 2: Add attachment count to mail-unread

**Files:**
- Modify: `swift/Sources/AppleBridge/Mail.swift` (unreadSummary method, ~line 51-95; parseUnreadSummary, ~line 339-373)

**Step 1: Update unreadSummary AppleScript**

In the message loop inside `unreadSummary()`, add attachment count. Change the `set end of msgList to` line:

```swift
set end of msgList to msgId & "|||" & msgSubject & "|||" & msgSender & "|||" & msgDate & "|||" & (msgFlagged as string) & "|||" & ((count of mail attachments of msg) as string)
```

**Step 2: Update parseUnreadSummary to extract attachment fields**

In the message-parsing section, after the `flagged` field:

```swift
if fields.count > 5 {
    let count = Int(fields[5].trimmingCharacters(in: .whitespaces)) ?? 0
    msg["attachmentCount"] = count
    msg["hasAttachments"] = count > 0
}
```

**Step 3: Build and verify**

```bash
cd swift && swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Sources/AppleBridge/Info.plist
./swift/.build/release/apple-bridge mail-unread --limit 3
```

Expected: Each message in `recentUnread` includes `attachmentCount` and `hasAttachments`.

**Step 4: Commit**

```bash
git add swift/Sources/AppleBridge/Mail.swift
git commit -m "feat(mail): add attachment count to unread summary"
```

---

### Task 3: Add attachment count to mail-flagged

**Files:**
- Modify: `swift/Sources/AppleBridge/Mail.swift` (flagged method, ~line 179-215; parseFlaggedList, ~line 394-411)

**Step 1: Update flagged AppleScript**

In the `flagged()` method's message loop, add attachment count:

```swift
set end of resultList to msgId & "|||" & msgSubject & "|||" & msgSender & "|||" & msgDate & "|||" & (name of acct) & "|||" & ((count of mail attachments of msg) as string)
```

**Step 2: Update parseFlaggedList**

After the `account` field:

```swift
if fields.count > 5 {
    let count = Int(fields[5].trimmingCharacters(in: .whitespaces)) ?? 0
    msg["attachmentCount"] = count
    msg["hasAttachments"] = count > 0
}
```

**Step 3: Build and verify**

```bash
cd swift && swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Sources/AppleBridge/Info.plist
./swift/.build/release/apple-bridge mail-flagged --limit 3
```

**Step 4: Commit**

```bash
git add swift/Sources/AppleBridge/Mail.swift
git commit -m "feat(mail): add attachment count to flagged results"
```

---

### Task 4: Add full attachment list to mail-message (readMessage)

**Files:**
- Modify: `swift/Sources/AppleBridge/Mail.swift` (readMessage method, ~line 137-176)

**Step 1: Update readMessage AppleScript**

Replace the readMessage script to also enumerate attachments. After fetching `msgCc`, add attachment enumeration:

```swift
let script = """
tell application "Mail"
    set targetMsg to first message of inbox whose message id is "\(escapedId)"
    set msgSubject to subject of targetMsg
    set msgSender to sender of targetMsg
    set msgDate to date received of targetMsg as «class isot» as string
    set msgRead to read status of targetMsg
    set msgFlagged to flagged status of targetMsg
    set msgContent to content of targetMsg
    set msgTo to address of every to recipient of targetMsg
    set msgCc to address of every cc recipient of targetMsg
    set attachList to {}
    repeat with att in every mail attachment of targetMsg
        set attName to name of att
        set attMime to MIME type of att
        set end of attachList to attName & ":::" & attMime
    end repeat
    return msgSubject & "|||" & msgSender & "|||" & msgDate & "|||" & (msgRead as string) & "|||" & (msgFlagged as string) & "|||" & msgContent & "|||" & (msgTo as string) & "|||" & (msgCc as string) & "|||" & (my joinList(attachList, "^^^"))
end tell

on joinList(theList, delim)
    set oldDelim to AppleScript's text item delimiters
    set AppleScript's text item delimiters to delim
    set theResult to theList as string
    set AppleScript's text item delimiters to oldDelim
    return theResult
end joinList
"""
```

**Step 2: Update readMessage parser**

After the `cc` field, parse attachments:

```swift
if parts.count > 8 && !parts[8].isEmpty {
    let attachStrings = parts[8].components(separatedBy: "^^^")
    let attachments: [[String: Any]] = attachStrings.enumerated().compactMap { (idx, attStr) in
        let fields = attStr.components(separatedBy: ":::")
        guard fields.count >= 2 else { return nil }
        return [
            "index": idx,
            "name": fields[0],
            "mimeType": fields[1]
        ]
    }
    message["attachments"] = attachments
    message["attachmentCount"] = attachments.count
    message["hasAttachments"] = !attachments.isEmpty
} else {
    message["attachments"] = [] as [[String: Any]]
    message["attachmentCount"] = 0
    message["hasAttachments"] = false
}
```

**Step 3: Build and verify**

```bash
cd swift && swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Sources/AppleBridge/Info.plist
./swift/.build/release/apple-bridge mail-message --id "<some-message-id-with-attachment>"
```

Expected: Output includes `attachments` array with `index`, `name`, `mimeType` entries.

**Step 4: Commit**

```bash
git add swift/Sources/AppleBridge/Mail.swift
git commit -m "feat(mail): add attachment list to read_message output"
```

---

### Task 5: Add saveAttachment Swift method

**Files:**
- Modify: `swift/Sources/AppleBridge/Mail.swift` (add new method after readMessage)

**Step 1: Add saveAttachment method**

Add after the `createDraft` method, before `// MARK: - AppleScript Execution`:

```swift
/// Save a specific attachment from a message to disk.
static func saveAttachment(messageId: String, index: Int, outputDir: String) {
    let escapedId = escapeForAppleScript(messageId)
    let resolvedDir: String
    if outputDir.hasPrefix("~") {
        resolvedDir = (outputDir as NSString).expandingTildeInPath
    } else {
        resolvedDir = outputDir
    }

    // Create output directory if needed
    let fm = FileManager.default
    if !fm.fileExists(atPath: resolvedDir) {
        do {
            try fm.createDirectory(atPath: resolvedDir, withIntermediateDirectories: true)
        } catch {
            JSONOutput.error("Failed to create output directory: \(error.localizedDescription)")
            return
        }
    }

    let escapedDir = escapeForAppleScript(resolvedDir)
    // AppleScript index is 1-based
    let asIndex = index + 1

    let script = """
    tell application "Mail"
        set targetMsg to first message of inbox whose message id is "\(escapedId)"
        set attList to every mail attachment of targetMsg
        if (count of attList) < \(asIndex) then
            return "ERROR:::Attachment index out of range. Message has " & ((count of attList) as string) & " attachments."
        end if
        set att to item \(asIndex) of attList
        set attName to name of att
        set attMime to MIME type of att
        set savePath to POSIX file "\(escapedDir)/" & attName
        save att in savePath
        return attName & ":::" & attMime & ":::" & POSIX path of savePath
    end tell
    """

    guard let raw = runAppleScript(script) else { return }

    if raw.hasPrefix("ERROR:::") {
        let errorMsg = String(raw.dropFirst("ERROR:::".count))
        JSONOutput.error(errorMsg)
        return
    }

    let fields = raw.components(separatedBy: ":::")
    guard fields.count >= 3 else {
        JSONOutput.error("Unexpected response format from Mail.app")
        return
    }

    let result: [String: Any] = [
        "name": fields[0],
        "mimeType": fields[1],
        "path": fields[2]
    ]
    JSONOutput.success(result)
}
```

**Step 2: Build**

```bash
cd swift && swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Sources/AppleBridge/Info.plist
```

**Step 3: Commit**

```bash
git add swift/Sources/AppleBridge/Mail.swift
git commit -m "feat(mail): add saveAttachment Swift method"
```

---

### Task 6: Add MailSaveAttachment subcommand

**Files:**
- Modify: `swift/Sources/AppleBridge/AppleBridge.swift` (add subcommand struct + register it)

**Step 1: Add subcommand struct**

Add after the `MailCreateDraft` struct (after ~line 221):

```swift
struct MailSaveAttachment: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mail-save-attachment",
        abstract: "Save a message attachment to disk."
    )

    @Option(name: .long, help: "Message ID (from mail-search or mail-unread)")
    var id: String

    @Option(name: .long, help: "Attachment index (0-based, from mail-message output)")
    var index: Int

    @Option(name: .long, help: "Output directory (default: /tmp/apple-mcp-attachments)")
    var path: String = "/tmp/apple-mcp-attachments"

    func run() async throws {
        MailBridge.saveAttachment(messageId: id, index: index, outputDir: path)
    }
}
```

**Step 2: Register in subcommands array**

Add `MailSaveAttachment.self` after `MailCreateDraft.self` in the `subcommands` array (~line 39).

**Step 3: Build and verify**

```bash
cd swift && swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Sources/AppleBridge/Info.plist
./swift/.build/release/apple-bridge mail-save-attachment --help
```

Expected: Shows `--id`, `--index`, `--path` options.

**Step 4: Commit**

```bash
git add swift/Sources/AppleBridge/AppleBridge.swift
git commit -m "feat(mail): add mail-save-attachment subcommand"
```

---

### Task 7: Add mail.save_attachment MCP tool

**Files:**
- Modify: `src/tools/mail.ts` (add tool registration after mail.flagged)

**Step 1: Add tool registration**

After the `mail.flagged` tool block (after ~line 163), add:

```typescript
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
      .describe("Output directory (default: /tmp/apple-mcp-attachments)"),
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
```

**Step 2: Build TypeScript**

```bash
npx tsc
```

**Step 3: Commit**

```bash
git add src/tools/mail.ts
git commit -m "feat(mail): add mail.save_attachment MCP tool"
```

---

### Task 8: Update tool description for mail.read_message

**Files:**
- Modify: `src/tools/mail.ts` (~line 80)

**Step 1: Update description**

Change the `mail.read_message` description to mention attachments:

```typescript
"Get the full content of an email message by its message ID (from mail.search or mail.unread_summary). Returns subject, sender, date, body, to, cc, and attachments (name, MIME type, index for use with mail.save_attachment).",
```

**Step 2: Build TypeScript**

```bash
npx tsc
```

**Step 3: Commit**

```bash
git add src/tools/mail.ts
git commit -m "feat(mail): update read_message description to mention attachments"
```

---

### Task 9: Full integration test

**Step 1: Rebuild everything**

```bash
cd swift && swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Sources/AppleBridge/Info.plist && cd .. && npx tsc
```

**Step 2: Test listing tools show attachment counts**

```bash
./swift/.build/release/apple-bridge mail-search --query "." --limit 2
./swift/.build/release/apple-bridge mail-unread --limit 2
./swift/.build/release/apple-bridge mail-flagged --limit 2
```

Verify: Each message has `attachmentCount` and `hasAttachments` fields.

**Step 3: Test read_message with attachment details**

Find a message ID from step 2, then:

```bash
./swift/.build/release/apple-bridge mail-message --id "<message-id>"
```

Verify: Output includes `attachments` array. For messages with attachments, entries have `index`, `name`, `mimeType`.

**Step 4: Test save_attachment**

If a message has attachments:

```bash
./swift/.build/release/apple-bridge mail-save-attachment --id "<message-id>" --index 0
ls /tmp/apple-mcp-attachments/
```

Verify: File exists at the returned path.

**Step 5: Test error case -- invalid index**

```bash
./swift/.build/release/apple-bridge mail-save-attachment --id "<message-id>" --index 999
```

Verify: Returns error status with "index out of range" message.

**Step 6: Update CLAUDE.md mail tool count**

Update `mail.ts` description in CLAUDE.md from "6 tools" to "7 tools" and mention the new attachment capabilities.

**Step 7: Final commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for mail attachment tools"
```
