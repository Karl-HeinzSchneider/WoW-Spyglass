import { readFileSync } from "node:fs";
import { extname } from "node:path";
import { FALLBACK_LOCALE } from "./config.js";
import { type ScannedItem } from "./items.js";
import { type LuaValue, luaGet, parseSavedVariables } from "./savedvars.js";

/**
 * What the addon recorded in-game (`ForeverLootDB.global.discovered`, see src/core/discovery.lua):
 * scanned items with everything GetItemInfo/GetItemStats return, and per boss (DungeonEncounter
 * id) how often it was killed and which items were seen dropping. `/fl export` writes the same
 * shape as JSON.
 */
export interface Discovered {
  build?: string;
  /** GetLocale() of the recording client: the language of every item name. */
  locale: string;
  items: Map<number, DiscoveredItem>;
  loot: Map<number, DiscoveredLoot>;
}

/** A scanned item as recorded: one name, in `Discovered.locale`. */
export type DiscoveredItem = Omit<ScannedItem, "names"> & { name: string };

export interface DiscoveredLoot {
  kills: number;
  /** itemID -> kills in which it was seen */
  items: Map<number, number>;
}

/** A Lua table from SavedVariables or a JSON object: entries with their keys as numbers. */
function numericEntries(value: unknown): [number, unknown][] {
  const raw: [unknown, unknown][] = value instanceof Map ? [...value] : value && typeof value === "object" ? Object.entries(value) : [];
  const out: [number, unknown][] = [];
  for (const [key, entry] of raw) {
    const id = Number(key);
    if (Number.isInteger(id) && id > 0) out.push([id, entry]);
  }
  return out;
}

function field(value: unknown, key: string): unknown {
  if (value instanceof Map) return value.get(key);
  if (value && typeof value === "object") return (value as Record<string, unknown>)[key];
  return undefined;
}

function num(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function stats(value: unknown): Record<string, number> | undefined {
  const entries: [unknown, unknown][] = value instanceof Map ? [...value] : value && typeof value === "object" ? Object.entries(value) : [];
  const out: Record<string, number> = {};
  let any = false;
  for (const [key, v] of entries) {
    if (typeof key === "string" && typeof v === "number" && Number.isFinite(v) && v !== 0) {
      out[key] = v;
      any = true;
    }
  }
  return any ? out : undefined;
}

function normalize(root: unknown, source: string): Discovered {
  const items = new Map<number, DiscoveredItem>();
  for (const [id, entry] of numericEntries(field(root, "items"))) {
    const name = field(entry, "name");
    if (typeof name !== "string" || name === "") continue;
    const slot = field(entry, "slot");
    items.set(id, {
      name,
      quality: num(field(entry, "quality"), 1),
      itemLevel: num(field(entry, "itemLevel"), 1),
      reqLevel: num(field(entry, "reqLevel")),
      classID: num(field(entry, "classID")),
      subclassID: num(field(entry, "subclassID")),
      slot: typeof slot === "string" ? slot : "",
      bind: num(field(entry, "bind")),
      icon: num(field(entry, "icon")),
      sellPrice: num(field(entry, "sellPrice")),
      stackCount: num(field(entry, "stackCount"), 1),
      setID: num(field(entry, "setID")),
      expansionID: num(field(entry, "expansionID")),
      craftingReagent: field(entry, "craftingReagent") === true,
      stats: stats(field(entry, "stats")),
    });
  }
  const loot = new Map<number, DiscoveredLoot>();
  for (const [encounterID, entry] of numericEntries(field(root, "loot"))) {
    const seen = new Map<number, number>();
    for (const [itemID, count] of numericEntries(field(entry, "items"))) {
      const n = num(count);
      if (n > 0) seen.set(itemID, n);
    }
    loot.set(encounterID, { kills: num(field(entry, "kills")), items: seen });
  }
  if (items.size === 0 && loot.size === 0) throw new Error(`${source}: nothing recorded in it`);
  const build = field(root, "build");
  const locale = field(root, "locale");
  return {
    build: typeof build === "string" ? build : undefined,
    locale: typeof locale === "string" && locale !== "" ? locale : FALLBACK_LOCALE,
    items,
    loot,
  };
}

/**
 * Loads a SavedVariables file (`ForeverLoot.lua`, uses `ForeverLootDB.global.discovered`) or a
 * `/fl export` JSON file.
 */
export function loadDiscovered(path: string): Discovered {
  const text = readFileSync(path, "utf-8");
  if (extname(path).toLowerCase() === ".json") return normalize(JSON.parse(text), path);
  const globals: Map<string, LuaValue> = parseSavedVariables(text);
  const discovered = luaGet(globals.get("ForeverLootDB"), "global", "discovered");
  if (!discovered) throw new Error(`${path}: no ForeverLootDB.global.discovered in it (is it ForeverLoot's SavedVariables file, written after a /reload or logout?)`);
  return normalize(discovered, path);
}
