import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import { createCanvas } from "canvas";
import { layout, prepare } from "@chenglou/pretext";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const fixturesPath = path.resolve(__dirname, "pretext-fixtures.json");

const DEFAULT_PREPARE_P95_BUDGET_MS = 200;
const DEFAULT_LAYOUT_P95_BUDGET_MS = 200;
const DEFAULT_ITERATIONS = 20;
const DEFAULT_MAX_LAYOUT_BYTES = 24 * 1024 * 1024;
const DEFAULT_FALLBACK_RATE_MAX = 0.001;
const LAYOUT_WIDTH_PX = 1080;
const LINE_HEIGHT_PX = 18;
const FONT_PROFILE = "13px Menlo";

if (typeof globalThis.OffscreenCanvas === "undefined") {
  globalThis.OffscreenCanvas = class OffscreenCanvas {
    constructor(width, height) {
      return createCanvas(width, height);
    }
  };
}

function durationMs(startNs) {
  return Number(process.hrtime.bigint() - startNs) / 1_000_000;
}

function percentile(values, p) {
  if (values.length === 0) {
    return 0;
  }
  const sorted = [...values].sort((a, b) => a - b);
  const rank = Math.ceil((sorted.length * p) / 100);
  const index = Math.min(Math.max(rank - 1, 0), sorted.length - 1);
  return sorted[index];
}

function loadFixtures() {
  const raw = fs.readFileSync(fixturesPath, "utf8");
  const parsed = JSON.parse(raw);
  if (!Array.isArray(parsed)) {
    throw new Error("Fixture file must contain an array.");
  }
  return parsed;
}

function expandFixtureMacros(rawDiff) {
  let expanded = rawDiff;

  expanded = expanded.replace(/\{\{LONG_LINE_(\d+)\}\}/g, (_, widthText) => {
    const width = Number.parseInt(widthText, 10);
    if (!Number.isFinite(width) || width <= 0) {
      throw new Error(`Invalid LONG_LINE macro width: ${widthText}`);
    }
    return "x".repeat(width);
  });

  expanded = expanded.replace(/\{\{REPEAT_ADDED_LINES_(\d+)\}\}/g, (_, countText) => {
    const count = Number.parseInt(countText, 10);
    if (!Number.isFinite(count) || count <= 0) {
      throw new Error(`Invalid REPEAT_ADDED_LINES macro count: ${countText}`);
    }

    return Array.from({ length: count }, (_, index) => `+generated fixture line ${index + 1}`).join("\n");
  });

  return expanded;
}

function fallbackLayoutSummary(diffText, reason) {
  const lines = diffText.split("\n");
  return {
    prepareMs: 0,
    layoutMs: 0,
    visualRows: Math.max(lines.length, 1),
    fallbackActivated: true,
    fallbackReason: reason
  };
}

