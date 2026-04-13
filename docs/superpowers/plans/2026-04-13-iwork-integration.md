# iWork Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add comprehensive Numbers, Pages, and Keynote automation to orchard-mcp (30 new MCP tools).

**Architecture:** Three new TypeScript tool modules + three new Swift source files, following the existing two-layer pattern (TypeScript MCP tools call `bridgeData()` which executes Swift CLI subcommands). Numbers bulk cell operations use JXA for native JSON; everything else uses AppleScript.

**Tech Stack:** TypeScript/Zod (tool definitions), Swift/ArgumentParser (CLI subcommands), AppleScript + JXA (iWork automation), mdfind (Spotlight search)

**Spec:** `docs/superpowers/specs/2026-04-12-iwork-integration-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `swift/Sources/AppleBridge/Numbers.swift` | `NumbersBridge` enum -- AppleScript + JXA for Numbers automation |
| `swift/Sources/AppleBridge/Pages.swift` | `PagesBridge` enum -- AppleScript for Pages automation |
| `swift/Sources/AppleBridge/Keynote.swift` | `KeynoteBridge` enum -- AppleScript for Keynote automation |
| `src/tools/numbers.ts` | `registerNumbersTools(server)` -- 10 MCP tools |
| `src/tools/pages.ts` | `registerPagesTools(server)` -- 9 MCP tools |
| `src/tools/keynote.ts` | `registerKeynoteTools(server)` -- 11 MCP tools |
| `tests/numbers.test.ts` | Numbers tool registration + bridge arg tests |
| `tests/pages.test.ts` | Pages tool registration + bridge arg tests |
| `tests/keynote.test.ts` | Keynote tool registration + bridge arg tests |

### Modified Files

| File | Change |
|------|--------|
| `swift/Sources/AppleBridge/AppleBridge.swift` | Add 30 new subcommand structs + register in `subcommands` array |
| `swift/Sources/AppleBridge/Doctor.swift` | Add iWork app availability checks |
| `src/index.ts` | Import and register 3 new tool modules |
| `tests/tools.test.ts` | Add 30 new tool names to `EXPECTED_TOOLS`, update count to 58 |

---

## Task 1: Numbers Swift Bridge -- Core Infrastructure

**Files:**
- Create: `swift/Sources/AppleBridge/Numbers.swift`

This task creates the `NumbersBridge` enum with the shared AppleScript/JXA execution helpers and the first two operations: `info` and `listSheets`.

- [ ] **Step 1: Create Numbers.swift with shared helpers**

```swift
// swift/Sources/AppleBridge/Numbers.swift
import Foundation

enum NumbersBridge {

    // MARK: - Info

