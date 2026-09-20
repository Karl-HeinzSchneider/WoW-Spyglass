#!/usr/bin/env node
/**
 * ForeverLoot database tools.
 *
 *   npm run gen              wago.tools Map/DungeonEncounter (cached) + .contribute/ -> db/generated/
 *   npm run gen -- --check   exit 1 if db/generated/ is out of date (CI)
 *   npm run check            validate the curated loot files against the game data and the scans
 *   npm run fix              same, and rewrite names / add missing encounters
 *   npm run import -- FILE   merge what the addon recorded in-game (a SavedVariables
 *                            ForeverLoot.lua or a /fl export JSON) into .contribute/items/ and
 *                            the curated loot files
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { parseArgs } from "node:util";
import { dirname, relative } from "node:path";
import { ROOT, loadConfig } from "./config.js";
import { type CuratedFile, loadCurated, serialize, validate } from "./curated.js";
import { loadDiscovered } from "./discovered.js";
import { build, write } from "./generate.js";
import { importDiscovered } from "./import.js";
import { saveScannedItems } from "./items.js";
import { loadReference } from "./reference.js";

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: { check: { type: "boolean", default: false }, fix: { type: "boolean", default: false } },
});
const command = positionals[0] ?? "generate";
if (!["generate", "check", "import"].includes(command)) {
  console.error(`unknown command ${command}`);
  process.exit(2);
}
const importPath = command === "import" ? positionals[1] : undefined;
if (command === "import" && !importPath) {
  console.error("usage: npm run import -- <SavedVariables ForeverLoot.lua or export .json>");
  process.exit(2);
}
// `import` always fixes: it writes the curated files anyway.
const fix = values.fix || command === "import";

const config = loadConfig();
const ref = await loadReference(config);
const curated = loadCurated();
console.log(
  `build ${ref.build}: ${ref.instances.size} instances, ${ref.encounters.size} encounters; ` +
    `${ref.items.size} scanned items (${ref.itemLocales.join("/") || "no names"}); ${curated.length} curated file(s)`,
);

if (importPath) {
  const discovered = loadDiscovered(importPath);
  console.log(`importing ${importPath}${discovered.build ? ` (recorded on build ${discovered.build})` : ""}`);
  for (const line of importDiscovered(discovered, ref, curated)) console.log(`  ${line}`);
  saveScannedItems(ref.items);
}

const problems = validate(curated, ref, fix);
for (const p of problems) console.log(`${p.warning ? "warning" : p.fixable ? (fix ? "fixed" : "fixable") : "ERROR"}  ${relative(ROOT, p.file)}: ${p.message}`);
const errors = problems.filter((p) => !p.fixable && !p.warning);
if (fix) writeCurated(curated);

if (command === "check") {
  console.log(errors.length ? `${errors.length} error(s)` : "curated files OK");
  process.exit(errors.length ? 1 : 0);
}
if (command === "import") {
  console.log(errors.length ? `${errors.length} error(s); fix them, then run npm run gen` : "imported; now run npm run gen");
  process.exit(errors.length ? 1 : 0);
}
if (errors.length) {
  console.error(`${errors.length} error(s) in curated files; not generating`);
  process.exit(1);
}
const changed = write(build(ref, curated, config), values.check);
if (values.check) {
  console.log(changed ? "db/generated is out of date" : "db/generated is up to date");
  process.exit(changed ? 1 : 0);
}
console.log(changed ? `${changed} file(s) written` : "db/generated unchanged");

function writeCurated(files: CuratedFile[]): void {
  for (const file of files) {
    mkdirSync(dirname(file.path), { recursive: true });
    writeFileSync(file.path, serialize(file.data), "utf-8");
  }
}
