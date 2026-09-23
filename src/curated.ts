import { readdirSync, readFileSync } from "node:fs";
import { basename, resolve } from "node:path";
import { CURATED_DIRS, FALLBACK_LOCALE } from "./config.js";
import { type InstanceType, type Reference, nameOf } from "./reference.js";

/**
 * A curated instance file: .contribute/data/dungeons/<name>.json or .contribute/data/raids/<name>.json.
 * Only ids matter; every `name` is informational and rewritten by `npm run fix`.
 */
export interface CuratedInstance {
  /** Map.ID of the instance (see ForeverLoot/db/generated/instances.lua for the list). */
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
  /** Picture of the boss for its card in the browser (texture path or fileID). */
  portrait?: string | number;
  /**
   * CreatureDisplayID of the boss's model. The client renders the portrait from it, which is
   * how bosses without Encounter Journal art get a picture; `portrait` wins when both are set.
   */
  displayID?: number;
  /** The boss's NPC id. Not shipped: a note of where `displayID` came from, so it can be re-checked. */
  npc?: number;
  /** Boss level and creature type ("Beast", "Undead", ...) as the game shows them; the card says "60 Beast". */
  level?: number;
  creatureType?: string;
  /** Quest ids the boss is involved in (objective or starts one); the card gets a "!" and the tooltip lists them. */
  quests?: number[];
  loot: CuratedLoot[];
}

export interface CuratedLoot extends CuratedItemRow {
  /** Drop chance 0..1; omit when unknown. */
  chance?: number;
}

export interface CuratedFile {
  path: string;
  /** Folder it was found in; the generator warns when it disagrees with Map.InstanceType. */
  folder: InstanceType;
  /** Output name: ForeverLoot/db/generated/loot/<slug>.lua */
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

/** An item row as every curated file has them: an id, or a name that resolves to one. */
export interface CuratedItemRow {
  /** Item id; may be left out when `name` identifies exactly one client item (`fix` fills it in). */
  item?: number;
  name?: string;
}

/** Problem sink shared by the validators (instance files here, item lists in lists.ts). */
export class Checker {
  readonly problems: Problem[] = [];
  private byName?: Map<string, number[]>;

  constructor(
    readonly ref: Reference,
    readonly fix: boolean,
  ) {}

  report(file: { path: string }, message: string, fixable = false): void {
    this.problems.push({ file: file.path, message, fixable });
  }

  warn(file: { path: string }, message: string): void {
    this.problems.push({ file: file.path, message, fixable: false, warning: true });
  }

  /** enUS item name (case-insensitive) -> ids, built on first use for rows that only give a name. */
  private itemsByName(): Map<string, number[]> {
    if (!this.byName) {
      this.byName = new Map();
      for (const [id, name] of this.ref.names.get(FALLBACK_LOCALE)!.items) {
        const key = name.toLowerCase();
        const list = this.byName.get(key);
        if (list) list.push(id);
        else this.byName.set(key, [id]);
      }
    }
    return this.byName;
  }

  /**
   * Checks one item row: resolves a name-only row to its id, rejects duplicates within `seen`
   * and rewrites the name from the scans. Returns false when the row has no usable item id.
   */
  checkItemRow(file: { path: string }, where: string, row: CuratedItemRow, seen: Set<number>): boolean {
    const { ref, fix } = this;
    if (row.item === undefined && typeof row.name === "string" && row.name !== "") {
      // Name-only row: resolve it when exactly one item carries that name.
      const ids = this.itemsByName().get(row.name.toLowerCase()) ?? [];
      if (ids.length === 1) {
        this.report(file, `${where}: "${row.name}" -> item ${ids[0]}`, true);
        if (fix) row.item = ids[0];
        else return false;
      } else if (ids.length === 0) {
        this.report(file, `${where}: no item is named "${row.name}"; give its \`item\` id`);
        return false;
      } else {
        this.report(file, `${where}: "${row.name}" is ambiguous (items ${ids.join(", ")}); give its \`item\` id`);
        return false;
      }
    }
    if (row.item === undefined || !Number.isInteger(row.item)) {
      this.report(file, `${where}: row without an \`item\``);
      return false;
    }
    if (seen.has(row.item)) this.report(file, `${where}: item ${row.item} listed twice`);
    seen.add(row.item);
    // Rows are curated independently of the scans: an unscanned item still gets its row (the
    // page shows it once the client fetches it), it is just not searchable yet, and its name
    // stays whatever the contributor typed.
    if (!ref.items.has(row.item)) {
      this.warn(file, `${where}: item ${row.item} (${row.name ?? "?"}) hasn't been scanned yet; /fl scan it in-game and import`);
      return true;
    }
    const itemName = nameOf(ref, "items", row.item);
    if (row.name !== itemName) {
      this.report(file, `item ${row.item}: name "${row.name ?? ""}" -> "${itemName}"`, true);
      if (fix) row.name = itemName;
    }
    return true;
  }
}

/** Validates ids against the reference data; with `fix`, rewrites names and adds missing encounters. */
export function validate(files: CuratedFile[], checker: Checker): void {
  const { ref, fix } = checker;
  const seenMaps = new Map<number, string>();
  const report = checker.report.bind(checker);

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
      for (const field of ["displayID", "npc"] as const) {
        const value = enc[field];
        if (value !== undefined && (!Number.isInteger(value) || value <= 0)) {
          report(file, `encounter ${enc.id}: \`${field}\` must be a positive integer id`);
        }
      }
      if (!Array.isArray(enc.loot)) {
        report(file, `encounter ${enc.id}: \`loot\` must be an array`, true);
        if (fix) enc.loot = [];
        else continue;
      }
      const seenItems = new Set<number>();
      for (const row of enc.loot) {
        if (!checker.checkItemRow(file, `encounter ${enc.id}`, row, seenItems)) continue;
        if (row.chance !== undefined && !(row.chance >= 0 && row.chance <= 1)) {
          report(file, `encounter ${enc.id}: item ${row.item} chance must be between 0 and 1`);
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
      portrait: e.portrait,
      displayID: e.displayID,
      npc: e.npc,
      level: e.level,
      creatureType: e.creatureType,
      quests: e.quests,
      loot: e.loot.map((r) => ({ item: r.item, name: r.name, chance: r.chance })),
    })),
  };
  return JSON.stringify(ordered, null, 2) + "\n";
}
