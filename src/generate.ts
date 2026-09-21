import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, relative, resolve } from "node:path";
import { type Config, FALLBACK_LOCALE, OUTPUT_DIR, ROOT } from "./config.js";
import { type CuratedFile } from "./curated.js";
import { type ScannedItem } from "./items.js";
import { type ListFile, ROW_FIELDS, rowsOf } from "./lists.js";
import { header, luaFields, luaString, luaValue } from "./lua.js";
import { type Reference, nameOf } from "./reference.js";

const DEFAULT_ICONS = {
  dungeon: "Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster",
  raid: "Interface\\Icons\\Achievement_Dungeon_ClassicRaider",
};

const ITEM_LAYOUT = "quality, itemLevel, reqLevel, classID, subclassID, slot, bind, icon, stats, sellPrice, stackCount, setID, expansionID, craftingReagent";

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

function emitInstances(ref: Reference, curated: Map<number, CuratedFile>): string {
  const out = [header(`wago.tools Map+DungeonEncounter, build ${ref.build}, plus levels/icons from .contribute`)];
  out.push("local Data = ForeverLoot.Data\n");
  const ids = [...ref.instances.keys()].sort((a, b) => a - b);
  for (const id of ids) {
    const inst = ref.instances.get(id)!;
    const cur = curated.get(id)?.data;
    out.push(`\n-- ${nameOf(ref, "instances", id)}\n`);
    out.push(`Data:AddInstance(${id}, {\n`);
    out.push(
      ...luaFields(
        {
          type: inst.type,
          expansionID: inst.expansionID,
          minLevel: cur?.minLevel,
          maxLevel: cur?.maxLevel,
          icon: cur?.icon ?? DEFAULT_ICONS[inst.type],
          background: cur?.background,
          backgroundCoords: cur?.backgroundCoords,
        },
        ["type", "expansionID", "minLevel", "maxLevel", "icon", "background", "backgroundCoords"],
      ).map((l) => l + "\n"),
    );
    out.push(`    bosses = ${luaValue(inst.encounters)},\n})\n`);
    for (const encID of inst.encounters) {
      const enc = ref.encounters.get(encID)!;
      const c = cur?.encounters.find((e) => e.id === encID);
      const fields = luaFields(
        { instanceID: id, order: enc.order, portrait: c?.portrait, level: c?.level, creatureType: c?.creatureType, quests: c?.quests },
        ["instanceID", "order", "portrait", "level", "creatureType", "quests"],
        "",
      )
        .join(" ")
        .replace(/,$/, "");
      out.push(`Data:AddBoss(${encID}, { ${fields} }) -- ${nameOf(ref, "encounters", encID)}\n`);
    }
  }
  return out.join("");
}

