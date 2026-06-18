export interface CalendarEventLike {
  end: string;
}

export interface ReminderLike {
  isCompleted: boolean;
  completionDate?: string;
}

export function cutoffDate(maxAgeDays: number, now: Date = new Date()): Date {
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  return new Date(startOfToday.getTime() - maxAgeDays * 86_400_000);
}

function parseIsoDate(value: string): Date | undefined {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return undefined;
  }
  return parsed;
}

export function isCalendarRangeFullyBeforeCutoff(
  startISO: string,
  endISO: string,
  maxAgeDays: number | undefined,
  now: Date = new Date()
): boolean {
  if (maxAgeDays === undefined) {
    return false;
  }
  const end = parseIsoDate(endISO);
  if (!end) {
    return false;
  }
  const cutoff = cutoffDate(maxAgeDays, now);
  return end.getTime() < cutoff.getTime();
}

export function filterCalendarEvents<T extends CalendarEventLike>(
  events: T[],
  maxAgeDays: number | undefined,
  now: Date = new Date()
): T[] {
  if (maxAgeDays === undefined) {
    return events;
  }
  const cutoff = cutoffDate(maxAgeDays, now);
  return events.filter((event) => {
    const end = parseIsoDate(event.end);
    if (!end) {
      return true;
    }
    return end.getTime() >= cutoff.getTime();
  });
}

export function filterReminders<T extends ReminderLike>(
  reminders: T[],
  maxAgeDays: number | undefined,
  now: Date = new Date()
): T[] {
  if (maxAgeDays === undefined) {
    return reminders;
  }
  const cutoff = cutoffDate(maxAgeDays, now);
  return reminders.filter((reminder) => {
    if (!reminder.isCompleted) {
      return true;
    }
    if (!reminder.completionDate) {
      return true;
    }
    const completionDate = parseIsoDate(reminder.completionDate);
    if (!completionDate) {
      return true;
    }
    return completionDate.getTime() >= cutoff.getTime();
  });
}
