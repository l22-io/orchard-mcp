import Contacts
import EventKit
import Foundation

// Reason: The doctor subcommand provides a single entry point to verify
// all permissions are granted and list accessible resources. Useful for
// first-run setup and debugging.

enum DoctorBridge {
    static func run() async {
        var report: [String: Any] = [
            "version": "0.5.0",
            "platform": "macOS",
            "systemVersion": ProcessInfo.processInfo.operatingSystemVersionString
        ]

        // Calendar permissions
        let calStatus = EKEventStore.authorizationStatus(for: .event)
        let calStatusStr = authStatusName(calStatus)
        report["calendar"] = [
            "status": calStatusStr,
            "granted": calStatus == .fullAccess
        ]

        // Reason: If not determined, attempt to request so the user gets prompted.
        if calStatus == .notDetermined {
            let granted = await CalendarBridge.requestAccess()
            report["calendar"] = [
                "status": granted ? "fullAccess" : "denied",
                "granted": granted,
                "note": "Permission was just requested."
            ]
        }

        // If we have calendar access, list calendar count and accounts
        if calStatus == .fullAccess || calStatus == .notDetermined {
            let store = EKEventStore()
            _ = try? await store.requestFullAccessToEvents()
            let calendars = store.calendars(for: .event)
            let accounts = Set(calendars.compactMap { $0.source?.title })
            report["calendarSummary"] = [
                "count": calendars.count,
                "accounts": Array(accounts).sorted()
            ]
        }

        // Reminders permissions
        let remStatus = EKEventStore.authorizationStatus(for: .reminder)
        report["reminders"] = [
            "status": authStatusName(remStatus),
            "granted": remStatus == .fullAccess
        ]

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

        // Mail -- we can only check if osascript is available
        // Reason: Mail access is via AppleScript, no programmatic permission check exists.
        let mailCheck = checkMailAccess()
        report["mail"] = mailCheck

        // iWork apps
        let numbersCheck = checkIWorkApp("Numbers")
        let pagesCheck = checkIWorkApp("Pages")
        let keynoteCheck = checkIWorkApp("Keynote")
        report["numbers"] = numbersCheck
        report["pages"] = pagesCheck
        report["keynote"] = keynoteCheck

        // Notes -- AppleScript-based, same shape as Mail
        report["notes"] = checkNotesAccess()

        // Contacts -- native CNContactStore
        let contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
        report["contacts"] = [
            "status": contactsAuthName(contactsStatus),
            "granted": contactsStatus == .authorized
        ]
        if contactsStatus == .notDetermined {
            let granted = await ContactsBridge.requestAccess()
            report["contacts"] = [
                "status": granted ? "authorized" : "denied",
                "granted": granted,
                "note": "Permission was just requested."
            ]
        }

        // Guidance
        var actions: [String] = []
        if calStatus != .fullAccess {
            actions.append("Calendar: Grant access in System Settings > Privacy & Security > Calendars")
        }
        if remStatus != .fullAccess {
            actions.append("Reminders: Grant access in System Settings > Privacy & Security > Reminders")
        }
        if !(mailCheck["accessible"] as? Bool ?? false) {
            actions.append("Mail: Run apple-bridge with a mail subcommand to trigger the Automation permission dialog")
        }
        if !(numbersCheck["installed"] as? Bool ?? false) {
            actions.append("Numbers: Install from App Store for spreadsheet tools")
        }
        if !(pagesCheck["installed"] as? Bool ?? false) {
            actions.append("Pages: Install from App Store for document tools")
        }
        if !(keynoteCheck["installed"] as? Bool ?? false) {
            actions.append("Keynote: Install from App Store for presentation tools")
        }
        let notesAccessible = (report["notes"] as? [String: Any])?["accessible"] as? Bool ?? false
        if !notesAccessible {
            actions.append("Notes: Run apple-bridge with a notes subcommand to trigger the Automation permission dialog")
        }
        if contactsStatus != .authorized {
            actions.append("Contacts: Grant access in System Settings > Privacy & Security > Contacts")
        }
        if !actions.isEmpty {
            report["requiredActions"] = actions
        }

        JSONOutput.success(report)
    }

