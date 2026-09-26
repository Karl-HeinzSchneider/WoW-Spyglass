import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

/** Repository layout, relative to this file (src/config.ts). */
export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
export const CONTRIBUTE_DIR = resolve(ROOT, ".contribute");
export const DATA_DIR = resolve(CONTRIBUTE_DIR, "data");
export const CACHE_DIR = resolve(ROOT, ".cache");
export const OUTPUT_DIR = resolve(ROOT, "Spyglass", "db", "generated");
export const LOCALE_OUTPUT_DIR = resolve(ROOT, "Spyglass_Locale", "db", "generated");
export const DATABASE_OUTPUT_DIR = resolve(ROOT, "Spyglass_Database", "db", "generated");

/** Curated input folders; the key is informational, Map.InstanceType decides the real type. */
export const CURATED_DIRS = {
  dungeon: resolve(DATA_DIR, "dungeons"),
  raid: resolve(DATA_DIR, "raids"),
} as const;

/**
 * Curated item lists, one folder per built-in module and one file per list (a profession, a
 * battleground, a collection, a faction): see lists.ts.
 */
export const LIST_KINDS = ["crafting", "pvp", "collections", "reputation"] as const;
export type ListKind = (typeof LIST_KINDS)[number];
export const LIST_DIRS = Object.fromEntries(LIST_KINDS.map((kind) => [kind, resolve(DATA_DIR, kind)])) as Record<
  ListKind,
  string
>;

/** The item database's source: in-game scans, one JSON file per id range (see items.ts). */
export const SCANNED_ITEMS_DIR = resolve(DATA_DIR, "items");
/** Drop folder for `npm run import` without a path: SavedVariables .lua and /sg export .json files (gitignored). */
export const INBOX_DIR = resolve(CONTRIBUTE_DIR, "inbox");

export const FALLBACK_LOCALE = "enUS";
/**
 * Every value of the client's [TextLocale] TOC path variable. The locale addon's TOC loads
 * `locales\[TextLocale]\<file>`, and a missing file is a LUA_WARNING at login, so the generator
 * writes each LOCALE_FILES entry for all of them (a placeholder where there are no names).
 */
export const CLIENT_LOCALES = [
  "enUS",
  "enGB",
  "deDE",
  "esES",
  "esMX",
  "frFR",
  "itIT",
  "koKR",
  "ptBR",
  "ruRU",
  "zhCN",
  "zhTW",
] as const;
export const LOCALE_FILES = ["items.lua", "instances.lua", "bosses.lua", "crafting.lua"] as const;

export interface Config {
  /** wago.tools build, e.g. "1.60.1.69913" (see https://wago.tools/api/builds). */
  build: string;
  /** Locales to ship names for; enUS is always included first. */
  locales: string[];
  /** Map IDs to leave out even though they have encounters (test maps). */
  excludeMaps: number[];
  /** Split Spyglass_Database/db/generated/items/items_NNN.lua after this many rows. */
  itemsPerFile: number;
}

export function loadConfig(): Config {
  const raw = JSON.parse(readFileSync(resolve(DATA_DIR, "config.json"), "utf-8")) as Partial<Config>;
  const locales = [FALLBACK_LOCALE, ...(raw.locales ?? []).filter((l) => l !== FALLBACK_LOCALE)];
  if (!raw.build) throw new Error("config.json: `build` is required");
  return {
    build: raw.build,
    locales,
    excludeMaps: raw.excludeMaps ?? [],
    itemsPerFile: raw.itemsPerFile ?? 2500,
  };
}