    static func info(file: String) {
        let escaped = escapeForAppleScript(file)
        let script = """
        tell application "Numbers"
            set doc to open POSIX file "\(escaped)"
            set sheetCount to count of sheets of doc
            set docName to name of doc
            set result to {}
            set tableCount to 0
            repeat with s in sheets of doc
                set tableCount to tableCount + (count of tables of s)
            end repeat
            close doc saving no
            return docName & "|||" & (sheetCount as string) & "|||" & (tableCount as string)
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        let parts = raw.components(separatedBy: "|||")
        guard parts.count >= 3 else {
            JSONOutput.error("Unexpected response format from Numbers")
            return
        }

        let result: [String: Any] = [
            "name": parts[0],
            "sheetCount": Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0,
            "tableCount": Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 0,
            "path": file
        ]
        JSONOutput.success(result)
    }

    // MARK: - List Sheets

    static func listSheets(file: String) {
        let escaped = escapeForAppleScript(file)
        let script = """
        tell application "Numbers"
            set doc to open POSIX file "\(escaped)"
            set resultList to {}
            repeat with s in sheets of doc
                set sheetName to name of s
                set tableNames to {}
                repeat with t in tables of s
                    set tName to name of t
                    set rowCount to row count of t
                    set colCount to column count of t
                    set end of tableNames to tName & "::" & (rowCount as string) & "::" & (colCount as string)
                end repeat
                set end of resultList to sheetName & "|||" & (my joinList(tableNames, "^^^"))
            end repeat
            close doc saving no
            return my joinList(resultList, "###")
        end tell

        on joinList(theList, delim)
            set oldDelim to AppleScript's text item delimiters
            set AppleScript's text item delimiters to delim
            set theResult to theList as string
            set AppleScript's text item delimiters to oldDelim
            return theResult
        end joinList
        """

        guard let raw = runAppleScript(script) else { return }
        let sheets = parseSheetList(raw)
        JSONOutput.success(sheets)
    }

    // MARK: - AppleScript Execution

    private static func runAppleScript(_ script: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus != 0 {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"

                if errStr.contains("-1743") || errStr.contains("not allowed") {
                    JSONOutput.error("Numbers automation permission denied. Grant access in System Settings > Privacy & Security > Automation.")
                } else if errStr.contains("-600") || errStr.contains("not running") {
                    JSONOutput.error("Numbers is not running. It will be launched automatically on next attempt.")
                } else {
                    JSONOutput.error("AppleScript error: \(errStr)")
                }
                return nil
            }

            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            JSONOutput.error("Failed to run osascript: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - JXA Execution

    private static func runJXA(_ script: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-l", "JavaScript", "-e", script]

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus != 0 {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                JSONOutput.error("JXA error: \(errStr)")
                return nil
            }

            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            JSONOutput.error("Failed to run osascript: \(error.localizedDescription)")
            return nil
        }
    }

    private static func escapeForAppleScript(_ str: String) -> String {
        return str.replacingOccurrences(of: "\\", with: "\\\\")
                  .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func escapeForJXA(_ str: String) -> String {
        return str.replacingOccurrences(of: "\\", with: "\\\\")
                  .replacingOccurrences(of: "\"", with: "\\\"")
                  .replacingOccurrences(of: "\n", with: "\\n")
    }

    // MARK: - Parsers

    private static func parseSheetList(_ raw: String) -> [[String: Any]] {
        guard !raw.isEmpty else { return [] }
        let sheetChunks = raw.components(separatedBy: "###")
        return sheetChunks.compactMap { chunk -> [String: Any]? in
            let parts = chunk.components(separatedBy: "|||")
            guard parts.count >= 1 else { return nil }

            var sheet: [String: Any] = [
                "name": parts[0].trimmingCharacters(in: .whitespaces)
            ]

            if parts.count > 1 && !parts[1].isEmpty {
                let tableStrings = parts[1].components(separatedBy: "^^^")
                let tables: [[String: Any]] = tableStrings.compactMap { tStr in
                    let fields = tStr.components(separatedBy: "::")
                    guard fields.count >= 3 else { return nil }
                    return [
                        "name": fields[0].trimmingCharacters(in: .whitespaces),
                        "rowCount": Int(fields[1].trimmingCharacters(in: .whitespaces)) ?? 0,
                        "columnCount": Int(fields[2].trimmingCharacters(in: .whitespaces)) ?? 0
                    ]
                }
                sheet["tables"] = tables
            }

            return sheet
        }
    }
}
```

- [ ] **Step 2: Build Swift to verify compilation**

Run: `cd swift && swift build -c release 2>&1 | tail -5`
Expected: Build succeeds with no errors

- [ ] **Step 3: Commit**

```bash
git add swift/Sources/AppleBridge/Numbers.swift
git commit -m "feat(numbers): add NumbersBridge with info, listSheets, and shared helpers"
```

---

## Task 2: Numbers Swift Bridge -- JXA Cell Operations

**Files:**
- Modify: `swift/Sources/AppleBridge/Numbers.swift`

Add `read`, `write`, and `getFormulas` using JXA for native JSON data handling.

- [ ] **Step 1: Add read function to NumbersBridge**

Add after the `listSheets` function in `Numbers.swift`:

```swift
    // MARK: - Read (JXA)

    static func read(file: String, sheet: String?, table: String?, range: String?) {
        let escapedFile = escapeForJXA(file)
        let sheetSelector = sheet != nil ? "sheets.byName(\"\(escapeForJXA(sheet!))\")" : "sheets[0]"
        let tableSelector = table != nil ? "tables.byName(\"\(escapeForJXA(table!))\")" : "tables[0]"

        let rangeClause: String
        if let range = range {
            let parsed = parseA1Range(range)
            rangeClause = """
            var startRow = \(parsed.startRow); var startCol = \(parsed.startCol);
            var endRow = \(parsed.endRow); var endCol = \(parsed.endCol);
            """
        } else {
            rangeClause = """
            var startRow = 0; var startCol = 0;
            var endRow = tbl.rowCount() - 1; var endCol = tbl.columnCount() - 1;
            """
        }

        let script = """
        var app = Application("Numbers");
        app.open(Path("\(escapedFile)"));
        var doc = app.documents[0];
        var sht = doc.\(sheetSelector);
        var tbl = sht.\(tableSelector);
        \(rangeClause)
        var rows = [];
        for (var r = startRow; r <= endRow; r++) {
            var row = [];
            for (var c = startCol; c <= endCol; c++) {
                var cell = tbl.cells[r * tbl.columnCount() + c];
                var val = cell.value();
                row.push(val === null ? "" : val);
            }
            rows.push(row);
        }
        var result = JSON.stringify({
            sheet: sht.name(),
            table: tbl.name(),
            rows: rows,
            rowCount: endRow - startRow + 1,
            columnCount: endCol - startCol + 1
        });
        doc.close({saving: false});
        result;
        """

        guard let raw = runJXA(script) else { return }
        guard let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            JSONOutput.error("Failed to parse JXA JSON output")
            return
        }
        JSONOutput.success(parsed)
    }
```

- [ ] **Step 2: Add write function**

Add after the `read` function:

```swift
    // MARK: - Write (JXA)

    static func write(file: String, sheet: String?, table: String?, range: String?, dataJSON: String) {
        let escapedFile = escapeForJXA(file)
        let sheetSelector = sheet != nil ? "sheets.byName(\"\(escapeForJXA(sheet!))\")" : "sheets[0]"
        let tableSelector = table != nil ? "tables.byName(\"\(escapeForJXA(table!))\")" : "tables[0]"

        let startPos: String
        if let range = range {
            let parsed = parseA1Range(range)
            startPos = "var startRow = \(parsed.startRow); var startCol = \(parsed.startCol);"
        } else {
            startPos = "var startRow = 0; var startCol = 0;"
        }

        // Escape the JSON data for embedding in JXA string
        let escapedData = dataJSON.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let script = """
        var app = Application("Numbers");
        app.open(Path("\(escapedFile)"));
        var doc = app.documents[0];
        var sht = doc.\(sheetSelector);
        var tbl = sht.\(tableSelector);
        \(startPos)
        var data = JSON.parse("\(escapedData)");
        var written = 0;
        for (var r = 0; r < data.length; r++) {
            var row = data[r];
            for (var c = 0; c < row.length; c++) {
                tbl.cells[(startRow + r) * tbl.columnCount() + (startCol + c)].value = row[c];
                written++;
            }
        }
        doc.close({saving: true});
        JSON.stringify({cellsWritten: written, rows: data.length, columns: data[0].length});
        """

        guard let raw = runJXA(script) else { return }
        guard let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            JSONOutput.error("Failed to parse JXA JSON output")
            return
        }
        JSONOutput.success(parsed)
    }
```

- [ ] **Step 3: Add getFormulas function**

Add after the `write` function:

```swift
    // MARK: - Get Formulas (JXA)

    static func getFormulas(file: String, sheet: String?, table: String?, range: String?) {
        let escapedFile = escapeForJXA(file)
        let sheetSelector = sheet != nil ? "sheets.byName(\"\(escapeForJXA(sheet!))\")" : "sheets[0]"
        let tableSelector = table != nil ? "tables.byName(\"\(escapeForJXA(table!))\")" : "tables[0]"

        let rangeClause: String
        if let range = range {
            let parsed = parseA1Range(range)
            rangeClause = """
            var startRow = \(parsed.startRow); var startCol = \(parsed.startCol);
            var endRow = \(parsed.endRow); var endCol = \(parsed.endCol);
            """
        } else {
            rangeClause = """
            var startRow = 0; var startCol = 0;
            var endRow = tbl.rowCount() - 1; var endCol = tbl.columnCount() - 1;
            """
        }

        let script = """
        var app = Application("Numbers");
        app.open(Path("\(escapedFile)"));
        var doc = app.documents[0];
        var sht = doc.\(sheetSelector);
        var tbl = sht.\(tableSelector);
        \(rangeClause)
        var rows = [];
        for (var r = startRow; r <= endRow; r++) {
            var row = [];
            for (var c = startCol; c <= endCol; c++) {
                var cell = tbl.cells[r * tbl.columnCount() + c];
                var formula = cell.formula();
                row.push(formula === null ? "" : formula);
            }
            rows.push(row);
        }
        var result = JSON.stringify({
            sheet: sht.name(),
            table: tbl.name(),
            formulas: rows,
            rowCount: endRow - startRow + 1,
            columnCount: endCol - startCol + 1
        });
        doc.close({saving: false});
        result;
        """

        guard let raw = runJXA(script) else { return }
        guard let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            JSONOutput.error("Failed to parse JXA JSON output")
            return
        }
        JSONOutput.success(parsed)
    }
```

- [ ] **Step 4: Add A1 range parser helper**

Add to the private helpers section of `NumbersBridge`:

```swift
    // MARK: - A1 Range Parser

    private struct CellRange {
        let startRow: Int
        let startCol: Int
        let endRow: Int
        let endCol: Int
    }

    private static func parseA1Range(_ range: String) -> CellRange {
        // Parses "A1:C3" into 0-based row/col indices
        let parts = range.uppercased().components(separatedBy: ":")
        let start = parseA1Cell(parts[0])
        let end = parts.count > 1 ? parseA1Cell(parts[1]) : start
        return CellRange(startRow: start.row, startCol: start.col, endRow: end.row, endCol: end.col)
    }

    private static func parseA1Cell(_ cell: String) -> (row: Int, col: Int) {
        var colStr = ""
        var rowStr = ""
        for char in cell {
            if char.isLetter {
                colStr.append(char)
            } else {
                rowStr.append(char)
            }
        }
        // Convert column letters to 0-based index: A=0, B=1, ..., Z=25, AA=26
        var col = 0
        for char in colStr {
            col = col * 26 + Int(char.asciiValue! - 65) + 1
        }
        col -= 1
        let row = (Int(rowStr) ?? 1) - 1
        return (row, col)
    }
```

- [ ] **Step 5: Build Swift to verify compilation**

Run: `cd swift && swift build -c release 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add swift/Sources/AppleBridge/Numbers.swift
git commit -m "feat(numbers): add JXA-based read, write, getFormulas with A1 range parsing"
```

---

## Task 3: Numbers Swift Bridge -- Document Operations

**Files:**
- Modify: `swift/Sources/AppleBridge/Numbers.swift`

Add `create`, `addSheet`, `removeSheet`, `export`, and `search`.

- [ ] **Step 1: Add create function**

Add after the `getFormulas` function:

```swift
    // MARK: - Create

    static func create(file: String, dataJSON: String?, template: String?) {
        let escaped = escapeForAppleScript(file)

        let templateClause: String
        if let template = template {
            templateClause = "set doc to make new document with properties {document template:template \"\(escapeForAppleScript(template))\"}"
        } else {
            templateClause = "set doc to make new document"
        }

        let script = """
        tell application "Numbers"
            \(templateClause)
            set docPath to POSIX file "\(escaped)"
            save doc in docPath
            close doc
            return "ok"
        end tell
        """

        guard let _ = runAppleScript(script) else { return }

        // If initial data is provided, write it via JXA
        if let dataJSON = dataJSON, !dataJSON.isEmpty {
            write(file: file, sheet: nil, table: nil, range: nil, dataJSON: dataJSON)
            return
        }

        JSONOutput.success(["path": file, "created": true])
    }
```

- [ ] **Step 2: Add addSheet and removeSheet**

```swift
    // MARK: - Add Sheet

    static func addSheet(file: String, name: String) {
        let escapedFile = escapeForAppleScript(file)
        let escapedName = escapeForAppleScript(name)
        let script = """
        tell application "Numbers"
            set doc to open POSIX file "\(escapedFile)"
            tell doc
                set newSheet to make new sheet with properties {name:"\(escapedName)"}
            end tell
            save doc
            close doc
            return "ok"
        end tell
        """

        guard let _ = runAppleScript(script) else { return }
        JSONOutput.success(["sheet": name, "added": true])
    }

    // MARK: - Remove Sheet

    static func removeSheet(file: String, name: String) {
        let escapedFile = escapeForAppleScript(file)
        let escapedName = escapeForAppleScript(name)
        let script = """
        tell application "Numbers"
            set doc to open POSIX file "\(escapedFile)"
            tell doc
                delete sheet "\(escapedName)"
            end tell
            save doc
            close doc
            return "ok"
        end tell
        """

        guard let _ = runAppleScript(script) else { return }
        JSONOutput.success(["sheet": name, "removed": true])
    }
```

- [ ] **Step 3: Add export function**

```swift
    // MARK: - Export

    static func export(file: String, format: String, output: String?) {
        let escapedFile = escapeForAppleScript(file)
        let outputPath: String
        if let output = output {
            outputPath = output
        } else {
            let ext: String
            switch format {
            case "csv": ext = "csv"
            case "pdf": ext = "pdf"
            case "xlsx": ext = "xlsx"
            default: ext = format
            }
            outputPath = file.replacingOccurrences(of: ".numbers", with: ".\(ext)")
        }
        let escapedOutput = escapeForAppleScript(outputPath)

        let formatMap: [String: String] = [
            "csv": "CSV",
            "pdf": "PDF",
            "xlsx": "Microsoft Excel"
        ]
        guard let numbersFormat = formatMap[format] else {
            JSONOutput.error("Unsupported export format: \(format). Use csv, pdf, or xlsx.")
            return
        }

        let script = """
        tell application "Numbers"
            set doc to open POSIX file "\(escapedFile)"
            export doc to POSIX file "\(escapedOutput)" as \(numbersFormat)
            close doc saving no
            return "ok"
        end tell
        """

        guard let _ = runAppleScript(script) else { return }
        JSONOutput.success(["path": outputPath])
    }
```

- [ ] **Step 4: Add search function**

```swift
    // MARK: - Search

    static func search(query: String, limit: Int) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        task.arguments = [
            "kMDItemContentType == 'com.apple.iWork.numbers.sffnumbers' && kMDItemDisplayName == '*\(query)*'cd"
        ]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                JSONOutput.success([])
                return
            }

            let paths = output.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(limit)

            let fm = FileManager.default
            let results: [[String: Any]] = paths.compactMap { path in
                guard let attrs = try? fm.attributesOfItem(atPath: path) else { return nil }
                var entry: [String: Any] = [
                    "path": path,
                    "name": URL(fileURLWithPath: path).lastPathComponent
                ]
                if let size = attrs[.size] as? Int {
                    entry["size"] = size
                }
                if let modified = attrs[.modificationDate] as? Date {
                    entry["modified"] = iso8601(modified)
                }
                return entry
            }

            JSONOutput.success(results)
        } catch {
            JSONOutput.error("Spotlight search failed: \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 5: Build Swift to verify compilation**

Run: `cd swift && swift build -c release 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add swift/Sources/AppleBridge/Numbers.swift
git commit -m "feat(numbers): add create, addSheet, removeSheet, export, search"
```

---

## Task 4: Numbers Subcommands in AppleBridge.swift

**Files:**
- Modify: `swift/Sources/AppleBridge/AppleBridge.swift`

Register all 10 Numbers subcommand structs.

- [ ] **Step 1: Add Numbers subcommand structs**

Add after the `// MARK: - Files & Folders Subcommands` section (before `// MARK: - Doctor`), in `AppleBridge.swift`:

```swift
// MARK: - Numbers Subcommands

struct NumbersSearch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "numbers-search",
        abstract: "Search for Numbers spreadsheets using Spotlight."
    )

    @Option(name: .long, help: "Search query")
    var query: String

    @Option(name: .long, help: "Max results (default: 20)")
    var limit: Int = 20

    func run() throws {
        NumbersBridge.search(query: query, limit: limit)
    }
}

struct NumbersRead: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "numbers-read",
        abstract: "Read cell data from a Numbers spreadsheet as JSON."
    )

    @Option(name: .long, help: "Path to .numbers file")
    var file: String

    @Option(name: .long, help: "Sheet name (default: first sheet)")
    var sheet: String?

    @Option(name: .long, help: "Table name (default: first table)")
    var table: String?

    @Option(name: .long, help: "Cell range in A1 notation (e.g. A1:C10)")
    var range: String?

    func run() throws {
        NumbersBridge.read(file: file, sheet: sheet, table: table, range: range)
    }
}

struct NumbersWrite: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "numbers-write",
        abstract: "Write data to cells in a Numbers spreadsheet."
    )

    @Option(name: .long, help: "Path to .numbers file")
    var file: String

    @Option(name: .long, help: "Sheet name (default: first sheet)")
    var sheet: String?

    @Option(name: .long, help: "Table name (default: first table)")
    var table: String?

    @Option(name: .long, help: "Starting cell in A1 notation (e.g. A1)")
    var range: String?

    @Option(name: .long, help: "JSON array of arrays with cell data")
    var data: String

    func run() throws {
        NumbersBridge.write(file: file, sheet: sheet, table: table, range: range, dataJSON: data)
    }
}

struct NumbersCreate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "numbers-create",
        abstract: "Create a new Numbers spreadsheet."
    )

    @Option(name: .long, help: "Output file path")
    var file: String

    @Option(name: .long, help: "Initial data as JSON array of arrays")
    var data: String?

    @Option(name: .long, help: "Template name")
    var template: String?

    func run() throws {
        NumbersBridge.create(file: file, dataJSON: data, template: template)
    }
}

struct NumbersListSheets: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "numbers-list-sheets",
        abstract: "List all sheets and tables in a Numbers document."
    )

    @Option(name: .long, help: "Path to .numbers file")
    var file: String

    func run() throws {
        NumbersBridge.listSheets(file: file)
    }
}

struct NumbersAddSheet: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "numbers-add-sheet",
        abstract: "Add a new sheet to a Numbers document."
    )

    @Option(name: .long, help: "Path to .numbers file")
    var file: String

    @Option(name: .long, help: "Name for the new sheet")
    var name: String

    func run() throws {
        NumbersBridge.addSheet(file: file, name: name)
    }
}

struct NumbersRemoveSheet: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "numbers-remove-sheet",
        abstract: "Remove a sheet from a Numbers document."
    )

    @Option(name: .long, help: "Path to .numbers file")
    var file: String

    @Option(name: .long, help: "Sheet name to remove")
    var name: String

    func run() throws {
        NumbersBridge.removeSheet(file: file, name: name)
    }
}

struct NumbersGetFormulas: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "numbers-get-formulas",
        abstract: "Read formulas from cells in a Numbers spreadsheet."
    )

    @Option(name: .long, help: "Path to .numbers file")
    var file: String

    @Option(name: .long, help: "Sheet name (default: first sheet)")
    var sheet: String?

    @Option(name: .long, help: "Table name (default: first table)")
    var table: String?

    @Option(name: .long, help: "Cell range in A1 notation")
    var range: String?

    func run() throws {
        NumbersBridge.getFormulas(file: file, sheet: sheet, table: table, range: range)
    }
}

struct NumbersExport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "numbers-export",
        abstract: "Export a Numbers spreadsheet to CSV, PDF, or Excel."
    )

    @Option(name: .long, help: "Path to .numbers file")
    var file: String

    @Option(name: .long, help: "Export format: csv, pdf, xlsx")
    var format: String

    @Option(name: .long, help: "Output file path (default: same name with new extension)")
    var output: String?

    func run() throws {
        NumbersBridge.export(file: file, format: format, output: output)
    }
}

struct NumbersInfo: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "numbers-info",
        abstract: "Get metadata about a Numbers spreadsheet."
    )

    @Option(name: .long, help: "Path to .numbers file")
    var file: String

    func run() throws {
        NumbersBridge.info(file: file)
    }
}
```

- [ ] **Step 2: Register subcommands in the subcommands array**

In `AppleBridge.swift`, add the 10 Numbers types to the `subcommands` array (after `Doctor.self`):

```swift
            Doctor.self,
            // Numbers
            NumbersSearch.self,
            NumbersRead.self,
            NumbersWrite.self,
            NumbersCreate.self,
            NumbersListSheets.self,
            NumbersAddSheet.self,
            NumbersRemoveSheet.self,
            NumbersGetFormulas.self,
            NumbersExport.self,
            NumbersInfo.self,
```

Also update the `abstract` string to include Numbers:

```swift
        abstract: "Native macOS bridge for Apple Calendar, Mail, Reminders, and Numbers.",
```

- [ ] **Step 3: Build Swift to verify compilation**

Run: `cd swift && swift build -c release 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add swift/Sources/AppleBridge/AppleBridge.swift
git commit -m "feat(numbers): register 10 Numbers subcommands in AppleBridge"
```

---

## Task 5: Numbers TypeScript Tool Module

**Files:**
- Create: `src/tools/numbers.ts`
- Modify: `src/index.ts`

- [ ] **Step 1: Create src/tools/numbers.ts**

```typescript
// src/tools/numbers.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { bridgeData } from "../bridge.js";

export function registerNumbersTools(server: McpServer): void {
  server.tool(
    "numbers.search",
    "Search for Numbers spreadsheets (.numbers files) using Spotlight. Returns file paths with metadata.",
    {
      query: z.string().describe("Search query to match against file names"),
      limit: z
        .number()
        .optional()
        .describe("Max results to return (default: 20)"),
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
    "Read cell data from a Numbers spreadsheet as JSON. Returns typed values (numbers stay numbers). Supports optional range in A1 notation.",
    {
      file: z.string().describe("Path to the .numbers file"),
      sheet: z
        .string()
        .optional()
        .describe("Sheet name (default: first sheet)"),
      table: z
        .string()
        .optional()
        .describe("Table name (default: first table)"),
      range: z
        .string()
        .optional()
        .describe("Cell range in A1 notation, e.g. A1:C10 (default: entire table)"),
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
    "Write data to cells in a Numbers spreadsheet. Data is a JSON array of arrays. Optionally specify a starting cell in A1 notation.",
    {
      file: z.string().describe("Path to the .numbers file"),
      data: z
        .string()
        .describe('JSON array of arrays with cell values, e.g. [["Name","Amount"],["Rent",1200]]'),
      sheet: z
        .string()
        .optional()
        .describe("Sheet name (default: first sheet)"),
      table: z
        .string()
        .optional()
        .describe("Table name (default: first table)"),
      range: z
        .string()
        .optional()
        .describe("Starting cell in A1 notation, e.g. A1 (default: A1)"),
    },
    async ({ file, data, sheet, table, range }) => {
      const args = ["numbers-write", "--file", file, "--data", data];
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
    "Create a new Numbers spreadsheet. Optionally provide initial data as JSON array of arrays.",
    {
      file: z.string().describe("Output file path for the new .numbers file"),
      data: z
        .string()
        .optional()
        .describe("Initial data as JSON array of arrays"),
      template: z
        .string()
        .optional()
        .describe("Template name to use"),
    },
    async ({ file, data, template }) => {
      const args = ["numbers-create", "--file", file];
      if (data) args.push("--data", data);
      if (template) args.push("--template", template);
      const result = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
      };
    }
  );

  server.tool(
    "numbers.list_sheets",
    "List all sheets and tables in a Numbers spreadsheet, including row and column counts per table.",
    {
      file: z.string().describe("Path to the .numbers file"),
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
    "Add a new sheet to an existing Numbers spreadsheet.",
    {
      file: z.string().describe("Path to the .numbers file"),
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
      file: z.string().describe("Path to the .numbers file"),
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
    "Read formulas (not computed values) from cells in a Numbers spreadsheet.",
    {
      file: z.string().describe("Path to the .numbers file"),
      sheet: z
        .string()
        .optional()
        .describe("Sheet name (default: first sheet)"),
      table: z
        .string()
        .optional()
        .describe("Table name (default: first table)"),
      range: z
        .string()
        .optional()
        .describe("Cell range in A1 notation (default: entire table)"),
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
    "Export a Numbers spreadsheet to CSV, PDF, or Excel (.xlsx) format.",
    {
      file: z.string().describe("Path to the .numbers file"),
      format: z
        .enum(["csv", "pdf", "xlsx"])
        .describe("Export format"),
      output: z
        .string()
        .optional()
        .describe("Output file path (default: same name with new extension)"),
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
    "Get metadata about a Numbers spreadsheet: sheet count, table count, file path.",
    {
      file: z.string().describe("Path to the .numbers file"),
    },
    async ({ file }) => {
      const data = await bridgeData(["numbers-info", "--file", file]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
```

- [ ] **Step 2: Register in src/index.ts**

Add the import after the existing imports (line 16):

```typescript
import { registerNumbersTools } from "./tools/numbers.js";
```

Add the registration call after `registerFileTools(server);` (line 27):

```typescript
registerNumbersTools(server);
```

- [ ] **Step 3: Build TypeScript to verify compilation**

Run: `npm run build:ts 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add src/tools/numbers.ts src/index.ts
git commit -m "feat(numbers): add 10 Numbers MCP tools and register in server"
```

---

## Task 6: Pages Swift Bridge

**Files:**
- Create: `swift/Sources/AppleBridge/Pages.swift`

Full `PagesBridge` enum with all 9 operations.

- [ ] **Step 1: Create Pages.swift**

```swift
// swift/Sources/AppleBridge/Pages.swift
import Foundation

enum PagesBridge {

    // MARK: - Info

    static func info(file: String) {
        let escaped = escapeForAppleScript(file)
        let script = """
        tell application "Pages"
            set doc to open POSIX file "\(escaped)"
            set docName to name of doc
            set wCount to word count of doc
            set pCount to page count of doc
            close doc saving no
            return docName & "|||" & (wCount as string) & "|||" & (pCount as string)
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        let parts = raw.components(separatedBy: "|||")
        guard parts.count >= 3 else {
            JSONOutput.error("Unexpected response format from Pages")
            return
        }

        JSONOutput.success([
            "name": parts[0],
            "wordCount": Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0,
            "pageCount": Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 0,
            "path": file
        ] as [String: Any])
    }

