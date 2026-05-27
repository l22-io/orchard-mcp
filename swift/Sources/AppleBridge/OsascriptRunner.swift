import Foundation
import Darwin

// Reason: Single PID slot for the currently-running osascript child. apple-bridge
// runs one subcommand per invocation and each runOsascript call is synchronous,
// so at most one osascript is alive at any moment. Stored as sig_atomic_t so
// the C-convention signal handler can read it without locks (async-signal-safe).
// File-scope is required: @convention(c) closures cannot capture Swift state, so
// the handler reaches it as a C global.
private var currentChildPid: sig_atomic_t = 0

/// Language flavour passed to `osascript`. AppleScript is the default; JXA is
/// used by Numbers for native JSON output via JavaScript for Automation.
enum OsascriptLanguage {
    case appleScript
    case javaScript
}

/// Raw result of an osascript invocation. Used by callers that need to inspect
/// status without emitting a JSON error envelope (e.g. Doctor's probes).
struct OsascriptResult {
    let status: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

enum OsascriptRunner {

    /// Default watchdog window. Long enough for typical iWork/Notes/Mail
    /// operations under load; short enough that the Swift watchdog fires
    /// before node's per-call timeout under default conditions.
    static let defaultTimeout: TimeInterval = 120

    /// SIGKILL grace period after the initial SIGTERM. Apple Events held by
    /// host apps (Mail, Notes) can keep osascript unresponsive to SIGTERM for
    /// a moment; SIGKILL is uncatchable so the second signal always wins.
    private static let sigkillGrace: TimeInterval = 2

    /// Install signal handlers that kill the currently-running osascript child
    /// before apple-bridge dies from SIGTERM/SIGINT/SIGHUP. Required because
    /// Foundation.Process on macOS spawns its child into a new process group,
    /// so the node-side group-kill in src/bridge.ts only hits apple-bridge --
    /// the osascript grandchild gets orphaned (PPID=1) and keeps holding
    /// Mail.app's Apple Event queue hostage. The handler is async-signal-safe:
    /// it only reads currentChildPid (sig_atomic_t) and calls kill/signal/raise,
    /// all of which are listed as signal-safe by POSIX.
    static func installSignalHandlers() {
        let handler: @convention(c) (Int32) -> Void = { signo in
            let pid = pid_t(currentChildPid)
            if pid > 0 {
                _ = kill(pid, SIGKILL)
            }
            // Restore default disposition and re-raise so we exit with the
            // standard signal status (and any system-level cleanup runs).
            signal(signo, SIG_DFL)
            raise(signo)
        }
        signal(SIGTERM, handler)
        signal(SIGINT, handler)
        signal(SIGHUP, handler)
    }

    /// Convenience entry point that emits a `JSONOutput.error` and returns nil
    /// on any failure (timeout, non-zero exit, spawn failure). On success
    /// returns the trimmed stdout. `appName` is used to build the standard
    /// permission-denied / not-running messages that every iWork module emits;
    /// `timeoutHint` is an optional sentence appended to the timeout message
    /// (used by Mail to suggest narrowing the search scope).
    static func run(
        script: String,
        language: OsascriptLanguage = .appleScript,
        timeout: TimeInterval = defaultTimeout,
        appName: String,
        timeoutHint: String? = nil
    ) -> String? {
        guard let result = runRaw(script: script, language: language, timeout: timeout) else {
            JSONOutput.error("Failed to spawn osascript")
            return nil
        }
        if result.timedOut {
            var msg = "\(appName) AppleScript exceeded \(Int(timeout))s timeout - killed to free \(appName)."
            if let hint = timeoutHint {
                msg += " \(hint)"
            }
            JSONOutput.error(msg)
            return nil
        }
        if result.status != 0 {
            let errStr = result.stderr.isEmpty ? "Unknown error" : result.stderr
            if errStr.contains("-1743") || errStr.contains("not allowed") {
                JSONOutput.error("\(appName) automation permission denied. Grant access in System Settings > Privacy & Security > Automation > apple-bridge > \(appName).")
            } else if errStr.contains("-600") || errStr.contains("not running") {
                JSONOutput.error("\(appName) is not running. Open \(appName) and try again.")
            } else {
                JSONOutput.error("AppleScript error: \(errStr)")
            }
            return nil
        }
        return result.stdout
    }

    /// Raw runner that returns status + stdout + stderr without side effects on
    /// the JSON envelope. Returns nil only on spawn failure. Used by callers
    /// that need to inspect status (e.g. Doctor probing "is Notes accessible").
    static func runRaw(
        script: String,
        language: OsascriptLanguage = .appleScript,
        timeout: TimeInterval = defaultTimeout
    ) -> OsascriptResult? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        switch language {
        case .appleScript:
            task.arguments = ["-e", script]
        case .javaScript:
            task.arguments = ["-l", "JavaScript", "-e", script]
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
        } catch {
            return nil
        }

        let pid = task.processIdentifier
        currentChildPid = sig_atomic_t(pid)
        defer { currentChildPid = 0 }

        let timeoutLock = NSLock()
        var didTimeOut = false

        let watchdog = DispatchWorkItem {
            guard task.isRunning else { return }
            timeoutLock.lock()
            didTimeOut = true
            timeoutLock.unlock()
            task.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + sigkillGrace) {
                if task.isRunning { kill(pid, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        task.waitUntilExit()
        watchdog.cancel()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        timeoutLock.lock()
        let timedOut = didTimeOut
        timeoutLock.unlock()

        return OsascriptResult(
            status: task.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            timedOut: timedOut
        )
    }
}
