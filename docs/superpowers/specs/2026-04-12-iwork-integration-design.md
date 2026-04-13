# iWork Integration Design Spec

**Date**: 2026-04-12
**Status**: Draft
**Scope**: Add Numbers, Pages, and Keynote support to orchard-mcp

## Overview

Extend orchard-mcp with comprehensive iWork automation -- full read/write/create/export support for Numbers, Pages, and Keynote. Follows the existing two-layer architecture (TypeScript MCP tools + Swift CLI bridge). No separate server; iWork tools join the existing tool registry alongside Calendar, Mail, Reminders, Files, and System.

## Decision Record

- **Same server vs separate**: Same server. iWork fits orchard-mcp's identity ("macOS system services for AI"). The bridge infrastructure, build pipeline, and .app bundle TCC workaround would be duplicated for no benefit. Tool definitions add ~2-3k tokens to context -- negligible.
- **Scripting approach**: Hybrid (Approach C). AppleScript for document-level operations (create, export, slide management). JXA for bulk cell data in Numbers (read, write, get_formulas) where native JSON support avoids delimiter parsing fragility.

## Tool Inventory

### numbers.* (10 tools)

| Tool | Description |
|------|-------------|
| `numbers.search` | Spotlight search for .numbers files with metadata (sheet count, size, dates) |
| `numbers.read` | Read cell data from a sheet as JSON (supports ranges or full sheet) |
| `numbers.write` | Write data to specific cells or ranges |
| `numbers.create` | Create a new spreadsheet, optionally from CSV/JSON data |
| `numbers.list_sheets` | List all sheets/tables in a document |
| `numbers.add_sheet` | Add a new sheet to an existing document |
| `numbers.remove_sheet` | Remove a sheet from a document |
| `numbers.get_formulas` | Read formulas (not computed values) from cells |
| `numbers.export` | Export to CSV, PDF, or Excel (.xlsx) |
| `numbers.info` | Document metadata (sheets, tables, row/column counts, size) |

### pages.* (9 tools)

| Tool | Description |
|------|-------------|
| `pages.search` | Spotlight search for .pages files with metadata |
| `pages.read` | Extract text content from a document |
| `pages.write` | Replace the full body text of a document |
| `pages.create` | Create a new document, optionally from text/markdown |
| `pages.find_replace` | Find and replace text |
| `pages.insert_table` | Insert a table with data |
| `pages.list_sections` | List document sections/pages |
| `pages.export` | Export to PDF, Word (.docx), plain text, EPUB |
| `pages.info` | Document metadata (page count, word count, size) |

### keynote.* (11 tools)

| Tool | Description |
|------|-------------|
| `keynote.search` | Spotlight search for .key files with metadata |
| `keynote.read` | Extract content from slides (text, notes) |
| `keynote.create` | Create a new presentation |
| `keynote.add_slide` | Add a slide with layout, text, and notes |
| `keynote.edit_slide` | Edit text/notes on an existing slide |
| `keynote.remove_slide` | Remove a slide |
| `keynote.reorder_slides` | Move slides to new positions |
| `keynote.list_slides` | List all slides with titles and layouts |
| `keynote.list_themes` | List available Keynote themes/masters |
| `keynote.export` | Export to PDF, PowerPoint (.pptx), images (per-slide PNG/JPEG) |
| `keynote.info` | Presentation metadata (slide count, theme, size) |

**Total**: 30 new tools (28 existing + 30 = 58 total)

## Architecture

### TypeScript Side

3 new tool modules following the existing pattern:

```
src/tools/numbers.ts   -> registerNumbersTools(server)
src/tools/pages.ts     -> registerPagesTools(server)
src/tools/keynote.ts   -> registerKeynoteTools(server)
```

Registered in `src/index.ts` alongside the existing 5 modules. Each tool handler calls `bridgeData(["subcommand", ...args])`.

### Swift Side

3 new source files in `swift/Sources/AppleBridge/`:

```
Numbers.swift    -> AppleScript + JXA for Numbers automation
Pages.swift      -> AppleScript for Pages automation
Keynote.swift    -> AppleScript for Keynote automation
```

30 new subcommands registered in `AppleBridge.swift`. All use `ParsableCommand` (sync -- `osascript` calls are blocking). All output through `JSONOutput.success(data)` / `JSONOutput.error(msg)`.

### Scripting Split

| Scripting | Used for | Why |
|-----------|----------|-----|
| JXA (`osascript -l JavaScript`) | `numbers.read`, `numbers.write`, `numbers.get_formulas` | Native JSON support. Bulk cell data comes back as typed arrays -- no delimiter parsing. |
| AppleScript (`osascript`) | Everything else | More reliable for app-level operations (document lifecycle, export, slide management). Better tested, fewer edge-case bugs. |
| mdfind | `*.search` tools | Spotlight queries for file discovery with iWork-specific metadata. |

### No New Dependencies

- AppleScript and JXA are built into macOS
- No new Swift frameworks in `Package.swift`
- Spotlight queries use existing `mdfind`/`mdls` approach from `files.search`
- No TCC entitlements needed -- iWork apps don't require permission grants like Calendar/Reminders

## Data Formats

### Numbers Cell Data

The core data structure for `numbers.read` and `numbers.write`:

```json
{
  "sheet": "Sheet 1",
  "table": "Table 1",
  "rows": [
    ["Name", "Amount", "Date"],
    ["Rent", 1200.00, "2026-04-01"],
    ["Groceries", 350.50, "2026-04-03"]
  ],
  "rowCount": 3,
  "columnCount": 3
}
```