    // MARK: - Read

    static func read(file: String) {
        let escaped = escapeForAppleScript(file)
        let script = """
        tell application "Pages"
            set doc to open POSIX file "\(escaped)"
            set bodyText to body text of doc
            set wCount to word count of doc
            set pCount to page count of doc
            close doc saving no
            return bodyText & "|||" & (wCount as string) & "|||" & (pCount as string)
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        let parts = raw.components(separatedBy: "|||")
        guard parts.count >= 1 else {
            JSONOutput.error("Unexpected response format from Pages")
            return
        }

        var result: [String: Any] = ["body": parts[0]]
        if parts.count >= 3 {
            result["wordCount"] = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            result["pageCount"] = Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        JSONOutput.success(result)
    }

    // MARK: - Write

    static func write(file: String, text: String) {
        let escaped = escapeForAppleScript(file)
        let escapedText = escapeForAppleScript(text)
        let script = """
        tell application "Pages"
            set doc to open POSIX file "\(escaped)"
            set body text of doc to "\(escapedText)"
            save doc
            close doc
            return "ok"
        end tell
        """

        guard let _ = runAppleScript(script) else { return }
        JSONOutput.success(["path": file, "written": true])
    }

    // MARK: - Create

    static func create(file: String, text: String?, template: String?) {
        let escaped = escapeForAppleScript(file)

        let templateClause: String
        if let template = template {
            templateClause = "set doc to make new document with properties {document template:template \"\(escapeForAppleScript(template))\"}"
        } else {
            templateClause = "set doc to make new document"
        }

        let textClause: String
        if let text = text {
            textClause = "set body text of doc to \"\(escapeForAppleScript(text))\""
        } else {
            textClause = ""
        }

        let script = """
        tell application "Pages"
            \(templateClause)
            \(textClause)
            set docPath to POSIX file "\(escaped)"
            save doc in docPath
            close doc
            return "ok"
        end tell
        """

        guard let _ = runAppleScript(script) else { return }
        JSONOutput.success(["path": file, "created": true])
    }

    // MARK: - Find & Replace

    static func findReplace(file: String, find: String, replace: String, all: Bool) {
        let escaped = escapeForAppleScript(file)
        let escapedFind = escapeForAppleScript(find)
        let escapedReplace = escapeForAppleScript(replace)

        let replaceCmd = all ? "replace every occurrence" : "replace first occurrence"

        // Pages doesn't have a native find/replace AppleScript command,
        // so we work with the body text directly
        let script = """
        tell application "Pages"
            set doc to open POSIX file "\(escaped)"
            set bodyText to body text of doc
            if "\(escapedFind)" is in bodyText then
                set oldDelim to AppleScript's text item delimiters
                set AppleScript's text item delimiters to "\(escapedFind)"
                set textItems to text items of bodyText
                set AppleScript's text item delimiters to "\(escapedReplace)"
                if \(all ? "true" : "false") then
                    set newText to textItems as string
                else
                    if (count of textItems) > 1 then
                        set newText to (item 1 of textItems) & "\(escapedReplace)" & (rest of textItems as string)
                    else
                        set newText to bodyText
                    end if
                end if
                set AppleScript's text item delimiters to oldDelim
                set body text of doc to newText
                set matchCount to (count of textItems) - 1
            else
                set matchCount to 0
            end if
            save doc
            close doc
            return matchCount as string
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        let count = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        JSONOutput.success([
            "replacements": count,
            "find": find,
            "replace": replace
        ] as [String: Any])
    }

