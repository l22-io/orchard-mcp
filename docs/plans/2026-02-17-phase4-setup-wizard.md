# Phase 4a: Setup Wizard Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an `apple-mcp setup` command that checks prerequisites, builds the Swift binary and .app bundle, triggers TCC permissions, and prints MCP client config snippets.

**Architecture:** Single new file `src/setup.ts` with a `runSetup()` function called from `index.ts` when `argv[2] === "setup"`. Uses `child_process.execFile` for shell commands and Node `readline` for interactive prompts. No new dependencies.

**Tech Stack:** TypeScript, Node.js readline, child_process

---

### Task 1: Scaffold `src/setup.ts` with entry point and helpers

**Files:**
- Create: `src/setup.ts`
- Modify: `src/index.ts`

**Step 1: Create `src/setup.ts` with the runner skeleton and output helpers**

```typescript
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createInterface } from "node:readline";
import { mkdirSync, copyFileSync, writeFileSync, existsSync, readFileSync, unlinkSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { tmpdir } from "node:os";

const execFileAsync = promisify(execFile);
const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(__dirname, "..");
const swiftDir = resolve(projectRoot, "swift");
const bridgeBin = resolve(swiftDir, ".build", "release", "apple-bridge");
const appBundle = resolve(swiftDir, ".build", "AppleBridge.app");
const infoPlist = resolve(swiftDir, "Sources", "AppleBridge", "Info.plist");

function log(msg: string): void {
  process.stdout.write(`      ${msg}\n`);
}

function step(n: number, total: number, title: string): void {
  process.stdout.write(`\n[${n}/${total}] ${title}\n`);
}

async function ask(question: string): Promise<string> {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((res) => {
    rl.question(`      ${question} `, (answer) => {
      rl.close();
      res(answer.trim());
    });
  });
}

async function run(cmd: string, args: string[], opts?: { cwd?: string; timeout?: number }): Promise<{ stdout: string; stderr: string }> {
  return execFileAsync(cmd, args, {
    timeout: opts?.timeout ?? 120_000,
    maxBuffer: 10 * 1024 * 1024,
    cwd: opts?.cwd,
  });
}

export async function runSetup(nonInteractive: boolean): Promise<void> {
  const total = 6;
  process.stdout.write("\napple-mcp setup\n================\n");

  const ok1 = await checkPrereqs(total);
  if (!ok1) process.exit(1);

  const ok2 = await buildSwift(total);
  if (!ok2) process.exit(1);

  await buildAppBundle(total);
  await requestPermissions(total, nonInteractive);
  await printClientConfig(total);
  await validate(total);
}
```

**Step 2: Add the `setup` route in `src/index.ts`**

At the top of `index.ts`, after the shebang and before the McpServer import, add:

```typescript
// Handle `apple-mcp setup` subcommand before starting MCP server.
if (process.argv[2] === "setup") {
  const { runSetup } = await import("./setup.js");
  await runSetup(process.argv.includes("--non-interactive"));
  process.exit(0);
}
```

**Step 3: Compile to verify**

Run: `npx tsc 2>&1`
Expected: Errors for missing functions (checkPrereqs, buildSwift, etc.) -- that's fine, we'll add them next. If there are OTHER errors, fix them.

Actually, to avoid compile errors, add stub functions at the bottom of setup.ts:

```typescript
async function checkPrereqs(_total: number): Promise<boolean> { return true; }
async function buildSwift(_total: number): Promise<boolean> { return true; }
async function buildAppBundle(_total: number): Promise<void> {}
async function requestPermissions(_total: number, _nonInteractive: boolean): Promise<void> {}
async function printClientConfig(_total: number): Promise<void> {}
async function validate(_total: number): Promise<void> {}
```

**Step 4: Compile and verify**

Run: `npx tsc 2>&1`
Expected: No errors

**Step 5: Commit**

```bash
git add src/setup.ts src/index.ts
git commit -m "feat(setup): scaffold setup wizard entry point"
```

---

### Task 2: Implement prerequisite checks

**Files:**
- Modify: `src/setup.ts`

**Step 1: Replace the `checkPrereqs` stub**

