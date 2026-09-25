import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, relative, resolve } from "node:path";
import {
  CLIENT_LOCALES,
  type Config,
  DATABASE_OUTPUT_DIR,
  FALLBACK_LOCALE,
  LOCALE_FILES,
  LOCALE_OUTPUT_DIR,
  OUTPUT_DIR,
  ROOT,
} from "./config.js";
import {
  type CuratedFile,
  type CuratedInstance,
  type CuratedLoot,
  type CuratedQuest,
  classToken,
  instanceIDOf,
} from "./curated.js";
import { type ScannedItem } from "./items.js";
import { type ListFile, type ListSection, ROW_FIELDS, rowsOf } from "./lists.js";
import { header, luaFields, luaString, luaValue } from "./lua.js";
import { type Recipe, type SkillLine, shipsRecipe } from "./recipes.js";
import { type Instance, type Reference, nameOf } from "./reference.js";

const DEFAULT_ICONS = {
  dungeon: "Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster",
  raid: "Interface\\Icons\\Achievement_Dungeon_ClassicRaider",
};

const ITEM_LAYOUT =
  "quality, itemLevel, reqLevel, classID, subclassID, slot, bind, icon, stats, sellPrice, stackCount, setID, expansionID, craftingReagent";

/** Item row layout; must match Data.ITEM in ForeverLoot/src/data/data.lua (stats is nil when the item has none). */
function itemRow(item: ScannedItem): unknown[] {
  return [
    item.quality,
    item.itemLevel,
    item.reqLevel,
    item.classID,
    item.subclassID,
    item.slot,
    item.bind,
    item.icon,
    item.stats && Object.keys(item.stats).length > 0 ? item.stats : null,
    item.sellPrice,
    item.stackCount,
    item.setID ?? 0,
    item.expansionID,
    item.craftingReagent,
  ];
}

function emitItems(ids: number[], ref: Reference): string {
  const out = [header(".contribute/items (in-game scans)"), "local Data = ForeverLoot.Data\n\n"];
  out.push(`-- { ${ITEM_LAYOUT} }; see Data.ITEM.\n`);
  out.push("Data:AddItems({\n");
  for (const id of ids) out.push(`    [${id}] = ${luaValue(itemRow(ref.items.get(id)!))},\n`);
  out.push("})\n");
  return out.join("");
}

function emitInstances(ref: Reference, curated: CuratedFile[]): string {
  const out = [header(`wago.tools Map+DungeonEncounter, build ${ref.build}, plus levels/icons from .contribute`)];
  out.push("local Data = ForeverLoot.Data\n");
  const maps = [...ref.instances.keys()].sort((a, b) => a - b);
  for (const map of maps) {
    const inst = ref.instances.get(map)!;
    const files = curated.filter((f) => f.data.map === map);
    const parts = files.filter((f) => f.data.id !== undefined).sort((a, b) => a.data.id! - b.data.id!);
    if (parts.length === 0) {
      out.push(...emitInstance(ref, map, inst, inst.encounters, files[0]?.data));
      continue;
    }
    // A map players see as several dungeons: one instance per file, with the encounters it lists.
    for (const file of parts) {
      const listed = new Set(file.data.encounters.map((e) => e.id));
      out.push(
        ...emitInstance(
          ref,
          file.data.id!,
          inst,
          inst.encounters.filter((id) => listed.has(id)),
          file.data,
        ),
      );
    }
  }
  return out.join("");
}

