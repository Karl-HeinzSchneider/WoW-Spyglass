import { readdirSync, readFileSync } from "node:fs";
import { basename, resolve } from "node:path";
import { LIST_DIRS, LIST_KINDS, type ListKind } from "./config.js";
import { type Checker, type CuratedItemRow } from "./curated.js";

/**
 * A curated item list: .contribute/data/<kind>/<name>.json, one file per profession (crafting),
 * battleground or rank set (pvp), collection type (collections) or faction (reputation). The
 * file name is the list's id, `name` is what the browser shows, and the rows are items with
 * the fields the kind knows (see ROW_FIELDS). Unlike the instance files, nothing here comes
 * from a game table, so `name` is the display name, not informational.
 */
export interface CuratedList {
  /** Display name of the list, e.g. "Blacksmithing" or "Argent Dawn". */
  name: string;
  /** Texture path shown on the tile, e.g. "Interface\\Icons\\Trade_BlackSmithing". */
  icon?: string;
  /** Wide picture filling the tile (texture path or fileID), instead of the icon. */
  background?: string | number;
  /** Part of `background` to show: [left, right, top, bottom] in 0..1; the whole texture when omitted. */
  backgroundCoords?: [number, number, number, number];
  /** Small text in the tile's bottom-left corner, e.g. "Alliance" or "Level 40+". */
  info?: string;
  /** Position among the module's tiles; lower first, by name when equal or missing. */
  order?: number;
  /** reputation: the game's FactionID. */
  faction?: number;
  /** crafting: the game's SkillLine id of the profession. */
  skillLine?: number;
  /** The rows, under the kind's key (ROWS_KEY): `recipes`, `rewards` or `items`. */
  recipes?: CuratedListRow[];
  rewards?: CuratedListRow[];
  items?: CuratedListRow[];
}

/**
 * One item of a list. Besides the item, every kind has its own optional fields (ROW_FIELDS);
 * `group` overrides the browser's default grouping (by standing, rank, skill tier) with a label
 * of the contributor's choosing.
 */
export interface CuratedListRow extends CuratedItemRow {
  group?: string;
  /** crafting: the recipe's spell id. */
  spell?: number;
  /** crafting: required profession skill. */
  skill?: number;
  /** crafting, collections: where it comes from, free text ("Trainer", "Vendor: Ogunaro Wolfrunner"). */
  source?: string;
  /** pvp: required honor rank 1..14. */
  rank?: number;
  /** pvp, reputation: required standing, "Neutral" .. "Exalted". */
  standing?: string;
  /** Faction restriction, "Alliance" or "Horde"; omitted = both. */
  side?: string;
}

export interface ListFile {
  path: string;
  kind: ListKind;
  /** The list id, from the file name: ForeverLoot/db/generated/<kind>/<slug>.lua and Data.lists[kind][slug]. */
  slug: string;
  data: CuratedList;
}

/** The key the rows live under, per kind. */
export const ROWS_KEY: Record<ListKind, "recipes" | "rewards" | "items"> = {
  crafting: "recipes",
  pvp: "rewards",
  collections: "items",
  reputation: "rewards",
};

/** The list-level id fields each kind may carry, checked to be integers and passed through to Lua. */
const LIST_ID_FIELDS: Record<ListKind, (keyof CuratedList)[]> = {
  crafting: ["skillLine"],
  pvp: [],
  collections: [],
  reputation: ["faction"],
};

export const STANDINGS = ["Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted"];
const SIDES = ["Alliance", "Horde"];

/** What a row field must look like: a number range, a string, or one of a fixed set of strings. */
type FieldSpec = { type: "integer"; min?: number; max?: number } | { type: "string" } | { type: "enum"; values: string[] };

const FIELD_SPECS: Record<string, FieldSpec> = {
  group: { type: "string" },
  spell: { type: "integer", min: 1 },
  skill: { type: "integer", min: 0 },
  source: { type: "string" },
  rank: { type: "integer", min: 1, max: 14 },
  standing: { type: "enum", values: STANDINGS },
  side: { type: "enum", values: SIDES },
};

/** Row fields each kind accepts (besides `item`, `name` and `group`); the emit order in Lua. */
export const ROW_FIELDS: Record<ListKind, (keyof CuratedListRow)[]> = {
  crafting: ["spell", "skill", "source"],
  pvp: ["rank", "standing", "side"],
  collections: ["source", "side"],
  reputation: ["standing", "side"],
};

export function rowsOf(file: ListFile): CuratedListRow[] {
  return file.data[ROWS_KEY[file.kind]] ?? [];
}

