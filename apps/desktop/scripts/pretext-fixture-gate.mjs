import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const RENDER_POLICY = {
  canvasLineThreshold: 1600,
  canvasCharThreshold: 100000
};

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const fixturesPath = path.resolve(__dirname, "pretext-fixtures.json");

function detectLineKind(line) {
  if (line.startsWith("@@")) {
    return "hunk";
  }
  if (line.startsWith("+") && !line.startsWith("+++")) {
    return "added";
  }
  if (line.startsWith("-") && !line.startsWith("---")) {
    return "deleted";
  }
  if (
    line.startsWith("diff --git") ||
    line.startsWith("index ") ||
    line.startsWith("---") ||
    line.startsWith("+++")
  ) {
    return "meta";
  }
  return "context";
}

function pickDefaultMode(text) {
  const lineCount = text.split("\n").length;
  const charCount = text.length;
  if (
    lineCount > RENDER_POLICY.canvasLineThreshold ||
    charCount > RENDER_POLICY.canvasCharThreshold
  ) {
    return "canvas";
  }
  return "dom";
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

function analyzeDiff(diffText) {
  const lines = diffText.split("\n");
  const mappedLines = lines.map((rawLine, index) => {
    const line = rawLine.endsWith("\r") ? rawLine.slice(0, -1) : rawLine;
    return {
      lineNumber: index + 1,
      kind: detectLineKind(line),
      charLength: Array.from(line).length
    };
  });

  const changedLines = mappedLines.filter((line) => line.kind === "added" || line.kind === "deleted").length;
  const maxLineChars = mappedLines.reduce(
    (maxChars, line) => (line.charLength > maxChars ? line.charLength : maxChars),
    0
  );

  return {
    defaultMode: pickDefaultMode(diffText),
    lineCount: mappedLines.length,
    changedLines,
    maxLineChars,
    hasCrLf: /\r\n/.test(diffText),
    hasBidiMarkers: /[\u202A-\u202E\u2066-\u2069]/u.test(diffText),
    hasMixedScripts:
      /[\u0590-\u05FF]/u.test(diffText) &&
      /[\u0400-\u04FF]/u.test(diffText) &&
      /[\u4E00-\u9FFF]/u.test(diffText),
    mappedLines
  };
}

function deterministicSignature(analysis) {
  return analysis.mappedLines
    .map((line) => `${line.lineNumber}:${line.kind}:${line.charLength}`)
    .join("|");
}

function validateFixture(fixture) {
  const failures = [];
  const diffText = expandFixtureMacros(fixture.diff);
  const analysisA = analyzeDiff(diffText);
  const analysisB = analyzeDiff(diffText);

  if (deterministicSignature(analysisA) !== deterministicSignature(analysisB)) {
    failures.push("line mapping is not deterministic");
  }

  const expected = fixture.expect ?? {};

  if (expected.defaultMode && analysisA.defaultMode !== expected.defaultMode) {
    failures.push(`expected defaultMode=${expected.defaultMode} but got ${analysisA.defaultMode}`);
  }

  if (Array.isArray(expected.containsKinds)) {
    const kindSet = new Set(analysisA.mappedLines.map((line) => line.kind));
    for (const kind of expected.containsKinds) {
      if (!kindSet.has(kind)) {
        failures.push(`expected line kind '${kind}' to appear in mapped output`);
      }
    }
  }

  if (
    Number.isFinite(expected.changedLinesAtLeast) &&
    analysisA.changedLines < expected.changedLinesAtLeast
  ) {
    failures.push(
      `expected changedLines >= ${expected.changedLinesAtLeast} but got ${analysisA.changedLines}`
    );
  }

  if (Number.isFinite(expected.lineCountAtLeast) && analysisA.lineCount < expected.lineCountAtLeast) {
    failures.push(`expected lineCount >= ${expected.lineCountAtLeast} but got ${analysisA.lineCount}`);
  }

  if (Number.isFinite(expected.minMaxLineChars) && analysisA.maxLineChars < expected.minMaxLineChars) {
    failures.push(`expected maxLineChars >= ${expected.minMaxLineChars} but got ${analysisA.maxLineChars}`);
  }

  if (expected.requireBidiMarkers === true && !analysisA.hasBidiMarkers) {
    failures.push("expected bidi markers in fixture payload");
  }

  if (expected.requireMixedScripts === true && !analysisA.hasMixedScripts) {
    failures.push("expected mixed script sample (Hebrew/Cyrillic/CJK) in fixture payload");
  }

  if (expected.requireCrLf === true && !analysisA.hasCrLf) {
    failures.push("expected CRLF line endings in fixture payload");
  }

  return {
    id: fixture.id,
    description: fixture.description,
    failures,
    summary: {
      defaultMode: analysisA.defaultMode,
      lineCount: analysisA.lineCount,
      changedLines: analysisA.changedLines,
      maxLineChars: analysisA.maxLineChars
    }
  };
}

function loadFixtures() {
  const raw = fs.readFileSync(fixturesPath, "utf8");
  const parsed = JSON.parse(raw);
  if (!Array.isArray(parsed)) {
    throw new Error("Fixture file must contain an array.");
  }
  return parsed;
}

function main() {
  const fixtures = loadFixtures();
  const results = fixtures.map(validateFixture);
  const failures = results.filter((result) => result.failures.length > 0);

  console.log(`Pretext fixture gate executed ${results.length} fixtures.`);
  for (const result of results) {
    console.log(
      `- ${result.id}: mode=${result.summary.defaultMode}, lines=${result.summary.lineCount}, changed=${result.summary.changedLines}, maxLineChars=${result.summary.maxLineChars}`
    );
  }

  if (failures.length > 0) {
    console.error("\nPretext fixture gate failed:");
    for (const failed of failures) {
      console.error(`* ${failed.id}: ${failed.description}`);
      for (const failure of failed.failures) {
        console.error(`  - ${failure}`);
      }
    }
    process.exit(1);
  }

  console.log("Pretext fixture gate passed.");
}

main();
