# Reminders Write Operations Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add full CRUD operations (create list, create reminder, complete, delete reminder, delete list) to apple-mcp Reminders.

**Architecture:** Same two-layer pattern as existing read ops. Swift functions in `RemindersBridge` use EventKit write APIs (`saveCalendar`, `save`, `remove`). Subcommands in `AppleBridge.swift` expose them as CLI. TypeScript MCP tools in `reminders.ts` call the bridge.

**Tech Stack:** Swift (EventKit, ArgumentParser), TypeScript (MCP SDK, Zod)

---

### Task 1: Add `id` field to `formatReminder()` output

Write ops need to reference reminders by ID. The existing `formatReminder()` helper doesn't include it.

**Files:**
- Modify: `swift/Sources/AppleBridge/Reminders.swift:153-173`

**Step 1: Add `id` to `formatReminder()`**

In `Reminders.swift`, find the `formatReminder` function (line 153). Add `calendarItemIdentifier` as `"id"` to the dict:

```swift
private static func formatReminder(_ rem: EKReminder) -> [String: Any] {
    var dict: [String: Any] = [
        "id": rem.calendarItemIdentifier,
        "title": rem.title ?? "(no title)",
        "isCompleted": rem.isCompleted,
        "list": rem.calendar.title,
        "priority": rem.priority
    ]
    // ... rest unchanged
}
```

**Step 2: Verify build**

Run: `cd swift && swift build -c release 2>&1 | tail -5`
Expected: `Build complete!`

**Step 3: Verify id appears in output**

Run: `TMPFILE=$(mktemp) && open -W -n -a swift/.build/AppleBridge.app --args reminders --list Reminders --limit 1 --output "$TMPFILE" && cat "$TMPFILE" && rm "$TMPFILE"`
Expected: JSON with `"id"` field on each reminder.

**Step 4: Commit**

```bash
git add swift/Sources/AppleBridge/Reminders.swift
git commit -m "feat(reminders): add id field to reminder output"
```

---

### Task 2: Swift -- `createList()` and `createReminder()`

**Files:**
- Modify: `swift/Sources/AppleBridge/Reminders.swift` -- add two new static functions after `today()` (line 149)

**Step 1: Add `createList` function**

Add after the `today()` function, before `// MARK: - Helpers`:

```swift
static func createList(name: String) async {
    guard await requestAccess() else {
        JSONOutput.error("Reminders access denied. Grant access in System Settings > Privacy & Security > Reminders.")
        return
    }

    let cal = EKCalendar(for: .reminder, eventStore: store)
    cal.title = name

    // Use the default reminder source (iCloud if available)
    guard let source = store.defaultCalendarForNewReminders()?.source else {
        JSONOutput.error("No reminder source available.")
        return
    }
    cal.source = source

    do {
        try store.saveCalendar(cal, commit: true)
        let result: [String: Any] = [
            "id": cal.calendarIdentifier,
            "title": cal.title,
            "account": source.title,
            "allowsModify": cal.allowsContentModifications
        ]
        JSONOutput.success(result)
    } catch {
        JSONOutput.error("Failed to create list: \(error.localizedDescription)")
    }
}
```

**Step 2: Add `createReminder` function**

Add after `createList`:

```swift
static func createReminder(listName: String, title: String, dueDate: String?, priority: Int, notes: String?) async {
    guard await requestAccess() else {
        JSONOutput.error("Reminders access denied. Grant access in System Settings > Privacy & Security > Reminders.")
        return
    }

    let matches = store.calendars(for: .reminder).filter {
        $0.title.localizedCaseInsensitiveCompare(listName) == .orderedSame
    }
    guard let calendar = matches.first else {
        JSONOutput.error("Reminder list not found: \(listName)")
        return
    }

    let reminder = EKReminder(eventStore: store)
    reminder.title = title
    reminder.calendar = calendar
    reminder.priority = priority

    if let notes = notes {
        reminder.notes = notes
    }

    if let dueDateStr = dueDate {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        // Also try date-only format
        let formatters = [formatter]
        var parsed: Date?
        for fmt in formatters {
            parsed = fmt.date(from: dueDateStr)
            if parsed != nil { break }
        }
        if parsed == nil {
            // Try date-only: YYYY-MM-DD
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone.current
            parsed = df.date(from: dueDateStr)
        }
        guard let due = parsed else {
            JSONOutput.error("Invalid date format: \(dueDateStr). Use ISO 8601 (e.g. 2026-02-18T10:00:00Z or 2026-02-18).")
            return
        }
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: due
        )
    }

    do {
        try store.save(reminder, commit: true)
        JSONOutput.success(formatReminder(reminder))
    } catch {
        JSONOutput.error("Failed to create reminder: \(error.localizedDescription)")
    }
}
```

