# Phase 5: Files & Folders Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Give MCP agents the ability to find, read, and manipulate files/folders on macOS via Spotlight search, text extraction (PDF/images/documents), and file operations (move/copy/trash/mkdir).

**Architecture:** New `Files.swift` in the Swift layer with 8 subcommands. Uses FileManager for directory ops, `mdfind` for Spotlight search, PDFKit for PDFs, Vision for OCR, `textutil` for documents. New `files.ts` in TypeScript layer with 8 MCP tools. All paths validated to be under home directory.

**Tech Stack:** Swift (FileManager, PDFKit, Vision, Process for mdfind/textutil/mdls), TypeScript MCP tools with Zod schemas.

---

### Task 1: Files.swift -- path validation, file-list, file-info

**Files:**
- Create: `swift/Sources/AppleBridge/Files.swift`
- Modify: `swift/Package.swift` (add PDFKit, Vision linker settings)

**Step 1: Update Package.swift to link PDFKit and Vision**

Add to `linkerSettings`:

```swift
linkerSettings: [
    .linkedFramework("EventKit"),
    .linkedFramework("Foundation"),
    .linkedFramework("PDFKit"),
    .linkedFramework("Vision")
]
```

**Step 2: Create Files.swift with path validation, list, and info**

```swift
import Foundation
import UniformTypeIdentifiers

enum FilesBridge {
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

        // Spotlight metadata via mdls
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        process.arguments = ["-plist", "-", resolved]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
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
        } catch {}

        JSONOutput.success(info)
    }
}
```

**Step 3: Build Swift to verify**

Run: `cd swift && swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Sources/AppleBridge/Info.plist`
Expected: Build succeeds (subcommands not registered yet, but Files.swift compiles).

**Step 4: Commit**

```bash
git add swift/Sources/AppleBridge/Files.swift swift/Package.swift
git commit -m "feat(files): add Files.swift with path validation, list, and info"
```

---

### Task 2: file-search via Spotlight

**Files:**
- Modify: `swift/Sources/AppleBridge/Files.swift`

**Step 1: Add search function to FilesBridge**

Append to `Files.swift` before the closing `}` of the enum:

```swift
    // MARK: - Search (Spotlight)

    static func search(query: String, kind: String?, scope: String?) {
        let scopeDir = scope.flatMap({ validatePath($0) }) ?? home

        var mdfindQuery = query
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
                mdfindQuery = "(\(query)) && (kMDItemContentTypeTree == '\(uti)')"
            }
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-onlyin", scopeDir, mdfindQuery]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
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
        } catch {
            JSONOutput.error("mdfind failed: \(error.localizedDescription)")
        }
    }
```

**Step 2: Build Swift to verify**

Run: `cd swift && swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Sources/AppleBridge/Info.plist`
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add swift/Sources/AppleBridge/Files.swift
git commit -m "feat(files): add Spotlight search via mdfind"
```

---

### Task 3: file-read with text extraction

**Files:**
- Modify: `swift/Sources/AppleBridge/Files.swift`

**Step 1: Add read function with multi-format extraction**

Append to `Files.swift` before the closing `}` of the enum:

```swift
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
                text = extractImageText(url: url)
                method = "vision-ocr"
            } else {
                text = extractViaTextutil(path: resolved)
                method = "textutil"
            }
        } else {
            text = try? String(contentsOfFile: resolved, encoding: .utf8)
            if text != nil {
                method = "direct"
            } else {
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
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let pageText = page.string {
                text += pageText + "\n"
            }
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
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "txt", "-stdout", path]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)
            return (text?.isEmpty == true) ? nil : text
        } catch {
            return nil
        }
    }
