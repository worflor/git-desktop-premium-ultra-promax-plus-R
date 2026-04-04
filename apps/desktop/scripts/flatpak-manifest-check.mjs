import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const manifestPath = path.resolve(__dirname, "../flatpak/com.gdpu.desktop.json");

function fail(message) {
  console.error(`Flatpak manifest check failed: ${message}`);
  process.exit(1);
}

function assert(condition, message) {
  if (!condition) {
    fail(message);
  }
}

function main() {
  if (!fs.existsSync(manifestPath)) {
    fail(`manifest not found at ${manifestPath}`);
  }

  const payload = fs.readFileSync(manifestPath, "utf8");
  const manifest = JSON.parse(payload);

  assert(manifest["app-id"] === "com.gdpu.desktop", "app-id must be com.gdpu.desktop");
  assert(typeof manifest.runtime === "string" && manifest.runtime.length > 0, "runtime is required");
  assert(
    typeof manifest["runtime-version"] === "string" && manifest["runtime-version"].length > 0,
    "runtime-version is required"
  );
  assert(typeof manifest.sdk === "string" && manifest.sdk.length > 0, "sdk is required");
  assert(manifest.command === "gdpu-desktop", "command must be gdpu-desktop");
  assert(Array.isArray(manifest.modules) && manifest.modules.length > 0, "modules must be a non-empty array");

  const module = manifest.modules[0];
  assert(module.name === "gdpu-desktop", "first module must be named gdpu-desktop");
  assert(Array.isArray(module["build-commands"]) && module["build-commands"].length > 0, "build-commands are required");
  assert(Array.isArray(module.sources) && module.sources.length > 0, "sources are required");

  console.log("Flatpak manifest check passed.");
}

main();