**Step 3: Verify build**

Run: `cd swift && swift build -c release 2>&1 | tail -5`
Expected: `Build complete!`

**Step 4: Commit**

```bash
git add swift/Sources/AppleBridge/Reminders.swift
git commit -m "feat(reminders): add createList and createReminder functions"
```

---

### Task 3: Swift -- `completeReminder()`, `deleteReminder()`, `deleteList()`

**Files:**
- Modify: `swift/Sources/AppleBridge/Reminders.swift` -- add three more static functions after `createReminder()`

**Step 1: Add `completeReminder` function**

```swift
static func completeReminder(id: String) async {
    guard await requestAccess() else {
        JSONOutput.error("Reminders access denied. Grant access in System Settings > Privacy & Security > Reminders.")
        return
    }

    guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
        JSONOutput.error("Reminder not found with id: \(id)")
        return
    }

    reminder.isCompleted = true

    do {
        try store.save(reminder, commit: true)
        JSONOutput.success(formatReminder(reminder))
    } catch {
        JSONOutput.error("Failed to complete reminder: \(error.localizedDescription)")
    }
}
```

**Step 2: Add `deleteReminder` function**

```swift
static func deleteReminder(id: String) async {
    guard await requestAccess() else {
        JSONOutput.error("Reminders access denied. Grant access in System Settings > Privacy & Security > Reminders.")
        return
    }

    guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
        JSONOutput.error("Reminder not found with id: \(id)")
        return
    }

    let info = formatReminder(reminder)

    do {
        try store.remove(reminder, commit: true)
        JSONOutput.success(info)
    } catch {
        JSONOutput.error("Failed to delete reminder: \(error.localizedDescription)")
    }
}
```

**Step 3: Add `deleteList` function**

```swift
static func deleteList(id: String, force: Bool) async {
    guard await requestAccess() else {
        JSONOutput.error("Reminders access denied. Grant access in System Settings > Privacy & Security > Reminders.")
        return
    }

    guard let calendar = store.calendar(withIdentifier: id) else {
        JSONOutput.error("Reminder list not found with id: \(id)")
        return
    }

    if !force {
        // Check for existing reminders
        let predicate = store.predicateForReminders(in: [calendar])
        let reminders = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { result in
                continuation.resume(returning: result ?? [])
            }
        }
        if !reminders.isEmpty {
            JSONOutput.error("List '\(calendar.title)' has \(reminders.count) reminders. Use --force to delete anyway.")
            return
        }
    }

    let info: [String: Any] = [
        "id": calendar.calendarIdentifier,
        "title": calendar.title
    ]

    do {
        try store.removeCalendar(calendar, commit: true)
        JSONOutput.success(info)
    } catch {
        JSONOutput.error("Failed to delete list: \(error.localizedDescription)")
    }
}
```

**Step 4: Verify build**

Run: `cd swift && swift build -c release 2>&1 | tail -5`
Expected: `Build complete!`

**Step 5: Commit**

```bash
git add swift/Sources/AppleBridge/Reminders.swift
git commit -m "feat(reminders): add complete, delete reminder, delete list functions"
```

---

### Task 4: Swift subcommands in AppleBridge.swift

**Files:**
- Modify: `swift/Sources/AppleBridge/AppleBridge.swift:32-46` (subcommands array) and append new structs after `RemindersToday` (line 219)

**Step 1: Add 5 new subcommand structs**

Add after `RemindersToday` struct (line 219), before `// MARK: - Doctor`:

