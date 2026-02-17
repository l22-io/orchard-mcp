# Phase 2: Reminders Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Reminders support to apple-mcp via 3 MCP tools backed by a new Swift EventKit bridge, following the exact patterns established by Calendar (Phase 1).

**Architecture:** New `RemindersBridge` enum in Swift uses EventKit's `fetchReminders(matching:)` (callback-based, bridged to async). Three new subcommands (`reminder-lists`, `reminders`, `reminders-today`) are registered in `AppleBridge.swift`. TypeScript side gets `src/tools/reminders.ts` with `registerReminderTools()` wired into `index.ts`. Doctor gains a `remindersSummary` section.

**Tech Stack:** Swift 5.9 / EventKit / ArgumentParser, TypeScript / Zod / MCP SDK

---

### Task 1: Swift -- RemindersBridge core with `listLists()`

**Files:**
- Create: `swift/Sources/AppleBridge/Reminders.swift`

**Step 1: Create `Reminders.swift` with access helpers and `listLists()`**

```swift
import EventKit
import Foundation

enum RemindersBridge {
    private static let store = EKEventStore()

    static func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    static func authorizationStatus() -> EKAuthorizationStatus {
        return EKEventStore.authorizationStatus(for: .reminder)
    }

    static func listLists() async {
        guard await requestAccess() else {
            JSONOutput.error("Reminders access denied. Grant access in System Settings > Privacy & Security > Reminders.")
            return
        }

        let calendars = store.calendars(for: .reminder)
        let result: [[String: Any]] = calendars.map { cal in
            var dict: [String: Any] = [
                "id": cal.calendarIdentifier,
                "title": cal.title,
                "allowsModify": cal.allowsContentModifications
            ]
            if let source = cal.source {
                dict["account"] = source.title
            }
            if let color = cal.cgColor {
                let components = color.components ?? []
                if components.count >= 3 {
                    let r = Int(components[0] * 255)
                    let g = Int(components[1] * 255)
                    let b = Int(components[2] * 255)
                    dict["color"] = String(format: "#%02x%02x%02x", r, g, b)
                }
            }
            return dict
        }

        JSONOutput.success(result)
    }
}
```

**Step 2: Build to verify compilation**

Run: `cd swift && swift build -c release 2>&1`
Expected: Build succeeds (file compiles but subcommands not wired yet)

**Step 3: Commit**

```bash
git add swift/Sources/AppleBridge/Reminders.swift
git commit -m "feat(reminders): add RemindersBridge with listLists"
```

---

### Task 2: Swift -- `listReminders()` and `today()`

**Files:**
- Modify: `swift/Sources/AppleBridge/Reminders.swift`

**Step 1: Add `listReminders()` with filter support**

Append to `RemindersBridge` enum, before the closing `}`:

