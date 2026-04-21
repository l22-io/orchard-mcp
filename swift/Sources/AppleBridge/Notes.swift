import Foundation

// Notes.app access uses AppleScript via osascript. Requires Automation
// permission (prompted on first call). Same pattern as Mail.swift.

enum NotesBridge {

    // MARK: - Public API

    static func listFolders() {
        let script = """
        tell application "Notes"
            set resultList to {}
            repeat with acct in every account
                set acctName to name of acct
                repeat with f in every folder of acct
                    set fName to name of f
                    set fCount to count of notes of f
                    set end of resultList to acctName & "|||" & fName & "|||" & (fCount as string)
                end repeat
            end repeat
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
        JSONOutput.success(parseFolderList(raw))
    }

    static func listNotes(folder: String?, account: String?, limit: Int) {
        let target: String
        if let f = folder, let a = account {
            target = "folder \"\(escapeForAppleScript(f))\" of account \"\(escapeForAppleScript(a))\""
        } else if let f = folder {
            target = "folder \"\(escapeForAppleScript(f))\""
        } else {
            target = "every note"
        }

        let collect: String
        if folder != nil {
            collect = "set noteList to (every note of \(target))"
        } else {
            collect = "set noteList to \(target)"
        }

        let script = """
        tell application "Notes"
            set resultList to {}
            \(collect)
            set noteCount to count of noteList
            set maxItems to \(limit)
            if noteCount < maxItems then set maxItems to noteCount
            repeat with i from 1 to maxItems
                set n to item i of noteList
                set nId to id of n
                set nName to name of n
                set nModified to (modification date of n) as «class isot» as string
                set end of resultList to nId & "|||" & nName & "|||" & nModified
            end repeat
            return my joinList(resultList, "###") & "###TOTAL:::" & (noteCount as string)
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
        let parts = raw.components(separatedBy: "###TOTAL:::")
        let total = parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0 : 0
        let notes = parseNoteList(parts[0])
        JSONOutput.success([
            "notes": notes,
            "total": total,
            "limit": limit,
            "hasMore": notes.count < total
        ] as [String: Any])
    }

    static func search(query: String, limit: Int, searchIn: String) {
        let escapedQuery = escapeForAppleScript(query)
        let whereClause: String
        switch searchIn {
        case "title":
            whereClause = "whose name contains searchQuery"
        case "body":
            whereClause = "whose plaintext contains searchQuery"
        default:
            whereClause = "whose name contains searchQuery or plaintext contains searchQuery"
        }

        let script = """
        tell application "Notes"
            set searchQuery to "\(escapedQuery)"
            set resultList to {}
            set matches to (every note \(whereClause))
            set matchCount to count of matches
            set maxItems to \(limit)
            if matchCount < maxItems then set maxItems to matchCount
            repeat with i from 1 to maxItems
                set n to item i of matches
                set nId to id of n
                set nName to name of n
                set nModified to (modification date of n) as «class isot» as string
                set end of resultList to nId & "|||" & nName & "|||" & nModified
            end repeat
            return my joinList(resultList, "###") & "###TOTAL:::" & (matchCount as string)
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
        let parts = raw.components(separatedBy: "###TOTAL:::")
        let total = parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0 : 0
        let notes = parseNoteList(parts[0])
        JSONOutput.success([
            "notes": notes,
            "total": total,
            "limit": limit,
            "hasMore": notes.count < total
        ] as [String: Any])
    }

    static func readNote(id: String, maxBodyLength: Int) {
        let escapedId = escapeForAppleScript(id)
        let script = """
        tell application "Notes"
            try
                set n to note id "\(escapedId)"
            on error
                return "ERROR_NOT_FOUND"
            end try
            set nName to name of n
            set nModified to (modification date of n) as «class isot» as string
            set nCreated to (creation date of n) as «class isot» as string
            set nBody to plaintext of n
            return nName & "|||" & nCreated & "|||" & nModified & "|||" & nBody
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        if raw == "ERROR_NOT_FOUND" {
            JSONOutput.error("Note not found: \(id)")
            return
        }
        let parts = raw.components(separatedBy: "|||")
        guard parts.count >= 4 else {
            JSONOutput.error("Unexpected response format from Notes.app")
            return
        }
        var body = parts[3]
        if maxBodyLength > 0 && body.count > maxBodyLength {
            body = String(body.prefix(maxBodyLength)) + "\n\n[truncated — \(body.count) chars total]"
        }
        JSONOutput.success([
            "id": id,
            "title": parts[0],
            "created": parts[1],
            "modified": parts[2],
            "body": body
        ])
    }

    // MARK: - AppleScript plumbing

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
                    JSONOutput.error("Notes automation permission denied. Grant access in System Settings > Privacy & Security > Automation > apple-bridge > Notes.")
                } else if errStr.contains("-600") || errStr.contains("not running") {
                    JSONOutput.error("Notes.app is not running. Open Notes.app and try again.")
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
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\" & (ASCII character 13) & (ASCII character 10) & \"")
            .replacingOccurrences(of: "\n", with: "\" & (ASCII character 10) & \"")
            .replacingOccurrences(of: "\r", with: "\" & (ASCII character 13) & \"")
            .replacingOccurrences(of: "\t", with: "\" & (ASCII character 9) & \"")
    }

    // MARK: - Parsers

    private static func parseFolderList(_ raw: String) -> [[String: Any]] {
        guard !raw.isEmpty else { return [] }
        let chunks = raw.components(separatedBy: "###")
        return chunks.compactMap { chunk in
            let parts = chunk.components(separatedBy: "|||")
            guard parts.count >= 3 else { return nil }
            return [
                "account": parts[0].trimmingCharacters(in: .whitespaces),
                "name": parts[1].trimmingCharacters(in: .whitespaces),
                "noteCount": Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 0
            ]
        }
    }

    private static func parseNoteList(_ raw: String) -> [[String: Any]] {
        guard !raw.isEmpty else { return [] }
        let chunks = raw.components(separatedBy: "###")
        return chunks.compactMap { chunk in
            let parts = chunk.components(separatedBy: "|||")
            guard parts.count >= 3 else { return nil }
            return [
                "id": parts[0],
                "title": parts[1],
                "modified": parts[2]
            ]
        }
    }
}
