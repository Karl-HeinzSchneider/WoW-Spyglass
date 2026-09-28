#!/usr/bin/env node
/**
 * Spyglass database tools.
 *
 *   npm run gen              wago.tools Map/DungeonEncounter (cached) + .contribute/data/ -> <addon>/db/generated/
 *                            (Spyglass, Spyglass_Locale, Spyglass_Database)
 *   npm run generate:check   exit 1 if generated files are out of date (CI)
 *   npm run check            validate the curated files (instances and item lists) against the
 *                            game data and the scans
 *   npm run fix              same, and rewrite names / add missing encounters
 *   npm run import           merge what the addon recorded in-game (SavedVariables
 *                            Spyglass_Scraper.lua and /sg export JSON files in .contribute/inbox/)
 *                            into .contribute/data/items/ and the curated loot files
 *   npm run import -- FILE   same for one file anywhere
 */
import { existsSync, mkdirSync, readdirSync } from "node:fs";
import { parseArgs } from "node:util";
import { dirname, relative, resolve } from "node:path";
import { INBOX_DIR, ROOT, loadConfig } from "./config.js";
import { Checker, type CuratedFile, loadCurated, serialize, validate } from "./curated.js";
import { loadDiscovered } from "./discovered.js";
import { build, write } from "./generate.js";
import { importDiscovered } from "./import.js";
import { saveScannedItems } from "./items.js";
import { writeJson } from "./json.js";
import { type ListFile, loadLists, serializeList, validateLists } from "./lists.js";
import { type QuestFile, loadQuests, questDefinitions, serializeQuestFile, validateQuests } from "./quests.js";
import { shipsRecipe } from "./recipes.js";
import { loadReference, relinkRecipes } from "./reference.js";

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: { check: { type: "boolean", default: false }, fix: { type: "boolean", default: false } },
});
const command = positionals[0] ?? "generate";
if (!["generate", "check", "import"].includes(command)) {
  console.error(`unknown command ${command}`);
  process.exit(2);
}
// `npm run import -- <file>` imports that file; without one, every .lua/.json in .contribute/inbox/.
const importPaths: string[] = [];
if (command === "import") {
  if (positionals[1]) importPaths.push(positionals[1]);
  else if (existsSync(INBOX_DIR)) {
    for (const entry of readdirSync(INBOX_DIR).sort()) {
      if (/\.(lua|json)$/i.test(entry)) importPaths.push(resolve(INBOX_DIR, entry));
    }
  }
  if (importPaths.length === 0) {
    console.error(
      `nothing to import: put a SavedVariables Spyglass_Scraper.lua or a /sg export .json into ${relative(ROOT, INBOX_DIR)}/, or pass a path`,
    );
    process.exit(2);
  }
}
// `import` always fixes: it writes the curated files anyway.
const fix = values.fix || command === "import";

const config = loadConfig();
const ref = await loadReference(config);
const curated = loadCurated();
const lists = loadLists();
const quests = loadQuests();
const shippedRecipes = [...ref.recipes.values()].filter((r) => shipsRecipe(r, ref.items)).length;
console.log(
  `build ${ref.build}: ${ref.instances.size} instances, ${ref.encounters.size} encounters; ` +
    `${ref.items.size} scanned items (${ref.itemLocales.join("/") || "no names"}); ` +
    `${ref.recipes.size} recipes of ${ref.skillLines.size} professions, ${shippedRecipes} with scanned items; ` +
    `${curated.length} curated instance(s), ${questDefinitions(quests).size} quest(s), ${lists.length} list(s)`,
);

for (const path of importPaths) {
  const discovered = loadDiscovered(path);
  console.log(`importing ${relative(ROOT, path)}${discovered.build ? ` (recorded on build ${discovered.build})` : ""}`);
  for (const line of importDiscovered(discovered, ref, curated)) console.log(`  ${line}`);
}
if (importPaths.length > 0) {
  await saveScannedItems(ref.items);
  relinkRecipes(ref);
}

const checker = new Checker(ref, fix);
validate(curated, checker);
validateLists(lists, checker);
validateQuests(quests, curated, checker);
const problems = checker.problems;
for (const p of problems)
  console.log(
    `${p.warning ? "warning" : p.fixable ? (fix ? "fixed" : "fixable") : "ERROR"}  ${relative(ROOT, p.file)}: ${p.message}`,
  );
const errors = problems.filter((p) => !p.fixable && !p.warning);
if (fix) await writeCurated(curated, lists, quests);

if (command === "check") {
  console.log(errors.length ? `${errors.length} error(s)` : "curated files OK");
  process.exit(errors.length ? 1 : 0);
}
if (command === "import") {
  console.log(
    errors.length ? `${errors.length} error(s); fix them, then run npm run gen` : "imported; now run npm run gen",
  );
  process.exit(errors.length ? 1 : 0);
}
if (errors.length) {
  console.error(`${errors.length} error(s) in curated files; not generating`);
  process.exit(1);
}
const changed = write(build(ref, curated, lists, quests, config), values.check);
if (values.check) {
  console.log(changed ? "generated addon data is out of date" : "generated addon data is up to date");
  process.exit(changed ? 1 : 0);
}
console.log(changed ? `${changed} file(s) written` : "generated addon data unchanged");

async function writeCurated(files: CuratedFile[], lists: ListFile[], quests: QuestFile[]): Promise<void> {
  for (const file of files) {
    mkdirSync(dirname(file.path), { recursive: true });
    await writeJson(file.path, serialize(file.data));
  }
  for (const file of lists) await writeJson(file.path, serializeList(file));
  for (const file of quests) await writeJson(file.path, serializeQuestFile(file));
}