function emitInstance(
  ref: Reference,
  id: number,
  inst: Instance,
  encounters: number[],
  cur: CuratedInstance | undefined,
): string[] {
  const out: string[] = [];
  out.push(`\n-- ${cur?.id !== undefined ? cur.name : nameOf(ref, "instances", id)}\n`);
  out.push(`Data:AddInstance(${id}, {\n`);
  out.push(
    ...luaFields(
      {
        type: inst.type,
        displayName: cur?.displayName,
        expansionID: inst.expansionID,
        minLevel: cur?.minLevel,
        maxLevel: cur?.maxLevel,
        icon: cur?.icon ?? DEFAULT_ICONS[inst.type],
        background: cur?.background,
        backgroundCoords: cur?.backgroundCoords,
        entrance: cur?.entrance,
      },
      [
        "type",
        "displayName",
        "expansionID",
        "minLevel",
        "maxLevel",
        "icon",
        "background",
        "backgroundCoords",
        "entrance",
      ],
    ).map((l) => l + "\n"),
  );
  out.push(`    bosses = ${luaValue(encounters)},\n})\n`);
  for (const encID of encounters) {
    const enc = ref.encounters.get(encID)!;
    const c = cur?.encounters.find((e) => e.id === encID);
    const fields = luaFields(
      {
        instanceID: id,
        order: enc.order,
        portrait: c?.portrait,
        displayID: c?.displayID,
        level: c?.level,
        creatureType: c?.creatureType,
        quests: c?.quests,
      },
      ["instanceID", "order", "portrait", "displayID", "level", "creatureType", "quests"],
      "",
    )
      .join(" ")
      .replace(/,$/, "");
    out.push(`Data:AddBoss(${encID}, { ${fields} }) -- ${c?.name || nameOf(ref, "encounters", encID)}\n`);
  }
  return out;
}