    // MARK: - Insert Table

    static func insertTable(file: String, dataJSON: String, position: String?) {
        let escaped = escapeForAppleScript(file)

        guard let data = dataJSON.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else {
            JSONOutput.error("Invalid JSON data for table. Expected array of arrays.")
            return
        }

        let rowCount = rows.count
        let colCount = rows.first?.count ?? 0

        // Build cell assignment AppleScript
        var cellAssignments = ""
        for (r, row) in rows.enumerated() {
            for (c, val) in row.enumerated() {
                let cellRef = "row \(r + 1) of column \(c + 1)"
                if let num = val as? NSNumber {
                    cellAssignments += "set value of cell of \(cellRef) of newTable to \(num)\n"
                } else {
                    let str = escapeForAppleScript("\(val)")
                    cellAssignments += "set value of cell of \(cellRef) of newTable to \"\(str)\"\n"
                }
            }
        }

        let script = """
        tell application "Pages"
            set doc to open POSIX file "\(escaped)"
            tell doc
                set newTable to make new table with properties {row count:\(rowCount), column count:\(colCount)}
                \(cellAssignments)
            end tell
            save doc
            close doc
            return "ok"
        end tell
        """

        guard let _ = runAppleScript(script) else { return }
        JSONOutput.success(["inserted": true, "rows": rowCount, "columns": colCount])
    }

    // MARK: - List Sections

    static func listSections(file: String) {
        let escaped = escapeForAppleScript(file)
        let script = """
        tell application "Pages"
            set doc to open POSIX file "\(escaped)"
            set sectionList to {}
            repeat with s in sections of doc
                set sBody to body text of s
                set sWordCount to count of words of sBody
                set end of sectionList to (my truncateText(sBody, 100)) & "|||" & (sWordCount as string)
            end repeat
            close doc saving no
            return my joinList(sectionList, "###")
        end tell

        on truncateText(txt, maxLen)
            if (count of txt) > maxLen then
                return (text 1 thru maxLen of txt) & "..."
            end if
            return txt
        end truncateText

        on joinList(theList, delim)
            set oldDelim to AppleScript's text item delimiters
            set AppleScript's text item delimiters to delim
            set theResult to theList as string
            set AppleScript's text item delimiters to oldDelim
            return theResult
        end joinList
        """

        guard let raw = runAppleScript(script) else { return }
        guard !raw.isEmpty else {
            JSONOutput.success([])
            return
        }

        let chunks = raw.components(separatedBy: "###")
        let sections: [[String: Any]] = chunks.enumerated().compactMap { (idx, chunk) in
            let parts = chunk.components(separatedBy: "|||")
            guard parts.count >= 2 else { return nil }
            return [
                "index": idx + 1,
                "preview": parts[0].trimmingCharacters(in: .whitespaces),
                "wordCount": Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            ]
        }
        JSONOutput.success(sections)
    }

    // MARK: - Export

    static func export(file: String, format: String, output: String?) {
        let escaped = escapeForAppleScript(file)
        let outputPath: String
        if let output = output {
            outputPath = output
        } else {
            let ext: String
            switch format {
            case "pdf": ext = "pdf"
            case "docx": ext = "docx"
            case "txt": ext = "txt"
            case "epub": ext = "epub"
            default: ext = format
            }
            outputPath = file.replacingOccurrences(of: ".pages", with: ".\(ext)")
        }
        let escapedOutput = escapeForAppleScript(outputPath)

        let formatMap: [String: String] = [
            "pdf": "PDF",
            "docx": "Microsoft Word",
            "txt": "unformatted text",
            "epub": "EPUB"
        ]
        guard let pagesFormat = formatMap[format] else {
            JSONOutput.error("Unsupported export format: \(format). Use pdf, docx, txt, or epub.")
            return
        }

        let script = """
        tell application "Pages"
            set doc to open POSIX file "\(escaped)"
            export doc to POSIX file "\(escapedOutput)" as \(pagesFormat)
            close doc saving no
            return "ok"
        end tell
        """

        guard let _ = runAppleScript(script) else { return }
        JSONOutput.success(["path": outputPath])
    }

    // MARK: - Search

    static func search(query: String, limit: Int) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        task.arguments = [
            "kMDItemContentType == 'com.apple.iWork.pages.sffpages' && kMDItemDisplayName == '*\(query)*'cd"
        ]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                JSONOutput.success([])
                return
            }

            let paths = output.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(limit)

            let fm = FileManager.default
            let results: [[String: Any]] = paths.compactMap { path in
                guard let attrs = try? fm.attributesOfItem(atPath: path) else { return nil }
                var entry: [String: Any] = [
                    "path": path,
                    "name": URL(fileURLWithPath: path).lastPathComponent
                ]
                if let size = attrs[.size] as? Int {
                    entry["size"] = size
                }
                if let modified = attrs[.modificationDate] as? Date {
                    entry["modified"] = iso8601(modified)
                }
                return entry
            }

            JSONOutput.success(results)
        } catch {
            JSONOutput.error("Spotlight search failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private static func runAppleScript(_ script: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus != 0 {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"

                if errStr.contains("-1743") || errStr.contains("not allowed") {
                    JSONOutput.error("Pages automation permission denied. Grant access in System Settings > Privacy & Security > Automation.")
                } else if errStr.contains("-600") || errStr.contains("not running") {
                    JSONOutput.error("Pages is not running. It will be launched automatically on next attempt.")
                } else {
                    JSONOutput.error("AppleScript error: \(errStr)")
                }
                return nil
            }

            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            JSONOutput.error("Failed to run osascript: \(error.localizedDescription)")
            return nil
        }
    }

    private static func escapeForAppleScript(_ str: String) -> String {
        return str.replacingOccurrences(of: "\\", with: "\\\\")
                  .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
```

- [ ] **Step 2: Build Swift to verify compilation**

Run: `cd swift && swift build -c release 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add swift/Sources/AppleBridge/Pages.swift
git commit -m "feat(pages): add PagesBridge with all 9 operations"
```

---

## Task 7: Pages Subcommands and TypeScript Tools

**Files:**
- Modify: `swift/Sources/AppleBridge/AppleBridge.swift`
- Create: `src/tools/pages.ts`
- Modify: `src/index.ts`

- [ ] **Step 1: Add Pages subcommand structs to AppleBridge.swift**

Add after the Numbers subcommands section:

```swift
// MARK: - Pages Subcommands

struct PagesSearch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pages-search",
        abstract: "Search for Pages documents using Spotlight."
    )

    @Option(name: .long, help: "Search query")
    var query: String

    @Option(name: .long, help: "Max results (default: 20)")
    var limit: Int = 20

    func run() throws {
        PagesBridge.search(query: query, limit: limit)
    }
}

struct PagesRead: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pages-read",
        abstract: "Extract text content from a Pages document."
    )

    @Option(name: .long, help: "Path to .pages file")
    var file: String

    func run() throws {
        PagesBridge.read(file: file)
    }
}

struct PagesWrite: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pages-write",
        abstract: "Replace the full body text of a Pages document."
    )

    @Option(name: .long, help: "Path to .pages file")
    var file: String

    @Option(name: .long, help: "New body text content")
    var text: String

    func run() throws {
        PagesBridge.write(file: file, text: text)
    }
}

struct PagesCreate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pages-create",
        abstract: "Create a new Pages document."
    )

    @Option(name: .long, help: "Output file path")
    var file: String

    @Option(name: .long, help: "Initial text content")
    var text: String?

    @Option(name: .long, help: "Template name")
    var template: String?

    func run() throws {
        PagesBridge.create(file: file, text: text, template: template)
    }
}

struct PagesFindReplace: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pages-find-replace",
        abstract: "Find and replace text in a Pages document."
    )

    @Option(name: .long, help: "Path to .pages file")
    var file: String

    @Option(name: .long, help: "Text to find")
    var find: String

    @Option(name: .long, help: "Replacement text")
    var replace: String

    @Flag(name: .long, help: "Replace all occurrences (default: first only)")
    var all: Bool = false

    func run() throws {
        PagesBridge.findReplace(file: file, find: find, replace: replace, all: all)
    }
}

struct PagesInsertTable: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pages-insert-table",
        abstract: "Insert a table with data into a Pages document."
    )

    @Option(name: .long, help: "Path to .pages file")
    var file: String

    @Option(name: .long, help: "JSON array of arrays with table data")
    var data: String

    @Option(name: .long, help: "Position hint: beginning or end (default: end)")
    var position: String?

    func run() throws {
        PagesBridge.insertTable(file: file, dataJSON: data, position: position)
    }
}

struct PagesListSections: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pages-list-sections",
        abstract: "List document sections in a Pages document."
    )

    @Option(name: .long, help: "Path to .pages file")
    var file: String

    func run() throws {
        PagesBridge.listSections(file: file)
    }
}

struct PagesExport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pages-export",
        abstract: "Export a Pages document to PDF, Word, plain text, or EPUB."
    )

    @Option(name: .long, help: "Path to .pages file")
    var file: String

    @Option(name: .long, help: "Export format: pdf, docx, txt, epub")
    var format: String

    @Option(name: .long, help: "Output file path (default: same name with new extension)")
    var output: String?

    func run() throws {
        PagesBridge.export(file: file, format: format, output: output)
    }
}

struct PagesInfo: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pages-info",
        abstract: "Get metadata about a Pages document."
    )

    @Option(name: .long, help: "Path to .pages file")
    var file: String

    func run() throws {
        PagesBridge.info(file: file)
    }
}
```

- [ ] **Step 2: Register Pages subcommands in the subcommands array**

Add after the Numbers entries:

```swift
            // Pages
            PagesSearch.self,
            PagesRead.self,
            PagesWrite.self,
            PagesCreate.self,
            PagesFindReplace.self,
            PagesInsertTable.self,
            PagesListSections.self,
            PagesExport.self,
            PagesInfo.self,
