import Foundation

// Reason: No native Mail framework exists for reading messages. AppleScript via
// osascript is the only supported approach that doesn't require Full Disk Access.
// Same pattern as Doctor.swift checkMailAccess().

enum MailBridge {

    // MARK: - Public API

    /// List all mail accounts with their mailboxes and unread counts.
    static func listAccounts() {
        let script = """
        tell application "Mail"
            set resultList to {}
            repeat with acct in every account
                set acctName to name of acct
                try
                    set acctEmail to my joinList(email addresses of acct, ",")
                on error
                    set acctEmail to ""
                end try
                set mboxList to {}
                try
                    repeat with mbox in every mailbox of acct
                        set mboxName to name of mbox
                        set mboxUnread to unread count of mbox
                        set end of mboxList to mboxName & "::" & (mboxUnread as string)
                    end repeat
                end try
                set end of resultList to acctName & "|||" & acctEmail & "|||" & (my joinList(mboxList, "^^^"))
            end repeat
            return my joinList(resultList, "###")
        end tell

        on joinList(theList, delim)
            set oldDelim to AppleScript's text item delimiters
            set AppleScript's text item delimiters to delim
            set theResult to theList as string
            set AppleScript's text item delimiters to oldDelim
            return theResult
        end joinList
        """

        guard let raw = runAppleScript(script) else { return }
        let accounts = parseAccountList(raw)
        JSONOutput.success(accounts)
    }

    /// Unread summary: count per account + recent unread subjects/senders.
    static func unreadSummary(limit: Int) {
        let script = """
        tell application "Mail"
            set resultList to {}
            repeat with acct in every account
                set acctName to name of acct
                try
                    set msgs to (every message of inbox of acct whose read status is false)
                    set msgCount to count of msgs
                on error
                    set msgs to {}
                    set msgCount to 0
                end try
                set maxItems to \(limit)
                if msgCount < maxItems then set maxItems to msgCount
                set msgList to {}
                repeat with i from 1 to maxItems
                    try
                        set msg to item i of msgs
                        set msgSubject to subject of msg
                        set msgSender to sender of msg
                        set msgDate to date received of msg as «class isot» as string
                        set msgFlagged to flagged status of msg
                        set msgId to message id of msg
                        set end of msgList to msgId & "|||" & msgSubject & "|||" & msgSender & "|||" & msgDate & "|||" & (msgFlagged as string) & "|||" & ((count of mail attachments of msg) as string)
                    end try
                end repeat
                set end of resultList to acctName & ":::" & (msgCount as string) & ":::" & (my joinList(msgList, "^^^"))
            end repeat
            return my joinList(resultList, "###")
        end tell

        on joinList(theList, delim)
            set oldDelim to AppleScript's text item delimiters
            set AppleScript's text item delimiters to delim
            set theResult to theList as string
            set AppleScript's text item delimiters to oldDelim
            return theResult
        end joinList
        """

        guard let raw = runAppleScript(script) else { return }
        let accounts = parseUnreadSummary(raw, limit: limit)
        JSONOutput.success(accounts)
    }

    /// Search messages by subject/sender text across accounts.
    static func search(query: String, account: String?, mailbox: String?, limit: Int) {
        let accountFilter = account.map { "of account \"\($0)\"" } ?? ""
        let mailboxTarget = mailbox ?? "inbox"

        let script = """
        tell application "Mail"
            set resultList to {}
            set searchQuery to "\(escapeForAppleScript(query))"
            set msgs to (every message of \(mailboxTarget) \(accountFilter) whose subject contains searchQuery or sender contains searchQuery)
            set msgCount to count of msgs
            set maxItems to \(limit)
            if msgCount < maxItems then set maxItems to msgCount
            repeat with i from 1 to maxItems
                set msg to item i of msgs
                set msgId to message id of msg
                set msgSubject to subject of msg
                set msgSender to sender of msg
                set msgDate to date received of msg as «class isot» as string
                set msgRead to read status of msg
                set msgFlagged to flagged status of msg
                set end of resultList to msgId & "|||" & msgSubject & "|||" & msgSender & "|||" & msgDate & "|||" & (msgRead as string) & "|||" & (msgFlagged as string) & "|||" & ((count of mail attachments of msg) as string)
            end repeat
            return my joinList(resultList, "^^^")
        end tell

        on joinList(theList, delim)
            set oldDelim to AppleScript's text item delimiters
            set AppleScript's text item delimiters to delim
            set theResult to theList as string
            set AppleScript's text item delimiters to oldDelim
            return theResult
        end joinList
        """

        guard let raw = runAppleScript(script) else { return }
        let messages = parseMessageList(raw)
        JSONOutput.success(messages)
    }

