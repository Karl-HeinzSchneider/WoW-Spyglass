import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { SCANNED_ITEMS_DIR } from "./config.js";

/**
 * The item database's source: what `/fl scan` recorded in-game, merged in by `npm run import`.
 * One file per ID_RANGE ids (`items_270000.json` holds 270000..279999), keyed by item id, so an
 * item always lands in the same file and diffs stay small. Machine-written; not meant for
 * hand edits, though nothing breaks if you make them.
 *
 * Field meanings match Data.ITEM in src/data/data.lua; `names` is per locale, one per client
 * the item was scanned on.
 */
export interface ScannedItem {
  names: Record<string, string>;
  quality: number;
  itemLevel: number;
  reqLevel: number;
  classID: number;
  subclassID: number;
  /** INVTYPE_* or "" */
  slot: string;
  bind: number;
  /** Icon fileDataID */
  icon: number;
  sellPrice: number;
  stackCount: number;
  /** Item set id, 0 = none */
  setID: number;
  expansionID: number;
  craftingReagent: boolean;
  /** C_Item.GetItemStats without ITEM_MOD_/_SHORT, e.g. { INTELLECT: 4 } */
  stats?: Record<string, number>;
}

export const ID_RANGE = 10000;

const FIELDS = [
  "names",
  "quality",
  "itemLevel",
  "reqLevel",
  "classID",
  "subclassID",
  "slot",
  "bind",
  "icon",
  "sellPrice",
  "stackCount",
  "setID",
  "expansionID",
  "craftingReagent",
  "stats",
] as const;

function fileFor(rangeStart: number): string {
  return resolve(SCANNED_ITEMS_DIR, `items_${rangeStart}.json`);
}

export function loadScannedItems(): Map<number, ScannedItem> {
  const items = new Map<number, ScannedItem>();
  if (!existsSync(SCANNED_ITEMS_DIR)) return items;
  for (const entry of readdirSync(SCANNED_ITEMS_DIR).sort()) {
    if (!/^items_\d+\.json$/.test(entry)) continue;
    const raw = JSON.parse(readFileSync(resolve(SCANNED_ITEMS_DIR, entry), "utf-8")) as Record<string, ScannedItem>;
    for (const [key, value] of Object.entries(raw)) {
      const id = Number(key);
      if (!Number.isInteger(id) || id <= 0) throw new Error(`${entry}: "${key}" is not an item id`);
      items.set(id, value);
    }
  }
  return items;
}

/** Sorted ids, fixed field order and sorted stat/name keys, one file per id range; empty ranges get no file. */
export function saveScannedItems(items: Map<number, ScannedItem>): void {
  const byRange = new Map<number, Record<string, unknown>>();
  for (const id of [...items.keys()].sort((a, b) => a - b)) {
    const item = items.get(id)!;
    const entry: Record<string, unknown> = {};
    for (const field of FIELDS) {
      const value = item[field];
      if (value === undefined || value === null) continue;
      entry[field] = field === "names" || field === "stats" ? sortedKeys(value as Record<string, unknown>) : value;
    }
    const start = Math.floor(id / ID_RANGE) * ID_RANGE;
    let bucket = byRange.get(start);
    if (!bucket) {
      bucket = {};
      byRange.set(start, bucket);
    }
    bucket[String(id)] = entry;
  }
  mkdirSync(SCANNED_ITEMS_DIR, { recursive: true });
  for (const entry of readdirSync(SCANNED_ITEMS_DIR)) {
    const m = /^items_(\d+)\.json$/.exec(entry);
    if (m && !byRange.has(Number(m[1]))) rmSync(resolve(SCANNED_ITEMS_DIR, entry));
  }
  for (const [start, bucket] of byRange) {
    writeFileSync(fileFor(start), JSON.stringify(bucket, null, 2) + "\n", "utf-8");
  }
}

function sortedKeys<T>(obj: Record<string, T>): Record<string, T> {
  const out: Record<string, T> = {};
  for (const key of Object.keys(obj).sort()) out[key] = obj[key]!;
  return out;
}
