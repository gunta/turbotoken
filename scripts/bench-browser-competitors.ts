#!/usr/bin/env bun
import { existsSync, mkdirSync, statSync, writeFileSync } from "node:fs";
import { extname } from "node:path";
import {
  acquireBenchmarkLock,
  commandExists,
  resolvePath,
  section,
  writeJson,
} from "./_lib";

interface BrowserCompetitorRow {
  name: string;
  startupMs: number | null;
  encodeMs: number | null;
  mibPerSec: number | null;
  status: string;
}

interface BrowserCompetitorResult {
  generatedAt: string;
  status: "ok" | "failed";
  pageUrl: string;
  rows: BrowserCompetitorRow[];
  log: string;
  browserVersion: string | null;
  userAgent: string | null;
  note: string;
}

function contentType(pathname: string): string {
  switch (extname(pathname).toLowerCase()) {
    case ".html":
      return "text/html; charset=utf-8";
    case ".mjs":
    case ".js":
      return "text/javascript; charset=utf-8";
    case ".json":
      return "application/json; charset=utf-8";
    case ".wasm":
      return "application/wasm";
    case ".txt":
      return "text/plain; charset=utf-8";
    default:
      return "application/octet-stream";
  }
}

function parseCellNumber(text: string | null): number | null {
  if (text == null) {
    return null;
  }
  const trimmed = text.trim();
  if (trimmed === "-" || trimmed.length === 0) {
    return null;
  }
  const parsed = Number.parseFloat(trimmed);
  return Number.isFinite(parsed) ? parsed : null;
}

async function ensureRankFixture(path: string): Promise<void> {
  if (existsSync(path) && statSync(path).size > 0) {
    return;
  }
  const rankUrl = "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken";
  const response = await fetch(rankUrl);
  if (!response.ok) {
    throw new Error(`failed to download rank payload (${response.status}) from ${rankUrl}`);
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength === 0) {
    throw new Error("downloaded rank payload is empty");
  }
  mkdirSync(resolvePath("bench", "fixtures"), { recursive: true });
  writeFileSync(path, bytes);
}

async function main(): Promise<void> {
  acquireBenchmarkLock({ label: "bench-browser-competitors" });
  section("Browser benchmark (WASM competitors)");

  const outputPath = resolvePath("bench", "results", `bench-browser-competitors-${Date.now()}.json`);
  const htmlPath = resolvePath("bench", "browser", "wasm-competitors.html");
  const rankFixturePath = resolvePath("bench", "fixtures", "o200k_base.tiktoken");
  if (!existsSync(htmlPath)) {
    writeJson(outputPath, {
      generatedAt: new Date().toISOString(),
      status: "failed",
      reason: `missing browser benchmark page: ${htmlPath}`,
    });
    throw new Error(`missing browser benchmark page: ${htmlPath}`);
  }
  await ensureRankFixture(rankFixturePath);

  if (!commandExists("bun")) {
    writeJson(outputPath, {
      generatedAt: new Date().toISOString(),
      status: "failed",
      reason: "bun executable not found",
    });
    throw new Error("bun executable not found");
  }

  let chromiumModule: typeof import("playwright") | null = null;
  try {
    chromiumModule = await import("playwright");
  } catch (error) {
    writeJson(outputPath, {
      generatedAt: new Date().toISOString(),
      status: "failed",
      reason: "playwright is not installed; run bun install",
      error: String(error),
    });
    throw new Error("playwright is not installed; run `bun install`");
  }

  const repoRoot = resolvePath();
  const server = Bun.serve({
    port: 0,
    fetch(req) {
      const url = new URL(req.url);
      const pathname = url.pathname === "/" ? "/bench/browser/wasm-competitors.html" : decodeURIComponent(url.pathname);
      if (!pathname.startsWith("/")) {
        return new Response("bad request", { status: 400 });
      }
      const filePath = resolvePath(pathname.slice(1));
      if (!filePath.startsWith(repoRoot) || !existsSync(filePath)) {
        return new Response("not found", { status: 404 });
      }
      return new Response(Bun.file(filePath), {
        headers: {
          "content-type": contentType(filePath),
          "cache-control": "no-store",
        },
      });
    },
  });

  const pageUrl = `http://127.0.0.1:${server.port}/bench/browser/wasm-competitors.html`;
  let result: BrowserCompetitorResult;
  let exitCode = 0;

  try {
    const browser = await chromiumModule.chromium.launch({ headless: true });
    try {
      const page = await browser.newPage();
      await page.goto(pageUrl, { waitUntil: "networkidle", timeout: 120_000 });
      await page.click("#run", { timeout: 10_000 });
      await page.waitForFunction(
        () => {
          const statuses = Array.from(document.querySelectorAll("#rows tr .status")).map(
            (el) => (el.textContent ?? "").trim(),
          );
          return statuses.length > 0 && statuses.every((status) => status === "ok" || status === "failed");
        },
        undefined,
        { timeout: 300_000 },
      );

      const rows = await page.$$eval("#rows tr", (nodes) =>
        nodes.map((node) => {
          const cells = Array.from(node.querySelectorAll("td")).map((cell) => (cell.textContent ?? "").trim());
          return {
            name: cells[0] ?? "",
            startupMsText: cells[1] ?? "",
            encodeMsText: cells[2] ?? "",
            mibPerSecText: cells[3] ?? "",
            status: cells[4] ?? "",
          };
        }),
      );
      const parsedRows: BrowserCompetitorRow[] = rows.map((row) => ({
        name: row.name,
        startupMs: parseCellNumber(row.startupMsText),
        encodeMs: parseCellNumber(row.encodeMsText),
        mibPerSec: parseCellNumber(row.mibPerSecText),
        status: row.status || "unknown",
      }));
      const log = await page.$eval("#log", (el) => (el.textContent ?? "").trim());
      const userAgent = await page.evaluate(() => navigator.userAgent);

      const requiredNames = new Set([
        "turbotoken (WASM full BPE)",
        "gpt-tokenizer",
        "js-tiktoken",
      ]);
      const requiredFailures = parsedRows.filter(
        (row) => requiredNames.has(row.name) && row.status !== "ok",
      );
      if (requiredFailures.length > 0) {
        exitCode = 1;
      }

      result = {
        generatedAt: new Date().toISOString(),
        status: exitCode === 0 ? "ok" : "failed",
        pageUrl,
        rows: parsedRows,
        log,
        browserVersion: browser.version(),
        userAgent,
        note:
          "Runs bench/browser/wasm-competitors.html headlessly via Playwright and records startup/1MiB encode rows.",
      };
    } finally {
      await browser.close();
    }
  } catch (error) {
    result = {
      generatedAt: new Date().toISOString(),
      status: "failed",
      pageUrl,
      rows: [],
      log: `runner failed: ${String(error)}`,
      browserVersion: null,
      userAgent: null,
      note:
        "Runs bench/browser/wasm-competitors.html headlessly via Playwright and records startup/1MiB encode rows.",
    };
    exitCode = 1;
  } finally {
    server.stop(true);
  }

  writeJson(outputPath, result);
  if (exitCode !== 0) {
    console.error(`Browser competitor benchmark failed: ${outputPath}`);
    process.exit(exitCode);
  }
  console.log(`Browser competitor benchmark written: ${outputPath}`);
}

await main();
