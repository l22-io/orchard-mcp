export interface MailLocator {
  account?: string;
  mailbox?: string;
}

export function appendMailLocatorArgs(args: string[], locator: MailLocator): void {
  if (locator.account) {
    args.push("--account", locator.account);
  }
  if (locator.mailbox) {
    args.push("--mailbox", locator.mailbox);
  }
}

export function requireMailLocator(toolName: string, locator: MailLocator): void {
  if (!locator.account || !locator.mailbox) {
    throw new Error(
      `${toolName} requires account and mailbox from a recent mail.search, mail.unread_summary, or mail.flagged result. ` +
      "Refusing a bare message-id lookup because scanning every mailbox can make Mail.app unresponsive."
    );
  }
}
