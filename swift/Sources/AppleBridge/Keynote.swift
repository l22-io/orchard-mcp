import Foundation

enum KeynoteBridge {

    // MARK: - Info

    static func info(file: String) {
        let escaped = escapeForAppleScript(file)
        let script = """
        tell application "Keynote"
            set doc to open POSIX file "\(escaped)"
            set docName to name of doc
            set sc to count of slides of doc
            set themeName to name of document theme of doc
            close doc saving no
            return docName & "|||" & (sc as string) & "|||" & themeName
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        let parts = raw.components(separatedBy: "|||")
        guard parts.count >= 3 else {
            JSONOutput.error("Unexpected response format from Keynote")
            return
        }

        let result: [String: Any] = [
            "name": parts[0].trimmingCharacters(in: .whitespaces),
            "slideCount": Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0,
            "theme": parts[2].trimmingCharacters(in: .whitespaces),
            "path": file
        ]
        JSONOutput.success(result)
    }

    // MARK: - Read

    static func read(file: String, slideIndex: Int?) {
        let escaped = escapeForAppleScript(file)

        let slideScript: String
        if let idx = slideIndex {
            slideScript = """
            set slideList to {slide \(idx) of doc}
            """
        } else {
            slideScript = """
            set slideList to every slide of doc
            """
        }

        let script = """
        tell application "Keynote"
            set doc to open POSIX file "\(escaped)"
            \(slideScript)
            set resultParts to {}
            set slideIdx to 0
            repeat with s in slideList
                set slideIdx to slideIdx + 1
                set actualIdx to slideIdx
                \(slideIndex != nil ? "set actualIdx to \(slideIndex!)" : "")
                set slideTitle to ""
                try
                    set slideTitle to object text of default title item of s
                end try
                set slideBody to ""
                try
                    set slideBody to object text of default body item of s
                end try
                set slideNotes to presenter notes of s
                set slideLayout to name of base slide of s
                set slideSkipped to skipped of s
                set slideLine to (actualIdx as string) & "|||" & slideTitle & "|||" & slideBody & "|||" & slideNotes & "|||" & slideLayout & "|||" & (slideSkipped as string)
                set end of resultParts to slideLine
            end repeat
            close doc saving no
            set oldDelim to AppleScript's text item delimiters
            set AppleScript's text item delimiters to "###"
            set resultText to resultParts as string
            set AppleScript's text item delimiters to oldDelim
            return resultText
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        let slides = parseSlideList(raw)
        JSONOutput.success(slides)
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
            set docPath to POSIX file "\(escaped)"
            save doc in docPath
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

        let makeClause: String
        if let pos = position {
            makeClause = "set newSlide to make new slide at after slide \(pos) of doc"
        } else {
            makeClause = "set newSlide to make new slide at end of doc"
        }

        let layoutClause: String
        if let layout = layout {
            layoutClause = """
            try
                set base slide of newSlide to base slide "\(escapeForAppleScript(layout))" of document theme of doc
            end try
            """
        } else {
            layoutClause = ""
        }

        let titleClause: String
        if let title = title {
            titleClause = """
            try
                set object text of default title item of newSlide to "\(escapeForAppleScript(title))"
            end try
            """
        } else {
            titleClause = ""
        }

        let bodyClause: String
        if let body = body {
            bodyClause = """
            try
                set object text of default body item of newSlide to "\(escapeForAppleScript(body))"
            end try
            """
        } else {
            bodyClause = ""
        }

        let notesClause: String
        if let notes = notes {
            notesClause = """
            set presenter notes of newSlide to "\(escapeForAppleScript(notes))"
            """
        } else {
            notesClause = ""
        }

        let script = """
        tell application "Keynote"
            set doc to open POSIX file "\(escaped)"
            \(makeClause)
            \(layoutClause)
            \(titleClause)
            \(bodyClause)
            \(notesClause)
            set sc to count of slides of doc
            save doc
            close doc
            return sc as string
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        let slideCount = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        JSONOutput.success(["path": file, "slideCount": slideCount])
    }

    // MARK: - Edit Slide

    static func editSlide(file: String, slideIndex: Int, title: String?, body: String?, notes: String?) {
        let escaped = escapeForAppleScript(file)

        let titleClause: String
        if let title = title {
            titleClause = """
            try
                set object text of default title item of s to "\(escapeForAppleScript(title))"
            end try
            """
        } else {
            titleClause = ""
        }

        let bodyClause: String
        if let body = body {
            bodyClause = """
            try
                set object text of default body item of s to "\(escapeForAppleScript(body))"
            end try
            """
        } else {
            bodyClause = ""
        }

        let notesClause: String
        if let notes = notes {
            notesClause = """
            set presenter notes of s to "\(escapeForAppleScript(notes))"
            """
        } else {
            notesClause = ""
        }

        let script = """
        tell application "Keynote"
            set doc to open POSIX file "\(escaped)"
            set s to slide \(slideIndex) of doc
            \(titleClause)
            \(bodyClause)
            \(notesClause)
            save doc
            close doc
            return "ok"
        end tell
        """

        guard let _ = runAppleScript(script) else { return }
        JSONOutput.success(["path": file, "slide": slideIndex, "edited": true])
    }

    // MARK: - Remove Slide

    static func removeSlide(file: String, slideIndex: Int) {
        let escaped = escapeForAppleScript(file)
        let script = """
        tell application "Keynote"
            set doc to open POSIX file "\(escaped)"
            delete slide \(slideIndex) of doc
            set sc to count of slides of doc
            save doc
            close doc
            return sc as string
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        let remaining = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        JSONOutput.success(["path": file, "remainingSlides": remaining])
    }