```swift
    static func listReminders(listName: String?, filter: String, limit: Int) async {
        guard await requestAccess() else {
            JSONOutput.error("Reminders access denied. Grant access in System Settings > Privacy & Security > Reminders.")
            return
        }

        var calendars: [EKCalendar]? = nil
        if let name = listName {
            let matches = store.calendars(for: .reminder).filter {
                $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame
            }
            if matches.isEmpty {
                JSONOutput.error("Reminder list not found: \(name)")
                return
            }
            calendars = matches
        }

        let predicate = store.predicateForReminders(in: calendars)
        let allReminders = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: result ?? [])
            }
        }

        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)!

        let filtered: [EKReminder]
        switch filter {
        case "completed":
            filtered = allReminders.filter { $0.isCompleted }
        case "overdue":
            filtered = allReminders.filter { !$0.isCompleted && $0.dueDateComponents != nil && (Calendar.current.date(from: $0.dueDateComponents!) ?? .distantFuture) < startOfToday }
        case "dueToday":
            filtered = allReminders.filter {
                guard !$0.isCompleted, let dc = $0.dueDateComponents, let due = Calendar.current.date(from: dc) else { return false }
                return due >= startOfToday && due < endOfToday
            }
        case "all":
            filtered = allReminders
        default: // "incomplete"
            filtered = allReminders.filter { !$0.isCompleted }
        }

        let limited = Array(filtered.prefix(limit))
        let result: [[String: Any]] = limited.map { rem in
            formatReminder(rem)
        }

        JSONOutput.success(result)
    }

    static func today() async {
        guard await requestAccess() else {
            JSONOutput.error("Reminders access denied. Grant access in System Settings > Privacy & Security > Reminders.")
            return
        }

        let predicate = store.predicateForReminders(in: nil)
        let allReminders = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: result ?? [])
            }
        }

        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)!

        let todayAndOverdue = allReminders.filter { rem in
            guard !rem.isCompleted else { return false }
            guard let dc = rem.dueDateComponents, let due = Calendar.current.date(from: dc) else { return false }
            return due < endOfToday
        }

        let result: [[String: Any]] = todayAndOverdue.map { rem in
            formatReminder(rem)
        }

        JSONOutput.success(result)
    }

    // MARK: - Helpers

    private static func formatReminder(_ rem: EKReminder) -> [String: Any] {
        var dict: [String: Any] = [
            "title": rem.title ?? "(no title)",
            "isCompleted": rem.isCompleted,
            "list": rem.calendar.title,
            "priority": rem.priority
        ]
        if let dc = rem.dueDateComponents, let due = Calendar.current.date(from: dc) {
            dict["dueDate"] = iso8601(due)
        }
        if rem.isCompleted, let completed = rem.completionDate {
            dict["completionDate"] = iso8601(completed)
        }
        if let notes = rem.notes, !notes.isEmpty {
            dict["notes"] = notes
        }
        if rem.hasRecurrenceRules {
            dict["hasRecurrence"] = true
        }
        return dict
    }
```

**Step 2: Build to verify compilation**

Run: `cd swift && swift build -c release 2>&1`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add swift/Sources/AppleBridge/Reminders.swift
git commit -m "feat(reminders): add listReminders with filters and today"
```

---

### Task 3: Swift -- Wire subcommands in `AppleBridge.swift`

**Files:**
- Modify: `swift/Sources/AppleBridge/AppleBridge.swift`

**Step 1: Add three Reminders subcommand structs and register them**

Add to `subcommands` array in `AppleBridge`:
```swift
ReminderLists.self,
RemindersCmd.self,
RemindersToday.self,
```

Add a new `// MARK: - Reminders Subcommands` section before `// MARK: - Doctor`:

```swift
// MARK: - Reminders Subcommands

struct ReminderLists: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminder-lists",
        abstract: "List all reminder lists with account and color."
    )

    func run() async throws {
        await RemindersBridge.listLists()
    }
}

struct RemindersCmd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminders",
        abstract: "List reminders with optional filters."
    )

    @Option(name: .long, help: "Filter to a specific list name")
    var list: String?

    @Option(name: .long, help: "Filter: incomplete (default), completed, overdue, dueToday, all")
    var filter: String = "incomplete"

    @Option(name: .long, help: "Max reminders to return (default: 50)")
    var limit: Int = 50

    func run() async throws {
        await RemindersBridge.listReminders(listName: list, filter: filter, limit: limit)
    }
}

struct RemindersToday: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminders-today",
        abstract: "Incomplete reminders due today plus overdue across all lists."
    )

    func run() async throws {
        await RemindersBridge.today()
    }
}
```

**Step 2: Build and test CLI**

Run: `cd swift && swift build -c release 2>&1`
Expected: Build succeeds

Run: `./swift/.build/release/apple-bridge reminder-lists`
Expected: JSON envelope with status "ok" and list of reminder lists (or permission prompt)

Run: `./swift/.build/release/apple-bridge reminders-today`
Expected: JSON envelope with today's reminders

**Step 3: Commit**

```bash
git add swift/Sources/AppleBridge/AppleBridge.swift
git commit -m "feat(reminders): wire reminder-lists, reminders, reminders-today subcommands"
```

---

### Task 4: Swift -- Doctor remindersSummary

**Files:**
- Modify: `swift/Sources/AppleBridge/Doctor.swift`

**Step 1: Add remindersSummary block**

In `DoctorBridge.run()`, after the existing reminders permission check block (after line ~52 `report["reminders"] = ...`), and before the `// Mail` comment, add:

