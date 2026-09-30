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
 *   npm run import           merge what the addon recorded in-game (SavedVariables,
 *                            /sg export and /sg levels JSON files in .contribute/inbox/)
 *                            into the curated data
 *   npm run import -- FILE   same for one file anywhere
 */
import { existsSync, mkdirSync, readFileSync, readdirSync } from "node:fs";
import { parseArgs } from "node:util";
import { dirname, relative, resolve } from "node:path";
import { INBOX_DIR, ROOT, loadConfig } from "./config.js";
import { Checker, type CuratedFile, loadCurated, serialize, validate } from "./curated.js";
import { loadDiscovered } from "./discovered.js";
import {
  DUNGEON_LEVELS_PATH,
  importDungeonLevels,
  loadDungeonLevels,
  parseDungeonLevelScan,
  validateDungeonLevels,
} from "./dungeon-levels.js";
import { build, write } from "./generate.js";
import { importDiscovered } from "./import.js";
import { saveScannedItems } from "./items.js";
import { writeJson } from "./json.js";
import { type ListFile, loadLists, serializeList, validateLists } from "./lists.js";
import { shipsRecipe } from "./recipes.js";
import { loadReference, relinkRecipes } from "./reference.js";
import { type QuestFile, loadQuests, serializeQuests, validateQuests } from "./quests.js";

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
let dungeonLevels = loadDungeonLevels();
const quests = loadQuests();
const lists = loadLists();
const shippedRecipes = [...ref.recipes.values()].filter((r) => shipsRecipe(r, ref.items)).length;
console.log(
  `build ${ref.build}: ${ref.instances.size} instances, ${ref.encounters.size} encounters; ` +
    `${ref.items.size} scanned items (${ref.itemLocales.join("/") || "no names"}); ` +
    `${ref.recipes.size} recipes of ${ref.skillLines.size} professions, ${shippedRecipes} with scanned items; ` +
    `${curated.length} curated instance(s), ${quests.length} dungeon quest file(s), ${lists.length} list(s)`,
);

let importedDiscovered = false;
for (const path of importPaths) {
  const json = path.toLowerCase().endsWith(".json") ? JSON.parse(readFileSync(path, "utf-8")) : undefined;
  if (json?.kind === "dungeon-levels") {
    const scan = parseDungeonLevelScan(json);
    const result = importDungeonLevels(scan, curated);
    console.log(`importing ${relative(ROOT, path)} (dungeon levels, build ${scan.build})`);
    for (const line of result.lines) console.log(`  ${line}`);
    if (scan.build !== ref.build) console.log(`  scan build differs from pinned reference build ${ref.build}`);
    console.log(`  matched ${Object.keys(result.levels.dungeons).length} dungeon(s)`);
    dungeonLevels = result.levels;
    await writeJson(DUNGEON_LEVELS_PATH, JSON.stringify(dungeonLevels, null, 2) + "\n");
    continue;
  }
  const discovered = loadDiscovered(path);
  importedDiscovered = true;
  console.log(`importing ${relative(ROOT, path)}${discovered.build ? ` (recorded on build ${discovered.build})` : ""}`);
  for (const line of importDiscovered(discovered, ref, curated)) console.log(`  ${line}`);
}
if (importedDiscovered) {
  await saveScannedItems(ref.items);
  relinkRecipes(ref);
}

const checker = new Checker(ref, fix);
validateDungeonLevels(dungeonLevels, curated, checker);
validate(curated, checker);
validateQuests(quests, curated, checker);
validateLists(lists, checker);
const problems = checker.problems;
for (const p of problems)
  console.log(
    `${p.warning ? "warning" : p.fixable ? (fix ? "fixed" : "fixable") : "ERROR"}  ${relative(ROOT, p.file)}: ${p.message}`,
  );
const errors = problems.filter((p) => !p.fixable && !p.warning);
if (fix) await writeCurated(curated, quests, lists);

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
const changed = write(build(ref, curated, quests, lists, config), values.check);
if (values.check) {
  console.log(changed ? "generated addon data is out of date" : "generated addon data is up to date");
  process.exit(changed ? 1 : 0);
}
console.log(changed ? `${changed} file(s) written` : "generated addon data unchanged");

async function writeCurated(files: CuratedFile[], quests: QuestFile[], lists: ListFile[]): Promise<void> {
  for (const file of files) {
    mkdirSync(dirname(file.path), { recursive: true });
    await writeJson(file.path, serialize(file.data));
  }
  for (const file of quests) {
    if (Array.isArray(file.quests) && file.quests.every((q) => q && typeof q === "object" && !Array.isArray(q))) {
      await writeJson(file.path, serializeQuests(file));
    }
  }
  for (const file of lists) await writeJson(file.path, serializeList(file));
}