```swift
struct ReminderCreateList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminder-create-list",
        abstract: "Create a new reminder list."
    )

    @Option(name: .long, help: "Name for the new list")
    var name: String

    func run() async throws {
        await RemindersBridge.createList(name: name)
    }
}

struct ReminderCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminder-create",
        abstract: "Create a new reminder in a list."
    )

    @Option(name: .long, help: "List name to add the reminder to")
    var list: String

    @Option(name: .long, help: "Reminder title")
    var title: String

    @Option(name: .long, help: "Due date (ISO 8601, e.g. 2026-02-18 or 2026-02-18T10:00:00Z)")
    var due: String?

    @Option(name: .long, help: "Priority: 0=none, 1=high, 5=medium, 9=low (default: 0)")
    var priority: Int = 0

    @Option(name: .long, help: "Notes for the reminder")
    var notes: String?

    func run() async throws {
        await RemindersBridge.createReminder(listName: list, title: title, dueDate: due, priority: priority, notes: notes)
    }
}

struct ReminderComplete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminder-complete",
        abstract: "Mark a reminder as completed."
    )

    @Option(name: .long, help: "Reminder ID (from reminders command output)")
    var id: String

    func run() async throws {
        await RemindersBridge.completeReminder(id: id)
    }
}

struct ReminderDelete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminder-delete",
        abstract: "Delete a reminder."
    )

    @Option(name: .long, help: "Reminder ID (from reminders command output)")
    var id: String

    func run() async throws {
        await RemindersBridge.deleteReminder(id: id)
    }
}

struct ReminderDeleteList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminder-delete-list",
        abstract: "Delete a reminder list."
    )

    @Option(name: .long, help: "List ID (from reminder-lists command output)")
    var id: String

    @Flag(name: .long, help: "Delete even if the list has reminders")
    var force: Bool = false

    func run() async throws {
        await RemindersBridge.deleteList(id: id, force: force)
    }
}
```

**Step 2: Register subcommands**

In `AppleBridge.swift`, add the 5 new types to the `subcommands` array (line 32-45):

```swift
subcommands: [
    Calendars.self,
    Events.self,
    Search.self,
    MailAccounts.self,
    MailUnread.self,
    MailSearchCmd.self,
    MailMessage.self,
    MailFlagged.self,
    ReminderLists.self,
    RemindersCmd.self,
    RemindersToday.self,
    ReminderCreateList.self,
    ReminderCreate.self,
    ReminderComplete.self,
    ReminderDelete.self,
    ReminderDeleteList.self,
    Doctor.self
]
```

**Step 3: Verify build**

Run: `cd swift && swift build -c release 2>&1 | tail -5`
Expected: `Build complete!`

**Step 4: Commit**

```bash
git add swift/Sources/AppleBridge/AppleBridge.swift
git commit -m "feat(reminders): add 5 write subcommands to CLI"
```

---

### Task 5: End-to-end Swift CLI test

Test the full create -> complete -> delete cycle via the .app bundle.

**Step 1: Rebuild .app bundle**

```bash
cd swift
cp .build/release/apple-bridge .build/AppleBridge.app/Contents/MacOS/apple-bridge
codesign --force --sign - .build/AppleBridge.app
```

**Step 2: Create a test list**

```bash
TMPFILE=$(mktemp) && open -W -n -a swift/.build/AppleBridge.app --args reminder-create-list --name "Test-Write-Ops" --output "$TMPFILE" && cat "$TMPFILE" && rm "$TMPFILE"
```

Expected: `{"status": "ok", "data": {"id": "...", "title": "Test-Write-Ops", ...}}`
Save the list ID.

**Step 3: Create a test reminder**

```bash
TMPFILE=$(mktemp) && open -W -n -a swift/.build/AppleBridge.app --args reminder-create --list "Test-Write-Ops" --title "Test reminder" --due 2026-02-20 --priority 1 --notes "Test notes" --output "$TMPFILE" && cat "$TMPFILE" && rm "$TMPFILE"
```

Expected: `{"status": "ok", "data": {"id": "...", "title": "Test reminder", ...}}`
Save the reminder ID.

**Step 4: Complete the reminder**

```bash
TMPFILE=$(mktemp) && open -W -n -a swift/.build/AppleBridge.app --args reminder-complete --id <REMINDER_ID> --output "$TMPFILE" && cat "$TMPFILE" && rm "$TMPFILE"
```

Expected: `{"status": "ok", "data": {..., "isCompleted": true, ...}}`

**Step 5: Delete the reminder**

```bash
TMPFILE=$(mktemp) && open -W -n -a swift/.build/AppleBridge.app --args reminder-delete --id <REMINDER_ID> --output "$TMPFILE" && cat "$TMPFILE" && rm "$TMPFILE"
```

Expected: `{"status": "ok", "data": {...}}`

**Step 6: Delete the test list**