```swift
        if remStatus == .notDetermined {
            let granted = await RemindersBridge.requestAccess()
            report["reminders"] = [
                "status": granted ? "fullAccess" : "denied",
                "granted": granted,
                "note": "Permission was just requested."
            ]
        }

        if remStatus == .fullAccess || remStatus == .notDetermined {
            let store = EKEventStore()
            _ = try? await store.requestFullAccessToReminders()
            let lists = store.calendars(for: .reminder)
            report["remindersSummary"] = [
                "count": lists.count,
                "lists": lists.map { $0.title }.sorted()
            ]
        }
```

**Step 2: Build and test**

Run: `cd swift && swift build -c release 2>&1`
Expected: Build succeeds

Run: `./swift/.build/release/apple-bridge doctor`
Expected: JSON includes `remindersSummary` with list count and names

**Step 3: Commit**

```bash
git add swift/Sources/AppleBridge/Doctor.swift
git commit -m "feat(doctor): add remindersSummary to diagnostics"
```

---

### Task 5: TypeScript -- `src/tools/reminders.ts`

**Files:**
- Create: `src/tools/reminders.ts`

**Step 1: Create the reminders tool registration module**

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { bridgeData } from "../bridge.js";

export function registerReminderTools(server: McpServer): void {
  server.tool(
    "reminders.list_lists",
    "List all Apple Reminders lists with account name, color, and modification status.",
    {},
    async () => {
      const data = await bridgeData(["reminder-lists"]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );

  server.tool(
    "reminders.list_reminders",
    "List reminders from a specific list or all lists. Supports filters: incomplete (default), completed, overdue, dueToday, all.",
    {
      list: z
        .string()
        .optional()
        .describe("Filter to a specific reminder list name"),
      filter: z
        .enum(["incomplete", "completed", "overdue", "dueToday", "all"])
        .optional()
        .describe("Filter reminders by status (default: incomplete)"),
      limit: z
        .number()
        .optional()
        .describe("Max reminders to return (default: 50)"),
    },
    async ({ list, filter, limit }) => {
      const args = ["reminders"];
      if (list) {
        args.push("--list", list);
      }
      if (filter) {
        args.push("--filter", filter);
      }
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
    "reminders.today",
    "Get incomplete reminders due today plus any overdue reminders across all lists.",
    {},
    async () => {
      const data = await bridgeData(["reminders-today"]);
      return {
        content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
      };
    }
  );
}
```

**Step 2: Compile TypeScript**

Run: `npx tsc`
Expected: No errors

**Step 3: Commit**

```bash
git add src/tools/reminders.ts
git commit -m "feat(reminders): add TypeScript MCP tool definitions"
```

---

### Task 6: TypeScript -- Wire into `src/index.ts`

**Files:**
- Modify: `src/index.ts`

**Step 1: Add import and registration call**

Add import after existing tool imports:
```typescript
import { registerReminderTools } from "./tools/reminders.js";
```

Add registration call after `registerMailTools(server);`:
```typescript
registerReminderTools(server);
```

**Step 2: Compile TypeScript**

Run: `npx tsc`
Expected: No errors

**Step 3: Commit**

```bash
git add src/index.ts
git commit -m "feat(reminders): register reminder tools in MCP server"
```

---

### Task 7: End-to-end validation

**Files:** None (testing only)

**Step 1: Rebuild Swift binary**

Run: `cd swift && swift build -c release 2>&1`

**Step 2: Test all three CLI subcommands**

Run: `./swift/.build/release/apple-bridge reminder-lists`
Expected: `{"status": "ok", "data": [...]}`

Run: `./swift/.build/release/apple-bridge reminders --filter incomplete --limit 5`
Expected: `{"status": "ok", "data": [...]}`

Run: `./swift/.build/release/apple-bridge reminders-today`
Expected: `{"status": "ok", "data": [...]}`

**Step 3: Test doctor includes reminders**

Run: `./swift/.build/release/apple-bridge doctor`
Expected: Output includes `remindersSummary` with list count and names

**Step 4: Compile and verify MCP server**

Run: `npx tsc`
Expected: No errors

**Step 5: Verify MCP server starts**

Run: `echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1.0"}}}' | node build/index.js 2>/dev/null | head -c 500`
Expected: JSON-RPC response with server capabilities listing reminder tools
