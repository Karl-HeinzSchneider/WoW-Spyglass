import { readdirSync, readFileSync } from "node:fs";
import { basename, resolve } from "node:path";
import { LIST_DIRS, LIST_KINDS, type ListKind } from "./config.js";
import { type Checker, type CuratedItemRow } from "./curated.js";
import { type Recipe, shipsRecipe } from "./recipes.js";

/**
 * A curated item list: .contribute/data/<kind>/<name>.json, one file per profession (crafting),
 * battleground or rank set (pvp), collection type (collections) or faction (reputation). The
 * file name is the list's id, `name` is the fallback display name, and the rows are items with
 * the fields the kind knows (see ROW_FIELDS). Reputation names may be replaced at runtime by
 * the localized name returned for their FactionID.
 */
export interface CuratedList {
  /** Display name, or the readable fallback for a reputation resolved from its FactionID. */
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
  /** crafting: the game's SkillLine id of the profession; the module merges the generated recipes of that profession into the list at runtime. */
  skillLine?: number;
  /** The rows, under the kind's key (ROWS_KEY): `recipes`, `rewards` or `items`. */
  recipes?: CuratedListRow[];
  /** PvP rows, or reputation rows grouped by standing. */
  rewards?: CuratedListRow[] | ReputationRewards;
  items?: CuratedListRow[];
}

/** Reputation rewards are grouped in source; the generator adds `standing` to each Lua row. */
export type ReputationRewards = Partial<Record<Standing, CuratedListRow[]>>;

/**
 * One item of a list. Besides the item, every kind has its own optional fields (ROW_FIELDS);
 * `group` overrides the browser's default grouping (by standing, rank, skill tier) with a label
 * of the contributor's choosing.
 */
export interface CuratedListRow extends CuratedItemRow {
  group?: string;
  /** crafting: the recipe's spell id (`fix` fills it in from the recipe database when the item is made by exactly one recipe of the profession, and the other way round). */
  spell?: number;
  /** crafting: the skill needed to learn the recipe (trainer / recipe item requirement); the game's tables don't carry it. */
  skill?: number;
  /** crafting, collections: where it comes from, free text ("Trainer", "Vendor: Ogunaro Wolfrunner"). */
  source?: string;
  /** pvp: required honor rank 1..14. */
  rank?: number;
  /** PvP standing; generated reputation rows also receive this from their source group. */
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

export const STANDINGS = ["Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted"] as const;
export type Standing = (typeof STANDINGS)[number];
const SIDES = ["Alliance", "Horde"];

/** What a row field must look like: a number range, a string, or one of a fixed set of strings. */
type FieldSpec = { type: "integer"; min?: number; max?: number } | { type: "string" } | { type: "enum"; values: readonly string[] };

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
  const rows = file.data[ROWS_KEY[file.kind]];
  if (Array.isArray(rows)) return rows;
  if (file.kind !== "reputation" || !rows || typeof rows !== "object") return [];

  const grouped = rows as ReputationRewards;
  return STANDINGS.flatMap((standing) => (grouped[standing] ?? []).map((row) => ({ ...row, standing })));
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
    if (file.kind === "reputation") {
      const faction = Number.isInteger(d.faction) ? checker.ref.factions.get(d.faction!) : undefined;
      if (!faction) {
        checker.report(file, `\`faction\` ${d.faction ?? "?"} is not a FactionID with a reputation bar`);
      } else if (d.name !== faction.name) {
        checker.report(file, `name "${d.name}" -> "${faction.name}" (faction ${faction.id})`, true);
        if (checker.fix) d.name = faction.name;
      }
    }
    if (file.kind === "crafting" && d.skillLine !== undefined && !checker.ref.skillLines.has(d.skillLine)) {
      checker.report(file, `\`skillLine\` ${d.skillLine} is not a profession with recipes (${[...checker.ref.skillLines.values()].map((s) => `${s.id} ${s.name}`).join(", ")})`);
    }
    for (const field of ["faction", "skillLine"] as const) {
      if (d[field] !== undefined && !LIST_ID_FIELDS[file.kind].includes(field)) {
        checker.report(file, `\`${field}\` is not a field of ${file.kind} lists`);
      }
    }

    const key = ROWS_KEY[file.kind];
    let rows = d[key];
    if (rows === undefined) {
      checker.report(file, `\`${key}\` is missing`, true);
      if (checker.fix) {
        rows = file.kind === "reputation" ? {} : [];
        if (file.kind === "reputation") d.rewards = rows as ReputationRewards;
        else if (file.kind === "crafting") d.recipes = rows as CuratedListRow[];
        else if (file.kind === "pvp") d.rewards = rows as CuratedListRow[];
        else d.items = rows as CuratedListRow[];
      }
      else continue;
    } else if (file.kind === "reputation" && (Array.isArray(rows) || typeof rows !== "object" || rows === null)) {
      checker.report(file, "`rewards` must be an object grouped by standing");
      continue;
    } else if (file.kind !== "reputation" && !Array.isArray(rows)) {
      checker.report(file, `\`${key}\` must be an array`);
      continue;
    }
    for (const other of ["recipes", "rewards", "items"] as const) {
      if (other !== key && d[other] !== undefined) checker.report(file, `\`${other}\` is not the rows key of ${file.kind} lists (use \`${key}\`)`);
    }

