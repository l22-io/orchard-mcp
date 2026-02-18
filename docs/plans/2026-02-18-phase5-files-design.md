# Phase 5: Files & Folders Design

## Goal

Give MCP agents the ability to find, read, and manipulate files and folders on macOS. Scoped to the user's home directory. Text extraction from all common file types.

## Approach

Hybrid Swift + macOS CLI tools:
- **FileManager** for listing, metadata, and file operations (move, copy, trash, mkdir)
- **`mdfind`** for Spotlight search (file names + content, all indexed metadata)
- **`textutil`** for document text extraction (.docx, .rtf, .pages, .html, .odt)
- **PDFKit** for PDF text extraction
- **Vision** framework for OCR on images
- **Direct read** for plain text / source code files

Home folder boundary enforced in Swift before any operation.

## MCP Tools (8 tools)

### files.list
List directory contents with metadata.
- **Input**: `path` (relative to ~, default "."), `recursive` (bool, default false), `depth` (number, default 3 if recursive)
- **Output**: Array of `{name, path, size, isDirectory, created, modified, type}`

### files.info
Detailed metadata for a single file or folder.
- **Input**: `path`
- **Output**: FileManager attributes + Spotlight metadata (content type, where from, pixel dimensions, duration, etc.)

### files.search
Spotlight search via `mdfind`.
- **Input**: `query` (Spotlight query string), `kind` (optional: folder, image, pdf, document, audio, video, presentation, spreadsheet), `scope` (optional subdirectory, default ~)
- **Output**: Array of `{path, name, size, modified, kind, snippet}` (snippet from Spotlight content match when available)

### files.read
Read and extract text from a file.
- **Input**: `path`
- **Output**: `{path, contentType, text, truncated, byteSize}`
- Dispatch by UTI: plain text direct, PDF via PDFKit, images via Vision OCR, documents via `textutil -convert txt`
- Text output capped at 1MB; truncated flag set if exceeded

### files.move
Move or rename files/folders. Supports batch operations.
- **Input**: `operations` (array of `{source, destination}`)
- **Output**: Array of `{source, destination, success, error?}`

### files.copy
Copy a file or folder.
- **Input**: `source`, `destination`
- **Output**: `{source, destination, success}`

### files.create_folder
Create a directory with intermediate directories.
- **Input**: `path`
- **Output**: `{path, success}`

### files.trash
Move a file or folder to Trash.
- **Input**: `path`
- **Output**: `{path, trashPath, success}`

## Swift Subcommands

| Subcommand | Notes |
|---|---|
| `file-list --path <p> [--recursive] [--depth <n>]` | FileManager contentsOfDirectory |
| `file-info --path <p>` | FileManager attributes + `mdls` for Spotlight metadata |
| `file-search --query <q> [--kind <k>] [--scope <dir>]` | `mdfind -onlyin <scope>` |
| `file-read --path <p>` | UTI dispatch: direct / PDFKit / Vision / textutil |
| `file-move --items <json>` | Array of {source, dest} pairs via FileManager moveItem |
| `file-copy --source <p> --dest <p>` | FileManager copyItem |
| `file-create-folder --path <p>` | FileManager createDirectory(withIntermediateDirectories: true) |
| `file-trash --path <p>` | FileManager trashItem |

All subcommands validate paths are under home directory. Same JSON envelope as existing commands.

## Security

- All paths resolved to absolute and validated against `NSHomeDirectory()` before any operation
- Symlinks resolved before validation (no symlink escape)
- No access outside home folder
- Trash instead of hard delete
- Batch move validates all paths before executing any operation

## Out of Scope

- File sharing / AirDrop
- iCloud Drive download state management (Phase 8)
- Zip/archive creation
- File permissions modification
- Watch / live monitoring