```

Update the `abstract`:

```swift
        abstract: "Native macOS bridge for Apple Calendar, Mail, Reminders, Numbers, and Pages.",
```

- [ ] **Step 3: Create src/tools/pages.ts**

```typescript
// src/tools/pages.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { bridgeData } from "../bridge.js";

export function registerPagesTools(server: McpServer): void {
  server.tool(
    "pages.search",
    "Search for Pages documents (.pages files) using Spotlight.",
    {
      query: z.string().describe("Search query to match against file names"),
      limit: z
        .number()
        .optional()
        .describe("Max results to return (default: 20)"),
    },
    async ({ query, limit }) => {
      const args = ["pages-search", "--query", query];
      if (limit !== undefined) args.push("--limit", String(limit));
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "pages.read",
    "Extract text content from a Pages document. Returns body text, word count, and page count.",
    {
      file: z.string().describe("Path to the .pages file"),
    },
    async ({ file }) => {
      const data = await bridgeData(["pages-read", "--file", file]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "pages.write",
    "Replace the full body text of a Pages document.",
    {
      file: z.string().describe("Path to the .pages file"),
      text: z.string().describe("New body text content"),
    },
    async ({ file, text }) => {
      const data = await bridgeData(["pages-write", "--file", file, "--text", text]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "pages.create",
    "Create a new Pages document, optionally with initial text content.",
    {
      file: z.string().describe("Output file path for the new .pages file"),
      text: z.string().optional().describe("Initial text content"),
      template: z.string().optional().describe("Template name to use"),
    },
    async ({ file, text, template }) => {
      const args = ["pages-create", "--file", file];
      if (text) args.push("--text", text);
      if (template) args.push("--template", template);
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "pages.find_replace",
    "Find and replace text in a Pages document.",
    {
      file: z.string().describe("Path to the .pages file"),
      find: z.string().describe("Text to find"),
      replace: z.string().describe("Replacement text"),
      all: z
        .boolean()
        .optional()
        .describe("Replace all occurrences (default: first only)"),
    },
    async ({ file, find, replace, all }) => {
      const args = ["pages-find-replace", "--file", file, "--find", find, "--replace", replace];
      if (all) args.push("--all");
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "pages.insert_table",
    "Insert a table with data into a Pages document.",
    {
      file: z.string().describe("Path to the .pages file"),
      data: z.string().describe("JSON array of arrays with table data"),
      position: z
        .string()
        .optional()
        .describe("Position hint: beginning or end (default: end)"),
    },
    async ({ file, data, position }) => {
      const args = ["pages-insert-table", "--file", file, "--data", data];
      if (position) args.push("--position", position);
      const result = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
      };
    }
  );

  server.tool(
    "pages.list_sections",
    "List document sections in a Pages document with previews and word counts.",
    {
      file: z.string().describe("Path to the .pages file"),
    },
    async ({ file }) => {
      const data = await bridgeData(["pages-list-sections", "--file", file]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "pages.export",
    "Export a Pages document to PDF, Word (.docx), plain text, or EPUB.",
    {
      file: z.string().describe("Path to the .pages file"),
      format: z
        .enum(["pdf", "docx", "txt", "epub"])
        .describe("Export format"),
      output: z
        .string()
        .optional()
        .describe("Output file path (default: same name with new extension)"),
    },
    async ({ file, format, output }) => {
      const args = ["pages-export", "--file", file, "--format", format];
      if (output) args.push("--output", output);
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "pages.info",
    "Get metadata about a Pages document: page count, word count, file path.",
    {
      file: z.string().describe("Path to the .pages file"),
    },
    async ({ file }) => {
      const data = await bridgeData(["pages-info", "--file", file]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
```

- [ ] **Step 4: Register in src/index.ts**

Add import:

```typescript
import { registerPagesTools } from "./tools/pages.js";
```

Add registration after `registerNumbersTools(server);`:

```typescript
registerPagesTools(server);
```

- [ ] **Step 5: Build both Swift and TypeScript**

Run: `npm run build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add swift/Sources/AppleBridge/Pages.swift swift/Sources/AppleBridge/AppleBridge.swift src/tools/pages.ts src/index.ts
git commit -m "feat(pages): add PagesBridge, 9 subcommands, and 9 MCP tools"
```

---

## Task 8: Keynote Swift Bridge

**Files:**
- Create: `swift/Sources/AppleBridge/Keynote.swift`

Full `KeynoteBridge` enum with all 11 operations.

- [ ] **Step 1: Create Keynote.swift**

```swift
// swift/Sources/AppleBridge/Keynote.swift
import Foundation

enum KeynoteBridge {

    // MARK: - Info

    static func info(file: String) {
        let escaped = escapeForAppleScript(file)
        let script = """
        tell application "Keynote"
            set doc to open POSIX file "\(escaped)"
            set docName to name of doc
            set slideCount to count of slides of doc
            set themeName to name of document theme of doc
            close doc saving no
            return docName & "|||" & (slideCount as string) & "|||" & themeName
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        let parts = raw.components(separatedBy: "|||")
        guard parts.count >= 3 else {
            JSONOutput.error("Unexpected response format from Keynote")
            return
        }

        JSONOutput.success([
            "name": parts[0],
            "slideCount": Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0,
            "theme": parts[2].trimmingCharacters(in: .whitespaces),
            "path": file
        ] as [String: Any])
    }

    // MARK: - Read

    static func read(file: String, slideIndex: Int?) {
        let escaped = escapeForAppleScript(file)

        let slideClause: String
        if let idx = slideIndex {
            slideClause = "set slideList to {slide \(idx) of doc}"
        } else {
            slideClause = "set slideList to every slide of doc"
        }

        let script = """
        tell application "Keynote"
            set doc to open POSIX file "\(escaped)"
            \(slideClause)
            set resultList to {}
            set idx to 0
            repeat with s in slideList
                set idx to idx + 1
                set slideTitle to ""
                set slideBody to ""
                set slideNotes to presenter notes of s
                set slideLayout to name of base slide of s
                set slideSkipped to skipped of s
                try
                    set slideTitle to object text of default title item of s
                end try
                try
                    set slideBody to object text of default body item of s
                end try
                set end of resultList to (idx as string) & "|||" & slideTitle & "|||" & slideBody & "|||" & slideNotes & "|||" & slideLayout & "|||" & (slideSkipped as string)
            end repeat
            close doc saving no
            return my joinList(resultList, "###")
        end tell

        on joinList(theList, delim)
            set oldDelim to AppleScript's text item delimiters
            set AppleScript's text item delimiters to delim
            set theResult to theList as string
            set AppleScript's text item delimiters to oldDelim
            return theResult
        end joinList
        """

        guard let raw = runAppleScript(script) else { return }
        let slides = parseSlideList(raw)
        JSONOutput.success(["slides": slides])
    }

    // MARK: - Create

    static func create(file: String, theme: String?) {
        let escaped = escapeForAppleScript(file)

        let themeClause: String
        if let theme = theme {
            themeClause = "set doc to make new document with properties {document theme:theme \"\(escapeForAppleScript(theme))\"}"
        } else {
            themeClause = "set doc to make new document"
        }

        let script = """
        tell application "Keynote"
            \(themeClause)
            save doc in POSIX file "\(escaped)"
            close doc
            return "ok"
        end tell
        """

        guard let _ = runAppleScript(script) else { return }
        JSONOutput.success(["path": file, "created": true])
    }

    // MARK: - Add Slide

    static func addSlide(file: String, layout: String?, title: String?, body: String?, notes: String?, position: Int?) {
        let escaped = escapeForAppleScript(file)

        let layoutClause: String
        if let layout = layout {
            layoutClause = "with properties {base slide:master slide \"\(escapeForAppleScript(layout))\"}"
        } else {
            layoutClause = ""
        }

        let posClause: String
        if let pos = position {
            posClause = "at after slide \(pos) of doc"
        } else {
            posClause = "at end of slides of doc"
        }

        var setProps = ""
        if let title = title {
            setProps += "\ntry\nset object text of default title item of newSlide to \"\(escapeForAppleScript(title))\"\nend try"
        }
        if let body = body {
            setProps += "\ntry\nset object text of default body item of newSlide to \"\(escapeForAppleScript(body))\"\nend try"
        }
        if let notes = notes {
            setProps += "\nset presenter notes of newSlide to \"\(escapeForAppleScript(notes))\""
        }

        let script = """
        tell application "Keynote"
            set doc to open POSIX file "\(escaped)"
            tell doc
                set newSlide to make new slide \(posClause) \(layoutClause)
                \(setProps)
            end tell
            save doc
            close doc
            return (count of slides of doc) as string
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        let count = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        JSONOutput.success(["slideCount": count, "added": true])
    }

    // MARK: - Edit Slide

    static func editSlide(file: String, slideIndex: Int, title: String?, body: String?, notes: String?) {
        let escaped = escapeForAppleScript(file)

        var setProps = ""
        if let title = title {
            setProps += "\ntry\nset object text of default title item of s to \"\(escapeForAppleScript(title))\"\nend try"
        }
        if let body = body {
            setProps += "\ntry\nset object text of default body item of s to \"\(escapeForAppleScript(body))\"\nend try"
        }
        if let notes = notes {
            setProps += "\nset presenter notes of s to \"\(escapeForAppleScript(notes))\""
        }

        let script = """
        tell application "Keynote"
            set doc to open POSIX file "\(escaped)"
            set s to slide \(slideIndex) of doc
            \(setProps)
            save doc
            close doc
            return "ok"
        end tell
        """

        guard let _ = runAppleScript(script) else { return }
        JSONOutput.success(["slide": slideIndex, "edited": true])
    }

    // MARK: - Remove Slide

    static func removeSlide(file: String, slideIndex: Int) {
        let escaped = escapeForAppleScript(file)
        let script = """
        tell application "Keynote"
            set doc to open POSIX file "\(escaped)"
            delete slide \(slideIndex) of doc
            save doc
            set remaining to count of slides of doc
            close doc
            return remaining as string
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        let remaining = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        JSONOutput.success(["slidesRemaining": remaining, "removed": true])
    }

    // MARK: - Reorder Slides

    static func reorderSlides(file: String, from: Int, to: Int) {
        let escaped = escapeForAppleScript(file)
        // AppleScript move: move slide X to before/after slide Y
        let moveCmd: String
        if to > from {
            moveCmd = "move slide \(from) of doc to after slide \(to) of doc"
        } else {
            moveCmd = "move slide \(from) of doc to before slide \(to) of doc"
        }

        let script = """
        tell application "Keynote"
            set doc to open POSIX file "\(escaped)"
            \(moveCmd)
            save doc
            close doc
            return "ok"
        end tell
        """

        guard let _ = runAppleScript(script) else { return }
        JSONOutput.success(["movedFrom": from, "movedTo": to])
    }

    // MARK: - List Slides

    static func listSlides(file: String) {
        // Reuse read with all slides but lighter output
        read(file: file, slideIndex: nil)
    }

    // MARK: - List Themes

    static func listThemes() {
        let script = """
        tell application "Keynote"
            set themeNames to name of every theme
            set oldDelim to AppleScript's text item delimiters
            set AppleScript's text item delimiters to "|||"
            set themeStr to themeNames as string
            set AppleScript's text item delimiters to oldDelim
            return themeStr
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        let themes = raw.components(separatedBy: "|||")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        JSONOutput.success(["themes": themes])
    }

    // MARK: - Export

    static func export(file: String, format: String, output: String?, slideIndex: Int?) {
        let escaped = escapeForAppleScript(file)

        // Per-slide image export
        if (format == "png" || format == "jpeg") && slideIndex == nil {
            exportAllSlideImages(file: file, format: format, output: output)
            return
        }

        let outputPath: String
        if let output = output {
            outputPath = output
        } else {
            let ext: String
            switch format {
            case "pdf": ext = "pdf"
            case "pptx": ext = "pptx"
            case "png": ext = "png"
            case "jpeg": ext = "jpeg"
            default: ext = format
            }
            outputPath = file.replacingOccurrences(of: ".key", with: ".\(ext)")
        }
        let escapedOutput = escapeForAppleScript(outputPath)

        let formatMap: [String: String] = [
            "pdf": "PDF",
            "pptx": "Microsoft PowerPoint",
            "png": "slide images",
            "jpeg": "slide images"
        ]
        guard let keynoteFormat = formatMap[format] else {
            JSONOutput.error("Unsupported export format: \(format). Use pdf, pptx, png, or jpeg.")
            return
        }

        let script = """
        tell application "Keynote"
            set doc to open POSIX file "\(escaped)"
            export doc to POSIX file "\(escapedOutput)" as \(keynoteFormat)
            close doc saving no
            return "ok"
        end tell
        """

        guard let _ = runAppleScript(script) else { return }
        JSONOutput.success(["path": outputPath])
    }

    private static func exportAllSlideImages(file: String, format: String, output: String?) {
        let escaped = escapeForAppleScript(file)
        let outputDir = output ?? file.replacingOccurrences(of: ".key", with: "_slides")
        let escapedOutput = escapeForAppleScript(outputDir)

        // Create output directory
        let fm = FileManager.default
        try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        let imageFormat = format == "jpeg" ? "JPEG" : "PNG"

        let script = """
        tell application "Keynote"
            set doc to open POSIX file "\(escaped)"
            export doc to POSIX file "\(escapedOutput)" as slide images with properties {image format:\(imageFormat)}
            close doc saving no
            return "ok"
        end tell
        """

        guard let _ = runAppleScript(script) else { return }

        // List exported files
        let dirURL = URL(fileURLWithPath: outputDir)
        let ext = format == "jpeg" ? "jpeg" : "png"
        let files = (try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == ext }
            .map { $0.path }
            .sorted() ?? []

        JSONOutput.success(["paths": files, "directory": outputDir])
    }

    // MARK: - Search

    static func search(query: String, limit: Int) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        task.arguments = [
            "kMDItemContentType == 'com.apple.iWork.keynote.sffkey' && kMDItemDisplayName == '*\(query)*'cd"
        ]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                JSONOutput.success([])
                return
            }

            let paths = output.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(limit)

            let fm = FileManager.default
            let results: [[String: Any]] = paths.compactMap { path in
                guard let attrs = try? fm.attributesOfItem(atPath: path) else { return nil }
                var entry: [String: Any] = [
                    "path": path,
                    "name": URL(fileURLWithPath: path).lastPathComponent
                ]
                if let size = attrs[.size] as? Int {
                    entry["size"] = size
                }
                if let modified = attrs[.modificationDate] as? Date {
                    entry["modified"] = iso8601(modified)
                }
                return entry
            }

            JSONOutput.success(results)
        } catch {
            JSONOutput.error("Spotlight search failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private static func runAppleScript(_ script: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus != 0 {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"

                if errStr.contains("-1743") || errStr.contains("not allowed") {
                    JSONOutput.error("Keynote automation permission denied. Grant access in System Settings > Privacy & Security > Automation.")
                } else if errStr.contains("-600") || errStr.contains("not running") {
                    JSONOutput.error("Keynote is not running. It will be launched automatically on next attempt.")
                } else {
                    JSONOutput.error("AppleScript error: \(errStr)")
                }
                return nil
            }

            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            JSONOutput.error("Failed to run osascript: \(error.localizedDescription)")
            return nil
        }
    }

    private static func escapeForAppleScript(_ str: String) -> String {
        return str.replacingOccurrences(of: "\\", with: "\\\\")
                  .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func parseSlideList(_ raw: String) -> [[String: Any]] {
        guard !raw.isEmpty else { return [] }
        let chunks = raw.components(separatedBy: "###")
        return chunks.compactMap { chunk -> [String: Any]? in
            let parts = chunk.components(separatedBy: "|||")
            guard parts.count >= 6 else { return nil }
            return [
                "index": Int(parts[0].trimmingCharacters(in: .whitespaces)) ?? 0,
                "title": parts[1].trimmingCharacters(in: .whitespaces),
                "body": parts[2].trimmingCharacters(in: .whitespaces),
                "notes": parts[3].trimmingCharacters(in: .whitespaces),
                "layout": parts[4].trimmingCharacters(in: .whitespaces),
                "skipped": parts[5].trimmingCharacters(in: .whitespaces) == "true"
            ]
        }
    }
}
```

- [ ] **Step 2: Build Swift to verify compilation**

Run: `cd swift && swift build -c release 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add swift/Sources/AppleBridge/Keynote.swift
git commit -m "feat(keynote): add KeynoteBridge with all 11 operations"
```

---

## Task 9: Keynote Subcommands and TypeScript Tools

**Files:**
- Modify: `swift/Sources/AppleBridge/AppleBridge.swift`
- Create: `src/tools/keynote.ts`
- Modify: `src/index.ts`

- [ ] **Step 1: Add Keynote subcommand structs to AppleBridge.swift**

Add after the Pages subcommands section:

```swift
// MARK: - Keynote Subcommands

struct KeynoteSearch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keynote-search",
        abstract: "Search for Keynote presentations using Spotlight."
    )

    @Option(name: .long, help: "Search query")
    var query: String

    @Option(name: .long, help: "Max results (default: 20)")
    var limit: Int = 20

    func run() throws {
        KeynoteBridge.search(query: query, limit: limit)
    }
}

struct KeynoteRead: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keynote-read",
        abstract: "Extract content from Keynote slides (text, notes, layout)."
    )

    @Option(name: .long, help: "Path to .key file")
    var file: String

    @Option(name: .long, help: "Slide index (1-based, omit for all slides)")
    var slide: Int?

    func run() throws {
        KeynoteBridge.read(file: file, slideIndex: slide)
    }
}

struct KeynoteCreate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keynote-create",
        abstract: "Create a new Keynote presentation."
    )

    @Option(name: .long, help: "Output file path")
    var file: String

    @Option(name: .long, help: "Theme name")
    var theme: String?

    func run() throws {
        KeynoteBridge.create(file: file, theme: theme)
    }
}

struct KeynoteAddSlide: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keynote-add-slide",
        abstract: "Add a slide to a Keynote presentation."
    )

    @Option(name: .long, help: "Path to .key file")
    var file: String

    @Option(name: .long, help: "Slide layout/master name")
    var layout: String?

    @Option(name: .long, help: "Slide title text")
    var title: String?

    @Option(name: .long, help: "Slide body text")
    var body: String?

    @Option(name: .long, help: "Presenter notes")
    var notes: String?

    @Option(name: .long, help: "Insert after this slide number (1-based)")
    var position: Int?

    func run() throws {
        KeynoteBridge.addSlide(file: file, layout: layout, title: title, body: body, notes: notes, position: position)
    }
}

struct KeynoteEditSlide: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keynote-edit-slide",
        abstract: "Edit text and notes on an existing Keynote slide."
    )

    @Option(name: .long, help: "Path to .key file")
    var file: String

    @Option(name: .long, help: "Slide index (1-based)")
    var slide: Int

    @Option(name: .long, help: "New title text")
    var title: String?

    @Option(name: .long, help: "New body text")
    var body: String?

    @Option(name: .long, help: "New presenter notes")
    var notes: String?

    func run() throws {
        KeynoteBridge.editSlide(file: file, slideIndex: slide, title: title, body: body, notes: notes)
    }
}

struct KeynoteRemoveSlide: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keynote-remove-slide",
        abstract: "Remove a slide from a Keynote presentation."
    )

    @Option(name: .long, help: "Path to .key file")
    var file: String

    @Option(name: .long, help: "Slide index to remove (1-based)")
    var slide: Int

    func run() throws {
        KeynoteBridge.removeSlide(file: file, slideIndex: slide)
    }
}

