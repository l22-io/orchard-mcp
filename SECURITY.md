# Security Policy

## Supported Versions

Only the latest release on the `main` branch is supported with security updates.

| Branch | Supported |
| ------ | --------- |
| main   | Yes       |

## Reporting a Vulnerability

Please use [GitHub's private vulnerability reporting](https://github.com/l22-io/orchard-mcp/security/advisories/new) to report security issues. Navigate to the **Security** tab of the repository and select **Report a vulnerability**.

Do not open a public issue for security vulnerabilities.

## What Qualifies

The following are examples of issues we consider in scope:

- **Command injection through the Swift bridge** -- unsanitized input passed to `apple-bridge` subcommands or shell execution (e.g., `osascript` calls in Mail tools).
- **Unauthorized access to macOS services** -- bypassing or escalating beyond the permissions granted to the MCP server (EventKit, file system, Mail).
- **Path traversal in file operations** -- accessing files outside of intended directories through crafted tool inputs.
- **MCP transport or JSON-RPC protocol issues** -- vulnerabilities in the stdio transport layer, malformed message handling, or protocol-level exploits.
- **Information disclosure** -- leaking sensitive data from macOS services through error messages, logs, or unintended tool output.

## Response Timeline

- **Acknowledgment**: within 72 hours of report submission.
- **Initial assessment**: within 7 days.
- **Resolution target**: critical issues within 30 days; lower-severity issues on a best-effort basis.

We will coordinate disclosure with the reporter and credit them in release notes unless they prefer to remain anonymous.

## Out of Scope

The following are not considered vulnerabilities in orchard-mcp:

- **macOS permission prompts and entitlements** -- access control for Calendar, Reminders, Mail, and file system is managed by macOS. Issues with Apple's permission model should be reported to Apple.
- **Social engineering** -- tricking a user into granting permissions or running malicious commands.
- **Denial of service against the local machine** -- the server runs locally and is not exposed to the network by default.
- **Vulnerabilities in upstream dependencies** -- report these to the relevant maintainers. If a dependency issue directly impacts orchard-mcp, include details on how.
