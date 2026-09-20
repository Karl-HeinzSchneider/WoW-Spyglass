import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

/** Repository layout, relative to this file (.contribute/tools/src/config.ts). */
export const TOOLS_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "..");
export const CONTRIBUTE_DIR = resolve(TOOLS_DIR, "..");
export const ROOT = resolve(CONTRIBUTE_DIR, "..");
export const CACHE_DIR = resolve(TOOLS_DIR, ".cache");
export const OUTPUT_DIR = resolve(ROOT, "db", "generated");

/** Curated input folders; the key is informational, Map.InstanceType decides the real type. */
export const CURATED_DIRS = {
  dungeon: resolve(CONTRIBUTE_DIR, "dungeons"),
  raid: resolve(CONTRIBUTE_DIR, "raids"),
} as const;

export const FALLBACK_LOCALE = "enUS";

export interface Config {
  /** wago.tools build, e.g. "1.60.1.69913" (see https://wago.tools/api/builds). */
  build: string;
  /** Locales to ship names for; enUS is always included first. */
  locales: string[];
  /** Map IDs to leave out even though they have encounters (test maps). */
  excludeMaps: number[];
  /** Split db/generated/items_NNN.lua after this many rows. */
  itemsPerFile: number;
}

export function loadConfig(): Config {
  const raw = JSON.parse(readFileSync(resolve(TOOLS_DIR, "config.json"), "utf-8")) as Partial<Config>;
  const locales = [FALLBACK_LOCALE, ...(raw.locales ?? []).filter((l) => l !== FALLBACK_LOCALE)];
  if (!raw.build) throw new Error("config.json: `build` is required");
  return {
    build: raw.build,
    locales,
    excludeMaps: raw.excludeMaps ?? [],
    itemsPerFile: raw.itemsPerFile ?? 2500,
  };
}
