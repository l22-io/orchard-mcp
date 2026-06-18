import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { loadConfig, ALL_MODULES } from "../src/config.js";

const ENV_KEYS = [
  "ORCHARD_MCP_CONFIG",
  "ORCHARD_MCP_MODULES",
  "ORCHARD_MCP_CALENDAR_MAX_AGE_DAYS",
  "ORCHARD_MCP_REMINDERS_MAX_AGE_DAYS",
] as const;

describe("config loading", () => {
  let savedEnv: Record<string, string | undefined>;
  let tempDir: string;

  beforeEach(() => {
    savedEnv = Object.fromEntries(ENV_KEYS.map((key) => [key, process.env[key]]));
    for (const key of ENV_KEYS) {
      delete process.env[key];
    }
    tempDir = mkdtempSync(join(tmpdir(), "orchard-mcp-config-"));
    process.env.ORCHARD_MCP_CONFIG = join(tempDir, "config.json");
  });

  afterEach(() => {
    for (const key of ENV_KEYS) {
      if (savedEnv[key] === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = savedEnv[key];
      }
    }
    rmSync(tempDir, { recursive: true, force: true });
  });

  it("defaults to all modules with no age limits when config file is missing", () => {
    const config = loadConfig();
    assert.deepEqual(config.enabledModules, ALL_MODULES);
    assert.equal(config.calendarMaxAgeDays, undefined);
    assert.equal(config.remindersMaxAgeDays, undefined);
  });

  it("loads modules and age limits from config file", () => {
    writeFileSync(
      process.env.ORCHARD_MCP_CONFIG!,
      JSON.stringify({
        modules: ["calendar", "mail", "system"],
        calendarMaxAgeDays: 365,
        remindersMaxAgeDays: 90,
      })
    );

    const config = loadConfig();
    assert.deepEqual(config.enabledModules, ["calendar", "mail", "system"]);
    assert.equal(config.calendarMaxAgeDays, 365);
    assert.equal(config.remindersMaxAgeDays, 90);
  });

  it("defaults modules to all when config file omits modules key", () => {
    writeFileSync(
      process.env.ORCHARD_MCP_CONFIG!,
      JSON.stringify({ calendarMaxAgeDays: 30 })
    );

    const config = loadConfig();
    assert.deepEqual(config.enabledModules, ALL_MODULES);
    assert.equal(config.calendarMaxAgeDays, 30);
  });

  it("lets environment variables override config file values", () => {
    writeFileSync(
      process.env.ORCHARD_MCP_CONFIG!,
      JSON.stringify({
        modules: ["calendar"],
        calendarMaxAgeDays: 10,
        remindersMaxAgeDays: 20,
      })
    );
    process.env.ORCHARD_MCP_MODULES = "mail, files";
    process.env.ORCHARD_MCP_CALENDAR_MAX_AGE_DAYS = "100";
    process.env.ORCHARD_MCP_REMINDERS_MAX_AGE_DAYS = "200";

    const config = loadConfig();
    assert.deepEqual(config.enabledModules, ["mail", "files"]);
    assert.equal(config.calendarMaxAgeDays, 100);
    assert.equal(config.remindersMaxAgeDays, 200);
  });

  it("rejects unknown module names", () => {
    writeFileSync(
      process.env.ORCHARD_MCP_CONFIG!,
      JSON.stringify({ modules: ["calendar", "not-a-module"] })
    );

    assert.throws(() => loadConfig(), /unknown module "not-a-module"/);
  });

  it("rejects empty modules array in config file", () => {
    writeFileSync(
      process.env.ORCHARD_MCP_CONFIG!,
      JSON.stringify({ modules: [] })
    );

    assert.throws(() => loadConfig(), /must include at least one module/);
  });

  it("rejects empty ORCHARD_MCP_MODULES env var", () => {
    process.env.ORCHARD_MCP_MODULES = "";

    assert.throws(() => loadConfig(), /ORCHARD_MCP_MODULES.*must include at least one module/);
  });

  it("rejects invalid age values", () => {
    writeFileSync(
      process.env.ORCHARD_MCP_CONFIG!,
      JSON.stringify({ calendarMaxAgeDays: -1 })
    );

    assert.throws(() => loadConfig(), /calendarMaxAgeDays.*non-negative integer/);
  });

  it("rejects malformed config JSON", () => {
    writeFileSync(process.env.ORCHARD_MCP_CONFIG!, "{not json");

    assert.throws(() => loadConfig(), /Failed to read config file/);
  });
});
