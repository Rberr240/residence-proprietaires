#!/usr/bin/env node
// Extracts every inline <script> block (no src attribute) from every
// tracked *.html file and runs `node --check` on it, so a syntax
// error inside a large inline script (e.g. espace-proprietaire.html,
// admin.html) fails CI the same way an external .js file would.

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const repoRoot = path.resolve(__dirname, "..", "..");

const trackedHtmlFiles = execFileSync(
  "git",
  ["ls-files", "--", "*.html"],
  { cwd: repoRoot, encoding: "utf8" },
)
  .split("\n")
  .map((line) => line.trim())
  .filter(Boolean);

let failed = false;
let checkedCount = 0;

for (const relativePath of trackedHtmlFiles) {
  const absolutePath = path.join(repoRoot, relativePath);
  const html = fs.readFileSync(absolutePath, "utf8");

  // Inline scripts only: skip any <script ... src="...">.
  const scriptBlocks = [
    ...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi),
  ].map((match) => match[1]);

  scriptBlocks.forEach((code, index) => {
    if (!code.trim()) {
      return;
    }

    checkedCount += 1;

    const tmpFile = path.join(
      os.tmpdir(),
      `inline-js-check-${process.pid}-${checkedCount}.js`,
    );

    fs.writeFileSync(tmpFile, code);

    try {
      execFileSync("node", ["--check", tmpFile], { stdio: "pipe" });
      console.log(`OK   ${relativePath} (script #${index + 1})`);
    } catch (error) {
      failed = true;
      console.error(`FAIL ${relativePath} (script #${index + 1})`);
      console.error(error.stderr?.toString() || error.message);
    } finally {
      fs.unlinkSync(tmpFile);
    }
  });
}

console.log(`\nChecked ${checkedCount} inline <script> block(s).`);

if (failed) {
  process.exit(1);
}
