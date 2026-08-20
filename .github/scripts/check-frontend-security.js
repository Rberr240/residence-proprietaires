#!/usr/bin/env node
// Static regression guard for a handful of frontend security/UI
// properties introduced in the Sprint 1 UI/security hardening pass.
// Intentionally small and dependency-free, in the same spirit as
// check-inline-js.js: no browser, no test framework, just checks that
// are cheap to run on every push and catch an easy regression before
// it reaches a page.

const fs = require("node:fs");
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

const DANGEROUS_PATTERNS = [
  { name: "document.write(", pattern: /document\.write\(/ },
  { name: "eval(", pattern: /[^a-zA-Z0-9_.]eval\(/ },
  { name: "new Function(", pattern: /new\s+Function\(/ },
  { name: "javascript: URL", pattern: /href\s*=\s*["']javascript:/i },
];

for (const relativePath of trackedHtmlFiles) {
  const absolutePath = path.join(repoRoot, relativePath);
  const html = fs.readFileSync(absolutePath, "utf8");

  if (!html.trim()) {
    console.log(`SKIP ${relativePath} (empty file, not wired into the app)`);
    continue;
  }

  checkedCount += 1;

  // 1. Every target="_blank" anchor must carry noopener + noreferrer,
  //    or a reverse-tabnabbing/referrer-leak regression slips back in.
  const blankAnchors = [
    ...html.matchAll(/<a\b[^>]*target=["']_blank["'][^>]*>/gi),
  ];

  for (const [tag] of blankAnchors) {
    const relMatch = tag.match(/rel=["']([^"']*)["']/i);
    const relValues = (relMatch?.[1] || "").toLowerCase().split(/\s+/);

    if (
      !relValues.includes("noopener") ||
      !relValues.includes("noreferrer")
    ) {
      failed = true;
      console.error(
        `FAIL ${relativePath}: target="_blank" anchor missing rel="noopener noreferrer": ${tag.trim()}`,
      );
    }
  }

  // 2. Dangerous sinks that should never appear in this codebase.
  for (const { name, pattern } of DANGEROUS_PATTERNS) {
    if (pattern.test(html)) {
      failed = true;
      console.error(`FAIL ${relativePath}: found ${name}`);
    }
  }

  // 3. Pages with a <head> should declare a CSP (Report-Only while
  //    this sprint has no browser to verify an enforcing policy is
  //    safe — see docs/security.md — but it must be present).
  if (/<head[\s>]/i.test(html) && !/Content-Security-Policy/i.test(html)) {
    failed = true;
    console.error(`FAIL ${relativePath}: no Content-Security-Policy meta tag found`);
  }

  console.log(`OK   ${relativePath}`);
}

console.log(`\nChecked ${checkedCount} HTML file(s).`);

if (failed) {
  process.exit(1);
}
