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
        var doc = app.open(Path("\(escapedFile)"));
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

        let escapedData = dataJSON.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let script = """
        var app = Application("Numbers");
        var doc = app.open(Path("\(escapedFile)"));
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
        var doc = app.open(Path("\(escapedFile)"));
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

        if let dataJSON = dataJSON, !dataJSON.isEmpty {
            write(file: file, sheet: nil, table: nil, range: nil, dataJSON: dataJSON)
            return
        }

        JSONOutput.success(["path": file, "created": true])
    }

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

    // MARK: - A1 Range Parser

    private struct CellRange {
        let startRow: Int
        let startCol: Int
        let endRow: Int
        let endCol: Int
    }

    private static func parseA1Range(_ range: String) -> CellRange {
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
        var col = 0
        for char in colStr {
            col = col * 26 + Int(char.asciiValue! - 65) + 1
        }
        col -= 1
        let row = (Int(rowStr) ?? 1) - 1
        return (row, col)
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
