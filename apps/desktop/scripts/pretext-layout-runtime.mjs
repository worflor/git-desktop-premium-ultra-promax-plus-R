import process from "node:process";
import { createRequire } from "node:module";

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

async function readStdinJson() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(typeof chunk === "string" ? chunk : chunk.toString("utf8"));
  }

  const raw = chunks.join("").trim();
  if (!raw) {
    throw new Error("Missing JSON request payload on stdin.");
  }

  return JSON.parse(raw);
}

function assertFinitePositive(name, value, min) {
  if (!Number.isFinite(value) || value < min) {
    throw new Error(`${name} must be a finite number >= ${min}`);
  }
}

async function main() {
  const request = await readStdinJson();
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

  process.stdout.write(JSON.stringify(response));
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(message);
  process.exit(1);
});
