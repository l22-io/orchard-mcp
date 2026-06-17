import Foundation
import Darwin
import PDFKit
import UniformTypeIdentifiers
import Vision

enum FilesBridge {
    private static let processTimeout: TimeInterval = 10
    private static let processSigkillGrace: TimeInterval = 1
    private static let maxListItems = 1_000
    private static let maxPDFPages = 50
    private static let maxOCRImageBytes: Int64 = 10 * 1024 * 1024
    private static let maxTextutilBytes: Int64 = 20 * 1024 * 1024

    private static var home: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// Resolve and validate a path is under the home directory.
    /// Accepts relative paths (to ~), ~/... paths, or absolute paths.
    /// Resolves symlinks for existing paths to prevent escape.
    static func validatePath(_ input: String, mustExist: Bool = true) -> String? {
        let expanded: String
        if input.hasPrefix("/") {
            expanded = input
        } else if input.hasPrefix("~/") {
            expanded = home + String(input.dropFirst())
        } else {
            expanded = home + "/" + input
        }

        let url = URL(fileURLWithPath: expanded)
        let resolved: String
        if FileManager.default.fileExists(atPath: url.path) {
            resolved = url.resolvingSymlinksInPath().path
        } else if mustExist {
            return nil
        } else {
            resolved = url.standardized.path
        }

        guard resolved == home || resolved.hasPrefix(home + "/") else {
            return nil
        }
        return resolved
    }

    // MARK: - List

