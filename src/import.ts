import { resolve } from "node:path";
import { CURATED_DIRS } from "./config.js";
import { type CuratedFile } from "./curated.js";
import { type Discovered } from "./discovered.js";
import { ID_RANGE, type ScannedItem } from "./items.js";
import { type Reference, nameOf, refreshItemNames } from "./reference.js";

/** Below this many kills an observed ratio says little; the row is added without a chance. */
const MIN_KILLS_FOR_CHANCE = 10;

function slugOf(name: string): string {
  return name
    .toLowerCase()
    .replace(/'/g, "")
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

/**
 * Merges what the addon recorded into the repository data, in memory:
 * - every recorded item goes into the scanned items (`ref.items`, saved to .contribute/data/items/):
 *   the newer observation replaces the old, except that names of other locales are kept,
 * - each observed boss drop becomes a loot row in the boss's instance file (created when
 *   missing; `validate(..., fix)` afterwards fills its name and encounter list as usual),
 *   with a `chance` only when the row is new and the boss was killed often enough.
 * Existing loot rows and chances are never changed; their observed ratios are printed so a
 * human can judge them. Returns the report lines.
 */
export function importDiscovered(d: Discovered, ref: Reference, files: CuratedFile[]): string[] {
  const lines: string[] = [];

  let added = 0;
  let updated = 0;
  const touchedRanges = new Set<number>();
  for (const [id, item] of [...d.items].sort(([a], [b]) => a - b)) {
    const { name, id: _id, ...fields } = item; // the id is the key of the dump
    const existing = ref.items.get(id);
    const merged: ScannedItem = { ...fields, names: { ...(existing?.names ?? {}), [d.locale]: name } };
    if (existing) updated++;
    else added++;
    ref.items.set(id, merged);
    touchedRanges.add(Math.floor(id / ID_RANGE) * ID_RANGE);
  }
  if (added || updated) {
    const ranges = [...touchedRanges].sort((a, b) => a - b).map((start) => `items_${start}.json`);
    lines.push(`items (${d.locale}): ${added} new, ${updated} updated -> ${ranges.join(", ")}`);
  }
  refreshItemNames(ref); // so the loot rows below resolve and get their names

  const byMap = new Map(files.map((f) => [f.data.map, f]));
  for (const [encounterID, observed] of [...d.loot].sort(([a], [b]) => a - b)) {
    const encounter = ref.encounters.get(encounterID);
    if (!encounter) {
      lines.push(`encounter ${encounterID}: not in build ${ref.build}, skipped`);
      continue;
    }
    const instance = ref.instances.get(encounter.mapID);
    if (!instance) {
      lines.push(
        `encounter ${encounterID} (${nameOf(ref, "encounters", encounterID)}): map ${encounter.mapID} is not a known instance, skipped`,
      );
      continue;
    }
    // A split map (several files, each with an `id`): the file that lists the encounter.
    const shared = files.filter((f) => f.data.map === encounter.mapID);
    let file = shared.find((f) => f.data.encounters.some((e) => e.id === encounterID)) ?? byMap.get(encounter.mapID);
    if (
      file &&
      shared.some((f) => f.data.id !== undefined) &&
      !file.data.encounters.some((e) => e.id === encounterID)
    ) {
      lines.push(
        `encounter ${encounterID} (${nameOf(ref, "encounters", encounterID)}): map ${encounter.mapID} is split and none of its files lists it, skipped`,
      );
      continue;
    }
    if (!file) {
      const slug = slugOf(nameOf(ref, "instances", encounter.mapID));
      file = {
        path: resolve(CURATED_DIRS[instance.type], `${slug}.json`),
        folder: instance.type,
        slug,
        data: { map: encounter.mapID, encounters: [] },
      };
      files.push(file);
      byMap.set(encounter.mapID, file);
      lines.push(`new file ${instance.type}s/${slug}.json`);
    }
    let enc = file.data.encounters.find((e) => e.id === encounterID);
    if (!enc) {
      enc = { id: encounterID, loot: [] };
      file.data.encounters.push(enc);
    }
    if (!Array.isArray(enc.loot)) enc.loot = [];

    const parts: string[] = [];
    for (const [itemID, seen] of [...observed.items].sort(([a], [b]) => a - b)) {
      const ratio = observed.kills > 0 ? `${seen}/${observed.kills}` : `${seen}x`;
      const scanned = ref.items.has(itemID);
      const name = nameOf(ref, "items", itemID);
      if (enc.loot.some((row) => row.item === itemID)) {
        parts.push(`= ${name} ${ratio}`);
        continue;
      }
      const chance =
        observed.kills >= MIN_KILLS_FOR_CHANCE
          ? Math.min(1, Math.round((seen / observed.kills) * 100) / 100)
          : undefined;
      enc.loot.push({ item: itemID, name: scanned ? name : undefined, chance });
      parts.push(
        `+ ${name} ${ratio}${chance !== undefined ? ` -> ${Math.round(chance * 100)}%` : ""}${scanned ? "" : " (not scanned yet)"}`,
      );
    }
    lines.push(
      `${file.slug}: ${nameOf(ref, "encounters", encounterID)} (${encounterID}), ${observed.kills} kill(s): ${parts.join(", ") || "no drops seen"}`,
    );
  }
  return lines;
}