    /// Get full message content by message ID.
    static func readMessage(messageId: String) {
        let escapedId = escapeForAppleScript(messageId)

        let script = """
        tell application "Mail"
            set targetMsg to first message of inbox whose message id is "\(escapedId)"
            set msgSubject to subject of targetMsg
            set msgSender to sender of targetMsg
            set msgDate to date received of targetMsg as «class isot» as string
            set msgRead to read status of targetMsg
            set msgFlagged to flagged status of targetMsg
            set msgContent to content of targetMsg
            set msgTo to address of every to recipient of targetMsg
            set msgCc to address of every cc recipient of targetMsg
            return msgSubject & "|||" & msgSender & "|||" & msgDate & "|||" & (msgRead as string) & "|||" & (msgFlagged as string) & "|||" & msgContent & "|||" & (msgTo as string) & "|||" & (msgCc as string)
        end tell
        """

        guard let raw = runAppleScript(script) else { return }
        let parts = raw.components(separatedBy: "|||")
        guard parts.count >= 6 else {
            JSONOutput.error("Unexpected response format from Mail.app")
            return
        }

        var message: [String: Any] = [
            "id": messageId,
            "subject": parts[0],
            "sender": parts[1],
            "date": parts[2],
            "read": parts[3] == "true",
            "flagged": parts[4] == "true",
            "body": parts[5]
        ]
        if parts.count > 6 { message["to"] = parts[6] }
        if parts.count > 7 { message["cc"] = parts[7] }

        JSONOutput.success(message)
    }

    /// List flagged messages across all accounts.
    static func flagged(limit: Int) {
        let script = """
        tell application "Mail"
            set resultList to {}
            repeat with acct in every account
                try
                    repeat with mbox in every mailbox of acct
                        set flaggedMsgs to (every message of mbox whose flagged status is true)
                        repeat with msg in flaggedMsgs
                            set msgId to message id of msg
                            set msgSubject to subject of msg
                            set msgSender to sender of msg
                            set msgDate to date received of msg as «class isot» as string
                            set end of resultList to msgId & "|||" & msgSubject & "|||" & msgSender & "|||" & msgDate & "|||" & (name of acct) & "|||" & ((count of mail attachments of msg) as string)
                            if (count of resultList) >= \(limit) then exit repeat
                        end repeat
                        if (count of resultList) >= \(limit) then exit repeat
                    end repeat
                end try
                if (count of resultList) >= \(limit) then exit repeat
            end repeat
            return my joinList(resultList, "^^^")
        end tell

        on joinList(theList, delim)
            set oldDelim to AppleScript's text item delimiters
            set AppleScript's text item delimiters to delim
            set theResult to theList as string
            set AppleScript's text item delimiters to oldDelim
            return theResult
        end joinList
        """

        guard let raw = runAppleScript(script) else { return }
        let messages = parseFlaggedList(raw)
        JSONOutput.success(messages)
    }

