#!/usr/bin/env node
/**
 * ForeverLoot database tools.
 *
 *   npm run gen           download wago.tools tables (cached) + .contribute/*.json -> db/generated/
 *   npm run gen -- --check   exit 1 if db/generated/ is out of date (CI)
 *   npm run check         validate the curated files against the game data
 *   npm run fix           same, and rewrite names / add missing encounters
 */
import { writeFileSync } from "node:fs";
import { parseArgs } from "node:util";
import { relative } from "node:path";
import { loadConfig, ROOT } from "./config.js";
import { loadCurated, serialize, validate } from "./curated.js";
import { build, write } from "./generate.js";
import { loadReference } from "./reference.js";

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: { check: { type: "boolean", default: false }, fix: { type: "boolean", default: false } },
});
const command = positionals[0] ?? "generate";

const config = loadConfig();
const ref = await loadReference(config);
const curated = loadCurated();
console.log(
  `build ${ref.build}: ${ref.instances.size} instances, ${ref.encounters.size} encounters, ${ref.items.size} items, ` +
    `${config.locales.join("/")}; ${curated.length} curated file(s)`,
);

const problems = validate(curated, ref, values.fix);
for (const p of problems) console.log(`${p.fixable ? (values.fix ? "fixed" : "fixable") : "ERROR"}  ${relative(ROOT, p.file)}: ${p.message}`);
const errors = problems.filter((p) => !p.fixable);
if (values.fix) {
  for (const file of curated) writeFileSync(file.path, serialize(file.data), "utf-8");
}

if (command === "check") {
  console.log(errors.length ? `${errors.length} error(s)` : "curated files OK");
  process.exit(errors.length ? 1 : 0);
}
if (command !== "generate") {
  console.error(`unknown command ${command}`);
  process.exit(2);
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
