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
}