    private static func authStatusName(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .fullAccess: return "fullAccess"
        case .writeOnly: return "writeOnly"
        @unknown default: return "unknown"
        }
    }

    private static func checkIWorkApp(_ appName: String) -> [String: Any] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "tell application \"\(appName)\" to return name"]
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                return ["installed": true, "accessible": true]
            } else {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if errStr.contains("-600") || errStr.contains("not running") {
                    return ["installed": true, "accessible": false, "note": "\(appName) is not running."]
                }
                return ["installed": false, "accessible": false, "note": "\(appName) may not be installed."]
            }
        } catch {
            return ["installed": false, "accessible": false, "note": "Could not check \(appName): \(error.localizedDescription)"]
        }
    }

    private static func contactsAuthName(_ status: CNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .limited: return "limited"
        @unknown default: return "unknown"
        }
    }

    private static func checkNotesAccess() -> [String: Any] {
        guard let result = runOsascriptBounded(["-e", "tell application \"Notes\" to count of accounts"]) else {
            return [
                "accessible": false,
                "note": "Notes.app did not respond within \(Int(doctorAppleScriptTimeout))s. It may be busy or unresponsive; system_doctor refuses to wait longer to avoid orphaning osascript."
            ]
        }
        if result.status == 0 {
            return [
                "accessible": true,
                "accountCount": Int(result.output) ?? 0
            ]
        }
        return [
            "accessible": false,
            "note": "Notes automation permission not yet granted or Notes.app not running."
        ]
    }

    private static func checkMailAccess() -> [String: Any] {
        // Reason: Try a minimal AppleScript to see if Mail.app is accessible.
        // This doesn't send the permission prompt -- it just checks if we can talk to Mail.
        guard let result = runOsascriptBounded(["-e", "tell application \"Mail\" to count of accounts"]) else {
            return [
                "accessible": false,
                "note": "Mail.app did not respond within \(Int(doctorAppleScriptTimeout))s. It may be busy or unresponsive; system_doctor refuses to wait longer to avoid orphaning osascript and wedging Mail.app's Apple Event queue."
            ]
        }
        if result.status == 0 {
            return [
                "accessible": true,
                "accountCount": Int(result.output) ?? 0
            ]
        }
        return [
            "accessible": false,
            "note": "Mail automation permission not yet granted or Mail.app not running."
        ]
    }

    // MARK: - Bounded osascript helper

    /// Hard timeout for any AppleScript invocation issued by the doctor. The
    /// doctor's job is to report state quickly; if Mail.app or Notes.app
    /// cannot answer "count of accounts" in this window they are by definition
    /// not accessible, and continuing to wait risks the outer Node bridge
    /// timer firing first and orphaning osascript (which then keeps Mail.app
    /// locked on Apple Events for as long as it stays alive).
    private static let doctorAppleScriptTimeout: TimeInterval = 5

    /// Run `osascript` with the given arguments under a hard timeout. Returns
    /// nil on timeout (or spawn failure); otherwise returns the exit status
    /// and trimmed stdout. The watchdog SIGTERMs first, then SIGKILLs after
    /// a short grace so Apple-Event-wedged osascript processes are reaped.
    private static func runOsascriptBounded(
        _ args: [String],
        timeoutSeconds: TimeInterval = doctorAppleScriptTimeout
    ) -> (status: Int32, output: String)? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = args
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return nil
        }

        let pid = task.processIdentifier
        let didTimeOut = TimeoutFlag()
        let watchdog = DispatchWorkItem {
            guard task.isRunning else { return }
            didTimeOut.set()
            task.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if task.isRunning { kill(pid, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: watchdog)
        task.waitUntilExit()
        watchdog.cancel()

        if didTimeOut.value { return nil }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (task.terminationStatus, output)
    }

    /// Thread-safe flag for the bounded osascript watchdog. Mirrors the
    /// MailBridge.TimeoutFlag used by Mail.swift's runAppleScript.
    private final class TimeoutFlag {
        private let lock = NSLock()
        private var fired = false
        func set() { lock.lock(); fired = true; lock.unlock() }
        var value: Bool { lock.lock(); defer { lock.unlock() }; return fired }
    }
}
