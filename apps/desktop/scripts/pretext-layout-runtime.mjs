import process from "node:process";
import { createRequire } from "node:module";
import { createInterface } from "node:readline";

import { createCanvas } from "canvas";
import { layout, prepare } from "@chenglou/pretext";

const require = createRequire(import.meta.url);
const pretextPackage = require("@chenglou/pretext/package.json");

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

function assertFinitePositive(name, value, min) {
  if (!Number.isFinite(value) || value < min) {
    throw new Error(`${name} must be a finite number >= ${min}`);
  }
}

function processRequest(request) {
  const text = typeof request.text === "string" ? request.text : "";
  const widthPx = Number(request.widthPx);
  const lineHeightPx = Number(request.lineHeightPx);
  const fontProfile = typeof request.fontProfile === "string" && request.fontProfile.trim().length > 0
    ? request.fontProfile.trim()
    : "13px Menlo";

  assertFinitePositive("widthPx", widthPx, 1);
  assertFinitePositive("lineHeightPx", lineHeightPx, 1);

  const prepareStartedAt = process.hrtime.bigint();
  const prepared = prepare(text, fontProfile, { whiteSpace: "pre-wrap" });
  const prepareMs = durationMs(prepareStartedAt);

  const layoutStartedAt = process.hrtime.bigint();
  const layoutResult = layout(prepared, widthPx, lineHeightPx);
  const layoutMs = durationMs(layoutStartedAt);

  const response = {
    ok: true,
    pretextVersion: typeof pretextPackage.version === "string" ? pretextPackage.version : "unknown",
    prepareMs,
    layoutMs,
    lineCount: layoutResult.lineCount,
    height: layoutResult.height
  };

  return response;
}

async function main() {
  const input = createInterface({
    input: process.stdin,
    crlfDelay: Infinity,
    terminal: false
  });

  for await (const rawLine of input) {
    const line = rawLine.trim();
    if (!line) {
      continue;
    }

    let response;
    try {
      const request = JSON.parse(line);
      response = processRequest(request);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      response = {
        ok: false,
        error: message
      };
    }

    process.stdout.write(`${JSON.stringify(response)}\n`);
  }
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(message);
  process.exit(1);
});