// Generated provenance comments keep their pre-monorepo paths so a layout-only migration does
// not rewrite every generated file. The real source paths are rooted under .contribute/data/.
function sourceLabel(path: string): string {
  return relative(ROOT, path).replace(/\\/g, "/").replace(/^\.contribute\/data\//, ".contribute/");
}

function emitLoot(file: CuratedFile, ref: Reference): string {
  const rel = sourceLabel(file.path);
  const out = [header(rel), "local Data = ForeverLoot.Data\n"];
  out.push(`\n-- ${nameOf(ref, "instances", file.data.map)} (map ${file.data.map})\n`);
  for (const enc of file.data.encounters) {
    if (!enc.loot?.length) continue;
    out.push(`\nData:AddBossLoot(${enc.id}, { -- ${nameOf(ref, "encounters", enc.id)}\n`);
    for (const row of enc.loot) {
      if (row.item === undefined) continue; // name-only row that `npm run fix` hasn't resolved yet
      const chance = row.chance !== undefined ? `, ${luaValue(row.chance)}` : "";
      out.push(`    { ${row.item}${chance} }, -- ${nameOf(ref, "items", row.item)}\n`);
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
        icon: d.icon,
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
  out.push("})\n");
  const rows = rowsOf(file).filter((row) => row.item !== undefined); // name-only rows that `npm run fix` hasn't resolved yet
  if (rows.length > 0) {
    out.push(`Data:AddListLoot(${luaString(file.kind)}, ${luaString(file.slug)}, {\n`);
    for (const row of rows) {
      const fields = luaFields({ ...row }, [...ROW_FIELDS[file.kind], "group"], "").map((f) => `, ${f.replace(/,$/, "")}`);
      const name = ref.items.has(row.item!) ? nameOf(ref, "items", row.item!) : (row.name ?? "?");
      out.push(`    { ${row.item}${fields.join("")} }, -- ${name}\n`);
    }
    out.push("})\n");
  }
  return out.join("");
}

function emitNames(locale: string, kind: "items" | "bosses" | "instances", table: Map<number, string>, source: string): string {
  const out = [header(`${source}, locale ${locale}`)];
  if (locale !== FALLBACK_LOCALE) out.push(`if GetLocale() ~= "${locale}" then\n    return\nend\n`);
  out.push("local Data = ForeverLoot.Data\n\n");
  out.push(`Data:AddNames("${locale}", "${kind}", {\n`);
  for (const id of [...table.keys()].sort((a, b) => a - b)) out.push(`    [${id}] = ${luaString(table.get(id)!)},\n`);
  out.push("})\n");
  return out.join("");
}

function emitXml(files: string[]): string {
  const lines = ['<Ui xmlns="http://www.blizzard.com/wow/ui/">', "\t<!-- Generated by .contribute/tools (npm run gen) - do not edit. -->"];
  for (const f of files) lines.push(`\t<Script file="${f.replace(/\//g, "\\")}" />`);
  lines.push("</Ui>");
  return lines.join("\n") + "\n";
}

/** Builds every output file in memory: { path relative to ForeverLoot/db/generated : content }. */
export function build(ref: Reference, curated: CuratedFile[], lists: ListFile[], config: Config): Map<string, string> {
  const files = new Map<string, string>();
  const order: string[] = [];
  const add = (path: string, content: string) => {
    files.set(path, content);
    order.push(path);
  };

  const itemIDs = [...ref.items.keys()].sort((a, b) => a - b);
  const chunks: number[][] = [];
  for (let i = 0; i < itemIDs.length; i += config.itemsPerFile) chunks.push(itemIDs.slice(i, i + config.itemsPerFile));
  chunks.forEach((chunk, i) => add(`items/items_${String(i + 1).padStart(3, "0")}.lua`, emitItems(chunk, ref)));

  const byMap = new Map(curated.map((f) => [f.data.map, f]));
  add("instances.lua", emitInstances(ref, byMap));

  for (const file of [...curated].sort((a, b) => a.slug.localeCompare(b.slug))) {
    if (file.data.encounters.some((e) => e.loot?.length)) add(`loot/${file.slug}.lua`, emitLoot(file, ref));
  }

  // Every list file becomes a tile in its module, rows or not (an empty one asks for contributions).
  for (const file of [...lists].sort((a, b) => a.kind.localeCompare(b.kind) || a.slug.localeCompare(b.slug))) {
    add(`${file.kind}/${file.slug}.lua`, emitList(file, ref));
  }

  // Item names exist for the locales that were scanned; instance/boss names for the configured ones.
  for (const locale of ref.itemLocales) {
    add(`locales/${locale}/items.lua`, emitNames(locale, "items", ref.names.get(locale)!.items, ".contribute/items (in-game scans)"));
  }
  for (const locale of config.locales) {
    const names = ref.names.get(locale)!;
    add(`locales/${locale}/instances.lua`, emitNames(locale, "instances", names.instances, `wago.tools build ${ref.build}`));
    add(`locales/${locale}/bosses.lua`, emitNames(locale, "bosses", names.encounters, `wago.tools build ${ref.build}`));
  }

  files.set("generated.xml", emitXml(order));
  return files;
}

/** Writes the files, removes stale ones; returns the number of files that changed. */
export function write(files: Map<string, string>, check: boolean): number {
  let changed = 0;
  const existing = new Set<string>();
  const walk = (dir: string) => {
    if (!existsSync(dir)) return;
    for (const entry of readdirSync(dir)) {
      const p = resolve(dir, entry);
      if (statSync(p).isDirectory()) walk(p);
      else existing.add(relative(OUTPUT_DIR, p).replace(/\\/g, "/"));
    }
  };
  walk(OUTPUT_DIR);

  for (const rel of [...existing].filter((p) => !files.has(p)).sort()) {
    changed++;
    if (check) console.log(`stale: ForeverLoot/db/generated/${rel}`);
    else {
      rmSync(resolve(OUTPUT_DIR, rel));
      console.log(`removed ForeverLoot/db/generated/${rel}`);
    }
  }
  for (const [rel, content] of files) {
    const path = resolve(OUTPUT_DIR, rel);
    // A checkout with core.autocrlf has CRLF on disk; that is not a content change.
    if (existsSync(path) && readFileSync(path, "utf-8").replace(/\r\n/g, "\n") === content) continue;
    changed++;
    if (check) console.log(`outdated: ForeverLoot/db/generated/${rel}`);
    else {
      mkdirSync(dirname(path), { recursive: true });
      writeFileSync(path, content, "utf-8");
      console.log(`wrote ForeverLoot/db/generated/${rel}`);
    }
  }
  return changed;
}
