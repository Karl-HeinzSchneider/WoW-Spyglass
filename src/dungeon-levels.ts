import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { DATA_DIR } from "./config.js";
import { type Checker, type CuratedFile, instanceIDOf } from "./curated.js";

export const DUNGEON_LEVELS_PATH = resolve(DATA_DIR, "dungeon-levels.json");

interface Activity {
  id: number;
  name: string;
  mapID: number;
  difficultyID: number;
  minLevelSuggestion: number;
  maxLevelSuggestion: number;
}

export interface DungeonLevel {
  activityID: number;
  name: string;
  minLevel: number;
  maxLevel: number;
}

export interface DungeonLevels {
  build: string;
  dungeons: Record<string, DungeonLevel>;
}

function positiveLevel(value: unknown): value is number {
  return Number.isInteger(value) && typeof value === "number" && value > 0;
}

/** The copyable `/sg levels` JSON; raw activities include other categories for safe matching. */
export function parseDungeonLevelScan(raw: unknown): { build: string; activities: Activity[] } {
  if (!raw || typeof raw !== "object" || (raw as { kind?: unknown }).kind !== "dungeon-levels") {
    throw new Error("not a dungeon-levels export");
  }
  const data = raw as { build?: unknown; activities?: unknown };
  if (typeof data.build !== "string" || !data.build || !data.activities || typeof data.activities !== "object") {
    throw new Error("dungeon-levels export needs a build and activities");
  }
  const activities: Activity[] = [];
  for (const [key, value] of Object.entries(data.activities)) {
    if (!value || typeof value !== "object") continue;
    const row = value as Partial<Activity>;
    const id = Number(key);
    if (!Number.isInteger(id) || id <= 0 || row.id !== id || !Number.isInteger(row.mapID) || row.mapID! <= 0) {
      continue;
    }
    activities.push({
      id,
      name: typeof row.name === "string" ? row.name : "",
      mapID: row.mapID!,
      difficultyID: Number.isInteger(row.difficultyID) ? row.difficultyID! : 0,
      minLevelSuggestion: row.minLevelSuggestion ?? 0,
      maxLevelSuggestion: row.maxLevelSuggestion ?? 0,
    });
  }
  if (activities.length === 0) throw new Error("dungeon-levels export has no activities with map IDs");
  return { build: data.build, activities };
}

function nameKey(name: string): string {
  return (
    name
      .toLowerCase()
      .match(/[a-z0-9]+/g)
      ?.sort()
      .join(" ") ?? ""
  );
}

/** Match by map, then name when several dungeons share a map. Never guess ambiguous activities. */
export function importDungeonLevels(
  scan: ReturnType<typeof parseDungeonLevelScan>,
  files: CuratedFile[],
): { levels: DungeonLevels; lines: string[] } {
  const dungeons: Record<string, DungeonLevel> = {};
  const lines: string[] = [];
  for (const file of files.filter((f) => f.folder === "dungeon")) {
    const candidates = scan.activities.filter(
      (a) =>
        a.mapID === file.data.map &&
        [0, 1, 201].includes(a.difficultyID) &&
        positiveLevel(a.minLevelSuggestion) &&
        positiveLevel(a.maxLevelSuggestion) &&
        a.maxLevelSuggestion >= a.minLevelSuggestion,
    );
    const matched = candidates.filter((a) => nameKey(a.name) === nameKey(file.data.name ?? ""));
    const choices = matched.length > 0 ? matched : candidates;
    const sameMap = files.filter((f) => f.folder === "dungeon" && f.data.map === file.data.map);
    const activity = choices.length === 1 && (matched.length > 0 || sameMap.length === 1) ? choices[0] : undefined;
    if (!activity) {
      lines.push(`${file.slug}: ${choices.length ? "ambiguous activity" : "no activity with usable levels"}; skipped`);
      continue;
    }
    const id = instanceIDOf(file.data);
    dungeons[id] = {
      activityID: activity.id,
      name: activity.name,
      minLevel: activity.minLevelSuggestion,
      maxLevel: activity.maxLevelSuggestion,
    };
    lines.push(`${file.slug}: ${activity.minLevelSuggestion}-${activity.maxLevelSuggestion} (activity ${activity.id})`);
  }
  return { levels: { build: scan.build, dungeons }, lines };
}

export function loadDungeonLevels(): DungeonLevels | undefined {
  if (!existsSync(DUNGEON_LEVELS_PATH)) return undefined;
  return JSON.parse(readFileSync(DUNGEON_LEVELS_PATH, "utf-8")) as DungeonLevels;
}

/** The snapshot verifies scanned dungeons and `fix` copies their levels into the curated files. */
export function validateDungeonLevels(levels: DungeonLevels | undefined, files: CuratedFile[], checker: Checker): void {
  if (!levels) return;
  const source = { path: DUNGEON_LEVELS_PATH };
  if (!levels.dungeons || typeof levels.dungeons !== "object" || Array.isArray(levels.dungeons)) {
    checker.report(source, "`dungeons` must be an object keyed by instance id");
    return;
  }
  for (const file of files.filter((f) => f.folder === "dungeon")) {
    const id = instanceIDOf(file.data);
    const entry = levels.dungeons[id];
    if (!entry) continue;
    if (!positiveLevel(entry.minLevel) || !positiveLevel(entry.maxLevel) || entry.minLevel > entry.maxLevel) {
      checker.report(source, `${file.slug}: invalid level range`);
      continue;
    }
    if (file.data.minLevel !== entry.minLevel || file.data.maxLevel !== entry.maxLevel) {
      checker.report(
        file,
        `levels ${file.data.minLevel ?? "?"}-${file.data.maxLevel ?? "?"} -> ${entry.minLevel}-${entry.maxLevel}`,
        checker.fix,
      );
      if (checker.fix) {
        file.data.minLevel = entry.minLevel;
        file.data.maxLevel = entry.maxLevel;
      }
    }
  }
}