function runPretextLayout(diffText) {
  let fallbackReason = null;
  const maxLayoutBytes = Number.parseInt(process.env.GDPU_PRETEXT_MAX_LAYOUT_BYTES ?? "", 10);
  const resolvedMaxLayoutBytes = Number.isFinite(maxLayoutBytes) && maxLayoutBytes >= 1024
    ? maxLayoutBytes
    : DEFAULT_MAX_LAYOUT_BYTES;

  if (diffText.length > resolvedMaxLayoutBytes) {
    fallbackReason = `payload exceeds pretext layout budget: ${diffText.length} > ${resolvedMaxLayoutBytes}`;
  }
  if (diffText.includes("\u0000")) {
    fallbackReason = "payload contains binary null bytes";
  }
  if (matchesTruthy(process.env.GDPU_FORCE_DIFF_FALLBACK ?? "")) {
    fallbackReason = "forced by GDPU_FORCE_DIFF_FALLBACK";
  }

  if (fallbackReason) {
    return fallbackLayoutSummary(diffText, fallbackReason);
  }

  try {
    const prepareStartedAt = process.hrtime.bigint();
    const prepared = prepare(diffText, FONT_PROFILE, { whiteSpace: "pre-wrap" });
    const prepareMs = durationMs(prepareStartedAt);

    const layoutStartedAt = process.hrtime.bigint();
    const layoutResult = layout(prepared, LAYOUT_WIDTH_PX, LINE_HEIGHT_PX);
    const layoutMs = durationMs(layoutStartedAt);

    return {
      prepareMs,
      layoutMs,
      visualRows: Math.max(layoutResult.lineCount, 1),
      fallbackActivated: false,
      fallbackReason: null
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return fallbackLayoutSummary(diffText, `pretext runtime error: ${message}`);
  }
}

function benchmarkFixture(fixture, iterations) {
  const payload = expandFixtureMacros(fixture.diff);
  const prepareSamples = [];
  const layoutSamples = [];
  let visualRows = 0;
  let fallbackActivated = false;
  let fallbackReason = null;

  for (let i = 0; i < iterations; i++) {
    const runtimeLayout = runPretextLayout(payload);
    prepareSamples.push(runtimeLayout.prepareMs);
    layoutSamples.push(runtimeLayout.layoutMs);
    visualRows = runtimeLayout.visualRows;
    fallbackActivated = runtimeLayout.fallbackActivated;
    fallbackReason = runtimeLayout.fallbackReason;
  }

  return {
    id: fixture.id,
    prepareP95Ms: percentile(prepareSamples, 95),
    layoutP95Ms: percentile(layoutSamples, 95),
    visualRows,
    fallbackActivated,
    fallbackReason
  };
}

function matchesTruthy(value) {
  const normalized = value.trim().toLowerCase();
  return normalized === "1" || normalized === "true" || normalized === "yes";
}

function main() {
  const prepareBudgetMs = Number.parseInt(process.env.GDPU_PRETEXT_CANARY_PREPARE_P95_MS ?? "", 10);
  const layoutBudgetMs = Number.parseInt(process.env.GDPU_PRETEXT_CANARY_LAYOUT_P95_MS ?? "", 10);
  const iterations = Number.parseInt(process.env.GDPU_PRETEXT_CANARY_ITERATIONS ?? "", 10);
  const fallbackRateBudget = Number.parseFloat(process.env.GDPU_PRETEXT_FALLBACK_RATE_MAX ?? "");

  const resolvedPrepareBudgetMs = Number.isFinite(prepareBudgetMs) && prepareBudgetMs > 0
    ? prepareBudgetMs
    : DEFAULT_PREPARE_P95_BUDGET_MS;
  const resolvedLayoutBudgetMs = Number.isFinite(layoutBudgetMs) && layoutBudgetMs > 0
    ? layoutBudgetMs
    : DEFAULT_LAYOUT_P95_BUDGET_MS;
  const resolvedIterations = Number.isFinite(iterations) && iterations > 0
    ? iterations
    : DEFAULT_ITERATIONS;
  const resolvedFallbackRateBudget = Number.isFinite(fallbackRateBudget) && fallbackRateBudget >= 0
    ? fallbackRateBudget
    : DEFAULT_FALLBACK_RATE_MAX;

  const fixtures = loadFixtures();
  const results = fixtures.map((fixture) => benchmarkFixture(fixture, resolvedIterations));

  let hasFailure = false;
  const fallbackCount = results.filter((result) => result.fallbackActivated).length;
  const fallbackRate = results.length === 0 ? 0 : fallbackCount / results.length;
  console.log(`Pretext canary benchmark ran ${results.length} fixtures with ${resolvedIterations} iterations each.`);

  for (const result of results) {
    console.log(
      `- ${result.id}: prepare_p95=${result.prepareP95Ms.toFixed(3)}ms layout_p95=${result.layoutP95Ms.toFixed(3)}ms visual_rows=${result.visualRows} fallback=${result.fallbackActivated}`
    );

    if (result.fallbackActivated && result.fallbackReason) {
      console.error(`  fallback reason: ${result.fallbackReason}`);
    }

    if (result.prepareP95Ms > resolvedPrepareBudgetMs || result.layoutP95Ms > resolvedLayoutBudgetMs) {
      hasFailure = true;
      console.error(
        `  budget violation: prepare<=${resolvedPrepareBudgetMs}ms layout<=${resolvedLayoutBudgetMs}ms`
      );
    }
  }

  console.log(
    `Fallback activation rate: ${(fallbackRate * 100).toFixed(2)}% (max ${(resolvedFallbackRateBudget * 100).toFixed(2)}%).`
  );
  if (fallbackRate > resolvedFallbackRateBudget) {
    hasFailure = true;
    console.error("  budget violation: fallback activation rate exceeded");
  }

  if (hasFailure) {
    process.exit(1);
  }

  console.log("Pretext canary benchmark passed.");
}

main();
