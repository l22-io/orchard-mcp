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
                set mboxList to my listMailboxes(acct, "")
                set end of resultList to acctName & "|||" & acctEmail & "|||" & (my joinList(mboxList, "^^^"))
            end repeat
            return my joinList(resultList, "###")
        end tell

        on listMailboxes(parentMbox, prefix)
            set mboxList to {}
            tell application "Mail"
                set childBoxes to every mailbox of parentMbox
                repeat with mbox in childBoxes
                    set fullName to prefix & name of mbox
                    set mboxUnread to unread count of mbox
                    set end of mboxList to fullName & "::" & (mboxUnread as string)
                end repeat
            end tell
            repeat with i from 1 to count of childBoxes
                set mbox to item i of childBoxes
                tell application "Mail"
                    set mboxName to prefix & name of mbox
                end tell
                set subList to my listMailboxes(mbox, mboxName & "/")
                set mboxList to mboxList & subList
            end repeat
            return mboxList
        end listMailboxes

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
                set msgs to {}
                set msgCount to 0
                -- Try inbox keyword first; fall back to All Mail only for accounts
                -- where inbox keyword fails (e.g. Proton Bridge).
                try
                    set msgs to (every message of inbox of acct whose read status is false)
                    set msgCount to count of msgs
                on error
                    try
                        set msgs to (every message of mailbox "All Mail" of acct whose read status is false)
                        set msgCount to count of msgs
                    end try
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

    /// Search messages by subject, sender, body, or all fields across accounts.
    static func search(query: String, account: String?, mailbox: String?, limit: Int, searchIn: String, offset: Int?) {
        let searchQuery = escapeForAppleScript(query)
        let effectiveOffset = offset ?? 0
        let whereClause: String
        switch searchIn {
        case "subject":
            whereClause = "whose subject contains searchQuery"
        case "sender":
            whereClause = "whose sender contains searchQuery"
        case "body":
            whereClause = "whose content contains searchQuery"
        default:
            whereClause = "whose subject contains searchQuery or sender contains searchQuery or content contains searchQuery"
        }

        let isAllMailboxes = mailbox == "all"
        let isAllAccounts = account == "all"

        let script: String
        if isAllMailboxes {
            // Case 3 & 4: iterate mailboxes
            let accountLoop: String
            if let acct = account, !isAllAccounts {
                // Case 3: specific account, all mailboxes
                accountLoop = "set acctList to every account whose name is \"\(escapeForAppleScript(acct))\""
            } else {
                // Case 4: all accounts, all mailboxes
                accountLoop = "set acctList to every account"
            }
            script = """
            tell application "Mail"
                set resultList to {}
                set searchQuery to "\(searchQuery)"
                \(accountLoop)
                set totalCount to 0
                set skipped to 0
                set collected to 0
                repeat with acct in acctList
                    repeat with mbox in every mailbox of acct
                        try
                            set mboxMsgs to (every message of mbox \(whereClause))
                            set mboxCount to count of mboxMsgs
                            set totalCount to totalCount + mboxCount
                            repeat with j from 1 to mboxCount
                                if skipped < \(effectiveOffset) then
                                    set skipped to skipped + 1
                                else if collected < \(limit) then
                                    set msg to item j of mboxMsgs
                                    set msgId to message id of msg
                                    set msgSubject to subject of msg
                                    set msgSender to sender of msg
                                    set msgDate to date received of msg as «class isot» as string
                                    set msgRead to read status of msg
                                    set msgFlagged to flagged status of msg
                                    set msgMbox to name of mbox
                                    set end of resultList to msgId & "|||" & msgSubject & "|||" & msgSender & "|||" & msgDate & "|||" & (msgRead as string) & "|||" & (msgFlagged as string) & "|||" & ((count of mail attachments of msg) as string) & "|||" & msgMbox
                                    set collected to collected + 1
                                end if
                            end repeat
                        end try
                    end repeat
                end repeat
                return my joinList(resultList, "^^^") & "###TOTAL:::" & (totalCount as string)
            end tell

            on joinList(theList, delim)
                set oldDelim to AppleScript's text item delimiters
                set AppleScript's text item delimiters to delim
                set theResult to theList as string
                set AppleScript's text item delimiters to oldDelim
                return theResult
            end joinList
            """
        } else {
            // Cases 1, 2, 5: single mailbox search (existing logic with whereClause)
            // When account is "all", leave accountFilter empty to search unified mailbox
            let accountFilter: String
            if let acct = account, acct != "all" {
                accountFilter = "of account \"\(escapeForAppleScript(acct))\""
            } else {
                accountFilter = ""
            }
            let mailboxTarget: String
            if let mbox = mailbox {
                mailboxTarget = "mailbox \"\(escapeForAppleScript(mbox))\""
            } else {
                mailboxTarget = "inbox"
            }

            let fallbackBlock: String
            if account != nil && account != "all" && mailbox == nil {
                fallbackBlock = """
                    on error
                        try
                            set msgs to (every message of mailbox "All Mail" \(accountFilter) \(whereClause))
                        end try
                """
            } else {
                fallbackBlock = ""
            }

            script = """
            tell application "Mail"
                set resultList to {}
                set searchQuery to "\(searchQuery)"
                set msgs to {}
                try
                    set msgs to (every message of \(mailboxTarget) \(accountFilter) \(whereClause))
                \(fallbackBlock)
                end try
                set msgCount to count of msgs
                set startIdx to \(effectiveOffset) + 1
                set endIdx to startIdx + \(limit) - 1
                if endIdx > msgCount then set endIdx to msgCount
                repeat with i from startIdx to endIdx
                    set msg to item i of msgs
                    set msgId to message id of msg
                    set msgSubject to subject of msg
                    set msgSender to sender of msg
                    set msgDate to date received of msg as «class isot» as string
                    set msgRead to read status of msg
                    set msgFlagged to flagged status of msg
                    set end of resultList to msgId & "|||" & msgSubject & "|||" & msgSender & "|||" & msgDate & "|||" & (msgRead as string) & "|||" & (msgFlagged as string) & "|||" & ((count of mail attachments of msg) as string)
                end repeat
                return my joinList(resultList, "^^^") & "###TOTAL:::" & (msgCount as string)
            end tell

            on joinList(theList, delim)
                set oldDelim to AppleScript's text item delimiters
                set AppleScript's text item delimiters to delim
                set theResult to theList as string
                set AppleScript's text item delimiters to oldDelim
                return theResult
            end joinList
            """
        }

        guard let raw = runAppleScript(script) else { return }

        // Split off total count metadata
        let totalParts = raw.components(separatedBy: "###TOTAL:::")
        let messagesRaw = totalParts[0]
        let total = totalParts.count > 1 ? Int(totalParts[1].trimmingCharacters(in: .whitespaces)) ?? 0 : 0

        let messages = parseMessageList(messagesRaw)

        if let offset = offset {
            // offset was explicitly provided — return pagination envelope
            let envelope: [String: Any] = [
                "messages": messages,
                "total": total,
                "offset": offset,
                "limit": limit,
                "hasMore": offset + limit < total
            ]
            JSONOutput.success(envelope)
        } else {
            // offset not provided — backwards-compatible flat array
            JSONOutput.success(messages)
        }
    }

    /// Get full message content by message ID.
    static func readMessage(messageId: String, maxBodyLength: Int) {
        let escapedId = escapeForAppleScript(messageId)

        let script = """
        tell application "Mail"
            -- Find message: unified inbox covers normal accounts; per-account
            -- fallback only for accounts where inbox keyword fails (Proton Bridge).
            set targetMsg to missing value
            try
                set targetMsg to first message of inbox whose message id is "\(escapedId)"
            end try
            if targetMsg is missing value then
                repeat with acct in every account
                    repeat with mbox in every mailbox of acct
                        try
                            set targetMsg to first message of mbox whose message id is "\(escapedId)"
                            exit repeat
                        end try
                    end repeat
                    if targetMsg is not missing value then exit repeat
                end repeat
            end if
            if targetMsg is missing value then
                return "ERROR_NOT_FOUND"
            end if
            set msgSubject to subject of targetMsg
            set msgSender to sender of targetMsg
            set msgDate to date received of targetMsg as «class isot» as string
            set msgRead to read status of targetMsg
            set msgFlagged to flagged status of targetMsg
            set msgContent to content of targetMsg
            set msgTo to address of every to recipient of targetMsg
            set msgCc to address of every cc recipient of targetMsg
            set attachList to {}
            repeat with att in every mail attachment of targetMsg
                set attName to name of att
                try
                    set attMime to MIME type of att
                on error
                    set attMime to "application/octet-stream"
                end try
                set end of attachList to attName & ":::" & attMime
            end repeat
            return msgSubject & "|||" & msgSender & "|||" & msgDate & "|||" & (msgRead as string) & "|||" & (msgFlagged as string) & "|||" & msgContent & "|||" & (msgTo as string) & "|||" & (msgCc as string) & "|||" & (my joinList(attachList, "^^^"))
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
        if raw == "ERROR_NOT_FOUND" {
            JSONOutput.error("Message not found. It may be in a mailbox not searched (try mail.search to locate it first).")
            return
        }
        let parts = raw.components(separatedBy: "|||")
        guard parts.count >= 6 else {
            JSONOutput.error("Unexpected response format from Mail.app")
            return
        }

        var body = parts[5]
        if maxBodyLength > 0 && body.count > maxBodyLength {
            body = String(body.prefix(maxBodyLength)) + "\n\n[truncated — \(body.count) chars total]"
        }

        var message: [String: Any] = [
            "id": messageId,
            "subject": parts[0],
            "sender": parts[1],
            "date": parts[2],
            "read": parts[3] == "true",
            "flagged": parts[4] == "true",
            "body": body
        ]
        if parts.count > 6 { message["to"] = parts[6] }
        if parts.count > 7 { message["cc"] = parts[7] }

        if parts.count > 8 && !parts[8].isEmpty {
            let attachStrings = parts[8].components(separatedBy: "^^^")
            let attachments: [[String: Any]] = attachStrings.enumerated().compactMap { (idx, attStr) in
                let fields = attStr.components(separatedBy: ":::")
                guard fields.count >= 2 else { return nil }
                return [
                    "index": idx,
                    "name": fields[0],
                    "mimeType": fields[1]
                ]
            }
            message["attachments"] = attachments
            message["attachmentCount"] = attachments.count
            message["hasAttachments"] = !attachments.isEmpty
        } else {
            message["attachments"] = [] as [[String: Any]]
            message["attachmentCount"] = 0
            message["hasAttachments"] = false
        }

        JSONOutput.success(message)
    }

    /// List flagged messages across all accounts.
    static func flagged(limit: Int, offset: Int?) {
        let effectiveOffset = offset ?? 0

        // Two script variants: without pagination (early-exit for performance)
        // and with pagination (must count all flagged messages for total).
        let script: String
        if offset != nil {
            // Pagination: iterate everything to compute totalCount
            script = """
            tell application "Mail"
                set resultList to {}
                set totalCount to 0
                set skipped to 0
                set collected to 0
                repeat with acct in every account
                    try
                        repeat with mbox in every mailbox of acct
                            set flaggedMsgs to (every message of mbox whose flagged status is true)
                            set totalCount to totalCount + (count of flaggedMsgs)
                            repeat with msg in flaggedMsgs
                                if skipped < \(effectiveOffset) then
                                    set skipped to skipped + 1
                                else if collected < \(limit) then
                                    set msgId to message id of msg
                                    set msgSubject to subject of msg
                                    set msgSender to sender of msg
                                    set msgDate to date received of msg as «class isot» as string
                                    set end of resultList to msgId & "|||" & msgSubject & "|||" & msgSender & "|||" & msgDate & "|||" & (name of acct) & "|||" & ((count of mail attachments of msg) as string)
                                    set collected to collected + 1
                                end if
                            end repeat
                        end repeat
                    end try
                end repeat
                return my joinList(resultList, "^^^") & "###TOTAL:::" & (totalCount as string)
            end tell

            on joinList(theList, delim)
                set oldDelim to AppleScript's text item delimiters
                set AppleScript's text item delimiters to delim
                set theResult to theList as string
                set AppleScript's text item delimiters to oldDelim
                return theResult
            end joinList
            """
        } else {
            // No pagination: early-exit once limit is reached
            script = """
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
        }

        guard let raw = runAppleScript(script) else { return }
        let totalParts = raw.components(separatedBy: "###TOTAL:::")
        let messagesRaw = totalParts[0]
        let total = totalParts.count > 1 ? Int(totalParts[1].trimmingCharacters(in: .whitespaces)) ?? 0 : 0
        let messages = parseFlaggedList(messagesRaw)

        if let offset = offset {
            let envelope: [String: Any] = [
                "messages": messages,
                "total": total,
                "offset": offset,
                "limit": limit,
                "hasMore": offset + limit < total
            ]
            JSONOutput.success(envelope)
        } else {
            JSONOutput.success(messages)
        }
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

    /// Save a specific attachment from a message to disk.
    static func saveAttachment(messageId: String, index: Int, outputDir: String) {
        guard index >= 0 else {
            JSONOutput.error("Attachment index must be non-negative. Got \(index).")
            return
        }
        let escapedId = escapeForAppleScript(messageId)
        guard let resolvedDir = FilesBridge.validatePath(outputDir, mustExist: false) else {
            JSONOutput.error("Output path is outside home directory: \(outputDir)")
            return
        }

        // Create output directory if needed
        let fm = FileManager.default
        if !fm.fileExists(atPath: resolvedDir) {
            do {
                try fm.createDirectory(atPath: resolvedDir, withIntermediateDirectories: true)
            } catch {
                JSONOutput.error("Failed to create output directory: \(error.localizedDescription)")
                return
            }
        }

        let escapedDir = escapeForAppleScript(resolvedDir)
        // AppleScript index is 1-based
        let asIndex = index + 1

        let script = """
        tell application "Mail"
            -- Find message: unified inbox covers normal accounts; per-account
            -- fallback only for accounts where inbox keyword fails (Proton Bridge).
            set targetMsg to missing value
            try
                set targetMsg to first message of inbox whose message id is "\(escapedId)"
            end try
            if targetMsg is missing value then
                repeat with acct in every account
                    repeat with mbox in every mailbox of acct
                        try
                            set targetMsg to first message of mbox whose message id is "\(escapedId)"
                            exit repeat
                        end try
                    end repeat
                    if targetMsg is not missing value then exit repeat
                end repeat
            end if
            if targetMsg is missing value then
                return "ERROR:::Message not found"
            end if
            set attList to every mail attachment of targetMsg
            if (count of attList) < \(asIndex) then
                return "ERROR:::Attachment index out of range. Message has " & ((count of attList) as string) & " attachments."
            end if
            set att to item \(asIndex) of attList
            set attName to name of att
            try
                set attMime to MIME type of att
            on error
                set attMime to "application/octet-stream"
            end try
            set fullPath to "\(escapedDir)/" & attName
            save att in (POSIX file fullPath)
            return attName & ":::" & attMime & ":::" & fullPath
        end tell
        """

        guard let raw = runAppleScript(script) else { return }

        if raw.hasPrefix("ERROR:::") {
            let errorMsg = String(raw.dropFirst("ERROR:::".count))
            JSONOutput.error(errorMsg)
            return
        }

        let fields = raw.components(separatedBy: ":::")
        guard fields.count >= 3 else {
            JSONOutput.error("Unexpected response format from Mail.app")
            return
        }

        let result: [String: Any] = [
            "name": fields[0],
            "mimeType": fields[1],
            "path": fields[2]
        ]
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
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\" & (ASCII character 13) & (ASCII character 10) & \"")
            .replacingOccurrences(of: "\n", with: "\" & (ASCII character 10) & \"")
            .replacingOccurrences(of: "\r", with: "\" & (ASCII character 13) & \"")
            .replacingOccurrences(of: "\t", with: "\" & (ASCII character 9) & \"")
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
            if fields.count > 7 {
                msg["mailbox"] = fields[7].trimmingCharacters(in: .whitespaces)
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
