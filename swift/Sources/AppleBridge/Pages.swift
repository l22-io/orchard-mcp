import Foundation

enum PagesBridge {

    // MARK: - Info

    static func info(file: String) {
        let escaped = escapeForAppleScript(file)
        let script = """
        tell application "Pages"
            set doc to open POSIX file "\(escaped)"
            set docName to name of doc
            set bodyText to body text of doc
            set wc to count of words of bodyText
            set pc to count of pages of doc
            close doc saving no
            return docName & "|||" & (wc as string) & "|||" & (pc as string)
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        let parts = raw.components(separatedBy: "|||")
        guard parts.count >= 3 else {
            JSONOutput.error("Unexpected response format from Pages")
            return
        }

        let result: [String: Any] = [
            "name": parts[0],
            "wordCount": Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0,
            "pageCount": Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 0,
            "path": file
        ]
        JSONOutput.success(result)
    }

    // MARK: - Read

    static func read(file: String) {
        let escaped = escapeForAppleScript(file)
        let script = """
        tell application "Pages"
            set doc to open POSIX file "\(escaped)"
            set bodyText to body text of doc
            set wc to count of words of bodyText
            set pc to count of pages of doc
            close doc saving no
            return bodyText & "|||" & (wc as string) & "|||" & (pc as string)
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        let parts = raw.components(separatedBy: "|||")
        guard parts.count >= 3 else {
            JSONOutput.error("Unexpected response format from Pages")
            return
        }

        let result: [String: Any] = [
            "text": parts[0],
            "wordCount": Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0,
            "pageCount": Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 0,
            "path": file
        ]
        JSONOutput.success(result)
    }

    // MARK: - Write

    static func write(file: String, text: String) {
        let escapedFile = escapeForAppleScript(file)
        let escapedText = escapeForAppleScript(text)
        let script = """
        tell application "Pages"
            set doc to open POSIX file "\(escapedFile)"
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
        if let text = text, !text.isEmpty {
            textClause = """
            set body text of doc to "\(escapeForAppleScript(text))"
            """
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
        let escapedFile = escapeForAppleScript(file)
        let escapedFind = escapeForAppleScript(find)
        let escapedReplace = escapeForAppleScript(replace)

        let replaceLogic: String
        if all {
            replaceLogic = """
            set AppleScript's text item delimiters to "\(escapedFind)"
            set textItems to text items of bodyText
            set matchCount to (count of textItems) - 1
            set AppleScript's text item delimiters to "\(escapedReplace)"
            set newText to textItems as string
            set AppleScript's text item delimiters to oldDelim
            """
        } else {
            replaceLogic = """
            set AppleScript's text item delimiters to "\(escapedFind)"
            set textItems to text items of bodyText
            if (count of textItems) > 1 then
                set matchCount to 1
                set firstPart to item 1 of textItems
                set restItems to items 2 thru -1 of textItems
                set AppleScript's text item delimiters to "\(escapedFind)"
                set restText to restItems as string
                set AppleScript's text item delimiters to oldDelim
                set newText to firstPart & "\(escapedReplace)" & restText
            else
                set matchCount to 0
                set newText to bodyText
            end if
            set AppleScript's text item delimiters to oldDelim
            """
        }

        let script = """
        tell application "Pages"
            set doc to open POSIX file "\(escapedFile)"
            set bodyText to body text of doc
        end tell
        set oldDelim to AppleScript's text item delimiters
        set matchCount to 0
        \(replaceLogic)
        tell application "Pages"
            set body text of doc to newText
            save doc
            close doc
            return matchCount as string
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        let count = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        JSONOutput.success(["replacements": count, "path": file])
    }

    // MARK: - Insert Table

    static func insertTable(file: String, dataJSON: String) {
        let escapedFile = escapeForAppleScript(file)

        guard let jsonData = dataJSON.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [[Any]] else {
            JSONOutput.error("Invalid data JSON: expected array of arrays")
            return
        }

        let rowCount = parsed.count
        guard rowCount > 0 else {
            JSONOutput.error("Data must contain at least one row")
            return
        }
        let colCount = parsed[0].count

        var cellScripts: [String] = []
        for (r, row) in parsed.enumerated() {
            for (c, val) in row.enumerated() {
                let cellVal: String
                if let num = val as? NSNumber {
                    cellVal = "\(num)"
                } else if let str = val as? String {
                    cellVal = "\"\(escapeForAppleScript(str))\""
                } else {
                    cellVal = "\"\(val)\""
                }
                cellScripts.append("set value of cell \(c + 1) of row \(r + 1) of newTable to \(cellVal)")
            }
        }

        let cellBlock = cellScripts.joined(separator: "\n            ")

        let script = """
        tell application "Pages"
            set doc to open POSIX file "\(escapedFile)"
            tell doc
                set newTable to make new table with properties {row count:\(rowCount), column count:\(colCount)}
                \(cellBlock)
            end tell
            save doc
            close doc
            return "ok"
        end tell
        """

        guard let _ = runAppleScript(script) else { return }
        JSONOutput.success([
            "path": file,
            "rows": rowCount,
            "columns": colCount,
            "inserted": true
        ])
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
                set sWords to word count of s
                set preview to ""
                if (count of characters of sBody) > 200 then
                    set preview to text 1 thru 200 of sBody
                else
                    set preview to sBody
                end if
                set end of sectionList to preview & "|||" & (sWords as string)
            end repeat
            close doc saving no
            set oldDelim to AppleScript's text item delimiters
            set AppleScript's text item delimiters to "###"
            set resultText to sectionList as string
            set AppleScript's text item delimiters to oldDelim
            return resultText
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        let sections = parseSectionList(raw)
        JSONOutput.success(sections)
    }

    // MARK: - Export

    static func export(file: String, format: String, dest: String?) {
        let escapedFile = escapeForAppleScript(file)
        let outputPath: String
        if let dest = dest {
            outputPath = dest
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
            set doc to open POSIX file "\(escapedFile)"
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

    // MARK: - Parsers

    private static func parseSectionList(_ raw: String) -> [[String: Any]] {
        guard !raw.isEmpty else { return [] }
        let sectionChunks = raw.components(separatedBy: "###")
        return sectionChunks.enumerated().compactMap { (index, chunk) -> [String: Any]? in
            let parts = chunk.components(separatedBy: "|||")
            guard parts.count >= 2 else { return nil }

            return [
                "index": index,
                "preview": parts[0].trimmingCharacters(in: .whitespaces),
                "wordCount": Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            ]
        }
    }
}