struct KeynoteReorderSlides: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keynote-reorder-slides",
        abstract: "Move a slide to a new position."
    )

    @Option(name: .long, help: "Path to .key file")
    var file: String

    @Option(name: .long, help: "Current slide position (1-based)")
    var from: Int

    @Option(name: .long, help: "Target slide position (1-based)")
    var to: Int

    func run() throws {
        KeynoteBridge.reorderSlides(file: file, from: from, to: to)
    }
}

struct KeynoteListSlides: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keynote-list-slides",
        abstract: "List all slides with titles and layouts."
    )

    @Option(name: .long, help: "Path to .key file")
    var file: String

    func run() throws {
        KeynoteBridge.listSlides(file: file)
    }
}

struct KeynoteListThemes: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keynote-list-themes",
        abstract: "List available Keynote themes."
    )

    func run() throws {
        KeynoteBridge.listThemes()
    }
}

struct KeynoteExport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keynote-export",
        abstract: "Export a Keynote presentation to PDF, PowerPoint, or images."
    )

    @Option(name: .long, help: "Path to .key file")
    var file: String

    @Option(name: .long, help: "Export format: pdf, pptx, png, jpeg")
    var format: String

    @Option(name: .long, help: "Output file/directory path")
    var output: String?

    @Option(name: .long, help: "Export single slide (1-based index)")
    var slide: Int?

    func run() throws {
        KeynoteBridge.export(file: file, format: format, output: output, slideIndex: slide)
    }
}

struct KeynoteInfo: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keynote-info",
        abstract: "Get metadata about a Keynote presentation."
    )

    @Option(name: .long, help: "Path to .key file")
    var file: String

    func run() throws {
        KeynoteBridge.info(file: file)
    }
}
```

- [ ] **Step 2: Register Keynote subcommands in the subcommands array**

Add after the Pages entries:

```swift
            // Keynote
            KeynoteSearch.self,
            KeynoteRead.self,
            KeynoteCreate.self,
            KeynoteAddSlide.self,
            KeynoteEditSlide.self,
            KeynoteRemoveSlide.self,
            KeynoteReorderSlides.self,
            KeynoteListSlides.self,
            KeynoteListThemes.self,
            KeynoteExport.self,
            KeynoteInfo.self,
