import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { resolve } from "node:path";

export const ALL_MODULES = [
  "calendar",
  "mail",
  "reminders",
  "files",
  "system",
  "numbers",
  "pages",
  "keynote",
  "notes",
  "contacts",
] as const;

export type ModuleName = (typeof ALL_MODULES)[number];

export interface OrchardConfig {
  enabledModules: readonly ModuleName[];
  calendarMaxAgeDays?: number;
  remindersMaxAgeDays?: number;
}

interface ConfigFile {
  modules?: unknown;
  calendarMaxAgeDays?: unknown;
  remindersMaxAgeDays?: unknown;
}

const DEFAULT_CONFIG_PATH = resolve(homedir(), ".config", "orchard-mcp", "config.json");

function isModuleName(value: string): value is ModuleName {
  return (ALL_MODULES as readonly string[]).includes(value);
}

function parseModules(value: unknown, source: string): ModuleName[] {
  if (value === undefined) {
    return [...ALL_MODULES];
  }
  if (!Array.isArray(value)) {
    throw new Error(`${source}: "modules" must be an array of module names.`);
  }
  if (value.length === 0) {
    throw new Error(
      `${source}: "modules" must include at least one module. Valid modules: ${ALL_MODULES.join(", ")}`
    );
  }
  const modules: ModuleName[] = [];
  for (const item of value) {
    if (typeof item !== "string" || !isModuleName(item)) {
      throw new Error(
        `${source}: unknown module "${String(item)}". Valid modules: ${ALL_MODULES.join(", ")}`
      );
    }
    if (!modules.includes(item)) {
      modules.push(item);
    }
  }
  return modules;
}

function parseModulesFromEnv(value: string | undefined, source: string): ModuleName[] | undefined {
  if (value === undefined) {
    return undefined;
  }
  const trimmed = value.trim();
  if (trimmed === "") {
    throw new Error(
      `${source}: must include at least one module. Valid modules: ${ALL_MODULES.join(", ")}`
    );
  }
  const parts = trimmed.split(",").map((part) => part.trim()).filter(Boolean);
  return parseModules(parts, source);
}

function parseMaxAgeDays(
  value: unknown,
  key: string,
  source: string
): number | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value === "string" && value.trim() === "") {
    return undefined;
  }
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isInteger(parsed) || parsed < 0) {
    throw new Error(`${source}: "${key}" must be a non-negative integer.`);
  }
  return parsed;
}

function readConfigFile(path: string): ConfigFile {
  try {
    return JSON.parse(readFileSync(path, "utf8")) as ConfigFile;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`Failed to read config file ${path}: ${message}`);
  }
}

function loadConfigFile(): ConfigFile {
  const configPath = process.env.ORCHARD_MCP_CONFIG?.trim() || DEFAULT_CONFIG_PATH;
  if (!existsSync(configPath)) {
    return {};
  }
  return readConfigFile(configPath);
}

export function loadConfig(): OrchardConfig {
  const fileConfig = loadConfigFile();
  const configPath = process.env.ORCHARD_MCP_CONFIG?.trim() || DEFAULT_CONFIG_PATH;
  const fileSource = existsSync(configPath) ? configPath : "config file";

  const envModules = parseModulesFromEnv(
    process.env.ORCHARD_MCP_MODULES,
    "ORCHARD_MCP_MODULES"
  );
  const enabledModules =
    envModules ?? parseModules(fileConfig.modules, fileSource);

  const calendarMaxAgeDays =
    parseMaxAgeDays(
      process.env.ORCHARD_MCP_CALENDAR_MAX_AGE_DAYS ?? fileConfig.calendarMaxAgeDays,
      "calendarMaxAgeDays",
      process.env.ORCHARD_MCP_CALENDAR_MAX_AGE_DAYS !== undefined
        ? "ORCHARD_MCP_CALENDAR_MAX_AGE_DAYS"
        : fileSource
    );
  const remindersMaxAgeDays =
    parseMaxAgeDays(
      process.env.ORCHARD_MCP_REMINDERS_MAX_AGE_DAYS ?? fileConfig.remindersMaxAgeDays,
      "remindersMaxAgeDays",
      process.env.ORCHARD_MCP_REMINDERS_MAX_AGE_DAYS !== undefined
        ? "ORCHARD_MCP_REMINDERS_MAX_AGE_DAYS"
        : fileSource
    );

  return {
    enabledModules,
    calendarMaxAgeDays,
    remindersMaxAgeDays,
  };
}

export function logConfig(config: OrchardConfig): void {
  console.error(
    `[orchard-mcp] Enabled modules: ${config.enabledModules.join(", ")}`
  );
  const limits: string[] = [];
  if (config.calendarMaxAgeDays !== undefined) {
    limits.push(`calendarMaxAgeDays=${config.calendarMaxAgeDays}`);
  }
  if (config.remindersMaxAgeDays !== undefined) {
    limits.push(`remindersMaxAgeDays=${config.remindersMaxAgeDays}`);
  }
  if (limits.length > 0) {
    console.error(`[orchard-mcp] ${limits.join(", ")}`);
  }
}

export function failConfig(error: unknown): never {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`[orchard-mcp] Configuration error: ${message}`);
  process.exit(1);
}
