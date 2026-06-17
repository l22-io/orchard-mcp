import { bridgeData, type BridgeOptions } from "./bridge.js";

export interface OperationProfile {
  name: string;
  lane: string;
  timeoutMs: number;
  queueTimeoutMs: number;
  maxOutputBytes?: number;
}

interface Waiter {
  profile: OperationProfile;
  timer: NodeJS.Timeout;
  resolve: () => void;
  reject: (err: Error) => void;
}

interface LaneState {
  running: boolean;
  queue: Waiter[];
}

const DEFAULT_OUTPUT_BYTES = 2 * 1024 * 1024;
const LARGE_OUTPUT_BYTES = 8 * 1024 * 1024;

const laneStates = new Map<string, LaneState>();

export const OPERATION_PROFILES = {
  calendarRead: {
    name: "calendar.read",
    lane: "calendar",
    timeoutMs: 15_000,
    queueTimeoutMs: 1_000,
    maxOutputBytes: DEFAULT_OUTPUT_BYTES,
  },
  contactsRead: {
    name: "contacts.read",
    lane: "contacts",
    timeoutMs: 15_000,
    queueTimeoutMs: 1_000,
    maxOutputBytes: DEFAULT_OUTPUT_BYTES,
  },
  fileRead: {
    name: "files.read",
    lane: "files",
    timeoutMs: 20_000,
    queueTimeoutMs: 500,
    maxOutputBytes: LARGE_OUTPUT_BYTES,
  },
  fileWrite: {
    name: "files.write",
    lane: "files",
    timeoutMs: 30_000,
    queueTimeoutMs: 500,
    maxOutputBytes: DEFAULT_OUTPUT_BYTES,
  },
  keynote: {
    name: "keynote.apple-events",
    lane: "keynote",
    timeoutMs: 30_000,
    queueTimeoutMs: 1_000,
    maxOutputBytes: LARGE_OUTPUT_BYTES,
  },
  mailMetadata: {
    name: "mail.metadata",
    lane: "mail",
    timeoutMs: 15_000,
    queueTimeoutMs: 500,
    maxOutputBytes: DEFAULT_OUTPUT_BYTES,
  },
  mailScan: {
    name: "mail.scan",
    lane: "mail",
    timeoutMs: 30_000,
    queueTimeoutMs: 500,
    maxOutputBytes: DEFAULT_OUTPUT_BYTES,
  },
  mailWrite: {
    name: "mail.write",
    lane: "mail",
    timeoutMs: 20_000,
    queueTimeoutMs: 500,
    maxOutputBytes: DEFAULT_OUTPUT_BYTES,
  },
  notes: {
    name: "notes.apple-events",
    lane: "notes",
    timeoutMs: 20_000,
    queueTimeoutMs: 1_000,
    maxOutputBytes: DEFAULT_OUTPUT_BYTES,
  },
  numbers: {
    name: "numbers.apple-events",
    lane: "numbers",
    timeoutMs: 30_000,
    queueTimeoutMs: 1_000,
    maxOutputBytes: LARGE_OUTPUT_BYTES,
  },
  pages: {
    name: "pages.apple-events",
    lane: "pages",
    timeoutMs: 30_000,
    queueTimeoutMs: 1_000,
    maxOutputBytes: LARGE_OUTPUT_BYTES,
  },
  remindersRead: {
    name: "reminders.read",
    lane: "reminders",
    timeoutMs: 15_000,
    queueTimeoutMs: 1_000,
    maxOutputBytes: DEFAULT_OUTPUT_BYTES,
  },
  remindersWrite: {
    name: "reminders.write",
    lane: "reminders",
    timeoutMs: 20_000,
    queueTimeoutMs: 1_000,
    maxOutputBytes: DEFAULT_OUTPUT_BYTES,
  },
  systemDoctor: {
    name: "system.doctor",
    lane: "doctor",
    timeoutMs: 20_000,
    queueTimeoutMs: 500,
    maxOutputBytes: DEFAULT_OUTPUT_BYTES,
  },
} satisfies Record<string, OperationProfile>;

export async function safeBridgeData(
  args: string[],
  profile: OperationProfile
): Promise<unknown> {
  const options: BridgeOptions = {
    timeoutMs: profile.timeoutMs,
    maxOutputBytes: profile.maxOutputBytes,
  };
  return runWithOperationProfile(profile, () => bridgeData(args, options));
}

export async function runWithOperationProfile<T>(
  profile: OperationProfile,
  operation: () => Promise<T>
): Promise<T> {
  const release = await acquireLane(profile);
  let timeout: NodeJS.Timeout | undefined;

  const operationPromise = Promise.resolve()
    .then(operation)
    .finally(() => {
      if (timeout) clearTimeout(timeout);
      release();
    });

  operationPromise.catch(() => {
    // The caller observes this rejection through the race below unless the
    // timeout has already fired. Either way, avoid an unhandled rejection when
    // the underlying work finishes after a timeout response was returned.
  });

  const timeoutPromise = new Promise<never>((_, reject) => {
    timeout = setTimeout(() => {
      reject(
        new Error(
          `${profile.name} exceeded ${profile.timeoutMs}ms safety budget`
        )
      );
    }, profile.timeoutMs);
    timeout.unref();
  });

  return Promise.race([operationPromise, timeoutPromise]);
}

function acquireLane(profile: OperationProfile): Promise<() => void> {
  const state = laneStates.get(profile.lane) ?? { running: false, queue: [] };
  laneStates.set(profile.lane, state);

  if (!state.running) {
    state.running = true;
    return Promise.resolve(() => releaseLane(profile.lane));
  }

  return new Promise((resolve, reject) => {
    const waiter: Waiter = {
      profile,
      timer: setTimeout(() => {
        const idx = state.queue.indexOf(waiter);
        if (idx >= 0) state.queue.splice(idx, 1);
        reject(
          new Error(
            `${profile.lane} is busy with another orchard-mcp operation; retry after the current call finishes.`
          )
        );
      }, profile.queueTimeoutMs),
      resolve: () => {
        clearTimeout(waiter.timer);
        resolve(() => releaseLane(profile.lane));
      },
      reject,
    };
    waiter.timer.unref();
    state.queue.push(waiter);
  });
}

function releaseLane(lane: string): void {
  const state = laneStates.get(lane);
  if (!state) return;

  const next = state.queue.shift();
  if (next) {
    next.resolve();
    return;
  }

  state.running = false;
}
