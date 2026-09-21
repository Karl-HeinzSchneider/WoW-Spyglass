import { readdirSync, readFileSync } from "node:fs";
import { basename, resolve } from "node:path";
import { CURATED_DIRS, FALLBACK_LOCALE } from "./config.js";
import { type InstanceType, type Reference, nameOf } from "./reference.js";

/**
 * A curated instance file: .contribute/dungeons/<name>.json or .contribute/raids/<name>.json.
 * Only ids matter; every `name` is informational and rewritten by `npm run fix`.
 */
export interface CuratedInstance {
  /** Map.ID of the instance (see db/generated/instances.lua for the list). */
  map: number;
  /** Informational, filled by `fix`. */
  name?: string;
  minLevel?: number;
  maxLevel?: number;
  /** Texture path shown in the browser, e.g. "Interface\\Icons\\INV_Misc_Key_13". */
  icon?: string;
  /** Wide picture behind the instance's tile in the browser (texture path or fileID). */
  background?: string | number;
  /** Part of `background` to show: [left, right, top, bottom] in 0..1; the whole texture when omitted. */
  backgroundCoords?: [number, number, number, number];
  encounters: CuratedEncounter[];
}

export interface CuratedEncounter {
  /** DungeonEncounter.ID */
  id: number;
  name?: string;
  loot: CuratedLoot[];
}

export interface CuratedLoot {
  /** Item id; may be left out when `name` identifies exactly one client item (`fix` fills it in). */
  item?: number;
  name?: string;
  /** Drop chance 0..1; omit when unknown. */
  chance?: number;
}

export interface CuratedFile {
  path: string;
  /** Folder it was found in; the generator warns when it disagrees with Map.InstanceType. */
  folder: InstanceType;
  /** Output name: db/generated/loot/<slug>.lua */
  slug: string;
  data: CuratedInstance;
}

export function loadCurated(): CuratedFile[] {
  const files: CuratedFile[] = [];
  for (const [folder, dir] of Object.entries(CURATED_DIRS) as [InstanceType, string][]) {
    let entries: string[] = [];
    try {
      entries = readdirSync(dir).filter((f) => f.endsWith(".json")).sort();
    } catch {
      continue; // folder may not exist yet
    }
    for (const entry of entries) {
      const path = resolve(dir, entry);
      const data = JSON.parse(readFileSync(path, "utf-8")) as CuratedInstance;
      files.push({ path, folder, slug: basename(entry, ".json"), data });
    }
  }
  return files;
}

export interface Problem {
  file: string;
  message: string;
  /** Fixable problems are corrected by `check --fix`; the rest need a human. */
  fixable: boolean;
  /** Warnings are printed but don't fail the run or stop generation. */
  warning?: boolean;
}

/** enUS item name (case-insensitive) -> ids, built on first use for rows that only give a name. */
function itemsByName(ref: Reference): Map<string, number[]> {
  const index = new Map<string, number[]>();
  for (const [id, name] of ref.names.get(FALLBACK_LOCALE)!.items) {
    const key = name.toLowerCase();
    const list = index.get(key);
    if (list) list.push(id);
    else index.set(key, [id]);
  }
  return index;
}

