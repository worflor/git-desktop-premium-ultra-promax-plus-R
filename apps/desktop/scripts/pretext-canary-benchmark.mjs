import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const fixturesPath = path.resolve(__dirname, "pretext-fixtures.json");

const DEFAULT_PREPARE_P95_BUDGET_MS = 200;
const DEFAULT_LAYOUT_P95_BUDGET_MS = 200;
const DEFAULT_ITERATIONS = 20;
const AVERAGE_GLYPH_WIDTH_PX = 8;
const LAYOUT_WIDTH_PX = 1080;

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

function simulatePretextPrepare(diffText) {
  const lines = diffText.split("\n");
  const lineLengths = lines.map((line) => Array.from(line.endsWith("\r") ? line.slice(0, -1) : line).length);
  return { lines, lineLengths };
}

function simulatePretextLayout(prepared) {
  const maxColumns = Math.max(Math.floor(LAYOUT_WIDTH_PX / AVERAGE_GLYPH_WIDTH_PX), 16);
  let visualRows = 0;

  for (const length of prepared.lineLengths) {
    const rows = length === 0 ? 1 : Math.ceil(length / maxColumns);
    visualRows += rows;
  }

  return {
    visualRows,
    lineCount: prepared.lines.length
  };
}

function benchmarkFixture(fixture, iterations) {
  const payload = expandFixtureMacros(fixture.diff);
  const prepareSamples = [];
  const layoutSamples = [];
  let visualRows = 0;

  for (let i = 0; i < iterations; i++) {
    const prepareStartedAt = process.hrtime.bigint();
    const prepared = simulatePretextPrepare(payload);
    prepareSamples.push(durationMs(prepareStartedAt));

    const layoutStartedAt = process.hrtime.bigint();
    const layout = simulatePretextLayout(prepared);
    layoutSamples.push(durationMs(layoutStartedAt));
    visualRows = layout.visualRows;
  }

  return {
    id: fixture.id,
    prepareP95Ms: percentile(prepareSamples, 95),
    layoutP95Ms: percentile(layoutSamples, 95),
    visualRows
  };
}

function main() {
  const prepareBudgetMs = Number.parseInt(process.env.GDPU_PRETEXT_CANARY_PREPARE_P95_MS ?? "", 10);
  const layoutBudgetMs = Number.parseInt(process.env.GDPU_PRETEXT_CANARY_LAYOUT_P95_MS ?? "", 10);
  const iterations = Number.parseInt(process.env.GDPU_PRETEXT_CANARY_ITERATIONS ?? "", 10);

  const resolvedPrepareBudgetMs = Number.isFinite(prepareBudgetMs) && prepareBudgetMs > 0
    ? prepareBudgetMs
    : DEFAULT_PREPARE_P95_BUDGET_MS;
  const resolvedLayoutBudgetMs = Number.isFinite(layoutBudgetMs) && layoutBudgetMs > 0
    ? layoutBudgetMs
    : DEFAULT_LAYOUT_P95_BUDGET_MS;
  const resolvedIterations = Number.isFinite(iterations) && iterations > 0
    ? iterations
    : DEFAULT_ITERATIONS;

  const fixtures = loadFixtures();
  const results = fixtures.map((fixture) => benchmarkFixture(fixture, resolvedIterations));

  let hasFailure = false;
  console.log(`Pretext canary benchmark ran ${results.length} fixtures with ${resolvedIterations} iterations each.`);

  for (const result of results) {
    console.log(
      `- ${result.id}: prepare_p95=${result.prepareP95Ms.toFixed(3)}ms layout_p95=${result.layoutP95Ms.toFixed(3)}ms visual_rows=${result.visualRows}`
    );

    if (result.prepareP95Ms > resolvedPrepareBudgetMs || result.layoutP95Ms > resolvedLayoutBudgetMs) {
      hasFailure = true;
      console.error(
        `  budget violation: prepare<=${resolvedPrepareBudgetMs}ms layout<=${resolvedLayoutBudgetMs}ms`
      );
    }
  }

  if (hasFailure) {
    process.exit(1);
  }

  console.log("Pretext canary benchmark passed.");
}

main();