    static func list(path: String, recursive: Bool, depth: Int) {
        guard let resolved = validatePath(path) else {
            JSONOutput.error("Path is outside home directory or does not exist: \(path)")
            return
        }

        let fm = FileManager.default
        let url = URL(fileURLWithPath: resolved)

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue else {
            JSONOutput.error("Not a directory: \(path)")
            return
        }

        var items: [[String: Any]] = []

        if recursive {
            if let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .isDirectoryKey, .contentTypeKey],
                options: [.skipsHiddenFiles]
            ) {
                while let itemURL = enumerator.nextObject() as? URL {
                    if enumerator.level > depth {
                        enumerator.skipDescendants()
                        continue
                    }
                    if let entry = fileEntry(itemURL) {
                        items.append(entry)
                        if items.count >= maxListItems { break }
                    }
                }
            }
        } else {
            do {
                let contents = try fm.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .isDirectoryKey, .contentTypeKey],
                    options: [.skipsHiddenFiles]
                )
                for itemURL in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    if let entry = fileEntry(itemURL) {
                        items.append(entry)
                        if items.count >= maxListItems { break }
                    }
                }
            } catch {
                JSONOutput.error("Failed to list directory: \(error.localizedDescription)")
                return
            }
        }

        JSONOutput.success(items)
    }

    private static func fileEntry(_ url: URL) -> [String: Any]? {
        do {
            let values = try url.resourceValues(forKeys: [
                .fileSizeKey, .creationDateKey, .contentModificationDateKey,
                .isDirectoryKey, .contentTypeKey
            ])
            var entry: [String: Any] = [
                "name": url.lastPathComponent,
                "path": url.path,
                "isDirectory": values.isDirectory ?? false,
            ]
            if let size = values.fileSize { entry["size"] = size }
            if let created = values.creationDate { entry["created"] = iso8601(created) }
            if let modified = values.contentModificationDate { entry["modified"] = iso8601(modified) }
            if let type = values.contentType { entry["type"] = type.identifier }
            return entry
        } catch {
            return nil
        }
    }

    // MARK: - Info

    static func info(path: String) {
        guard let resolved = validatePath(path) else {
            JSONOutput.error("Path is outside home directory or does not exist: \(path)")
            return
        }

        let fm = FileManager.default
        let url = URL(fileURLWithPath: resolved)

        var info: [String: Any] = ["path": resolved, "name": url.lastPathComponent]

        do {
            let attrs = try fm.attributesOfItem(atPath: resolved)
            if let size = attrs[.size] as? Int64 { info["size"] = size }
            if let created = attrs[.creationDate] as? Date { info["created"] = iso8601(created) }
            if let modified = attrs[.modificationDate] as? Date { info["modified"] = iso8601(modified) }
            if let type = attrs[.type] as? FileAttributeType {
                info["fileType"] = type == .typeDirectory ? "directory" : type == .typeSymbolicLink ? "symlink" : "regular"
            }
            if let perms = attrs[.posixPermissions] as? Int {
                info["permissions"] = String(format: "%o", perms)
            }
        } catch {}

        if let result = runProcess(
            executable: "/usr/bin/mdls",
            arguments: ["-plist", "-", resolved]
        ), result.status == 0 {
            let data = result.stdout
            if let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] {
                let mdKeys: [String: String] = [
                    "kMDItemContentType": "contentType",
                    "kMDItemKind": "kind",
                    "kMDItemWhereFroms": "whereFroms",
                    "kMDItemPixelHeight": "pixelHeight",
                    "kMDItemPixelWidth": "pixelWidth",
                    "kMDItemDurationSeconds": "duration",
                    "kMDItemNumberOfPages": "pageCount",
                    "kMDItemAuthors": "authors",
                    "kMDItemTitle": "title",
                ]
                var spotlight: [String: Any] = [:]
                for (mdKey, friendlyKey) in mdKeys {
                    if let value = plist[mdKey], !(value is NSNull) {
                        spotlight[friendlyKey] = value
                    }
                }
                if !spotlight.isEmpty {
                    info["spotlight"] = spotlight
                }
            }
        }

        JSONOutput.success(info)
    }

    // MARK: - Search (Spotlight)

    private static func sanitizeSpotlightQuery(_ query: String) -> String {
        let forbidden = CharacterSet(charactersIn: "()'\"\\")
        return query.components(separatedBy: forbidden).joined(separator: " ")
    }

    static func search(query: String, kind: String?, scope: String?) {
        let scopeDir = scope.flatMap({ validatePath($0) }) ?? home

        let safeQuery = sanitizeSpotlightQuery(query)
        var mdfindQuery = safeQuery
        if let kind = kind {
            let typeMap: [String: String] = [
                "folder": "public.folder",
                "image": "public.image",
                "pdf": "com.adobe.pdf",
                "document": "public.composite-content",
                "audio": "public.audio",
                "video": "public.movie",
                "presentation": "public.presentation",
                "spreadsheet": "public.spreadsheet",
            ]
            if let uti = typeMap[kind] {
                mdfindQuery = "(\(safeQuery)) && (kMDItemContentTypeTree == '\(uti)')"
            }
        }

        guard let result = runProcess(
            executable: "/usr/bin/mdfind",
            arguments: ["-onlyin", scopeDir, mdfindQuery]
        ), result.status == 0 else {
            JSONOutput.error("mdfind failed or exceeded \(Int(processTimeout))s timeout")
            return
        }

        guard let output = String(data: result.stdout, encoding: .utf8) else {
            JSONOutput.success([Any]())
            return
        }

        let paths = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        var results: [[String: Any]] = []

        for path in paths.prefix(50) {
            let url = URL(fileURLWithPath: path)
            var entry: [String: Any] = [
                "path": path,
                "name": url.lastPathComponent,
            ]
            do {
                let values = try url.resourceValues(forKeys: [
                    .fileSizeKey, .contentModificationDateKey, .contentTypeKey
                ])
                if let size = values.fileSize { entry["size"] = size }
                if let modified = values.contentModificationDate { entry["modified"] = iso8601(modified) }
                if let type = values.contentType { entry["type"] = type.identifier }
            } catch {}
            results.append(entry)
        }

        JSONOutput.success(results)
    }

    // MARK: - Read (text extraction)

    static func read(path: String) {
        guard let resolved = validatePath(path) else {
            JSONOutput.error("Path is outside home directory or does not exist: \(path)")
            return
        }

        let url = URL(fileURLWithPath: resolved)
        let fm = FileManager.default

        guard fm.fileExists(atPath: resolved) else {
            JSONOutput.error("File not found: \(path)")
            return
        }

        let attrs = try? fm.attributesOfItem(atPath: resolved)
        let byteSize = (attrs?[.size] as? Int64) ?? 0

        let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey])
        let contentType = resourceValues?.contentType

        let maxTextBytes = 1_000_000
        var text: String?
        var method = "unknown"

        if let ct = contentType {
            if ct.conforms(to: .plainText) || ct.conforms(to: .sourceCode)
                || ct.conforms(to: .shellScript) || ct.conforms(to: .json)
                || ct.conforms(to: .xml) || ct.conforms(to: .yaml) {
                text = try? String(contentsOfFile: resolved, encoding: .utf8)
                method = "direct"
            } else if ct.conforms(to: .pdf) {
                text = extractPDF(url: url)
                method = "pdfkit"
            } else if ct.conforms(to: .image) {
                if byteSize > maxOCRImageBytes {
                    JSONOutput.error("Image is too large for OCR safety budget: \(byteSize) bytes (max \(maxOCRImageBytes)).")
                    return
                }
                text = extractImageText(url: url)
                method = "vision-ocr"
            } else {
                if byteSize > maxTextutilBytes {
                    JSONOutput.error("File is too large for textutil extraction safety budget: \(byteSize) bytes (max \(maxTextutilBytes)).")
                    return
                }
                text = extractViaTextutil(path: resolved)
                method = "textutil"
            }
        } else {
            text = try? String(contentsOfFile: resolved, encoding: .utf8)
            if text != nil {
                method = "direct"
            } else {
                if byteSize > maxTextutilBytes {
                    JSONOutput.error("File is too large for textutil extraction safety budget: \(byteSize) bytes (max \(maxTextutilBytes)).")
                    return
                }
                text = extractViaTextutil(path: resolved)
                method = "textutil"
            }
        }

        guard var extractedText = text, !extractedText.isEmpty else {
            JSONOutput.error("Could not extract text from file: \(url.lastPathComponent)")
            return
        }

        var truncated = false
        if extractedText.utf8.count > maxTextBytes {
            extractedText = String(extractedText.prefix(maxTextBytes))
            truncated = true
        }

        let result: [String: Any] = [
            "path": resolved,
            "contentType": contentType?.identifier ?? "unknown",
            "method": method,
            "text": extractedText,
            "truncated": truncated,
            "byteSize": byteSize,
        ]
        JSONOutput.success(result)
    }

    private static func extractPDF(url: URL) -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        var text = ""
        let pageLimit = min(doc.pageCount, maxPDFPages)
        for i in 0..<pageLimit {
            if let page = doc.page(at: i), let pageText = page.string {
                text += pageText + "\n"
            }
        }
        if doc.pageCount > maxPDFPages {
            text += "\n[truncated after \(maxPDFPages) PDF pages out of \(doc.pageCount)]"
        }
        return text.isEmpty ? nil : text
    }

    private static func extractImageText(url: URL) -> String? {
        guard let imageData = try? Data(contentsOf: url) else { return nil }

        let requestHandler = VNImageRequestHandler(data: imageData, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate

        do {
            try requestHandler.perform([request])
            guard let observations = request.results else { return nil }
            let text = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    private static func extractViaTextutil(path: String) -> String? {
        guard let result = runProcess(
            executable: "/usr/bin/textutil",
            arguments: ["-convert", "txt", "-stdout", path]
        ), result.status == 0 else { return nil }
        let text = String(data: result.stdout, encoding: .utf8)
        return (text?.isEmpty == true) ? nil : text
    }

    private struct ProcessResult {
        let status: Int32
        let stdout: Data
    }

    private static func runProcess(executable: String, arguments: [String]) -> ProcessResult? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let pid = process.processIdentifier
        let watchdog = DispatchWorkItem {
            guard process.isRunning else { return }
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + processSigkillGrace) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + processTimeout, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(status: process.terminationStatus, stdout: data)
    }

    // MARK: - File Operations

    static func move(itemsJSON: String) {
        guard let data = itemsJSON.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            JSONOutput.error("Invalid JSON. Expected: [{\"source\": \"...\", \"destination\": \"...\"}]")
            return
        }

        // Validate all paths first
        for item in items {
            guard let src = item["source"], let dst = item["destination"] else {
                JSONOutput.error("Each item must have 'source' and 'destination' keys")
                return
            }
            guard validatePath(src) != nil else {
                JSONOutput.error("Source path outside home directory: \(src)")
                return
            }
            guard validatePath(dst, mustExist: false) != nil else {
                JSONOutput.error("Destination path outside home directory: \(dst)")
                return
            }
        }

        let fm = FileManager.default
        var results: [[String: Any]] = []

        for item in items {
            let src = validatePath(item["source"]!)!
            let dst = validatePath(item["destination"]!, mustExist: false)!
            var result: [String: Any] = ["source": src, "destination": dst]
            do {
                try fm.moveItem(atPath: src, toPath: dst)
                result["success"] = true
            } catch {
                result["success"] = false
                result["error"] = error.localizedDescription
            }
            results.append(result)
        }

        JSONOutput.success(results)
    }

    static func copy(source: String, destination: String) {
        guard let src = validatePath(source) else {
            JSONOutput.error("Source path outside home directory or does not exist: \(source)")
            return
        }
        guard let dst = validatePath(destination, mustExist: false) else {
            JSONOutput.error("Destination path outside home directory: \(destination)")
            return
        }

        do {
            try FileManager.default.copyItem(atPath: src, toPath: dst)
            JSONOutput.success(["source": src, "destination": dst, "success": true])
        } catch {
            JSONOutput.error("Copy failed: \(error.localizedDescription)")
        }
    }

    static func createFolder(path: String) {
        guard let resolved = validatePath(path, mustExist: false) else {
            JSONOutput.error("Path is outside home directory: \(path)")
            return
        }

        do {
            try FileManager.default.createDirectory(atPath: resolved, withIntermediateDirectories: true)
            JSONOutput.success(["path": resolved, "success": true])
        } catch {
            JSONOutput.error("Create folder failed: \(error.localizedDescription)")
        }
    }

    static func trash(path: String) {
        guard let resolved = validatePath(path) else {
            JSONOutput.error("Path is outside home directory or does not exist: \(path)")
            return
        }

        let url = URL(fileURLWithPath: resolved)
        var trashURL: NSURL?

        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashURL)
            var result: [String: Any] = ["path": resolved, "success": true]
            if let trashPath = trashURL?.path {
                result["trashPath"] = trashPath
            }
            JSONOutput.success(result)
        } catch {
            JSONOutput.error("Trash failed: \(error.localizedDescription)")
        }
    }
}