/** Validates ids against the reference data; with `fix`, rewrites names and adds missing encounters. */
export function validate(files: CuratedFile[], ref: Reference, fix: boolean): Problem[] {
  const problems: Problem[] = [];
  const seenMaps = new Map<number, string>();
  let byName: Map<string, number[]> | undefined;
  const report = (file: CuratedFile, message: string, fixable = false) =>
    problems.push({ file: file.path, message, fixable });
  const warn = (file: CuratedFile, message: string) => problems.push({ file: file.path, message, fixable: false, warning: true });

  for (const file of files) {
    const d = file.data;
    if (!Number.isInteger(d.map)) {
      report(file, "`map` must be a Map.ID");
      continue;
    }
    const instance = ref.instances.get(d.map);
    if (!instance) {
      report(file, `map ${d.map} is not an instance with encounters in build ${ref.build}`);
      continue;
    }
    const other = seenMaps.get(d.map);
    if (other) report(file, `map ${d.map} is also defined in ${other}`);
    seenMaps.set(d.map, file.path);
    if (instance.type !== file.folder) {
      report(file, `map ${d.map} is a ${instance.type} but the file is in the ${file.folder}s folder`);
    }
    if (d.minLevel !== undefined && d.maxLevel !== undefined && d.minLevel > d.maxLevel) {
      report(file, "`minLevel` is greater than `maxLevel`");
    }
    if (!Array.isArray(d.encounters)) {
      report(file, "`encounters` must be an array");
      continue;
    }

    const instanceName = nameOf(ref, "instances", d.map);
    if (d.name !== instanceName) {
      report(file, `name "${d.name ?? ""}" -> "${instanceName}"`, true);
      if (fix) d.name = instanceName;
    }

    const seenEncounters = new Set<number>();
    for (const enc of d.encounters) {
      if (!Number.isInteger(enc.id)) {
        report(file, "encounter without an `id`");
        continue;
      }
      const known = ref.encounters.get(enc.id);
      if (!known) {
        report(file, `encounter ${enc.id} does not exist`);
        continue;
      }
      if (known.mapID !== d.map) {
        report(file, `encounter ${enc.id} (${nameOf(ref, "encounters", enc.id)}) belongs to map ${known.mapID}`);
      }
      if (seenEncounters.has(enc.id)) report(file, `encounter ${enc.id} listed twice`);
      seenEncounters.add(enc.id);
      const encName = nameOf(ref, "encounters", enc.id);
      if (enc.name !== encName) {
        report(file, `encounter ${enc.id}: name "${enc.name ?? ""}" -> "${encName}"`, true);
        if (fix) enc.name = encName;
      }
      if (!Array.isArray(enc.loot)) {
        report(file, `encounter ${enc.id}: \`loot\` must be an array`, true);
        if (fix) enc.loot = [];
        else continue;
      }
      const seenItems = new Set<number>();
      for (const row of enc.loot) {
        if (row.item === undefined && typeof row.name === "string" && row.name !== "") {
          // Name-only row: resolve it when exactly one item carries that name.
          byName ??= itemsByName(ref);
          const ids = byName.get(row.name.toLowerCase()) ?? [];
          if (ids.length === 1) {
            report(file, `encounter ${enc.id}: "${row.name}" -> item ${ids[0]}`, true);
            if (fix) row.item = ids[0];
            else continue;
          } else if (ids.length === 0) {
            report(file, `encounter ${enc.id}: no item is named "${row.name}"; give its \`item\` id`);
            continue;
          } else {
            report(file, `encounter ${enc.id}: "${row.name}" is ambiguous (items ${ids.join(", ")}); give its \`item\` id`);
            continue;
          }
        }
        if (row.item === undefined || !Number.isInteger(row.item)) {
          report(file, `encounter ${enc.id}: loot row without an \`item\``);
          continue;
        }
        if (seenItems.has(row.item)) report(file, `encounter ${enc.id}: item ${row.item} listed twice`);
        seenItems.add(row.item);
        if (row.chance !== undefined && !(row.chance >= 0 && row.chance <= 1)) {
          report(file, `encounter ${enc.id}: item ${row.item} chance must be between 0 and 1`);
        }
        // Drops are curated independently of the scans: an unscanned item still gets its loot row
        // (the boss page shows it once the client fetches it), it is just not searchable yet, and
        // its name stays whatever the contributor typed.
        if (!ref.items.has(row.item)) {
          warn(file, `encounter ${enc.id}: item ${row.item} (${row.name ?? "?"}) hasn't been scanned yet; /fl scan it in-game and import`);
          continue;
        }
        const itemName = nameOf(ref, "items", row.item);
        if (row.name !== itemName) {
          report(file, `item ${row.item}: name "${row.name ?? ""}" -> "${itemName}"`, true);
          if (fix) row.name = itemName;
        }
      }
    }

    // Encounters the game knows but the file doesn't list yet: add empty skeletons in order.
    const missing = instance.encounters.filter((id) => !seenEncounters.has(id));
    if (missing.length > 0) {
      report(file, `missing encounters: ${missing.map((id) => `${id} (${nameOf(ref, "encounters", id)})`).join(", ")}`, true);
      if (fix) {
        for (const id of missing) d.encounters.push({ id, name: nameOf(ref, "encounters", id), loot: [] });
        d.encounters.sort((a, b) => (ref.encounters.get(a.id)?.order ?? 0) - (ref.encounters.get(b.id)?.order ?? 0));
      }
    }
  }
  return problems;
}

/** Stable key order so `fix` produces minimal diffs. */
export function serialize(d: CuratedInstance): string {
  const ordered = {
    map: d.map,
    name: d.name,
    minLevel: d.minLevel,
    maxLevel: d.maxLevel,
    icon: d.icon,
    background: d.background,
    backgroundCoords: d.backgroundCoords,
    encounters: d.encounters.map((e) => ({
      id: e.id,
      name: e.name,
      loot: e.loot.map((r) => ({ item: r.item, name: r.name, chance: r.chance })),
    })),
  };
  return JSON.stringify(ordered, null, 2) + "\n";
}