```

**Step 2: Add imports at top of Files.swift**

Add after the existing `import` lines at the top of the file:

```swift
import PDFKit
import Vision
```

**Step 3: Build Swift to verify**

Run: `cd swift && swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Sources/AppleBridge/Info.plist`
Expected: Build succeeds.

**Step 4: Commit**

```bash
git add swift/Sources/AppleBridge/Files.swift
git commit -m "feat(files): add file-read with PDF, OCR, and textutil extraction"
```

---

### Task 4: File operations (move, copy, create-folder, trash)

**Files:**
- Modify: `swift/Sources/AppleBridge/Files.swift`

**Step 1: Add file operation functions**

Append to `Files.swift` before the closing `}` of the enum:

```swift
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
```

**Step 2: Build Swift to verify**

Run: `cd swift && swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Sources/AppleBridge/Info.plist`
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add swift/Sources/AppleBridge/Files.swift
git commit -m "feat(files): add move, copy, create-folder, and trash operations"
```

---

### Task 5: Register subcommands in AppleBridge.swift

**Files:**
- Modify: `swift/Sources/AppleBridge/AppleBridge.swift`

**Step 1: Add subcommands to the configuration**

Add to the `subcommands` array in `AppleBridge`:

```swift
FileList.self,
FileInfo.self,
FileSearchCmd.self,
FileRead.self,
FileMove.self,
FileCopy.self,
FileCreateFolder.self,
FileTrash.self,
```

**Step 2: Add the subcommand structs**

Append before `// MARK: - Doctor`:

```swift
// MARK: - Files & Folders Subcommands

struct FileList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-list",
        abstract: "List directory contents with metadata."
    )

    @Option(name: .long, help: "Directory path (relative to ~ or absolute)")
    var path: String = "."

    @Flag(name: .long, help: "List recursively")
    var recursive: Bool = false

    @Option(name: .long, help: "Max recursion depth (default: 3)")
    var depth: Int = 3

    func run() throws {
        FilesBridge.list(path: path, recursive: recursive, depth: depth)
    }
}

struct FileInfo: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-info",
        abstract: "Get detailed file or folder metadata."
    )

    @Option(name: .long, help: "File path (relative to ~ or absolute)")
    var path: String

    func run() throws {
        FilesBridge.info(path: path)
    }
}

struct FileSearchCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-search",
        abstract: "Search files using Spotlight."
    )

    @Option(name: .long, help: "Search query (Spotlight syntax)")
    var query: String

    @Option(name: .long, help: "Filter by kind: folder, image, pdf, document, audio, video, presentation, spreadsheet")
    var kind: String?

    @Option(name: .long, help: "Search scope directory (relative to ~ or absolute)")
    var scope: String?

    func run() throws {
        FilesBridge.search(query: query, kind: kind, scope: scope)
    }
}

struct FileRead: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-read",
        abstract: "Read and extract text from a file."
    )

    @Option(name: .long, help: "File path (relative to ~ or absolute)")
    var path: String

    func run() throws {
        FilesBridge.read(path: path)
    }
}

struct FileMove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-move",
        abstract: "Move or rename files and folders."
    )

    @Option(name: .long, help: "JSON array of {\"source\": \"...\", \"destination\": \"...\"} pairs")
    var items: String

    func run() throws {
        FilesBridge.move(itemsJSON: items)
    }
}

struct FileCopy: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-copy",
        abstract: "Copy a file or folder."
    )

    @Option(name: .long, help: "Source path")
    var source: String

    @Option(name: .long, help: "Destination path")
    var dest: String

    func run() throws {
        FilesBridge.copy(source: source, destination: dest)
    }
}

struct FileCreateFolder: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-create-folder",
        abstract: "Create a directory with intermediate directories."
    )

    @Option(name: .long, help: "Directory path to create")
    var path: String

    func run() throws {
        FilesBridge.createFolder(path: path)
    }
}

struct FileTrash: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file-trash",
        abstract: "Move a file or folder to Trash."
    )

    @Option(name: .long, help: "File or folder path to trash")
    var path: String

    func run() throws {
        FilesBridge.trash(path: path)
    }
}
```

**Step 3: Build and test Swift binary**

Run: `cd swift && swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Sources/AppleBridge/Info.plist`
Expected: Build succeeds.

Test: `./swift/.build/release/apple-bridge file-list --path Documents`
Expected: JSON with status ok and array of file entries.