// Generated provenance comments keep their pre-monorepo paths so a layout-only migration does
// not rewrite every generated file. The real source paths are rooted under .contribute/data/.
function sourceLabel(path: string): string {
  return relative(ROOT, path)
    .replace(/\\/g, "/")
    .replace(/^\.contribute\/data\//, ".contribute/");
}

/** One `{ itemID, chance }` loot row per line, with the item's name as a comment. */
function emitLootRows(rows: CuratedLoot[], ref: Reference, indent: string): string[] {
  const out: string[] = [];
  for (const row of rows) {
    if (row.item === undefined) continue; // name-only row that `npm run fix` hasn't resolved yet
    const chance = row.chance !== undefined ? `, ${luaValue(row.chance)}` : "";
    out.push(`${indent}{ ${row.item}${chance} }, -- ${nameOf(ref, "items", row.item)}\n`);
  }
  return out;
}

/** The quests that can ship: the addon keeps quests by id, one without is left out until it has one. */
function shippedQuests(file: CuratedFile): CuratedQuest[] {
  return (file.data.quests ?? []).filter((q) => q.id !== undefined);
}

/** True when the file has anything to ship: a boss's drops, the instance's trash or a quest. */
export function hasLoot(file: CuratedFile): boolean {
  const d = file.data;
  return d.encounters.some((e) => e.loot?.length) || !!d.trash?.length || shippedQuests(file).length > 0;
}

function emitLoot(file: CuratedFile, ref: Reference): string {
  const rel = sourceLabel(file.path);
  const out = [header(rel), "local Data = ForeverLoot.Data\n"];
  const id = instanceIDOf(file.data);
  out.push(
    `\n-- ${file.data.id !== undefined ? file.data.name : nameOf(ref, "instances", id)} (map ${file.data.map})\n`,
  );
  for (const enc of file.data.encounters) {
    if (!enc.loot?.length) continue;
    out.push(`\nData:AddBossLoot(${enc.id}, { -- ${enc.name || nameOf(ref, "encounters", enc.id)}\n`);
    out.push(...emitLootRows(enc.loot, ref, "    "));
    out.push("})\n");
  }
  // The instance's own two categories, keyed by the map rather than by an encounter.
  if (file.data.trash?.length) {
    out.push(`\nData:AddTrashLoot(${id}, {\n`);
    out.push(...emitLootRows(file.data.trash, ref, "    "));
    out.push("})\n");
  }
  const quests = shippedQuests(file);
  if (quests.length > 0) {
    out.push(`\nData:AddQuests(${id}, {\n`);
    for (const quest of quests) {
      const fields = luaFields(
        { ...quest, class: quest.class && classToken(quest.class) },
        ["id", "name", "side", "class"],
        "",
      ).join(" ");
      const items = emitLootRows(quest.items ?? [], ref, "        ");
      if (items.length === 0) {
        out.push(`    { ${fields} items = {} },\n`);
        continue;
      }
      out.push(`    { ${fields} items = {\n`, ...items, "    } },\n");
    }
    out.push("})\n");
  }
  return out.join("");
}

/** One curated list: its definition, then its rows as `{ itemID, field = value, ... }`. */
function emitList(file: ListFile, ref: Reference): string {
  const rel = sourceLabel(file.path);
  const d = file.data;
  const out = [header(rel), "local Data = ForeverLoot.Data\n"];
  out.push(`\n-- ${d.name}\n`);
  out.push(`Data:AddList(${luaString(file.kind)}, ${luaString(file.slug)}, {\n`);
  out.push(
    ...luaFields(
      {
        name: d.name,
        icon: d.icon ?? (d.skillLine !== undefined ? ref.skillLines.get(d.skillLine)?.icon : undefined),
        background: d.background,
        backgroundCoords: d.backgroundCoords,
        info: d.info,
        order: d.order,
        factionID: d.faction,
        skillLineID: d.skillLine,
      },
      ["name", "icon", "background", "backgroundCoords", "info", "order", "factionID", "skillLineID"],
    ).map((l) => l + "\n"),
  );
  out.push(...emitSections(d.sections, ref));
  if (d.panel && d.panel.length > 0) {
    out.push("    panel = {\n", ...d.panel.map((widget) => `        ${luaValue(widget)},\n`), "    },\n");
  }
  out.push("})\n");
  // Rows without an item are either name-only rows `npm run fix` hasn't resolved yet (dropped) or
  // crafting rows naming a recipe that makes no item (an enchant: kept, the spell is the row).
  const rows = rowsOf(file).filter(
    (row) => row.item !== undefined || (file.kind === "crafting" && row.spell !== undefined),
  );
  if (rows.length > 0) {
    out.push(`Data:AddListLoot(${luaString(file.kind)}, ${luaString(file.slug)}, {\n`);
    for (const row of rows) {
      const fields = luaFields({ ...row }, [...ROW_FIELDS[file.kind], "group"], "").map(
        (f) => `${f.replace(/,$/, "")}`,
      );
      if (row.item !== undefined) fields.unshift(String(row.item));
      const name =
        row.item !== undefined && ref.items.has(row.item)
          ? nameOf(ref, "items", row.item)
          : (row.name ?? ref.recipes.get(row.spell ?? 0)?.name ?? "?");
      out.push(`    { ${fields.join(", ")} }, -- ${name}\n`);
    }
    out.push("})\n");
  }
  return out.join("");
}

/**
 * A crafting list's subheaders: one line per section, with the categories' names as a comment,
 * so the ids stay readable next to the generated recipe file they come from.
 */
function emitSections(sections: ListSection[] | undefined, ref: Reference): string[] {
  if (!sections || sections.length === 0) return [];
  const out = ["    sections = {\n"];
  for (const section of sections) {
    const names = section.categories
      .map((c) => (typeof c === "number" ? (ref.categories.get(c)?.name ?? `#${c}`) : c))
      .join(", ");
    out.push(
      `        { name = ${luaString(section.name)}, categories = ${luaValue(section.categories)} }, -- ${names}\n`,
    );
  }
  out.push("    },\n");
  return out;
}

const RECIPE_LAYOUT =
  "skillLineID, itemID, count, minSkill, yellow, green, grey, categoryID, reagents, tools, auto, taughtBy";

/** The skill needed to learn a recipe: from the recipe item that teaches it, else the ability's own minimum. */
export function learnSkillOf(recipe: Recipe): number {
  return Math.max(recipe.minSkill, recipe.learnSkill);
}

/** Recipe row layout; must match Data.RECIPE in ForeverLoot/src/data/data.lua. */
function recipeRow(recipe: Recipe): unknown[] {
  return [
    recipe.skillLineID,
    recipe.itemID,
    recipe.count,
    learnSkillOf(recipe),
    recipe.yellow,
    recipe.green,
    recipe.grey,
    recipe.categoryID,
    recipe.reagents.length > 0 ? recipe.reagents.flat() : null,
    recipe.tools.length > 0 ? recipe.tools : null,
    recipe.auto ? true : null,
    recipe.taughtBy > 0 ? recipe.taughtBy : null,
  ];
}

/** Trims the trailing nils a positional row would otherwise end with. */
function trimRow(row: unknown[]): unknown[] {
  let end = row.length;
  while (end > 0 && (row[end - 1] === null || row[end - 1] === undefined)) end--;
  return row.slice(0, end);
}

/** One profession: its trade skill categories (for group order) and the recipes the scans confirm. */
function emitRecipes(skillLine: SkillLine, recipes: Recipe[], ref: Reference): string {
  const out = [
    header(`wago.tools SkillLineAbility/SpellReagents/SpellEffect, build ${ref.build}`),
    "local Data = ForeverLoot.Data\n",
  ];
  out.push(`\n-- ${skillLine.name} (SkillLine ${skillLine.id})\n`);
  const categories = [...ref.categories.values()]
    .filter((c) => c.skillLineID === skillLine.id)
    .sort((a, b) => a.order - b.order || a.id - b.id);
  if (categories.length > 0) {
    out.push("Data:AddCategories({\n");
    for (const c of categories)
      out.push(`    [${c.id}] = { skillLineID = ${c.skillLineID}, order = ${c.order} }, -- ${c.name}\n`);
    out.push("})\n");
  }
  const orderOf = (r: Recipe) => ref.categories.get(r.categoryID)?.order ?? Number.MAX_SAFE_INTEGER;
  const sorted = [...recipes].sort(
    (a, b) =>
      orderOf(a) - orderOf(b) ||
      a.categoryID - b.categoryID ||
      learnSkillOf(a) - learnSkillOf(b) ||
      a.yellow - b.yellow ||
      a.spellID - b.spellID,
  );
  out.push(`-- { ${RECIPE_LAYOUT} }; see Data.RECIPE. Keyed by the recipe's spell id.\n`);
  out.push("Data:AddRecipes({\n");
  for (const r of sorted) out.push(`    [${r.spellID}] = ${luaValue(trimRow(recipeRow(r)))}, -- ${r.name}\n`);
  out.push("})\n");
  return out.join("");
}

/** The localized names the crafting pages need: professions, trade skill categories and tools. */
function emitCraftingNames(locale: string, ref: Reference, skillLines: SkillLine[], recipes: Recipe[]): string {
  const names = ref.names.get(locale)!;
  const out = [header(`wago.tools SkillLine/TradeSkillCategory/TotemCategory, build ${ref.build}, locale ${locale}`)];
  if (locale !== FALLBACK_LOCALE) out.push(`if GetLocale() ~= "${locale}" then\n    return\nend\n`);
  out.push("local Data = ForeverLoot.Data\n");
  const shipped = new Set(skillLines.map((s) => s.id));
  const tools = new Set(recipes.flatMap((r) => r.tools));
  const tables: [string, Map<number, string>, (id: number) => boolean][] = [
    ["skillLines", names.skillLines, (id) => shipped.has(id)],
    ["categories", names.categories, (id) => shipped.has(ref.categories.get(id)?.skillLineID ?? 0)],
    ["tools", names.tools, (id) => tools.has(id)],
  ];
  for (const [kind, table, wanted] of tables) {
    out.push(`\nData:AddNames("${locale}", "${kind}", {\n`);
    for (const id of [...table.keys()].filter(wanted).sort((a, b) => a - b))
      out.push(`    [${id}] = ${luaString(table.get(id)!)},\n`);
    out.push("})\n");
  }
  return out.join("");
}

function emitNames(
  locale: string,
  kind: "items" | "bosses" | "instances",
  table: Map<number, string>,
  source: string,
): string {
  const out = [header(`${source}, locale ${locale}`)];
  if (locale !== FALLBACK_LOCALE) out.push(`if GetLocale() ~= "${locale}" then\n    return\nend\n`);
  out.push("local Data = ForeverLoot.Data\n\n");
  out.push(`Data:AddNames("${locale}", "${kind}", {\n`);
  for (const id of [...table.keys()].sort((a, b) => a - b)) out.push(`    [${id}] = ${luaString(table.get(id)!)},\n`);
  out.push("})\n");
  return out.join("");
}

function emitXml(files: string[]): string {
  const lines = [
    '<Ui xmlns="http://www.blizzard.com/wow/ui/">',
    "\t<!-- Generated by .contribute/tools (npm run gen) - do not edit. -->",
  ];
  for (const f of files) lines.push(`\t<Script file="${f.replace(/\//g, "\\")}" />`);
  lines.push("</Ui>");
  return lines.join("\n") + "\n";
}

export interface GeneratedFiles {
  core: Map<string, string>;
  locale: Map<string, string>;
  database: Map<string, string>;
}

/** Builds the three generated addon trees in memory, keyed by paths relative to their generated directory. */
export function build(ref: Reference, curated: CuratedFile[], lists: ListFile[], config: Config): GeneratedFiles {
  const core = new Map<string, string>();
  const locale = new Map<string, string>();
  const database = new Map<string, string>();
  const coreOrder: string[] = [];
  const databaseOrder: string[] = [];
  const addCore = (path: string, content: string) => {
    core.set(path, content);
    coreOrder.push(path);
  };
  // No loader for the locale addon: its TOC lists locales\[TextLocale]\*.lua, so the client
  // loads only its own language's files.
  const addLocale = (path: string, content: string) => {
    locale.set(path, content);
  };
  const addDatabase = (path: string, content: string) => {
    database.set(path, content);
    databaseOrder.push(path);
  };

  // Every scanned item row lives in the database addon; the core's lists get what they show
  // from the client (and from these rows when the database addon is installed).
  const itemIDs = [...ref.items.keys()].sort((a, b) => a - b);
  const chunks: number[][] = [];
  for (let i = 0; i < itemIDs.length; i += config.itemsPerFile) chunks.push(itemIDs.slice(i, i + config.itemsPerFile));
  chunks.forEach((chunk, i) => addDatabase(`items/items_${String(i + 1).padStart(3, "0")}.lua`, emitItems(chunk, ref)));

  addCore("instances.lua", emitInstances(ref, curated));

  for (const file of [...curated].sort((a, b) => a.slug.localeCompare(b.slug))) {
    if (hasLoot(file)) addCore(`loot/${file.slug}.lua`, emitLoot(file, ref));
  }

  // Every list file becomes a tile in its module, rows or not (an empty one asks for contributions).
  for (const file of [...lists].sort((a, b) => a.kind.localeCompare(b.kind) || a.slug.localeCompare(b.slug))) {
    addCore(`${file.kind}/${file.slug}.lua`, emitList(file, ref));
  }

  // Profession recipes, one file per profession that has any the scans confirm; the crafting
  // module merges them with the curated crafting lists at runtime.
  const recipes = [...ref.recipes.values()].filter((r) => shipsRecipe(r, ref.items));
  const skillLines: SkillLine[] = [];
  for (const skillLine of [...ref.skillLines.values()].sort((a, b) => a.slug.localeCompare(b.slug))) {
    const own = recipes.filter((r) => r.skillLineID === skillLine.id);
    if (own.length === 0) continue;
    skillLines.push(skillLine);
    addCore(`recipes/${skillLine.slug}.lua`, emitRecipes(skillLine, own, ref));
  }

  // English item names go with the item rows into the database addon (the core's lists take an
  // item's name from the client). Every other locale is the locale addon's: item names from
  // wago.tools' ItemSparse for the configured locales, and from in-game scans on a client of that
  // language (see refreshItemNames).
  for (const locale of ref.itemLocales) {
    const add = locale === FALLBACK_LOCALE ? addDatabase : addLocale;
    const source =
      locale === FALLBACK_LOCALE
        ? ".contribute/items (in-game scans)"
        : `.contribute/items (in-game scans) and wago.tools ItemSparse build ${ref.build}`;
    add(`locales/${locale}/items.lua`, emitNames(locale, "items", ref.names.get(locale)!.items, source));
  }
  // Bosses an instance file names differently from the game table (renamed by the server): the
  // file's name in every language, since the table's names for them are all the outdated one.
  const renamed = new Map<number, string>();
  for (const file of curated) {
    for (const enc of file.data.encounters) {
      if (enc.name && enc.name !== nameOf(ref, "encounters", enc.id)) renamed.set(enc.id, enc.name);
    }
  }
  for (const locale of config.locales) {
    const names = ref.names.get(locale)!;
    const add = locale === FALLBACK_LOCALE ? addCore : addLocale;
    const bosses = new Map(names.encounters);
    for (const [id, name] of renamed) {
      if (locale === FALLBACK_LOCALE) bosses.set(id, name);
      else bosses.delete(id); // falls back to the English one
    }
    // The parts of a split map have no name in the game's tables: the file's name is the English one.
    const parts =
      locale === FALLBACK_LOCALE
        ? curated.filter((f) => f.data.id !== undefined).map((f): [number, string] => [f.data.id!, f.data.name!])
        : [];
    add(
      `locales/${locale}/instances.lua`,
      emitNames(locale, "instances", new Map([...names.instances, ...parts]), `wago.tools build ${ref.build}`),
    );
    add(`locales/${locale}/bosses.lua`, emitNames(locale, "bosses", bosses, `wago.tools build ${ref.build}`));
    add(`locales/${locale}/crafting.lua`, emitCraftingNames(locale, ref, skillLines, recipes));
  }

  // The TOC's [TextLocale] entries need every file for every client language, or the client
  // warns at login (enUS/enGB have no names here at all, a scanned-only locale only items).
  for (const clientLocale of CLIENT_LOCALES) {
    for (const file of LOCALE_FILES) {
      const path = `locales/${clientLocale}/${file}`;
      if (!locale.has(path))
        addLocale(
          path,
          "-- Generated by .contribute/tools (npm run gen) - do not edit.\n" +
            `-- Placeholder: no ${clientLocale} names of this kind; the TOC's [TextLocale] entry needs the file.\n`,
        );
    }
  }

  core.set("generated.xml", emitXml(coreOrder));
  database.set("generated.xml", emitXml(databaseOrder));
  return { core, locale, database };
}

/** Writes the three addon trees, removes stale files, and returns the number of changed files. */
export function write(files: GeneratedFiles, check: boolean): number {
  return (
    writeTree(files.core, OUTPUT_DIR, "ForeverLoot/db/generated", check) +
    writeTree(files.locale, LOCALE_OUTPUT_DIR, "ForeverLoot_Locale/db/generated", check) +
    writeTree(files.database, DATABASE_OUTPUT_DIR, "ForeverLoot_Database/db/generated", check)
  );
}

function writeTree(files: Map<string, string>, outputDir: string, displayDir: string, check: boolean): number {
  let changed = 0;
  const existing = new Set<string>();
  const walk = (dir: string) => {
    if (!existsSync(dir)) return;
    for (const entry of readdirSync(dir)) {
      const p = resolve(dir, entry);
      if (statSync(p).isDirectory()) walk(p);
      else existing.add(relative(outputDir, p).replace(/\\/g, "/"));
    }
  };
  walk(outputDir);

  for (const rel of [...existing].filter((p) => !files.has(p)).sort()) {
    changed++;
    if (check) console.log(`stale: ${displayDir}/${rel}`);
    else {
      rmSync(resolve(outputDir, rel));
      console.log(`removed ${displayDir}/${rel}`);
    }
  }
  for (const [rel, content] of files) {
    const path = resolve(outputDir, rel);
    // A checkout with core.autocrlf has CRLF on disk; that is not a content change.
    if (existsSync(path) && readFileSync(path, "utf-8").replace(/\r\n/g, "\n") === content) continue;
    changed++;
    if (check) console.log(`outdated: ${displayDir}/${rel}`);
    else {
      mkdirSync(dirname(path), { recursive: true });
      writeFileSync(path, content, "utf-8");
      console.log(`wrote ${displayDir}/${rel}`);
    }
  }
  return changed;
}