```typescript
async function checkPrereqs(total: number): Promise<boolean> {
  step(1, total, "Checking prerequisites...");
  let ok = true;

  // macOS version: Darwin 24.x = macOS 15 (Sequoia), 23.x = macOS 14 (Sonoma)
  // We need macOS 14+ (Darwin kernel 23+)
  try {
    const { stdout } = await run("sw_vers", ["-productVersion"]);
    const ver = stdout.trim();
    const major = parseInt(ver.split(".")[0], 10);
    if (major >= 14) {
      log(`macOS ${ver} -- ok`);
    } else {
      log(`macOS ${ver} -- requires 14+ (Sonoma or later)`);
      ok = false;
    }
  } catch {
    log("Could not detect macOS version");
    ok = false;
  }

  // Swift
  try {
    const { stdout } = await run("swift", ["--version"]);
    const match = stdout.match(/Swift version ([\d.]+)/);
    const ver = match ? match[1] : "unknown";
    log(`Swift ${ver} -- ok`);
  } catch {
    log("Swift not found -- install Xcode Command Line Tools: xcode-select --install");
    ok = false;
  }

  // Node.js (already running, just report)
  const nodeVer = process.version;
  const nodeMajor = parseInt(nodeVer.slice(1).split(".")[0], 10);
  if (nodeMajor >= 18) {
    log(`Node.js ${nodeVer} -- ok`);
  } else {
    log(`Node.js ${nodeVer} -- requires 18+`);
    ok = false;
  }

  return ok;
}
```

**Step 2: Compile and test**

Run: `npx tsc 2>&1`
Expected: No errors

Run: `node build/index.js setup 2>/dev/null`
Expected: Shows prerequisites check with macOS, Swift, Node versions all "ok", then stubs for remaining steps

**Step 3: Commit**

```bash
git add src/setup.ts
git commit -m "feat(setup): implement prerequisite checks"
```

---

### Task 3: Implement Swift build step

**Files:**
- Modify: `src/setup.ts`

**Step 1: Replace the `buildSwift` stub**

```typescript
async function buildSwift(total: number): Promise<boolean> {
  step(2, total, "Building Swift binary...");
  try {
    await run("swift", [
      "build", "-c", "release",
      "-Xlinker", "-sectcreate",
      "-Xlinker", "__TEXT",
      "-Xlinker", "__info_plist",
      "-Xlinker", `Sources/AppleBridge/Info.plist`,
    ], { cwd: swiftDir, timeout: 300_000 });
    log("swift build -c release -- ok");
    return true;
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    log(`Swift build failed: ${msg}`);
    return false;
  }
}
```

**Step 2: Compile and test**

Run: `npx tsc 2>&1`
Expected: No errors

**Step 3: Commit**

```bash
git add src/setup.ts
git commit -m "feat(setup): implement Swift build step"
```

---

### Task 4: Implement .app bundle build step

**Files:**
- Modify: `src/setup.ts`

**Step 1: Replace the `buildAppBundle` stub**

```typescript
async function buildAppBundle(total: number): Promise<void> {
  step(3, total, "Building AppleBridge.app bundle...");

  const macosDir = resolve(appBundle, "Contents", "MacOS");
  const contentsDir = resolve(appBundle, "Contents");

  mkdirSync(macosDir, { recursive: true });
  copyFileSync(bridgeBin, resolve(macosDir, "apple-bridge"));
  copyFileSync(infoPlist, resolve(contentsDir, "Info.plist"));

  try {
    await run("codesign", ["--force", "--sign", "-", appBundle]);
    log("Created and signed -- ok");
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    log(`codesign failed: ${msg}`);
  }
}
```

**Step 2: Compile and test**

Run: `npx tsc 2>&1`
Expected: No errors

**Step 3: Commit**

```bash
git add src/setup.ts
git commit -m "feat(setup): implement .app bundle build step"
```

---

### Task 5: Implement TCC permission requests

**Files:**
- Modify: `src/setup.ts`

**Step 1: Replace the `requestPermissions` stub**

