import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createInterface } from "node:readline";
import {
  mkdirSync,
  copyFileSync,
  existsSync,
  readFileSync,
  unlinkSync,
} from "node:fs";
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

async function run(
  cmd: string,
  args: string[],
  opts?: { cwd?: string; timeout?: number }
): Promise<{ stdout: string; stderr: string }> {
  return execFileAsync(cmd, args, {
    timeout: opts?.timeout ?? 120_000,
    maxBuffer: 10 * 1024 * 1024,
    cwd: opts?.cwd,
  });
}

export async function runSetup(nonInteractive: boolean): Promise<void> {
  const total = 6;
  process.stdout.write("\norchard-mcp setup\n================\n");

  const ok1 = await checkPrereqs(total);
  if (!ok1) process.exit(1);

  const ok2 = await buildSwift(total);
  if (!ok2) process.exit(1);

  await buildAppBundle(total);
  await requestPermissions(total, nonInteractive);
  await printClientConfig(total);
  await validate(total);
}

// Step 1: Prerequisites
async function checkPrereqs(total: number): Promise<boolean> {
  step(1, total, "Checking prerequisites...");
  let ok = true;

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

  try {
    const { stdout } = await run("swift", ["--version"]);
    const match = stdout.match(/Swift version ([\d.]+)/);
    const ver = match ? match[1] : "unknown";
    log(`Swift ${ver} -- ok`);
  } catch {
    log("Swift not found -- install Xcode Command Line Tools: xcode-select --install");
    ok = false;
  }

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

// Step 2: Build Swift
async function buildSwift(total: number): Promise<boolean> {
  step(2, total, "Building Swift binary...");

  if (existsSync(bridgeBin)) {
    log("Binary already exists -- skipping build.");
    return true;
  }

  try {
    await run(
      "swift",
      [
        "build",
        "-c",
        "release",
        "-Xlinker",
        "-sectcreate",
        "-Xlinker",
        "__TEXT",
        "-Xlinker",
        "__info_plist",
        "-Xlinker",
        "Sources/AppleBridge/Info.plist",
      ],
      { cwd: swiftDir, timeout: 300_000 }
    );
    log("swift build -c release -- ok");
    return true;
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    log(`Swift build failed: ${msg}`);
    return false;
  }
}

// Step 3: Build .app bundle
async function buildAppBundle(total: number): Promise<void> {
  step(3, total, "Building AppleBridge.app bundle...");

  const macosDir = resolve(appBundle, "Contents", "MacOS");
  const binaryInApp = resolve(macosDir, "apple-bridge");

  if (existsSync(binaryInApp)) {
    log("App bundle already exists -- skipping build.");
    return;
  }

  mkdirSync(macosDir, { recursive: true });
  copyFileSync(bridgeBin, resolve(macosDir, "apple-bridge"));
  copyFileSync(infoPlist, resolve(appBundle, "Contents", "Info.plist"));

  try {
    await run("codesign", ["--force", "--sign", "-", appBundle]);
    log("Created and signed -- ok");
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    log(`codesign failed: ${msg}`);
  }
}

// Step 4: TCC permissions
async function requestPermissions(
  total: number,
  nonInteractive: boolean
): Promise<void> {
  step(4, total, "Requesting permissions...");

  // Helper: parse doctor output
  async function getDoctor(): Promise<Record<string, any> | null> {
    try {
      const { stdout } = await run(bridgeBin, ["doctor"]);
      const parsed = JSON.parse(stdout);
      return parsed.data ?? null;
    } catch {
      return null;
    }
  }

  // Helper: run command via .app bundle, return parsed JSON or null
  async function runViaApp(
    args: string[]
  ): Promise<Record<string, any> | null> {
    const outputFile = resolve(tmpdir(), `apple-bridge-${randomUUID()}.json`);
    try {
      const child = spawn("open", [
        "-W",
        "-n",
        "-a",
        appBundle,
        "--args",
        ...args,
        "--output",
        outputFile,
      ]);
      await new Promise<void>((res) => {
        child.on("close", () => res());
        child.on("error", () => res());
        setTimeout(() => {
          child.kill();
          res();
        }, 15_000);
      });
      if (existsSync(outputFile)) {
        const data = JSON.parse(readFileSync(outputFile, "utf-8"));
        try {
          unlinkSync(outputFile);
        } catch {}
        return data;
      }
      return null;
    } catch {
      try {
        unlinkSync(outputFile);
      } catch {}
      return null;
    }
  }

  const doctor = await getDoctor();

  // Calendar
  if (doctor?.calendar?.granted) {
    log("Calendar: fullAccess -- ok");
  } else if (nonInteractive) {
    log("Calendar: not granted (run interactively to trigger prompt)");
  } else {
    log("Calendar: requesting access...");
    try {
      await run(bridgeBin, ["calendars"]);
    } catch {}
    const d2 = await getDoctor();
    if (d2?.calendar?.granted) {
      log("Calendar: fullAccess -- ok");
    } else {
      log(
        "Calendar: not granted -- open System Settings > Privacy & Security > Calendars"
      );
    }
  }

  // Reminders (needs .app bundle for TCC on Sequoia)
  if (doctor?.reminders?.granted) {
    log("Reminders: fullAccess -- ok");
  } else if (nonInteractive) {
    log("Reminders: not granted (run interactively to trigger prompt)");
  } else {
    log("Reminders: requesting access via AppleBridge.app...");
    log("Grant access in the dialog that appears.");
    await runViaApp(["reminder-lists"]);
    await ask("Press Enter after granting access...");
    // Verify via .app bundle (direct binary won't have TCC on Sequoia)
    const result = await runViaApp(["reminder-lists"]);
    if (result?.status === "ok") {
      log("Reminders: fullAccess -- ok");
    } else {
      log(
        "Reminders: not granted -- open System Settings > Privacy & Security > Reminders"
      );
    }
  }

  // Mail
  if (doctor?.mail?.accessible) {
    const count = doctor.mail.accountCount ?? 0;
    log(`Mail: accessible (${count} accounts) -- ok`);
  } else if (nonInteractive) {
    log("Mail: not accessible (run interactively to trigger prompt)");
  } else {
    log("Mail: requesting access (Mail.app must be running)...");
    try {
      await run(bridgeBin, ["mail-accounts"]);
    } catch {}
    const d2 = await getDoctor();
    if (d2?.mail?.accessible) {
      log(`Mail: accessible (${d2.mail.accountCount} accounts) -- ok`);
    } else {
      log(
        "Mail: not accessible -- ensure Mail.app is running and grant Automation permission"
      );
    }
  }
}

// Step 5: MCP client config
async function printClientConfig(total: number): Promise<void> {
  step(5, total, "MCP client configuration");
  const serverPath = resolve(projectRoot, "build", "index.js");

  const warpExists = existsSync("/Applications/Warp.app");
  if (warpExists) {
    log("Warp detected. Add this MCP server in Warp settings:");
    log(`  Command: node`);
    log(`  Args: ${serverPath}`);
  }

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

// Step 6: Validation
async function validate(total: number): Promise<void> {
  step(6, total, "Validation");
  try {
    const { stdout } = await run(bridgeBin, ["doctor"]);
    const doctor = JSON.parse(stdout);
    const d = doctor.data;

    if (d?.calendarSummary) {
      log(
        `Calendar: ${d.calendarSummary.count} calendars across ${d.calendarSummary.accounts?.length ?? 0} accounts`
      );
    } else {
      log("Calendar: no access");
    }

    // Reminders: try direct first, fall back to .app bundle
    if (d?.remindersSummary && d.remindersSummary.count > 0) {
      log(`Reminders: ${d.remindersSummary.count} lists`);
    } else {
      const outputFile = resolve(
        tmpdir(),
        `apple-bridge-validate-${randomUUID()}.json`
      );
      try {
        const child = spawn("open", [
          "-W",
          "-n",
          "-a",
          appBundle,
          "--args",
          "reminder-lists",
          "--output",
          outputFile,
        ]);
        await new Promise<void>((res) => {
          child.on("close", () => res());
          child.on("error", () => res());
          setTimeout(() => {
            child.kill();
            res();
          }, 10_000);
        });
        if (existsSync(outputFile)) {
          const data = JSON.parse(readFileSync(outputFile, "utf-8"));
          unlinkSync(outputFile);
          if (data.status === "ok" && Array.isArray(data.data)) {
            const items = data.data.reduce(
              (sum: number, l: { itemCount?: number }) =>
                sum + (l.itemCount ?? 0),
              0
            );
            log(
              `Reminders: ${data.data.length} lists (${items.toLocaleString()} items)`
            );
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
