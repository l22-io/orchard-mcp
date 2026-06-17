export function assertIsoDateRangeWithinDays(
  startISO: string,
  endISO: string,
  maxDays: number,
  toolName: string
): void {
  const start = new Date(startISO);
  const end = new Date(endISO);
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
    return;
  }
  const days = (end.getTime() - start.getTime()) / 86_400_000;
  if (days < 0) {
    throw new Error(`${toolName} requires end to be after start.`);
  }
  if (days > maxDays) {
    throw new Error(
      `${toolName} refuses date ranges over ${maxDays} days because broad native queries can slow the host system. Narrow the date range and paginate by time.`
    );
  }
}

export function normalizeNotesSearchIn(
  searchIn: "title" | "body" | "all" | undefined
): "title" {
  if (searchIn === undefined || searchIn === "title") {
    return "title";
  }
  throw new Error(
    "Notes body search is disabled for orchard-mcp because it scans every note's plaintext through Apple Events. Use notes.list_notes plus notes.read_note on specific notes."
  );
}

export function requireNumbersRange(toolName: string, range: string | undefined): void {
  if (!range) {
    throw new Error(
      `${toolName} requires a cell range (for example A1:C50). Refusing to read an entire Numbers table through Apple Events.`
    );
  }
}

export function requireKeynoteSlideForImageExport(
  format: string,
  slide: number | undefined
): void {
  if ((format === "png" || format === "jpeg") && slide === undefined) {
    throw new Error(
      "keynote.export requires a slide index for PNG/JPEG exports. Refusing all-slide image export because it can monopolize Keynote."
    );
  }
}

export function assertBatchSize(
  toolName: string,
  count: number,
  maxCount: number
): void {
  if (count > maxCount) {
    throw new Error(
      `${toolName} accepts at most ${maxCount} items per call. Split the operation into smaller batches.`
    );
  }
}