```typescript
async function requestPermissions(total: number, nonInteractive: boolean): Promise<void> {
  step(4, total, "Requesting permissions...");

  // Calendar
  try {
    const { stdout } = await run(bridgeBin, ["doctor"]);
    const doctor = JSON.parse(stdout);
    const calStatus = doctor.data?.calendar?.granted;
    if (calStatus) {
      log("Calendar: fullAccess -- ok");
    } else {
      if (nonInteractive) {
        log("Calendar: not granted (run interactively to trigger prompt)");
      } else {
        log("Calendar: requesting access...");
        await run(bridgeBin, ["calendars"]);
        // Re-check
        const { stdout: s2 } = await run(bridgeBin, ["doctor"]);
        const d2 = JSON.parse(s2);
        if (d2.data?.calendar?.granted) {
          log("Calendar: fullAccess -- ok");
        } else {
          log("Calendar: not granted -- open System Settings > Privacy & Security > Calendars");
        }
      }
    }
  } catch {
    log("Calendar: could not check status");
  }

  // Reminders (needs .app bundle for TCC on Sequoia)
  try {
    const outputFile = resolve(tmpdir(), `apple-bridge-setup-${randomUUID()}.json`);
    // Try direct first
    const { stdout } = await run(bridgeBin, ["doctor"]);
    const doctor = JSON.parse(stdout);
    const remStatus = doctor.data?.reminders?.granted;
    if (remStatus) {
      log("Reminders: fullAccess -- ok");
    } else {
      if (nonInteractive) {
        log("Reminders: not granted (run interactively to trigger prompt)");
      } else {
        log("Reminders: requesting access via AppleBridge.app...");
        log("Grant access in the dialog that appears.");
        // Launch .app bundle to trigger TCC
        const child = spawn("open", ["-W", "-n", "-a", appBundle, "--args", "reminder-lists", "--output", outputFile]);
        await new Promise<void>((res) => {
          child.on("close", () => res());
          child.on("error", () => res());
          setTimeout(() => { child.kill(); res(); }, 15_000);
        });
        // Clean up
        try { unlinkSync(outputFile); } catch {}
        // Wait for user
        await ask("Press Enter after granting access...");
        // Re-check
        try {
          const { stdout: out } = await run(bridgeBin, ["reminder-lists"]);
          const result = JSON.parse(out);
          if (result.status === "ok") {
            log("Reminders: fullAccess -- ok");
          } else {
            // Try via .app bundle
            const of2 = resolve(tmpdir(), `apple-bridge-setup-${randomUUID()}.json`);
            const c2 = spawn("open", ["-W", "-n", "-a", appBundle, "--args", "reminder-lists", "--output", of2]);
            await new Promise<void>((res) => {
              c2.on("close", () => res());
              c2.on("error", () => res());
              setTimeout(() => { c2.kill(); res(); }, 10_000);
            });
            if (existsSync(of2)) {
              const data = JSON.parse(readFileSync(of2, "utf-8"));
              unlinkSync(of2);
              if (data.status === "ok") {
                log("Reminders: fullAccess (via .app bundle) -- ok");
              } else {
                log("Reminders: not granted -- open System Settings > Privacy & Security > Reminders");
              }
            } else {
              log("Reminders: not granted -- open System Settings > Privacy & Security > Reminders");
            }
          }
        } catch {
          log("Reminders: could not verify status");
        }
      }
    }
  } catch {
    log("Reminders: could not check status");
  }

  // Mail
  try {
    const { stdout } = await run(bridgeBin, ["doctor"]);
    const doctor = JSON.parse(stdout);
    const mailStatus = doctor.data?.mail?.accessible;
    if (mailStatus) {
      const count = doctor.data?.mail?.accountCount ?? 0;
      log(`Mail: accessible (${count} accounts) -- ok`);
    } else {
      if (nonInteractive) {
        log("Mail: not accessible (run interactively to trigger prompt)");
      } else {
        log("Mail: requesting access (Mail.app must be running)...");
        try {
          await run(bridgeBin, ["mail-accounts"]);
          const { stdout: s2 } = await run(bridgeBin, ["doctor"]);
          const d2 = JSON.parse(s2);
          if (d2.data?.mail?.accessible) {
            log(`Mail: accessible (${d2.data.mail.accountCount} accounts) -- ok`);
          } else {
            log("Mail: not accessible -- ensure Mail.app is running and grant Automation permission");
          }
        } catch {
          log("Mail: not accessible -- ensure Mail.app is running");
        }
      }
    }
  } catch {
    log("Mail: could not check status");
  }
}
```

**Step 2: Compile**

Run: `npx tsc 2>&1`
Expected: No errors

**Step 3: Commit**

```bash
git add src/setup.ts
git commit -m "feat(setup): implement TCC permission requests"
```

---

### Task 6: Implement MCP client config output

