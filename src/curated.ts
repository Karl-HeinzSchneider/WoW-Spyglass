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
  /**
   * The instance's own id when players see its map as several dungeons (Scarlet Monastery's four
   * wings all share map 189): every file of such a map has one, by convention map * 100 + n
   * (18901). Without it the instance id is the map id.
   */
  id?: number;
  /** Informational, filled by `fix`; for a file with an `id` it is the displayed name (no game table has it). */
  name?: string;
  /**
   * Shorter name the browser shows for the instance ("SM: Graveyard"): its tile, breadcrumbs and
   * page title, in every language. Tooltips and filters keep `name`.
   */
  displayName?: string;
  minLevel?: number;
  maxLevel?: number;
  /** Texture path shown in the browser, e.g. "Interface\\Icons\\INV_Misc_Key_13". */
  icon?: string;
  /** Wide picture behind the instance's tile in the browser (texture path or fileID). */
  background?: string | number;
  /** Part of `background` to show: [left, right, top, bottom] in 0..1; the whole texture when omitted. */
  backgroundCoords?: [number, number, number, number];
  encounters: CuratedEncounter[];
  /**
   * What the instance's non-boss enemies drop. Every instance has this category, so `fix` adds
   * an empty list to files that don't have one yet.
   */
  trash?: CuratedLoot[];
  /** The quests that take place in the instance and the items they reward. */
  quests?: CuratedQuest[];
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

/**
 * One quest of an instance and the items it rewards. This client ships no quest table, so both
 * the id and the title are curated: the id is what the game knows the quest by, `name` is what
 * the browser shows when the client cannot resolve the title itself.
 */
export interface CuratedQuest {
  /** Quest id. A quest without one is only warned about and not shipped until it has one. */
  id?: number;
  /** Quest title. Shipped, because no game table can supply it; `fix` never rewrites it. */
  name?: string;
  /** Faction the quest is available to: "Alliance", "Horde" or "Both"; omitted means both. */
  side?: string;
  /** The class a class quest is for ("Warlock"); omitted means any class. */
  class?: string;
  /** The items the quest rewards. */
  items: CuratedItemRow[];
}

/** What `CuratedQuest.side` accepts; leaving it out means the same as "Both". */
export const QUEST_SIDES = ["Alliance", "Horde", "Both"];

/** What `CuratedQuest.class` accepts; shipped as the client's class token (`classToken`). */
export const QUEST_CLASSES = ["Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid"];

/** "Warlock" -> "WARLOCK", the key of the client's LOCALIZED_CLASS_NAMES_MALE and RAID_CLASS_COLORS. */
export function classToken(name: string): string {
  return name.toUpperCase().replace(/ /g, "");
}

