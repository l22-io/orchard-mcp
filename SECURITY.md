# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.3.x   | Yes       |
| < 0.3   | No        |

## Reporting a Vulnerability

If you discover a security vulnerability in apple-mcp, please report it responsibly:

1. **Do not** open a public GitHub issue.
2. Email **security@l22.io** with a description of the vulnerability.
3. Include steps to reproduce if possible.

We will acknowledge your report within 48 hours and aim to release a fix within 7 days for critical issues.

## Scope

apple-mcp runs locally and accesses macOS data stores (Calendar, Mail, Reminders, filesystem) through native frameworks. It does not communicate with remote services. Security concerns typically involve:

- Unintended data exposure through MCP tool responses
- Path traversal in file operations (all paths are validated against home directory)
- Command injection in bridge calls (all arguments are passed as arrays, never shell-interpolated)
