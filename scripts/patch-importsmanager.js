// scripts/patch-importsmanager.js
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const sourceFile = path.join(__dirname, "../patches/ImportsManager.js");
const targetFile = path.join(
  __dirname,
  "../node_modules/hackchat-server/src/serverLib/ImportsManager.js"
);

if (fs.existsSync(sourceFile) && fs.existsSync(targetFile)) {
  fs.copyFileSync(sourceFile, targetFile);
  console.log("Patched ImportsManager.js successfully");
} else {
  console.error("Source or target file missing, patch not applied");
}