**Files:**
- Modify: `src/setup.ts`

**Step 1: Replace the `printClientConfig` stub**

```typescript
async function printClientConfig(total: number): Promise<void> {
  step(5, total, "MCP client configuration");
  const serverPath = resolve(projectRoot, "build", "index.js");

  // Warp -- check if Warp.app exists
  const warpExists = existsSync("/Applications/Warp.app");
  if (warpExists) {
    log("Warp detected. Add this MCP server in Warp settings:");
    log(`  Command: node`);
    log(`  Args: ${serverPath}`);
  }

  // Claude Code -- check if claude CLI exists
  let claudeExists = false;
  try {
    await run("which", ["claude"]);
    claudeExists = true;
  } catch {}
  if (claudeExists) {
    log("Claude Code detected. Run:");
    log(`  claude mcp add --scope user orchard -- node ${serverPath}`);
  }

  if (!warpExists && !claudeExists) {
    log("No supported MCP clients detected (Warp, Claude Code).");
    log("Generic MCP config:");
    log(`  Command: node`);
    log(`  Args: ${serverPath}`);
  }
}
```

**Step 2: Compile**

Run: `npx tsc 2>&1`
Expected: No errors

**Step 3: Commit**

```bash
git add src/setup.ts
git commit -m "feat(setup): implement MCP client config detection"
```

---

### Task 7: Implement validation step

**Files:**
- Modify: `src/setup.ts`

**Step 1: Replace the `validate` stub**

```typescript
async function validate(total: number): Promise<void> {
  step(6, total, "Validation");
  try {
    const { stdout } = await run(bridgeBin, ["doctor"]);
    const doctor = JSON.parse(stdout);
    const d = doctor.data;

    if (d?.calendarSummary) {
      log(`Calendar: ${d.calendarSummary.count} calendars across ${d.calendarSummary.accounts?.length ?? 0} accounts`);
    } else {
      log("Calendar: no access");
    }

    if (d?.remindersSummary && d.remindersSummary.count > 0) {
      log(`Reminders: ${d.remindersSummary.count} lists`);
    } else {
      // Try via .app bundle
      const outputFile = resolve(tmpdir(), `apple-bridge-validate-${randomUUID()}.json`);
      try {
        const child = spawn("open", ["-W", "-n", "-a", appBundle, "--args", "reminder-lists", "--output", outputFile]);
        await new Promise<void>((res) => {
          child.on("close", () => res());
          child.on("error", () => res());
          setTimeout(() => { child.kill(); res(); }, 10_000);
        });
        if (existsSync(outputFile)) {
          const data = JSON.parse(readFileSync(outputFile, "utf-8"));
          unlinkSync(outputFile);
          if (data.status === "ok" && Array.isArray(data.data)) {
            const items = data.data.reduce((sum: number, l: { itemCount?: number }) => sum + (l.itemCount ?? 0), 0);
            log(`Reminders: ${data.data.length} lists (${items.toLocaleString()} items)`);
          } else {
            log("Reminders: no access");
          }
        } else {
          log("Reminders: no access");
        }
      } catch {
        log("Reminders: no access");
      }
    }

    if (d?.mail?.accessible) {
      log(`Mail: ${d.mail.accountCount} accounts`);
    } else {
      log("Mail: no access");
    }

    log("");
    log("Ready to use.");
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    log(`Validation failed: ${msg}`);
  }
}
```

**Step 2: Compile**

Run: `npx tsc 2>&1`
Expected: No errors

**Step 3: Commit**

```bash
git add src/setup.ts
git commit -m "feat(setup): implement validation step"
```

---

### Task 8: End-to-end test

**Files:** None (testing only)

**Step 1: Run the full setup wizard**

Run: `node build/index.js setup`
Expected: All 6 steps execute, permissions checked, config printed, validation summary shown

**Step 2: Run non-interactive mode**

Run: `node build/index.js setup --non-interactive`
Expected: Same steps but no prompts, TCC status reported without triggering dialogs

**Step 3: Verify MCP server still works normally**

Run: `printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1.0"}}}\n' | timeout 5 node build/index.js 2>/dev/null`
Expected: JSON-RPC initialize response (MCP server mode unchanged)

**Step 4: Commit any fixes, then final commit**

```bash
git add src/setup.ts src/index.ts
git commit -m "feat(setup): complete setup wizard"
```
