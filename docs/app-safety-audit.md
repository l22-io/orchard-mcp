# App Safety Audit

orchard-mcp must protect the user's Mac first. A tool call is allowed to return less data or refuse an unsafe scope; it must not make Mail.app, Notes, Numbers, Pages, Keynote, Contacts, Calendar, Reminders, Spotlight, OCR, or the rest of the system unresponsive.

## Safety Policy

- All TypeScript tool handlers call `safeBridgeData(args, OPERATION_PROFILES.<profile>)`, never `bridgeData` directly.
- `OPERATION_PROFILES` in `src/safety.ts` assigns each operation to a lane, timeout, queue budget, and output-byte budget.
- GUI app lanes are serialized. Mail.app, Notes, Numbers, Pages, and Keynote each get one in-flight operation per lane.
- If an app lane is already busy past its queue budget, orchard-mcp refuses the new call before it touches the host app.
- Broad scopes are rejected before AppleScript/JXA, EventKit, Contacts, Spotlight, OCR, or file subprocesses start.
- `src/bridge.ts` enforces both timeout and output-size budgets when running `apple-bridge`.

## Current Risk Inventory

| Area | Host dependency | Guardrail |
| --- | --- | --- |
| Mail | Mail.app via AppleScript | `mail.save_attachment` requires account and mailbox locators. `mail.read_message` no longer scans every mailbox by default. `mail.list_accounts` returns bounded mailbox metadata without recursive unread counts. Broad body/all-field all-account all-mailbox search is refused. |
| Notes | Notes via AppleScript | Notes search defaults to title-only. Body/all search is refused because it scans every note plaintext. |
| Numbers | Numbers via AppleScript/JXA | `numbers.read` and `numbers.get_formulas` require an explicit cell range. Full-table reads are refused. |
| Pages | Pages via AppleScript | Calls are serialized through the Pages lane and bounded by timeout/output budgets. Large writes/tables are capped by schema. |
| Keynote | Keynote via AppleScript | PNG/JPEG export requires a slide index. All-slide image export is refused. Calls are serialized through the Keynote lane. |
| Calendar | EventKit | `calendar.list_events` and `calendar.search` refuse ranges over 31 days; the native bridge also caps date ranges and result counts. `calendar.create_event` validates calendar modifiability before save and runs through the Calendar lane. |
| Reminders | EventKit | List calls have bounded result limits in the schema and native bridge, and run through the Reminders lane. |
| Contacts | Contacts.framework | Calls run through the Contacts lane and output budget. Phone substring fallback stops after a native scan budget. |
| Files | FileManager, Spotlight, PDFKit, Vision, textutil | Calls run through the Files lane. `files.move` accepts at most 50 items per call. `mdfind`, `mdls`, and `textutil` use native subprocess timeouts. PDF, OCR, directory listing, and textutil extraction have native size/page/item budgets. |

## Known Follow-Ups

- Add deeper iWork document-size checks where AppleScript can read metadata before expensive text extraction.

## Manual Smoke Checks

- Mail.app remains responsive while `mail.search` refuses a broad body/all-mailbox/all-account query.
- `mail.save_attachment` with only `messageId` is refused before Mail.app is touched.
- Notes refuses `searchIn: "body"` and still allows title search.
- Numbers refuses `numbers.read` without `range`.
- Keynote refuses PNG/JPEG export without `slide`.
- `files.move` refuses batches over 50 operations.
