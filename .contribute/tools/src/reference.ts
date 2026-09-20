import { type Config, FALLBACK_LOCALE } from "./config.js";
import { fetchTable, int } from "./wago.js";

/** Everything the game client knows; nothing in here is hand-edited. */
export interface Reference {
  build: string;
  instances: Map<number, Instance>;
  encounters: Map<number, Encounter>;
  items: Map<number, Item>;
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

/** Same layout as Data.ITEM in src/data/data.lua. */
export interface Item {
  id: number;
  quality: number;
  itemLevel: number;
  reqLevel: number;
  classID: number;
  subclassID: number;
  slot: string; // INVTYPE_* or ""
  bind: number;
}

export interface LocaleNames {
  items: Map<number, string>;
  encounters: Map<number, string>;
  instances: Map<number, string>;
}

const INSTANCE_TYPES: Record<string, InstanceType> = { "1": "dungeon", "2": "raid" };

/** Item.InventoryType -> the equip location string the client uses. */
const INVENTORY_TYPES: Record<number, string> = {
  1: "INVTYPE_HEAD",
  2: "INVTYPE_NECK",
  3: "INVTYPE_SHOULDER",
  4: "INVTYPE_BODY",
  5: "INVTYPE_CHEST",
  6: "INVTYPE_WAIST",
  7: "INVTYPE_LEGS",
  8: "INVTYPE_FEET",
  9: "INVTYPE_WRIST",
  10: "INVTYPE_HAND",
  11: "INVTYPE_FINGER",
  12: "INVTYPE_TRINKET",
  13: "INVTYPE_WEAPON",
  14: "INVTYPE_SHIELD",
  15: "INVTYPE_RANGED",
  16: "INVTYPE_CLOAK",
  17: "INVTYPE_2HWEAPON",
  18: "INVTYPE_BAG",
  19: "INVTYPE_TABARD",
  20: "INVTYPE_ROBE",
  21: "INVTYPE_WEAPONMAINHAND",
  22: "INVTYPE_WEAPONOFFHAND",
  23: "INVTYPE_HOLDABLE",
  24: "INVTYPE_AMMO",
  25: "INVTYPE_THROWN",
  26: "INVTYPE_RANGEDRIGHT",
  27: "INVTYPE_QUIVER",
  28: "INVTYPE_RELIC",
};

export async function loadReference(config: Config): Promise<Reference> {
  const { build } = config;
  const [maps, dungeonEncounters, itemSparse, item] = await Promise.all([
    fetchTable("Map", build, FALLBACK_LOCALE),
    fetchTable("DungeonEncounter", build, FALLBACK_LOCALE),
    fetchTable("ItemSparse", build, FALLBACK_LOCALE),
    fetchTable("Item", build, FALLBACK_LOCALE),
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

  const classes = new Map<number, { classID: number; subclassID: number }>();
  for (const row of item) {
    classes.set(int(row.ID), { classID: int(row.ClassID), subclassID: int(row.SubclassID) });
  }
  const items = new Map<number, Item>();
  for (const row of itemSparse) {
    const id = int(row.ID);
    const cls = classes.get(id) ?? { classID: 0, subclassID: 0 };
    items.set(id, {
      id,
      quality: int(row.OverallQualityID),
      itemLevel: int(row.ItemLevel, 1),
      reqLevel: int(row.RequiredLevel),
      classID: cls.classID,
      subclassID: cls.subclassID,
      slot: INVENTORY_TYPES[int(row.InventoryType)] ?? "",
      bind: int(row.Bonding),
    });
  }

  const names = new Map<string, LocaleNames>();
  for (const locale of config.locales) {
    const [lMaps, lEnc, lItems] =
      locale === FALLBACK_LOCALE
        ? [maps, dungeonEncounters, itemSparse]
        : await Promise.all([
            fetchTable("Map", build, locale),
            fetchTable("DungeonEncounter", build, locale),
            fetchTable("ItemSparse", build, locale),
          ]);
    const table: LocaleNames = { items: new Map(), encounters: new Map(), instances: new Map() };
    for (const row of lMaps) {
      const id = int(row.ID);
      if (instances.has(id) && row.MapName_lang) table.instances.set(id, row.MapName_lang);
    }
    for (const row of lEnc) {
      const id = int(row.ID);
      if (encounters.has(id) && row.Name_lang) table.encounters.set(id, row.Name_lang);
    }
    for (const row of lItems) {
      const id = int(row.ID);
      if (items.has(id) && row.Display_lang) table.items.set(id, row.Display_lang);
    }
    names.set(locale, table);
  }

  return { build, instances, encounters, items, names };
}

/** enUS name lookup with an "#id" fallback, for comments and messages. */
export function nameOf(ref: Reference, kind: keyof LocaleNames, id: number): string {
  return ref.names.get(FALLBACK_LOCALE)?.[kind].get(id) ?? `#${id}`;
}