export function loadLists(): ListFile[] {
  const files: ListFile[] = [];
  for (const kind of LIST_KINDS) {
    let entries: string[] = [];
    try {
      entries = readdirSync(LIST_DIRS[kind]).filter((f) => f.endsWith(".json")).sort();
    } catch {
      continue; // folder may not exist yet
    }
    for (const entry of entries) {
      const path = resolve(LIST_DIRS[kind], entry);
      const data = JSON.parse(readFileSync(path, "utf-8")) as CuratedList;
      files.push({ path, kind, slug: basename(entry, ".json"), data });
    }
  }
  return files;
}

function checkField(value: unknown, spec: FieldSpec): string | undefined {
  switch (spec.type) {
    case "integer":
      if (!Number.isInteger(value)) return "must be an integer";
      if (spec.min !== undefined && (value as number) < spec.min) return `must be at least ${spec.min}`;
      if (spec.max !== undefined && (value as number) > spec.max) return `must be at most ${spec.max}`;
      return undefined;
    case "string":
      return typeof value === "string" && value !== "" ? undefined : "must be a non-empty string";
    case "enum":
      return spec.values.includes(value as string) ? undefined : `must be one of ${spec.values.join(", ")}`;
  }
}

/** Validates the list files: display fields, the kind's id fields and every row (via the checker). */
export function validateLists(files: ListFile[], checker: Checker): void {
  for (const file of files) {
    const d = file.data;
    if (!/^[a-z0-9_]+$/.test(file.slug)) {
      checker.report(file, "file name must be lowercase letters, digits and underscores (it is the list's id)");
    }
    if (typeof d.name !== "string" || d.name === "") {
      checker.report(file, "`name` must be a non-empty string (it is the displayed name)");
    }
    if (d.order !== undefined && typeof d.order !== "number") checker.report(file, "`order` must be a number");
    if (d.info !== undefined && typeof d.info !== "string") checker.report(file, "`info` must be a string");
    for (const field of LIST_ID_FIELDS[file.kind]) {
      if (d[field] !== undefined && !Number.isInteger(d[field])) checker.report(file, `\`${field}\` must be an integer id`);
    }
    for (const field of ["faction", "skillLine"] as const) {
      if (d[field] !== undefined && !LIST_ID_FIELDS[file.kind].includes(field)) {
        checker.report(file, `\`${field}\` is not a field of ${file.kind} lists`);
      }
    }

    const key = ROWS_KEY[file.kind];
    const rows = d[key];
    if (rows === undefined) {
      checker.report(file, `\`${key}\` is missing`, true);
      if (checker.fix) d[key] = [];
      else continue;
    } else if (!Array.isArray(rows)) {
      checker.report(file, `\`${key}\` must be an array`);
      continue;
    }
    for (const other of ["recipes", "rewards", "items"] as const) {
      if (other !== key && d[other] !== undefined) checker.report(file, `\`${other}\` is not the rows key of ${file.kind} lists (use \`${key}\`)`);
    }

    const seenItems = new Set<number>();
    const allowed = new Set<string>(["item", "name", "group", ...ROW_FIELDS[file.kind]]);
    for (const row of rowsOf(file)) {
      const where = `${key} ${row.item ?? row.name ?? "?"}`;
      for (const [field, value] of Object.entries(row)) {
        if (!allowed.has(field)) {
          checker.report(file, `${where}: unknown field \`${field}\``);
          continue;
        }
        const spec = FIELD_SPECS[field];
        const problem = spec && value !== undefined ? checkField(value, spec) : undefined;
        if (problem) checker.report(file, `${where}: \`${field}\` ${problem}`);
      }
      checker.checkItemRow(file, where, row, seenItems);
    }
  }
}

/** Stable key order so `fix` produces minimal diffs. */
export function serializeList(file: ListFile): string {
  const d = file.data;
  const ordered: Record<string, unknown> = {
    name: d.name,
    icon: d.icon,
    background: d.background,
    backgroundCoords: d.backgroundCoords,
    info: d.info,
    order: d.order,
  };
  for (const field of LIST_ID_FIELDS[file.kind]) ordered[field] = d[field];
  ordered[ROWS_KEY[file.kind]] = rowsOf(file).map((r) => {
    const row: Record<string, unknown> = { item: r.item, name: r.name };
    for (const field of ROW_FIELDS[file.kind]) row[field] = r[field];
    row.group = r.group;
    return row;
  });
  return JSON.stringify(ordered, null, 2) + "\n";
}
