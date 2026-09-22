import { type Config, FALLBACK_LOCALE } from "./config.js";
import { type ScannedItem, loadScannedItems } from "./items.js";
import { type Recipe, type SkillLine, type TradeSkillCategory, loadRecipes } from "./recipes.js";
import { fetchTable, int } from "./wago.js";

/**
 * Everything the generator draws on: instances, encounters and profession recipes from the game
 * client's tables (wago.tools), items from the in-game scans (.contribute/data/items/). Nothing in
 * here is hand-edited.
 */
export interface Reference {
  build: string;
  instances: Map<number, Instance>;
  encounters: Map<number, Encounter>;
  /** Professions with recipes, recipes by spell id and the trade skill window's categories (recipes.ts). */
  skillLines: Map<number, SkillLine>;
  recipes: Map<number, Recipe>;
  categories: Map<number, TradeSkillCategory>;
  items: Map<number, ScannedItem>;
  /** Locales that have item names, enUS first when present. */
  itemLocales: string[];
  names: Map<string, LocaleNames>;
}

export type InstanceType = "dungeon" | "raid";

export interface Instance {
  id: number; // Map.ID
  type: InstanceType;
  expansionID: number;
  encounters: number[]; // DungeonEncounter ids in OrderIndex order
}

export interface Encounter {
  id: number; // DungeonEncounter.ID
  mapID: number;
  order: number;
}

export interface LocaleNames {
  items: Map<number, string>;
  encounters: Map<number, string>;
  instances: Map<number, string>;
  skillLines: Map<number, string>;
  /** TradeSkillCategory names. */
  categories: Map<number, string>;
  /** TotemCategory names: the tools recipes need. */
  tools: Map<number, string>;
}

function emptyNames(): LocaleNames {
  return { items: new Map(), encounters: new Map(), instances: new Map(), skillLines: new Map(), categories: new Map(), tools: new Map() };
}

const INSTANCE_TYPES: Record<string, InstanceType> = { "1": "dungeon", "2": "raid" };

export async function loadReference(config: Config): Promise<Reference> {
  const { build } = config;
  const [maps, dungeonEncounters, recipeTables] = await Promise.all([
    fetchTable("Map", build, FALLBACK_LOCALE),
    fetchTable("DungeonEncounter", build, FALLBACK_LOCALE),
    loadRecipes(config),
  ]);

  // Encounters first: an instance is a map that has at least one (weeds out unused maps).
  const encounters = new Map<number, Encounter>();
  for (const row of dungeonEncounters) {
    const id = int(row.ID);
    encounters.set(id, { id, mapID: int(row.MapID), order: int(row.OrderIndex) });
  }

  const excluded = new Set(config.excludeMaps);
  const instances = new Map<number, Instance>();
  for (const row of maps) {
    const id = int(row.ID);
    const type = INSTANCE_TYPES[row.InstanceType ?? ""];
    if (!type || excluded.has(id)) continue;
    const list = [...encounters.values()]
      .filter((e) => e.mapID === id)
      .sort((a, b) => a.order - b.order || a.id - b.id)
      .map((e) => e.id);
    if (list.length === 0) continue;
    instances.set(id, { id, type, expansionID: int(row.ExpansionID), encounters: list });
  }

  const names = new Map<string, LocaleNames>();
  for (const locale of config.locales) {
    const [lMaps, lEnc] =
      locale === FALLBACK_LOCALE
        ? [maps, dungeonEncounters]
        : await Promise.all([fetchTable("Map", build, locale), fetchTable("DungeonEncounter", build, locale)]);
    const table = emptyNames();
    const recipeNames = recipeTables.names.get(locale);
    if (recipeNames) Object.assign(table, recipeNames);
    for (const row of lMaps) {
      const id = int(row.ID);
      if (instances.has(id) && row.MapName_lang) table.instances.set(id, row.MapName_lang);
    }
    for (const row of lEnc) {
      const id = int(row.ID);
      if (encounters.has(id) && row.Name_lang) table.encounters.set(id, row.Name_lang);
    }
    names.set(locale, table);
  }

  const ref: Reference = {
    build,
    instances,
    encounters,
    skillLines: recipeTables.skillLines,
    recipes: recipeTables.recipes,
    categories: recipeTables.categories,
    items: loadScannedItems(),
    itemLocales: [],
    names,
  };
  refreshItemNames(ref);
  return ref;
}

/** Rebuilds the per-locale item name tables from `ref.items`; call after the scanned items changed. */
export function refreshItemNames(ref: Reference): void {
  for (const table of ref.names.values()) table.items = new Map();
  const locales = new Set<string>();
  for (const [id, item] of ref.items) {
    for (const [locale, name] of Object.entries(item.names ?? {})) {
      if (!name) continue;
      let table = ref.names.get(locale);
      if (!table) {
        table = emptyNames();
        ref.names.set(locale, table);
      }
      table.items.set(id, name);
      locales.add(locale);
    }
  }
  ref.itemLocales = [...locales].sort((a, b) => (a === FALLBACK_LOCALE ? -1 : b === FALLBACK_LOCALE ? 1 : a.localeCompare(b)));
}

/** enUS name lookup (items: any scanned locale as a fallback) with an "#id" fallback, for comments and messages. */
export function nameOf(ref: Reference, kind: keyof LocaleNames, id: number): string {
  const name = ref.names.get(FALLBACK_LOCALE)?.[kind].get(id);
  if (name) return name;
  if (kind === "items") {
    for (const locale of ref.itemLocales) {
      const other = ref.names.get(locale)?.items.get(id);
      if (other) return other;
    }
  }
  return `#${id}`;
}