JXA preserves types natively -- numbers come back as numbers, not strings.

**Range addressing**: `numbers.read` and `numbers.write` accept an optional `range` parameter using A1 notation (e.g., `"A1:C10"`). Omit for full sheet. Sheet and table specified by name, defaulting to first sheet/first table.

### Pages Content

```json
{
  "body": "Full document text content...",
  "wordCount": 1450,
  "pageCount": 3
}
```

### Keynote Slides

```json
{
  "slides": [
    {
      "index": 1,
      "title": "Q1 Results",
      "body": "Revenue grew 15%...",
      "notes": "Mention partnership deal",
      "layout": "Title & Body",
      "skipped": false
    }
  ]
}
```

### Export Outputs

All export tools return `{ "path": "/path/to/exported/file.pdf" }`.

Keynote per-slide image export returns `{ "paths": ["/path/slide_001.png", ...] }`.

### Error Cases

Document not found, app not installed, file locked by another process, invalid range -- all go through the existing `JSONOutput.error(msg)` envelope. No new error handling patterns.

## Swift Subcommand Mapping

### Numbers (10 subcommands)

| Subcommand | Scripting | Key flags |
|---|---|---|
| `numbers-search` | mdfind | `--query`, `--limit` |
| `numbers-read` | JXA | `--file`, `--sheet`, `--table`, `--range` |
| `numbers-write` | JXA | `--file`, `--sheet`, `--table`, `--range`, `--data` (JSON) |
| `numbers-create` | AppleScript | `--file`, `--data` (JSON/CSV), `--template` |
| `numbers-list-sheets` | AppleScript | `--file` |
| `numbers-add-sheet` | AppleScript | `--file`, `--name` |
| `numbers-remove-sheet` | AppleScript | `--file`, `--name` |
| `numbers-get-formulas` | JXA | `--file`, `--sheet`, `--table`, `--range` |
| `numbers-export` | AppleScript | `--file`, `--format` (csv/pdf/xlsx), `--output` |
| `numbers-info` | AppleScript | `--file` |

### Pages (9 subcommands)

| Subcommand | Scripting | Key flags |
|---|---|---|
| `pages-search` | mdfind | `--query`, `--limit` |
| `pages-read` | AppleScript | `--file` |
| `pages-write` | AppleScript | `--file`, `--text` (replaces full body) |
| `pages-create` | AppleScript | `--file`, `--text`, `--template` |
| `pages-find-replace` | AppleScript | `--file`, `--find`, `--replace`, `--all` |
| `pages-insert-table` | AppleScript | `--file`, `--data` (JSON), `--position` |
| `pages-list-sections` | AppleScript | `--file` |
| `pages-export` | AppleScript | `--file`, `--format` (pdf/docx/txt/epub), `--output` |
| `pages-info` | AppleScript | `--file` |

### Keynote (11 subcommands)

| Subcommand | Scripting | Key flags |
|---|---|---|
| `keynote-search` | mdfind | `--query`, `--limit` |
| `keynote-read` | AppleScript | `--file`, `--slide` (optional, for single slide) |
| `keynote-create` | AppleScript | `--file`, `--theme` |
| `keynote-add-slide` | AppleScript | `--file`, `--layout`, `--title`, `--body`, `--notes`, `--position` |
| `keynote-edit-slide` | AppleScript | `--file`, `--slide`, `--title`, `--body`, `--notes` |
| `keynote-remove-slide` | AppleScript | `--file`, `--slide` |
| `keynote-reorder-slides` | AppleScript | `--file`, `--from`, `--to` |
| `keynote-list-slides` | AppleScript | `--file` |
| `keynote-list-themes` | AppleScript | (no flags) |
| `keynote-export` | AppleScript | `--file`, `--format` (pdf/pptx/png/jpeg), `--output`, `--slide` |
| `keynote-info` | AppleScript | `--file` |

## Testing Strategy

### Test Files

```
tests/numbers.test.ts
tests/pages.test.ts
tests/keynote.test.ts
```

### Approach

Integration tests calling the actual bridge (same as existing tests):

1. **Prerequisite check** -- skip if the iWork app isn't installed
2. **Create temp document** -- use the `create` tool, write to `$TMPDIR`
3. **Exercise CRUD** -- read, write, list, modify
4. **Export** -- verify each format produces a file at the expected path
5. **Cleanup** -- trash the temp document

### Numbers-specific

- Write JSON data, read back, verify types preserved (numbers stay numbers)
- Write formulas, read computed values vs raw formulas
- Range addressing (A1:C3) returns correct subset
- Multi-sheet operations

### Pages-specific

- Create with text, read back, verify content matches
- Find/replace across document
- Table insertion

### Keynote-specific

- Create with theme, add slides, verify slide count
- Reorder slides, verify new order
- Per-slide image export produces correct number of files

### Doctor Extension

Extend `system.doctor` to check whether Numbers, Pages, and Keynote are installed.

## Implementation Order

Recommended phasing:

1. **Numbers first** -- most complex (JXA + AppleScript hybrid), highest value
2. **Pages second** -- straightforward AppleScript, simpler document model
3. **Keynote third** -- most tools but well-scoped AppleScript operations
4. **Doctor + search** -- cross-cutting, add after core tools work

Each phase: Swift subcommands -> TypeScript tool module -> tests -> manual verification.