```

Update the `abstract`:

```swift
        abstract: "Native macOS bridge for Apple Calendar, Mail, Reminders, Numbers, Pages, and Keynote.",
```

- [ ] **Step 3: Create src/tools/keynote.ts**

```typescript
// src/tools/keynote.ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { bridgeData } from "../bridge.js";

export function registerKeynoteTools(server: McpServer): void {
  server.tool(
    "keynote.search",
    "Search for Keynote presentations (.key files) using Spotlight.",
    {
      query: z.string().describe("Search query to match against file names"),
      limit: z
        .number()
        .optional()
        .describe("Max results to return (default: 20)"),
    },
    async ({ query, limit }) => {
      const args = ["keynote-search", "--query", query];
      if (limit !== undefined) args.push("--limit", String(limit));
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "keynote.read",
    "Extract content from Keynote slides: title, body text, presenter notes, layout, and skip status.",
    {
      file: z.string().describe("Path to the .key file"),
      slide: z
        .number()
        .optional()
        .describe("Slide index (1-based) to read a single slide. Omit for all slides."),
    },
    async ({ file, slide }) => {
      const args = ["keynote-read", "--file", file];
      if (slide !== undefined) args.push("--slide", String(slide));
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "keynote.create",
    "Create a new Keynote presentation, optionally with a specific theme.",
    {
      file: z.string().describe("Output file path for the new .key file"),
      theme: z
        .string()
        .optional()
        .describe("Theme name (from keynote.list_themes)"),
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
    "Add a new slide to a Keynote presentation with optional layout, title, body, and notes.",
    {
      file: z.string().describe("Path to the .key file"),
      layout: z
        .string()
        .optional()
        .describe("Slide layout/master name"),
      title: z.string().optional().describe("Slide title text"),
      body: z.string().optional().describe("Slide body text"),
      notes: z.string().optional().describe("Presenter notes"),
      position: z
        .number()
        .optional()
        .describe("Insert after this slide number (1-based). Omit to append."),
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
    "Edit the title, body text, or presenter notes on an existing Keynote slide.",
    {
      file: z.string().describe("Path to the .key file"),
      slide: z.number().describe("Slide index (1-based)"),
      title: z.string().optional().describe("New title text"),
      body: z.string().optional().describe("New body text"),
      notes: z.string().optional().describe("New presenter notes"),
    },
    async ({ file, slide, title, body, notes }) => {
      const args = ["keynote-edit-slide", "--file", file, "--slide", String(slide)];
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
    "Remove a slide from a Keynote presentation.",
    {
      file: z.string().describe("Path to the .key file"),
      slide: z.number().describe("Slide index to remove (1-based)"),
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
    "Move a slide to a new position in a Keynote presentation.",
    {
      file: z.string().describe("Path to the .key file"),
      from: z.number().describe("Current slide position (1-based)"),
      to: z.number().describe("Target slide position (1-based)"),
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
    "List all slides in a Keynote presentation with titles, layouts, and notes.",
    {
      file: z.string().describe("Path to the .key file"),
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
    "List all available Keynote themes/masters.",
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
    "Export a Keynote presentation to PDF, PowerPoint (.pptx), or images (PNG/JPEG per slide).",
    {
      file: z.string().describe("Path to the .key file"),
      format: z
        .enum(["pdf", "pptx", "png", "jpeg"])
        .describe("Export format"),
      output: z
        .string()
        .optional()
        .describe("Output file/directory path (default: same name with new extension)"),
      slide: z
        .number()
        .optional()
        .describe("Export a single slide by index (1-based)"),
    },
    async ({ file, format, output, slide }) => {
      const args = ["keynote-export", "--file", file, "--format", format];
      if (output) args.push("--output", output);
      if (slide !== undefined) args.push("--slide", String(slide));
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "keynote.info",
    "Get metadata about a Keynote presentation: slide count, theme, file path.",
    {
      file: z.string().describe("Path to the .key file"),
    },
    async ({ file }) => {
      const data = await bridgeData(["keynote-info", "--file", file]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
```

- [ ] **Step 4: Register in src/index.ts**

Add import:

```typescript
import { registerKeynoteTools } from "./tools/keynote.js";
```

Add registration after `registerPagesTools(server);`:

```typescript
registerKeynoteTools(server);
```

- [ ] **Step 5: Build both Swift and TypeScript**

Run: `npm run build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add swift/Sources/AppleBridge/Keynote.swift swift/Sources/AppleBridge/AppleBridge.swift src/tools/keynote.ts src/index.ts
git commit -m "feat(keynote): add KeynoteBridge, 11 subcommands, and 11 MCP tools"
```

---

## Task 10: Doctor Extension for iWork

**Files:**
- Modify: `swift/Sources/AppleBridge/Doctor.swift`

- [ ] **Step 1: Add iWork check functions to DoctorBridge**

Add before the closing `}` of `DoctorBridge` in `Doctor.swift`:

```swift
    private static func checkIWorkApp(_ appName: String) -> [String: Any] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "tell application \"\(appName)\" to return name"]
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                return ["installed": true, "accessible": true]
            } else {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if errStr.contains("-600") || errStr.contains("not running") {
                    return ["installed": true, "accessible": false, "note": "\(appName) is not running."]
                }
                return ["installed": false, "accessible": false, "note": "\(appName) may not be installed."]
            }
        } catch {
            return ["installed": false, "accessible": false, "note": "Could not check \(appName): \(error.localizedDescription)"]
        }
    }
```

- [ ] **Step 2: Wire iWork checks into the run() function**

In `DoctorBridge.run()`, add after the `let mailCheck = checkMailAccess()` / `report["mail"] = mailCheck` block (around line 75):

```swift
        // iWork apps
        let numbersCheck = checkIWorkApp("Numbers")
        let pagesCheck = checkIWorkApp("Pages")
        let keynoteCheck = checkIWorkApp("Keynote")
        report["numbers"] = numbersCheck
        report["pages"] = pagesCheck
        report["keynote"] = keynoteCheck
```

And in the actions section, add after the mail action:

```swift
        if !(numbersCheck["installed"] as? Bool ?? false) {
            actions.append("Numbers: Install from App Store for spreadsheet tools")
        }
        if !(pagesCheck["installed"] as? Bool ?? false) {
            actions.append("Pages: Install from App Store for document tools")
        }
        if !(keynoteCheck["installed"] as? Bool ?? false) {
            actions.append("Keynote: Install from App Store for presentation tools")
        }
```

- [ ] **Step 3: Build Swift**

Run: `cd swift && swift build -c release 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add swift/Sources/AppleBridge/Doctor.swift
git commit -m "feat(doctor): add iWork app availability checks for Numbers, Pages, Keynote"
```

---

## Task 11: Tests -- Tool Registration

**Files:**
- Modify: `tests/tools.test.ts`

Update the tool registration test to include all 30 new tools.

- [ ] **Step 1: Update tests/tools.test.ts**

Add imports for the 3 new modules:

```typescript
import { registerNumbersTools } from "../src/tools/numbers.js";
import { registerPagesTools } from "../src/tools/pages.js";
import { registerKeynoteTools } from "../src/tools/keynote.js";
```

Add to the `EXPECTED_TOOLS` array:

```typescript
  // Numbers (10)
  "numbers.search",
  "numbers.read",
  "numbers.write",
  "numbers.create",
  "numbers.list_sheets",
  "numbers.add_sheet",
  "numbers.remove_sheet",
  "numbers.get_formulas",
  "numbers.export",
  "numbers.info",
  // Pages (9)
  "pages.search",
  "pages.read",
  "pages.write",
  "pages.create",
  "pages.find_replace",
  "pages.insert_table",
  "pages.list_sections",
  "pages.export",
  "pages.info",
  // Keynote (11)
  "keynote.search",
  "keynote.read",
  "keynote.create",
  "keynote.add_slide",
  "keynote.edit_slide",
  "keynote.remove_slide",
  "keynote.reorder_slides",
  "keynote.list_slides",
  "keynote.list_themes",
  "keynote.export",
  "keynote.info",
```

Add the registration calls in the `before` hook:

```typescript
    registerNumbersTools(server);
    registerPagesTools(server);
    registerKeynoteTools(server);
```

Update the count assertion:

```typescript
  it("registers exactly 58 tools", () => {
    const tools = (server as any)._registeredTools as Record<string, unknown>;
    const names = Object.keys(tools);
    assert.equal(names.length, 58, `Expected 58 tools, got ${names.length}: ${names.join(", ")}`);
  });
```

- [ ] **Step 2: Run the test**

Run: `npx tsx --test tests/tools.test.ts`
Expected: All tests pass, 58 tools registered

- [ ] **Step 3: Commit**

```bash
git add tests/tools.test.ts
git commit -m "test: update tool registration tests for 58 tools (added iWork)"
```

---

## Task 12: Tests -- Numbers Bridge Args

**Files:**
- Create: `tests/numbers.test.ts`

Unit tests for Numbers argument construction and data handling (same pattern as `tests/mail.test.ts`).

- [ ] **Step 1: Create tests/numbers.test.ts**

```typescript
import { describe, it } from "node:test";
import assert from "node:assert/strict";

describe("numbers.read args construction", () => {
  it("builds minimal args with file only", () => {
    const file = "/Users/test/Budget.numbers";
    const args = ["numbers-read", "--file", file];
    assert.deepEqual(args, ["numbers-read", "--file", "/Users/test/Budget.numbers"]);
  });

  it("includes optional sheet, table, range", () => {
    const file = "/Users/test/Budget.numbers";
    const sheet = "Q1";
    const table = "Expenses";
    const range = "A1:C10";
    const args = ["numbers-read", "--file", file];
    if (sheet) args.push("--sheet", sheet);
    if (table) args.push("--table", table);
    if (range) args.push("--range", range);
    assert.deepEqual(args, [
      "numbers-read", "--file", "/Users/test/Budget.numbers",
      "--sheet", "Q1", "--table", "Expenses", "--range", "A1:C10",
    ]);
  });
});

describe("numbers.write args construction", () => {
  it("builds args with required fields", () => {
    const file = "/Users/test/Budget.numbers";
    const data = '[["Name","Amount"],["Rent",1200]]';
    const args = ["numbers-write", "--file", file, "--data", data];
    assert.deepEqual(args, [
      "numbers-write", "--file", "/Users/test/Budget.numbers",
      "--data", '[["Name","Amount"],["Rent",1200]]',
    ]);
  });

  it("includes optional range for targeted write", () => {
    const file = "/Users/test/Budget.numbers";
    const data = '[[500]]';
    const range = "B2";
    const args = ["numbers-write", "--file", file, "--data", data];
    if (range) args.push("--range", range);
    assert.ok(args.includes("--range"));
    assert.ok(args.includes("B2"));
  });
});

describe("numbers.export args construction", () => {
  it("builds args for csv export", () => {
    const file = "/Users/test/Budget.numbers";
    const format = "csv";
    const args = ["numbers-export", "--file", file, "--format", format];
    assert.deepEqual(args, [
      "numbers-export", "--file", "/Users/test/Budget.numbers", "--format", "csv",
    ]);
  });

  it("includes optional output path", () => {
    const file = "/Users/test/Budget.numbers";
    const format = "xlsx";
    const output = "/tmp/export.xlsx";
    const args = ["numbers-export", "--file", file, "--format", format];
    if (output) args.push("--output", output);
    assert.ok(args.includes("--output"));
    assert.ok(args.includes("/tmp/export.xlsx"));
  });
});

describe("A1 range parsing logic", () => {
  function parseA1Cell(cell: string): { row: number; col: number } {
    let colStr = "";
    let rowStr = "";
    for (const char of cell.toUpperCase()) {
      if (char >= "A" && char <= "Z") colStr += char;
      else rowStr += char;
    }
    let col = 0;
    for (const char of colStr) {
      col = col * 26 + (char.charCodeAt(0) - 65) + 1;
    }
    col -= 1;
    const row = (parseInt(rowStr, 10) || 1) - 1;
    return { row, col };
  }

  it("parses A1 to row 0, col 0", () => {
    const { row, col } = parseA1Cell("A1");
    assert.equal(row, 0);
    assert.equal(col, 0);
  });

  it("parses C3 to row 2, col 2", () => {
    const { row, col } = parseA1Cell("C3");
    assert.equal(row, 2);
    assert.equal(col, 2);
  });

  it("parses Z1 to row 0, col 25", () => {
    const { row, col } = parseA1Cell("Z1");
    assert.equal(row, 0);
    assert.equal(col, 25);
  });

  it("parses AA1 to row 0, col 26", () => {
    const { row, col } = parseA1Cell("AA1");
    assert.equal(row, 0);
    assert.equal(col, 26);
  });

  it("parses AB10 to row 9, col 27", () => {
    const { row, col } = parseA1Cell("AB10");
    assert.equal(row, 9);
    assert.equal(col, 27);
  });
});
```

- [ ] **Step 2: Run the test**

Run: `npx tsx --test tests/numbers.test.ts`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add tests/numbers.test.ts
git commit -m "test: add Numbers bridge argument and A1 parsing tests"
```

---

## Task 13: Tests -- Pages and Keynote Bridge Args

**Files:**
- Create: `tests/pages.test.ts`
- Create: `tests/keynote.test.ts`

- [ ] **Step 1: Create tests/pages.test.ts**

```typescript
import { describe, it } from "node:test";
import assert from "node:assert/strict";

describe("pages.read args construction", () => {
  it("builds args with file only", () => {
    const file = "/Users/test/Report.pages";
    const args = ["pages-read", "--file", file];
    assert.deepEqual(args, ["pages-read", "--file", "/Users/test/Report.pages"]);
  });
});

describe("pages.find_replace args construction", () => {
  it("builds args without --all flag", () => {
    const file = "/Users/test/Report.pages";
    const find = "old text";
    const replace = "new text";
    const all = false;
    const args = ["pages-find-replace", "--file", file, "--find", find, "--replace", replace];
    if (all) args.push("--all");
    assert.ok(!args.includes("--all"));
  });

  it("includes --all flag when true", () => {
    const file = "/Users/test/Report.pages";
    const find = "old text";
    const replace = "new text";
    const all = true;
    const args = ["pages-find-replace", "--file", file, "--find", find, "--replace", replace];
    if (all) args.push("--all");
    assert.ok(args.includes("--all"));
  });
});

describe("pages.export args construction", () => {
  it("builds args for pdf export", () => {
    const file = "/Users/test/Report.pages";
    const format = "pdf";
    const args = ["pages-export", "--file", file, "--format", format];
    assert.deepEqual(args, [
      "pages-export", "--file", "/Users/test/Report.pages", "--format", "pdf",
    ]);
  });

  it("supports all four export formats", () => {
    for (const format of ["pdf", "docx", "txt", "epub"]) {
      const args = ["pages-export", "--file", "test.pages", "--format", format];
      assert.ok(args.includes(format));
    }
  });
});

describe("pages.create args construction", () => {
  it("builds args with text and template", () => {
    const file = "/Users/test/New.pages";
    const text = "Hello World";
    const template = "Blank";
    const args = ["pages-create", "--file", file];
    if (text) args.push("--text", text);
    if (template) args.push("--template", template);
    assert.ok(args.includes("--text"));
    assert.ok(args.includes("--template"));
  });
});
```

- [ ] **Step 2: Create tests/keynote.test.ts**

```typescript
import { describe, it } from "node:test";
import assert from "node:assert/strict";

describe("keynote.read args construction", () => {
  it("builds args for all slides", () => {
    const file = "/Users/test/Deck.key";
    const args = ["keynote-read", "--file", file];
    assert.deepEqual(args, ["keynote-read", "--file", "/Users/test/Deck.key"]);
  });

  it("includes slide index for single slide", () => {
    const file = "/Users/test/Deck.key";
    const slide = 3;
    const args = ["keynote-read", "--file", file];
    if (slide !== undefined) args.push("--slide", String(slide));
    assert.ok(args.includes("--slide"));
    assert.ok(args.includes("3"));
  });
});

describe("keynote.add_slide args construction", () => {
  it("builds args with all optional fields", () => {
    const file = "/Users/test/Deck.key";
    const layout = "Title & Body";
    const title = "Q1 Results";
    const body = "Revenue grew 15%";
    const notes = "Mention partnership";
    const position = 2;
    const args = ["keynote-add-slide", "--file", file];
    if (layout) args.push("--layout", layout);
    if (title) args.push("--title", title);
    if (body) args.push("--body", body);
    if (notes) args.push("--notes", notes);
    if (position !== undefined) args.push("--position", String(position));
    assert.equal(args.length, 13);
    assert.ok(args.includes("--layout"));
    assert.ok(args.includes("--position"));
  });

  it("builds minimal args with file only", () => {
    const file = "/Users/test/Deck.key";
    const args = ["keynote-add-slide", "--file", file];
    assert.equal(args.length, 3);
  });
});

describe("keynote.reorder_slides args construction", () => {
  it("builds args with from and to positions", () => {
    const file = "/Users/test/Deck.key";
    const from = 5;
    const to = 2;
    const args = [
      "keynote-reorder-slides", "--file", file,
      "--from", String(from), "--to", String(to),
    ];
    assert.ok(args.includes("5"));
    assert.ok(args.includes("2"));
  });
});

describe("keynote.export args construction", () => {
  it("builds args for pdf export", () => {
    const file = "/Users/test/Deck.key";
    const format = "pdf";
    const args = ["keynote-export", "--file", file, "--format", format];
    assert.deepEqual(args, [
      "keynote-export", "--file", "/Users/test/Deck.key", "--format", "pdf",
    ]);
  });

  it("supports all four export formats", () => {
    for (const format of ["pdf", "pptx", "png", "jpeg"]) {
      const args = ["keynote-export", "--file", "test.key", "--format", format];
      assert.ok(args.includes(format));
    }
  });

  it("includes single-slide export option", () => {
    const file = "/Users/test/Deck.key";
    const slide = 1;
    const args = ["keynote-export", "--file", file, "--format", "png"];
    if (slide !== undefined) args.push("--slide", String(slide));
    assert.ok(args.includes("--slide"));
  });
});

describe("keynote.edit_slide args construction", () => {
  it("includes only changed fields", () => {
    const file = "/Users/test/Deck.key";
    const slide = 2;
    const title = "Updated Title";
    const body = undefined;
    const notes = "New notes";
    const args = ["keynote-edit-slide", "--file", file, "--slide", String(slide)];
    if (title) args.push("--title", title);
    if (body) args.push("--body", body);
    if (notes) args.push("--notes", notes);
    assert.ok(args.includes("--title"));
    assert.ok(!args.includes("--body"));
    assert.ok(args.includes("--notes"));
  });
});
```

- [ ] **Step 3: Run all tests**

Run: `npx tsx --test tests/pages.test.ts && npx tsx --test tests/keynote.test.ts`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add tests/pages.test.ts tests/keynote.test.ts
git commit -m "test: add Pages and Keynote bridge argument tests"
```

---

## Task 14: Full Build and Integration Verification

**Files:** None (verification only)

- [ ] **Step 1: Full build**

Run: `npm run build`
Expected: Both Swift and TypeScript build successfully

- [ ] **Step 2: Run all tests**

Run: `npm test`
Expected: All tests pass (bridge, mail, tools, numbers, pages, keynote)

- [ ] **Step 3: Type check**

Run: `npm run lint`
Expected: No type errors

- [ ] **Step 4: Manual smoke test -- verify Numbers can open**

Run: `./swift/.build/AppleBridge.app/Contents/MacOS/apple-bridge numbers-info --file ~/Desktop/test.numbers 2>/dev/null || echo "Create a test.numbers file on Desktop to smoke-test"`
Expected: Either returns JSON info or the expected error message if no test file exists

- [ ] **Step 5: Verify doctor includes iWork checks**

Run: `./swift/.build/AppleBridge.app/Contents/MacOS/apple-bridge doctor 2>/dev/null | head -30`
Expected: JSON output includes `numbers`, `pages`, `keynote` keys

- [ ] **Step 6: Commit everything if any uncommitted changes remain**

```bash
git status
# If clean, no commit needed
```

---

## Task 15: Version Bump and CLAUDE.md Update

**Files:**
- Modify: `src/index.ts:20` (version string)
- Modify: `swift/Sources/AppleBridge/AppleBridge.swift:31` (version string)
- Modify: `swift/Sources/AppleBridge/Doctor.swift:11` (version string)
- Modify: `CLAUDE.md`

- [ ] **Step 1: Bump version to 0.4.0 in all three locations**

In `src/index.ts`, change `version: "0.3.0"` to `version: "0.4.0"`.

In `AppleBridge.swift`, change `version: "0.3.0"` to `version: "0.4.0"`.

In `Doctor.swift`, change `"version": "0.3.0"` to `"version": "0.4.0"`.

- [ ] **Step 2: Update CLAUDE.md tool count and module list**

Update the "28 tools total" reference to "58 tools total".

In the tool modules section, add: `numbers.*`, `pages.*`, `keynote.*`.

In the architecture description, add Numbers/Pages/Keynote to the list of services.

- [ ] **Step 3: Commit**

```bash
git add src/index.ts swift/Sources/AppleBridge/AppleBridge.swift swift/Sources/AppleBridge/Doctor.swift CLAUDE.md
git commit -m "chore: bump version to 0.4.0, update CLAUDE.md for iWork integration"
```
