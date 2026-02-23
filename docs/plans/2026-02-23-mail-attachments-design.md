# Mail Attachments Design

## Summary

Extend the mail tools to surface attachment metadata in listing tools and provide full attachment details when reading messages. Add a new tool to save attachments to disk.

## Scope

1. **Attachment metadata in listings** -- Add `hasAttachments` (bool) and `attachmentCount` (int) to search, unread summary, and flagged results.
2. **Full attachment list in read_message** -- Include an `attachments` array with `name` and `mimeType` for each attachment.
3. **New `mail.save_attachment` tool** -- Save a specific attachment to disk by message ID and 0-based index. Default output directory: `/tmp/apple-mcp-attachments/`.

## Architecture

Same two-layer pattern as existing mail tools: AppleScript queries Mail.app attachment properties, Swift parses delimited output, TypeScript exposes MCP tools.

Mail.app AppleScript dictionary exposes `mail attachment` objects on messages with `name`, `MIME type` properties and a `save` command.

## Changes

### Swift: Mail.swift

- `unreadSummary()`, `search()`, `flagged()`: Add `count of mail attachments of msg` to the delimited output for each message.
- `readMessage()`: Add attachment list (name, MIME type per attachment) to output.
- New `saveAttachment(messageId:index:outputDir:)`: Find message, get attachment at index, create output dir, use AppleScript `save` to write file, return `{ name, mimeType, path }`.
- `readMessage` currently only searches inbox. `saveAttachment` uses the same approach.

### Swift: AppleBridge.swift

- New `MailSaveAttachment` subcommand with `--id`, `--index`, `--path` options.

### TypeScript: mail.ts

- New `mail.save_attachment` tool registration with `messageId`, `index`, `path` parameters.

### Delimiter conventions

Attachment metadata in listings uses the existing `|||` field separator. Attachment list in readMessage uses `^^^` between attachments and `:::` between fields within each attachment (name:::mimeType).

## Files Touched

- `swift/Sources/AppleBridge/Mail.swift`
- `swift/Sources/AppleBridge/AppleBridge.swift`
- `src/tools/mail.ts`
