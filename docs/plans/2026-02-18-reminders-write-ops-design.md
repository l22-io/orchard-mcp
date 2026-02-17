# Reminders Write Operations Design

## Goal

Add full CRUD operations for Apple Reminders via apple-mcp, enabling programmatic list/reminder management for the Todoist side-by-side evaluation.

## Operations

| Operation | Swift subcommand | MCP tool | EventKit API |
|-----------|-----------------|----------|-------------|
| Create list | `reminder-create-list --name <n>` | `reminders.create_list` | `EKCalendar(for: .reminder)` + `store.saveCalendar()` |
| Create reminder | `reminder-create --list <l> --title <t> [--due <iso>] [--priority <0-4>] [--notes <n>]` | `reminders.create_reminder` | `EKReminder(eventStore:)` + `store.save()` |
| Complete reminder | `reminder-complete --id <calendarItemId>` | `reminders.complete_reminder` | `rem.isCompleted = true` + `store.save()` |
| Delete reminder | `reminder-delete --id <calendarItemId>` | `reminders.delete_reminder` | `store.remove(reminder, commit: true)` |
| Delete list | `reminder-delete-list --id <calendarId>` | `reminders.delete_list` | `store.removeCalendar(cal, commit: true)` |

## Key Details

- **Identifiers**: `formatReminder()` must include `id` (the `calendarItemIdentifier`) so complete/delete can target specific reminders.
- **Create reminder**: `--list` required (matched case-insensitively). Error if list doesn't exist -- don't auto-create.
- **Priority**: 0 = none, 1 = high, 5 = medium, 9 = low (EventKit convention).
- **Return values**: All write ops return the created/modified object in the JSON envelope on success.
- **Delete list guard**: Refuses if the list has items unless `--force` is passed.
- **TCC**: All writes use the same `requestFullAccessToReminders()` already in place.

## Files

- Modify: `swift/Sources/AppleBridge/Reminders.swift` -- add 5 static functions, add `id` to `formatReminder()`
- Modify: `swift/Sources/AppleBridge/AppleBridge.swift` -- add 5 subcommands
- Modify: `src/tools/reminders.ts` -- add 5 MCP tools