    // MARK: - Reorder Slides

    static func reorderSlides(file: String, from: Int, to: Int) {
        let escaped = escapeForAppleScript(file)

        let moveClause: String
        if to < from {
            moveClause = "move slide \(from) of doc to before slide \(to) of doc"
        } else {
            moveClause = "move slide \(from) of doc to after slide \(to) of doc"
        }

        let script = """
        tell application "Keynote"
            set doc to open POSIX file "\(escaped)"
            \(moveClause)
            save doc
            close doc
            return "ok"
        end tell
        """

        guard let _ = runAppleScript(script) else { return }
        JSONOutput.success(["path": file, "movedFrom": from, "movedTo": to])
    }

    // MARK: - List Themes

    static func listThemes() {
        let script = """
        tell application "Keynote"
            set themeNames to name of every theme
            set oldDelim to AppleScript's text item delimiters
            set AppleScript's text item delimiters to "|||"
            set resultText to themeNames as string
            set AppleScript's text item delimiters to oldDelim
            return resultText
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        let themes = raw.components(separatedBy: "|||")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        JSONOutput.success(themes)
    }

    // MARK: - Export

    static func export(file: String, format: String, dest: String?, slideIndex: Int?) {
        let escapedFile = escapeForAppleScript(file)

        let isImageExport = (format == "png" || format == "jpeg")

        if isImageExport && slideIndex == nil {
            exportSlideImages(file: file, format: format, dest: dest)
            return
        }

        let outputPath: String
        if let dest = dest {
            outputPath = dest
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
            "png": "PNG",
            "jpeg": "JPEG"
        ]
        guard let keynoteFormat = formatMap[format] else {
            JSONOutput.error("Unsupported export format: \(format). Use pdf, pptx, png, or jpeg.")
            return
        }

        if isImageExport, let idx = slideIndex {
            let script = """
            tell application "Keynote"
                set doc to open POSIX file "\(escapedFile)"
                export doc as slide images to POSIX file "\(escapedOutput)" with properties {image format:\(keynoteFormat), skipped slides:false}
                close doc saving no
                return "ok"
            end tell
            """
            guard let _ = runAppleScript(script) else { return }

            let fm = FileManager.default
            let dirURL = URL(fileURLWithPath: outputPath).deletingLastPathComponent()
            let ext = format == "jpeg" ? "jpeg" : "png"
            let pattern = dirURL.path
            if let files = try? fm.contentsOfDirectory(atPath: pattern) {
                let sorted = files.filter { $0.hasSuffix(ext) }.sorted()
                if idx > 0 && idx <= sorted.count {
                    let targetFile = dirURL.appendingPathComponent(sorted[idx - 1]).path
                    JSONOutput.success(["path": targetFile])
                    return
                }
            }
            JSONOutput.success(["path": outputPath])
            return
        }

        let script = """
        tell application "Keynote"
            set doc to open POSIX file "\(escapedFile)"
            export doc to POSIX file "\(escapedOutput)" as \(keynoteFormat)
            close doc saving no
            return "ok"
        end tell
        """

        guard let _ = runAppleScript(script) else { return }
        JSONOutput.success(["path": outputPath])
    }

    private static func exportSlideImages(file: String, format: String, dest: String?) {
        let escapedFile = escapeForAppleScript(file)
        let outputDir: String
        if let dest = dest {
            outputDir = dest
        } else {
            let base = file.replacingOccurrences(of: ".key", with: "_slides")
            outputDir = base
        }
        let escapedOutput = escapeForAppleScript(outputDir)

        let imageFormat = format == "jpeg" ? "JPEG" : "PNG"

        let fm = FileManager.default
        if !fm.fileExists(atPath: outputDir) {
            do {
                try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
            } catch {
                JSONOutput.error("Failed to create output directory: \(error.localizedDescription)")
                return
            }
        }

        let script = """
        tell application "Keynote"
            set doc to open POSIX file "\(escapedFile)"
            export doc as slide images to POSIX file "\(escapedOutput)" with properties {image format:\(imageFormat)}
            close doc saving no
            return "ok"
        end tell
        """

        guard let _ = runAppleScript(script) else { return }

        let ext = format == "jpeg" ? "jpeg" : "png"
        var exportedFiles: [String] = []
        if let files = try? fm.contentsOfDirectory(atPath: outputDir) {
            exportedFiles = files.filter { $0.hasSuffix(ext) || $0.hasSuffix("jpg") }
                .sorted()
                .map { "\(outputDir)/\($0)" }
        }

        JSONOutput.success([
            "directory": outputDir,
            "files": exportedFiles,
            "count": exportedFiles.count
        ] as [String: Any])
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

    // MARK: - Parsers

    private static func parseSlideList(_ raw: String) -> [[String: Any]] {
        guard !raw.isEmpty else { return [] }
        let slideChunks = raw.components(separatedBy: "###")
        return slideChunks.compactMap { chunk -> [String: Any]? in
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let parts = trimmed.components(separatedBy: "|||")
            guard parts.count >= 6 else { return nil }

            return [
                "index": Int(parts[0].trimmingCharacters(in: .whitespaces)) ?? 0,
                "title": parts[1].trimmingCharacters(in: .whitespaces),
                "body": parts[2].trimmingCharacters(in: .whitespaces),
                "notes": parts[3].trimmingCharacters(in: .whitespaces),
                "layout": parts[4].trimmingCharacters(in: .whitespaces),
                "skipped": parts[5].trimmingCharacters(in: .whitespaces).lowercased() == "true"
            ]
        }
    }
}