Test: `./swift/.build/release/apple-bridge file-search --query "apple-mcp"`
Expected: JSON with status ok and array of search results.

Test: `./swift/.build/release/apple-bridge file-info --path Documents`
Expected: JSON with status ok and metadata object.

**Step 4: Commit**

```bash
git add swift/Sources/AppleBridge/AppleBridge.swift
git commit -m "feat(files): register file subcommands in apple-bridge"
```

---

### Task 6: TypeScript MCP tools + registration

**Files:**
- Create: `src/tools/files.ts`
- Modify: `src/index.ts`

**Step 1: Create files.ts**

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { bridgeData } from "../bridge.js";

export function registerFileTools(server: McpServer): void {
  server.tool(
    "files.list",
    "List directory contents with metadata (name, size, dates, type). Paths relative to home directory.",
    {
      path: z
        .string()
        .optional()
        .describe("Directory path relative to ~ (default: home directory)"),
      recursive: z
        .boolean()
        .optional()
        .describe("List recursively (default: false)"),
      depth: z
        .number()
        .optional()
        .describe("Max recursion depth when recursive (default: 3)"),
    },
    async ({ path, recursive, depth }) => {
      const args = ["file-list"];
      if (path) args.push("--path", path);
      if (recursive) args.push("--recursive");
      if (depth !== undefined) args.push("--depth", String(depth));
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "files.info",
    "Get detailed metadata for a file or folder, including Spotlight attributes (content type, dimensions, authors, page count).",
    {
      path: z
        .string()
        .describe(
          "File path relative to ~ or absolute (must be under home directory)"
        ),
    },
    async ({ path }) => {
      const data = await bridgeData(["file-info", "--path", path]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "files.search",
    "Search files using macOS Spotlight. Searches file names and content across indexed volumes. Scoped to home directory.",
    {
      query: z
        .string()
        .describe(
          "Search query (Spotlight syntax, e.g. 'budget 2026' or 'kMDItemAuthor == \"John\"')"
        ),
      kind: z
        .enum([
          "folder",
          "image",
          "pdf",
          "document",
          "audio",
          "video",
          "presentation",
          "spreadsheet",
        ])
        .optional()
        .describe("Filter by file kind"),
      scope: z
        .string()
        .optional()
        .describe(
          "Subdirectory to search within (default: entire home directory)"
        ),
    },
    async ({ query, kind, scope }) => {
      const args = ["file-search", "--query", query];
      if (kind) args.push("--kind", kind);
      if (scope) args.push("--scope", scope);
      const data = await bridgeData(args);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "files.read",
    "Read and extract text from a file. Handles plain text, PDF (via PDFKit), images (via OCR), and documents (.docx, .rtf, .pages via textutil). Text capped at 1MB.",
    {
      path: z
        .string()
        .describe(
          "File path relative to ~ or absolute (must be under home directory)"
        ),
    },
    async ({ path }) => {
      const data = await bridgeData(["file-read", "--path", path]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "files.move",
    "Move or rename files and folders. Supports batch operations for mass renaming. All paths must be under home directory.",
    {
      operations: z
        .array(
          z.object({
            source: z.string().describe("Source path"),
            destination: z.string().describe("Destination path"),
          })
        )
        .describe("Array of move operations ({source, destination} pairs)"),
    },
    async ({ operations }) => {
      const data = await bridgeData([
        "file-move",
        "--items",
        JSON.stringify(operations),
      ]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "files.copy",
    "Copy a file or folder to a new location. Both paths must be under home directory.",
    {
      source: z.string().describe("Source file or folder path"),
      destination: z.string().describe("Destination path"),
    },
    async ({ source, destination }) => {
      const data = await bridgeData([
        "file-copy",
        "--source",
        source,
        "--dest",
        destination,
      ]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "files.create_folder",
    "Create a new directory with intermediate directories. Path must be under home directory.",
    {
      path: z.string().describe("Directory path to create"),
    },
    async ({ path }) => {
      const data = await bridgeData(["file-create-folder", "--path", path]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "files.trash",
    "Move a file or folder to the Trash (reversible delete). Path must be under home directory.",
    {
      path: z.string().describe("File or folder path to move to Trash"),
    },
    async ({ path }) => {
      const data = await bridgeData(["file-trash", "--path", path]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
```

**Step 2: Register in index.ts**

Add import and registration call alongside the existing tools:

```typescript
import { registerFileTools } from "./tools/files.js";
```

And after the existing `register*Tools` calls:

```typescript
registerFileTools(server);
```

**Step 3: Build TypeScript**

Run: `npx tsc`
Expected: No errors.

**Step 4: Commit**

```bash
git add src/tools/files.ts src/index.ts
git commit -m "feat(files): add 8 MCP tools for files & folders"
```

---

### Task 7: End-to-end testing

**Step 1: Test file-list**

Run: `./swift/.build/release/apple-bridge file-list --path Documents`
Expected: JSON array with file entries (name, path, size, isDirectory, etc.)

Run: `./swift/.build/release/apple-bridge file-list --path . --recursive --depth 1`
Expected: JSON array with home directory contents and one level of subdirectories.

**Step 2: Test file-info**

Run: `./swift/.build/release/apple-bridge file-info --path .zshrc`
Expected: JSON with file metadata including size, permissions, spotlight data.

**Step 3: Test file-search**

Run: `./swift/.build/release/apple-bridge file-search --query "apple-mcp"`
Expected: JSON array with matching files from home directory.

Run: `./swift/.build/release/apple-bridge file-search --query "test" --kind pdf`
Expected: JSON array with only PDF results.

**Step 4: Test file-read**

Run: `./swift/.build/release/apple-bridge file-read --path .zshrc`
Expected: JSON with text content, method "direct".

Find a PDF in ~/Documents and test:
Run: `./swift/.build/release/apple-bridge file-read --path "Documents/<some-pdf>.pdf"`
Expected: JSON with extracted text, method "pdfkit".

**Step 5: Test file operations**

Run: `./swift/.build/release/apple-bridge file-create-folder --path "Desktop/apple-mcp-test"`
Expected: JSON with success true.

Run: `./swift/.build/release/apple-bridge file-copy --source ".zshrc" --dest "Desktop/apple-mcp-test/zshrc-copy"`
Expected: JSON with success true.

Run: `./swift/.build/release/apple-bridge file-move --items '[{"source": "Desktop/apple-mcp-test/zshrc-copy", "destination": "Desktop/apple-mcp-test/zshrc-renamed"}]'`
Expected: JSON array with success true.

Run: `./swift/.build/release/apple-bridge file-trash --path "Desktop/apple-mcp-test"`
Expected: JSON with success true and trashPath.

**Step 6: Test path security**

Run: `./swift/.build/release/apple-bridge file-list --path /etc`
Expected: Error about path outside home directory.

Run: `./swift/.build/release/apple-bridge file-read --path ../../etc/passwd`
Expected: Error about path outside home directory.

**Step 7: Rebuild .app bundle and verify MCP server starts**

Run: `bash scripts/postinstall.sh` (will skip since binary exists, but rebuilds .app)

Actually, need to rebuild .app manually since postinstall skips:
```bash
rm -rf swift/.build/AppleBridge.app
bash scripts/postinstall.sh
```

Wait -- postinstall checks for both binary AND .app. If we remove the .app, it won't skip. But the binary already exists so Swift won't rebuild. Actually, looking at the script, it skips if BOTH exist. If only one is missing it will rebuild Swift AND build the .app. Since the binary exists, Swift build will be fast (no-op). This is fine.

Run: `rm -rf swift/.build/AppleBridge.app && bash scripts/postinstall.sh`
Expected: Rebuilds .app bundle.

Run: `node build/index.js setup --non-interactive`
Expected: Setup completes, all steps pass.

**Step 8: Update CLAUDE.md**

Update project structure to include Files.swift and files.ts. Update current state to mark Phase 5 as complete. Update tool counts.
