import { type Config, FALLBACK_LOCALE } from "./config.js";
import { type ScannedItem, loadScannedItems } from "./items.js";
import { type Recipe, type SkillLine, type TradeSkillCategory, linkRecipeItems, loadRecipes } from "./recipes.js";
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
  /** ItemSparse skill requirements, for linking scanned recipe items to recipes (`relinkRecipes`). */
  itemSkills: Map<number, { skillLineID: number; rank: number }>;
  /** Factions with a reputation bar (`Faction` rows with a ReputationIndex), for the reputation lists. */
  factions: Map<number, Faction>;
  items: Map<number, ScannedItem>;
  /** ItemSparse's item names per configured locale (enUS too, to check it means the scanned item). */
  wagoItemNames: Map<string, Map<number, string>>;
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

export interface Faction {
  id: number; // Faction.ID
  /** enUS name. */
  name: string;
  parentID: number;
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
  return {
    items: new Map(),
    encounters: new Map(),
    instances: new Map(),
    skillLines: new Map(),
    categories: new Map(),
    tools: new Map(),
  };
}

const INSTANCE_TYPES: Record<string, InstanceType> = { "1": "dungeon", "2": "raid" };

/**
 * One encounter set per map. A few maps (Blackfathom Deeps, Gnomeregan, Sunken Temple) also carry
 * other versions' sets for the same bosses (Season of Discovery raids, a second 5-player set); this
 * client has one version of each dungeon, the normal 5-player one. Per map, only the encounters of
 * the first difficulty in this list that the map has are kept: 0 = none (every other map),
 * 1 = Normal 5-player, 201 = Normal 5-player on a map without a difficulty-1 set (Gnomeregan).
 */
const ENCOUNTER_DIFFICULTIES = [0, 1, 201];

export async function loadReference(config: Config): Promise<Reference> {
  const { build } = config;
  const [maps, dungeonEncounters, factionRows, recipeTables] = await Promise.all([
    fetchTable("Map", build, FALLBACK_LOCALE),
    fetchTable("DungeonEncounter", build, FALLBACK_LOCALE),
    fetchTable("Faction", build, FALLBACK_LOCALE),
    loadRecipes(config),
  ]);

  const factions = new Map<number, Faction>();
  for (const row of factionRows) {
    if (int(row.ReputationIndex, -1) < 0) continue; // no reputation bar: team, guild and helper factions
    const id = int(row.ID);
    factions.set(id, { id, name: row.Name_lang ?? "", parentID: int(row.ParentFactionID) });
  }

  // Encounters first: an instance is a map that has at least one (weeds out unused maps).
  const difficulties = new Map<number, Set<number>>(); // map -> difficulty ids of its encounters
  for (const row of dungeonEncounters) {
    const mapID = int(row.MapID);
    const set = difficulties.get(mapID) ?? new Set<number>();
    set.add(int(row.DifficultyID));
    difficulties.set(mapID, set);
  }
  const encounters = new Map<number, Encounter>();
  for (const row of dungeonEncounters) {
    const id = int(row.ID);
    const mapID = int(row.MapID);
    const keep = ENCOUNTER_DIFFICULTIES.find((d) => difficulties.get(mapID)!.has(d));
    if (keep !== undefined && int(row.DifficultyID) !== keep) continue;
    encounters.set(id, { id, mapID, order: int(row.OrderIndex) });
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

  // One locale at a time: each ItemSparse table is a large CSV and only its names are kept.
  const wagoItemNames = new Map<string, Map<number, string>>();
  for (const locale of config.locales) {
    const table = new Map<number, string>();
    for (const row of await fetchTable("ItemSparse", build, locale)) {
      if (row.Display_lang) table.set(int(row.ID), row.Display_lang);
    }
    wagoItemNames.set(locale, table);
  }

  const ref: Reference = {
    build,
    instances,
    encounters,
    skillLines: recipeTables.skillLines,
    recipes: recipeTables.recipes,
    categories: recipeTables.categories,
    itemSkills: recipeTables.itemSkills,
    factions,
    items: loadScannedItems(),
    wagoItemNames,
    itemLocales: [],
    names,
  };
  refreshItemNames(ref);
  relinkRecipes(ref);
  return ref;
}

/** Re-links scanned recipe items to the recipes they teach; call after the scanned items changed. */
export function relinkRecipes(ref: Reference): void {
  linkRecipeItems(ref, ref.items);
}

/**
 * Rebuilds the per-locale item name tables of the scanned items; call after they changed. ItemSparse
 * names an item in every configured locale when its English name there is the scanned one (a
 * server rename would leave the table's names outdated in every language); a name scanned in-game
 * on a client of that language wins over it.
 */
export function refreshItemNames(ref: Reference): void {
  for (const table of ref.names.values()) table.items = new Map();
  const locales = new Set<string>();
  const set = (locale: string, id: number, name: string) => {
    let table = ref.names.get(locale);
    if (!table) {
      table = emptyNames();
      ref.names.set(locale, table);
    }
    table.items.set(id, name);
    locales.add(locale);
  };
  const wagoEnglish = ref.wagoItemNames.get(FALLBACK_LOCALE);
  for (const [id, item] of ref.items) {
    const english = item.names?.[FALLBACK_LOCALE];
    if (english && wagoEnglish?.get(id) === english) {
      for (const [locale, table] of ref.wagoItemNames) {
        const name = table.get(id);
        if (locale !== FALLBACK_LOCALE && name) set(locale, id, name);
      }
    }
    for (const [locale, name] of Object.entries(item.names ?? {})) {
      if (name) set(locale, id, name);
    }
  }
  ref.itemLocales = [...locales].sort((a, b) =>
    a === FALLBACK_LOCALE ? -1 : b === FALLBACK_LOCALE ? 1 : a.localeCompare(b),
  );
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