    const seenItems = new Set<number>();
    const allowedFields = ROW_FIELDS[file.kind].filter((field) => file.kind !== "reputation" || field !== "standing");
    const allowed = new Set<string>(["item", "name", "group", ...allowedFields]);
    const groupedRows: { row: CuratedListRow; where: string }[] = [];
    if (file.kind === "reputation") {
      const grouped = rows as ReputationRewards;
      for (const standing of Object.keys(grouped)) {
        if (!STANDINGS.includes(standing as Standing)) {
          checker.report(file, `rewards: unknown standing \`${standing}\``);
          continue;
        }
        const group = grouped[standing as Standing];
        if (!Array.isArray(group)) {
          checker.report(file, `rewards.${standing} must be an array`);
          continue;
        }
        for (const row of group) groupedRows.push({ row, where: `rewards.${standing} ${row.item ?? row.name ?? "?"}` });
      }
    } else {
      for (const row of rowsOf(file)) groupedRows.push({ row, where: `${key} ${row.item ?? row.name ?? (row.spell !== undefined ? `spell ${row.spell}` : "?")}` });
    }

    for (const { row, where } of groupedRows) {
      for (const [field, value] of Object.entries(row)) {
        if (!allowed.has(field)) {
          checker.report(file, `${where}: unknown field \`${field}\``);
          continue;
        }
        const spec = FIELD_SPECS[field];
        const problem = spec && value !== undefined ? checkField(value, spec) : undefined;
        if (problem) checker.report(file, `${where}: \`${field}\` ${problem}`);
      }
      if (file.kind !== "crafting") {
        checker.checkItemRow(file, where, row, seenItems);
        continue;
      }
      // Crafting rows may name a recipe instead of an item: a recipe that makes no item
      // (an enchant) has nothing else to name.
      const recipe = checkRecipeSpell(file, where, row, d.skillLine, checker);
      if (recipe && recipe.itemID === 0) {
        if (row.item !== undefined) checker.report(file, `${where}: spell ${row.spell} (${recipe.name}) makes no item; drop \`item\``);
        continue;
      }
      if (checker.checkItemRow(file, where, row, seenItems) && !recipe) fillRecipeSpell(file, where, row, d.skillLine, checker);
    }
  }

  // Every profession the recipe database knows should have its tile.
  const listed = new Set(files.filter((f) => f.kind === "crafting").map((f) => f.data.skillLine));
  for (const skillLine of checker.ref.skillLines.values()) {
    if (listed.has(skillLine.id)) continue;
    if (![...checker.ref.recipes.values()].some((r) => r.skillLineID === skillLine.id && shipsRecipe(r, checker.ref.items))) continue;
    checker.warn({ path: resolve(LIST_DIRS.crafting, `${skillLine.slug}.json`) }, `no crafting list for ${skillLine.name} (skillLine ${skillLine.id}); add one to show its recipes`);
  }
}

/**
 * A crafting row's `spell` against the recipe database: it must be a recipe of the file's
 * profession (an unknown one is allowed with a warning: server-side recipes are not in the
 * client's tables) and, with `fix`, fills in the item it makes. Returns the recipe when known.
 */
function checkRecipeSpell(file: ListFile, where: string, row: CuratedListRow, skillLine: number | undefined, checker: Checker): Recipe | undefined {
  const { ref, fix } = checker;
  if (row.spell === undefined) return undefined;
  const recipe = ref.recipes.get(row.spell);
  if (!recipe) {
    checker.warn(file, `${where}: spell ${row.spell} is not a recipe the client's tables know; it stays a plain row`);
    return undefined;
  }
  if (skillLine !== undefined && recipe.skillLineID !== skillLine) {
    checker.report(file, `${where}: spell ${row.spell} (${recipe.name}) belongs to skillLine ${recipe.skillLineID}, not ${skillLine}`);
  }
  if (recipe.itemID > 0 && row.item === undefined && row.name === undefined) {
    checker.report(file, `${where}: spell ${row.spell} makes item ${recipe.itemID} (${recipe.name})`, true);
    if (fix) row.item = recipe.itemID;
  } else if (recipe.itemID > 0 && row.item !== undefined && row.item !== recipe.itemID) {
    checker.report(file, `${where}: spell ${row.spell} (${recipe.name}) makes item ${recipe.itemID}, not ${row.item}`);
  }
  return recipe;
}

/** With `fix`, an item row gets its `spell` when exactly one recipe of the profession makes the item. */
function fillRecipeSpell(file: ListFile, where: string, row: CuratedListRow, skillLine: number | undefined, checker: Checker): void {
  const { ref, fix } = checker;
  if (row.item === undefined || row.spell !== undefined || skillLine === undefined) return;
  const makers: Recipe[] = [...ref.recipes.values()].filter((r) => r.skillLineID === skillLine && r.itemID === row.item);
  const maker = makers.length === 1 ? makers[0] : undefined;
  if (maker) {
    checker.report(file, `${where}: made by spell ${maker.spellID} (${maker.name})`, true);
    if (fix) row.spell = maker.spellID;
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
  const serializeRow = (r: CuratedListRow) => {
    const row: Record<string, unknown> = { item: r.item, name: r.name };
    for (const field of ROW_FIELDS[file.kind]) {
      if (file.kind !== "reputation" || field !== "standing") row[field] = r[field];
    }
    row.group = r.group;
    return row;
  };
  if (file.kind === "reputation") {
    const grouped = (d.rewards ?? {}) as ReputationRewards;
    ordered.rewards = Object.fromEntries(
      STANDINGS.filter((standing) => Object.hasOwn(grouped, standing)).map((standing) => [standing, (grouped[standing] ?? []).map(serializeRow)]),
    );
  } else {
    ordered[ROWS_KEY[file.kind]] = rowsOf(file).map(serializeRow);
  }
  return JSON.stringify(ordered, null, 2) + "\n";
}