    /// Create a draft email in Mail.app. Opens the compose window for user review.
    static func createDraft(to: [String], cc: [String]?, bcc: [String]?, subject: String, body: String, account: String?) {
        var recipientLines = ""
        for addr in to {
            recipientLines += "        make new to recipient with properties {address:\"\(escapeForAppleScript(addr))\"}\n"
        }
        if let ccAddrs = cc {
            for addr in ccAddrs {
                recipientLines += "        make new cc recipient with properties {address:\"\(escapeForAppleScript(addr))\"}\n"
            }
        }
        if let bccAddrs = bcc {
            for addr in bccAddrs {
                recipientLines += "        make new bcc recipient with properties {address:\"\(escapeForAppleScript(addr))\"}\n"
            }
        }

        let senderLine: String
        if let acct = account {
            senderLine = "    set sender of newMsg to \"\(escapeForAppleScript(acct))\""
        } else {
            senderLine = ""
        }

        let script = """
        tell application "Mail"
            set newMsg to make new outgoing message with properties {subject:"\(escapeForAppleScript(subject))", content:"\(escapeForAppleScript(body))", visible:true}
            tell newMsg
        \(recipientLines)    end tell
        \(senderLine)
        end tell
        """

        guard runAppleScript(script) != nil else { return }

        var result: [String: Any] = [
            "subject": subject,
            "to": to
        ]
        if let cc = cc { result["cc"] = cc }
        if let bcc = bcc { result["bcc"] = bcc }
        if let account = account { result["account"] = account }
        JSONOutput.success(result)
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
                    JSONOutput.error("Mail automation permission denied. Grant access in System Settings > Privacy & Security > Automation > apple-bridge > Mail.")
                } else if errStr.contains("-600") || errStr.contains("not running") {
                    JSONOutput.error("Mail.app is not running. Open Mail.app and try again.")
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

    private static func parseAccountList(_ raw: String) -> [[String: Any]] {
        guard !raw.isEmpty else { return [] }

        let accountChunks = raw.components(separatedBy: "###")
        return accountChunks.compactMap { chunk -> [String: Any]? in
            let parts = chunk.components(separatedBy: "|||")
            guard parts.count >= 2 else { return nil }

            var account: [String: Any] = [
                "name": parts[0].trimmingCharacters(in: .whitespaces),
                "email": parts[1].trimmingCharacters(in: .whitespaces)
            ]

            if parts.count > 2 && !parts[2].isEmpty {
                let mboxStrings = parts[2].components(separatedBy: "^^^")
                let mailboxes: [[String: Any]] = mboxStrings.compactMap { mboxStr in
                    let fields = mboxStr.components(separatedBy: "::")
                    guard fields.count >= 2 else { return nil }
                    return [
                        "name": fields[0].trimmingCharacters(in: .whitespaces),
                        "unreadCount": Int(fields[1].trimmingCharacters(in: .whitespaces)) ?? 0
                    ]
                }
                account["mailboxes"] = mailboxes
            }

            return account
        }
    }

    private static func parseUnreadSummary(_ raw: String, limit: Int) -> [[String: Any]] {
        guard !raw.isEmpty else { return [] }

        let accountChunks = raw.components(separatedBy: "###")
        return accountChunks.compactMap { chunk -> [String: Any]? in
            let parts = chunk.components(separatedBy: ":::")
            guard parts.count >= 2 else { return nil }

            var account: [String: Any] = [
                "account": parts[0].trimmingCharacters(in: .whitespaces),
                "unreadCount": Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            ]

            if parts.count > 2 && !parts[2].isEmpty {
                let msgStrings = parts[2].components(separatedBy: "^^^")
                let messages: [[String: Any]] = msgStrings.compactMap { msgStr in
                    let fields = msgStr.components(separatedBy: "|||")
                    guard fields.count >= 4 else { return nil }
                    var msg: [String: Any] = [
                        "id": fields[0],
                        "subject": fields[1],
                        "sender": fields[2],
                        "date": fields[3]
                    ]
                    if fields.count > 4 {
                        msg["flagged"] = fields[4] == "true"
                    }
                    if fields.count > 5 {
                        let count = Int(fields[5].trimmingCharacters(in: .whitespaces)) ?? 0
                        msg["attachmentCount"] = count
                        msg["hasAttachments"] = count > 0
                    }
                    return msg
                }
                account["recentUnread"] = messages
            }

            return account
        }
    }

    private static func parseMessageList(_ raw: String) -> [[String: Any]] {
        guard !raw.isEmpty else { return [] }

        let msgStrings = raw.components(separatedBy: "^^^")
        return msgStrings.compactMap { msgStr -> [String: Any]? in
            let fields = msgStr.components(separatedBy: "|||")
            guard fields.count >= 4 else { return nil }
            var msg: [String: Any] = [
                "id": fields[0],
                "subject": fields[1],
                "sender": fields[2],
                "date": fields[3]
            ]
            if fields.count > 4 { msg["read"] = fields[4] == "true" }
            if fields.count > 5 { msg["flagged"] = fields[5] == "true" }
            if fields.count > 6 {
                let count = Int(fields[6].trimmingCharacters(in: .whitespaces)) ?? 0
                msg["attachmentCount"] = count
                msg["hasAttachments"] = count > 0
            }
            return msg
        }
    }

    private static func parseFlaggedList(_ raw: String) -> [[String: Any]] {
        guard !raw.isEmpty else { return [] }

        let msgStrings = raw.components(separatedBy: "^^^")
        return msgStrings.compactMap { msgStr -> [String: Any]? in
            let fields = msgStr.components(separatedBy: "|||")
            guard fields.count >= 4 else { return nil }
            var msg: [String: Any] = [
                "id": fields[0],
                "subject": fields[1],
                "sender": fields[2],
                "date": fields[3],
                "flagged": true
            ]
            if fields.count > 4 { msg["account"] = fields[4] }
            if fields.count > 5 {
                let count = Int(fields[5].trimmingCharacters(in: .whitespaces)) ?? 0
                msg["attachmentCount"] = count
                msg["hasAttachments"] = count > 0
            }
            return msg
        }
    }
}