```bash
TMPFILE=$(mktemp) && open -W -n -a swift/.build/AppleBridge.app --args reminder-delete-list --id <LIST_ID> --output "$TMPFILE" && cat "$TMPFILE" && rm "$TMPFILE"
```

Expected: `{"status": "ok", "data": {"id": "...", "title": "Test-Write-Ops"}}`

**Step 7: Verify list is gone**

```bash
TMPFILE=$(mktemp) && open -W -n -a swift/.build/AppleBridge.app --args reminder-lists --output "$TMPFILE" && cat "$TMPFILE" && rm "$TMPFILE"
```

Expected: No "Test-Write-Ops" in the output.

---

### Task 6: TypeScript MCP tools

**Files:**
- Modify: `src/tools/reminders.ts:63` -- add 5 new tool registrations after `reminders.today`

**Step 1: Add 5 MCP tools**

Add after the `reminders.today` tool registration (before the closing `}`):

```typescript
server.tool(
  "reminders.create_list",
  "Create a new reminder list.",
  {
    name: z.string().describe("Name for the new list"),
  },
  async ({ name }) => {
    const data = await bridgeData(["reminder-create-list", "--name", name]);
    return {
      content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
    };
  }
);

server.tool(
  "reminders.create_reminder",
  "Create a new reminder in a list.",
  {
    list: z.string().describe("List name to add the reminder to"),
    title: z.string().describe("Reminder title"),
    due: z
      .string()
      .optional()
      .describe("Due date (ISO 8601, e.g. 2026-02-18 or 2026-02-18T10:00:00Z)"),
    priority: z
      .number()
      .optional()
      .describe("Priority: 0=none, 1=high, 5=medium, 9=low (default: 0)"),
    notes: z.string().optional().describe("Notes for the reminder"),
  },
  async ({ list, title, due, priority, notes }) => {
    const args = ["reminder-create", "--list", list, "--title", title];
    if (due) {
      args.push("--due", due);
    }
    if (priority !== undefined) {
      args.push("--priority", String(priority));
    }
    if (notes) {
      args.push("--notes", notes);
    }
    const data = await bridgeData(args);
    return {
      content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
    };
  }
);

server.tool(
  "reminders.complete_reminder",
  "Mark a reminder as completed.",
  {
    id: z.string().describe("Reminder ID (from reminders.list_reminders output)"),
  },
  async ({ id }) => {
    const data = await bridgeData(["reminder-complete", "--id", id]);
    return {
      content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
    };
  }
);

server.tool(
  "reminders.delete_reminder",
  "Delete a reminder.",
  {
    id: z.string().describe("Reminder ID (from reminders.list_reminders output)"),
  },
  async ({ id }) => {
    const data = await bridgeData(["reminder-delete", "--id", id]);
    return {
      content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
    };
  }
);

server.tool(
  "reminders.delete_list",
  "Delete a reminder list. Fails if the list has reminders unless force is true.",
  {
    id: z.string().describe("List ID (from reminders.list_lists output)"),
    force: z
      .boolean()
      .optional()
      .describe("Delete even if the list has reminders (default: false)"),
  },
  async ({ id, force }) => {
    const args = ["reminder-delete-list", "--id", id];
    if (force) {
      args.push("--force");
    }
    const data = await bridgeData(args);
    return {
      content: [{ type: "text", text: JSON.stringify(data, null, 2) }],
    };
  }
);
```

**Step 2: Build TypeScript**

Run: `npx tsc`
Expected: No errors.

**Step 3: Commit**

```bash
git add src/tools/reminders.ts
git commit -m "feat(reminders): add 5 write MCP tools"
```

---

### Task 7: Build, rebuild .app bundle, and verify MCP server

**Step 1: Full rebuild**

```bash
cd swift && swift build -c release
cp .build/release/apple-bridge .build/AppleBridge.app/Contents/MacOS/apple-bridge
codesign --force --sign - .build/AppleBridge.app
cd .. && npx tsc
```

**Step 2: Verify MCP server lists all tools**

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | node build/index.js 2>/dev/null
```

Expected: 18 tools total (13 existing + 5 new write ops). Look for `reminders.create_list`, `reminders.create_reminder`, `reminders.complete_reminder`, `reminders.delete_reminder`, `reminders.delete_list`.

**Step 3: Commit**

```bash
git add -A
git commit -m "chore: rebuild for reminders write ops"
```