/** The id the addon knows the instance by: its own `id` on a split map, else the map id. */
export function instanceIDOf(d: CuratedInstance): number {
  return d.id ?? d.map;
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
      entries = readdirSync(dir)
        .filter((f) => f.endsWith(".json"))
        .sort();
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
      this.warn(
        file,
        `${where}: item ${row.item} (${row.name ?? "?"}) hasn't been scanned yet; /fl scan it in-game and import`,
      );
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
  const report = checker.report.bind(checker);

  // A map is one file, or several that each have an `id` (a map players see as several dungeons).
  const byMap = new Map<number, CuratedFile[]>();
  for (const file of files) {
    const list = byMap.get(file.data.map);
    if (list) list.push(file);
    else byMap.set(file.data.map, [file]);
  }
  const isSplit = (map: number) => byMap.get(map)!.length > 1 || byMap.get(map)!.some((f) => f.data.id !== undefined);
  const seenIDs = new Map<number, string>();
  const listedIn = new Map<number, string>(); // encounter -> the file that lists it

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
    if (d.id !== undefined) {
      if (!Number.isInteger(d.id) || d.id <= 0) report(file, "`id` must be a positive integer (map * 100 + n)");
      else if (ref.instances.has(d.id))
        report(file, `id ${d.id} is the map id of ${nameOf(ref, "instances", d.id)}; use map * 100 + n`);
      else if (seenIDs.has(d.id)) report(file, `id ${d.id} is also used by ${seenIDs.get(d.id)}`);
      seenIDs.set(d.id, file.path);
    } else if (isSplit(d.map)) {
      report(file, `map ${d.map} is split into several files; each needs its own \`id\` (map * 100 + n)`);
    }
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

    if (d.id !== undefined) {
      // A part of a map has no name in any game table: the file's is the one shown.
      if (typeof d.name !== "string" || d.name === "") report(file, "a file with an `id` needs its own `name`");
    } else {
      const instanceName = nameOf(ref, "instances", d.map);
      if (d.name !== instanceName) {
        report(file, `name "${d.name ?? ""}" -> "${instanceName}"`, true);
        if (fix) d.name = instanceName;
      }
    }
    if (d.displayName !== undefined && (typeof d.displayName !== "string" || d.displayName === "")) {
      report(file, "`displayName` must be a non-empty string");
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
      else if (listedIn.has(enc.id))
        report(
          file,
          `encounter ${enc.id} (${nameOf(ref, "encounters", enc.id)}) is also listed in ${listedIn.get(enc.id)}`,
        );
      seenEncounters.add(enc.id);
      listedIn.set(enc.id, file.path);
      // The file's name wins: the server may have renamed a boss the client's table still knows by
      // an old name (Hall of Thanes' Magmatus is "Infurnus" there). `fix` only fills in a missing one.
      if (typeof enc.name !== "string" || enc.name === "") {
        const encName = nameOf(ref, "encounters", enc.id);
        report(file, `encounter ${enc.id}: name -> "${encName}"`, true);
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

    validateTrash(file, checker);
    validateQuests(file, checker);

    // Encounters the game knows but the file doesn't list yet: add empty skeletons in order. A
    // split map's are checked across all its files below, since `fix` can't know which part.
    const missing = isSplit(d.map) ? [] : instance.encounters.filter((id) => !seenEncounters.has(id));
    if (missing.length > 0) {
      report(
        file,
        `missing encounters: ${missing.map((id) => `${id} (${nameOf(ref, "encounters", id)})`).join(", ")}`,
        true,
      );
      if (fix) {
        for (const id of missing) d.encounters.push({ id, name: nameOf(ref, "encounters", id), loot: [] });
        d.encounters.sort((a, b) => (ref.encounters.get(a.id)?.order ?? 0) - (ref.encounters.get(b.id)?.order ?? 0));
      }
    }
  }

  // A split map: every encounter belongs in one of its files; one that is in none is only warned
  // about (listed twice is an error above).
  for (const [map, list] of byMap) {
    const instance = ref.instances.get(map);
    if (!instance || !isSplit(map)) continue;
    const missing = instance.encounters.filter((id) => !listedIn.has(id));
    if (missing.length > 0) {
      checker.warn(
        list[0]!,
        `map ${map}: encounters in none of its files: ${missing.map((id) => `${id} (${nameOf(ref, "encounters", id)})`).join(", ")}`,
      );
    }
  }
}

/**
 * The instance's trash loot: the same rows a boss has. Every instance drops something off its
 * non-boss enemies, so a file without the list gets an empty one instead of nothing at all —
 * the browser shows the category either way and then asks for contributions.
 */
function validateTrash(file: CuratedFile, checker: Checker): void {
  const d = file.data;
  if (d.trash === undefined) {
    checker.report(file, "no `trash` list; every instance has one -> []", true);
    if (!checker.fix) return;
    d.trash = [];
  }
  if (!Array.isArray(d.trash)) {
    checker.report(file, "`trash` must be an array", true);
    if (!checker.fix) return;
    d.trash = [];
  }
  const seen = new Set<number>();
  for (const row of d.trash) {
    if (!checker.checkItemRow(file, "trash", row, seen)) continue;
    if (row.chance !== undefined && !(row.chance >= 0 && row.chance <= 1)) {
      checker.report(file, `trash: item ${row.item} chance must be between 0 and 1`);
    }
  }
}

/**
 * The instance's quests. Only the id is checked against anything (it must be a positive integer
 * and unique in the file) — this client has no quest table, so the title cannot be verified and
 * a quest without one is only a warning.
 */
function validateQuests(file: CuratedFile, checker: Checker): void {
  const d = file.data;
  if (d.quests === undefined) return;
  if (!Array.isArray(d.quests)) {
    checker.report(file, "`quests` must be an array");
    return;
  }
  const seenQuests = new Set<number>();
  for (const quest of d.quests) {
    if (quest.id === undefined) {
      // Titles and rewards often come first; the id is added by hand later.
      checker.warn(file, `quest "${quest.name ?? "?"}": no \`id\`; it isn't shipped until it has one`);
      continue;
    }
    if (!Number.isInteger(quest.id) || quest.id <= 0) {
      checker.report(file, "quest without a positive integer `id`");
      continue;
    }
    if (seenQuests.has(quest.id)) checker.report(file, `quest ${quest.id} listed twice`);
    seenQuests.add(quest.id);
    if (quest.name === undefined || quest.name === "") {
      checker.warn(file, `quest ${quest.id}: no \`name\`; the browser can only show its id`);
    }
    if (quest.side !== undefined && !QUEST_SIDES.includes(quest.side)) {
      checker.report(file, `quest ${quest.id}: \`side\` must be one of ${QUEST_SIDES.join(", ")}`);
    }
    if (quest.class !== undefined && !QUEST_CLASSES.includes(quest.class)) {
      checker.report(file, `quest ${quest.id}: \`class\` must be one of ${QUEST_CLASSES.join(", ")}`);
    }
    if (!Array.isArray(quest.items)) {
      checker.report(file, `quest ${quest.id}: \`items\` must be an array`, true);
      if (checker.fix) quest.items = [];
      else continue;
    }
    // Items may repeat across quests (a shared reward), so each quest counts on its own.
    const seenItems = new Set<number>();
    for (const row of quest.items) checker.checkItemRow(file, `quest ${quest.id}`, row, seenItems);
  }
}

/** Stable key order so `fix` produces minimal diffs. */
export function serialize(d: CuratedInstance): string {
  const ordered = {
    map: d.map,
    id: d.id,
    name: d.name,
    displayName: d.displayName,
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
    trash: d.trash?.map((r) => ({ item: r.item, name: r.name, chance: r.chance })),
    quests: d.quests?.map((q) => ({
      id: q.id,
      name: q.name,
      side: q.side,
      class: q.class,
      items: (q.items ?? []).map((r) => ({ item: r.item, name: r.name })),
    })),
  };
  return JSON.stringify(ordered, null, 2) + "\n";
}
