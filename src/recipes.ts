import { type Config, FALLBACK_LOCALE } from "./config.js";
import { type ScannedItem } from "./items.js";
import { type Table, fetchTable, int } from "./wago.js";

/**
 * The recipe database: every profession recipe the client knows, from wago.tools' spell and
 * skill tables for the pinned build. Recipes are spells; a recipe is a SkillLineAbility row of a
 * profession whose spell either creates an item (SpellEffect 24) or enchants one (53/54) and
 * that needs reagents (SpellReagents). Items are server-side on this client, so which of these
 * recipes actually exist is decided by the scans (see `shipsRecipe`), not here.
 */
export interface RecipeTables {
  /** Root professions (SkillLine rows of category 11 = profession or 9 = secondary) that have at least one recipe. */
  skillLines: Map<number, SkillLine>;
  /** The trade skill window's headers ("Plate Helmets", "Elixirs"), keyed by TradeSkillCategory id. */
  categories: Map<number, TradeSkillCategory>;
  /** Recipes keyed by their spell id. */
  recipes: Map<number, Recipe>;
  /** Per-locale names of skill lines, categories and tools (TotemCategory ids). */
  names: Map<string, RecipeNames>;
  /** ItemSparse's skill requirement of items that have one (recipe items: "Plans: X" needs Blacksmithing 75), keyed by item id. */
  itemSkills: Map<number, { skillLineID: number; rank: number }>;
}

export interface SkillLine {
  id: number;
  /** enUS name, for file names and comments. */
  name: string;
  /** SpellIconFileID, a fileDataID the client can draw. */
  icon: number;
  /** Lowercase file-name form of the enUS name ("first_aid"). */
  slug: string;
}

export interface TradeSkillCategory {
  id: number;
  /** The root profession the category belongs to (tier skill lines are folded into their parent). */
  skillLineID: number;
  order: number;
  /** enUS name, for comments. */
  name: string;
}

export interface Recipe {
  spellID: number;
  /** enUS spell name, for comments. */
  name: string;
  skillLineID: number;
  /** Created item id; 0 when the recipe makes no item (enchants). */
  itemID: number;
  /** Items made per craft; [min, max] when the amount varies. */
  count: number | [number, number];
  /** SkillLineAbility.MinSkillLineRank; 1 for nearly every Classic recipe (the real requirement lives on trainers and recipe items). */
  minSkill: number;
  /** Skill needed to learn it from the recipe item that teaches it (`taughtBy`); 0 = no such item known. Set by `linkRecipeItems`. */
  learnSkill: number;
  /** Scanned recipe item ("Plans: Copper Chain Belt") that teaches it; 0 = none known. Set by `linkRecipeItems`. */
  taughtBy: number;
  /** Skill at which the recipe turns yellow, green and grey; orange below yellow. */
  yellow: number;
  green: number;
  grey: number;
  /** TradeSkillCategory id, 0 = none. */
  categoryID: number;
  /** [itemID, count] pairs. */
  reagents: [number, number][];
  /** Required tools as TotemCategory ids (Blacksmith Hammer, Anvil, Runed Copper Rod, ...). */
  tools: number[];
  /** Learned automatically when the skill reaches `minSkill` (AcquireMethod 1 or 2). */
  auto: boolean;
}

export interface RecipeNames {
  skillLines: Map<number, string>;
  categories: Map<number, string>;
  tools: Map<number, string>;
}

/** The raw tables `buildRecipes` reads, so tests can feed it small ones. */
export interface RecipeSource {
  skillLine: Table;
  skillLineAbility: Table;
  spellReagents: Table;
  spellEffect: Table;
  spellTotems: Table;
  tradeSkillCategory: Table;
  spellName: Table;
  totemCategory: Table;
  /** Only `ID`, `RequiredSkill` and `RequiredSkillRank` are read. */
  itemSparse: Table;
}

/** SkillLine.CategoryID values that are professions. */
const SKILL_CATEGORY_PROFESSION = 11;
const SKILL_CATEGORY_SECONDARY = 9;
/** SpellEffect.Effect values: create an item, enchant an item (permanent / temporary). */
const EFFECT_CREATE_ITEM = 24;
const EFFECT_CREATE_ITEM_2 = 157;
const EFFECT_ENCHANT_ITEM = 53;
const EFFECT_ENCHANT_ITEM_TEMPORARY = 54;
/** SkillLineAbility.AcquireMethod: learned when the skill reaches MinSkillLineRank / when the skill is learned. */
const ACQUIRE_ON_SKILL_VALUE = 1;
const ACQUIRE_ON_SKILL_LEARN = 2;
const MAX_REAGENTS = 8;

export function slugOf(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

/**
 * Turns the raw tables into the recipe database. Class-restricted abilities (rogue poisons,
 * which are a secondary skill line of their own) are kept; rows of test skill lines are left
 * out, and professions without any recipe are not listed.
 */
export function buildRecipes(
  source: RecipeSource,
  localeNames: Map<string, Pick<RecipeSource, "skillLine" | "tradeSkillCategory" | "totemCategory">>,
): RecipeTables {
  // Root profession of every skill line: the expansion tiers ("Blacksmithing" 2938 under 164) point at their parent.
  const rootOf = new Map<number, number>();
  const professions = new Map<number, SkillLine>();
  for (const row of source.skillLine) {
    const id = int(row.ID);
    const parent = int(row.ParentSkillLineID);
    rootOf.set(id, parent || id);
    const category = int(row.CategoryID);
    const name = row.DisplayName_lang ?? "";
    if (
      parent === 0 &&
      (category === SKILL_CATEGORY_PROFESSION || category === SKILL_CATEGORY_SECONDARY) &&
      !/\[DNT\]/.test(name)
    ) {
      professions.set(id, { id, name, icon: int(row.SpellIconFileID), slug: slugOf(name) });
    }
  }

  const spellNames = new Map<number, string>();
  for (const row of source.spellName) spellNames.set(int(row.ID), row.Name_lang ?? "");

  const reagents = new Map<number, [number, number][]>();
  for (const row of source.spellReagents) {
    const list: [number, number][] = [];
    for (let i = 0; i < MAX_REAGENTS; i++) {
      const item = int(row[`Reagent_${i}`]);
      if (item > 0) list.push([item, Math.max(1, int(row[`ReagentCount_${i}`]))]);
    }
    if (list.length > 0) reagents.set(int(row.SpellID), list);
  }

  const effects = new Map<number, { itemID: number; count: number | [number, number] } | { enchant: true }>();
  for (const row of source.spellEffect) {
    const effect = int(row.Effect);
    const spellID = int(row.SpellID);
    if (effect === EFFECT_CREATE_ITEM || effect === EFFECT_CREATE_ITEM_2) {
      const base = Math.max(1, Math.round(Number.parseFloat(row.EffectBasePointsF ?? "1") || 1));
      const variance = Number.parseFloat(row.Variance ?? "0") || 0;
      // The client rolls base * (1 ± variance / 2): base 3 with variance 0.67 makes 2-4.
      const spread = Math.round((base * variance) / 2);
      const count: number | [number, number] = spread > 0 ? [Math.max(1, base - spread), base + spread] : base;
      effects.set(spellID, { itemID: int(row.EffectItemType), count });
    } else if ((effect === EFFECT_ENCHANT_ITEM || effect === EFFECT_ENCHANT_ITEM_TEMPORARY) && !effects.has(spellID)) {
      effects.set(spellID, { enchant: true });
    }
  }

  const tools = new Map<number, number[]>();
  for (const row of source.spellTotems) {
    const list = [int(row.RequiredTotemCategoryID_0), int(row.RequiredTotemCategoryID_1)].filter((id) => id > 0);
    if (list.length > 0) tools.set(int(row.SpellID), list);
  }

  const categories = new Map<number, TradeSkillCategory>();
  for (const row of source.tradeSkillCategory) {
    const parent = int(row.ParentTradeSkillCategoryID);
    if (parent === 0) continue; // the profession's own root header
    const skillLineID = rootOf.get(int(row.SkillLineID)) ?? int(row.SkillLineID);
    if (!professions.has(skillLineID)) continue;
    const id = int(row.ID);
    categories.set(id, { id, skillLineID, order: int(row.OrderIndex), name: row.Name_lang ?? "" });
  }

  const recipes = new Map<number, Recipe>();
  for (const row of source.skillLineAbility) {
    const skillLineID = rootOf.get(int(row.SkillLine)) ?? int(row.SkillLine);
    const profession = professions.get(skillLineID);
    if (!profession) continue;
    const spellID = int(row.Spell);
    const made = effects.get(spellID);
    const needs = reagents.get(spellID) ?? [];
    if (!made || (needs.length === 0 && "enchant" in made)) continue;
    if (recipes.has(spellID)) continue; // a spell listed under two skill lines keeps its first
    const yellow = int(row.TrivialSkillLineRankLow);
    const grey = int(row.TrivialSkillLineRankHigh);
    const acquire = int(row.AcquireMethod);
    recipes.set(spellID, {
      spellID,
      name: spellNames.get(spellID) ?? "",
      skillLineID,
      itemID: "enchant" in made ? 0 : made.itemID,
      count: "enchant" in made ? 1 : made.count,
      minSkill: int(row.MinSkillLineRank),
      learnSkill: 0,
      taughtBy: 0,
      yellow,
      green: Math.floor((yellow + grey) / 2),
      grey,
      categoryID: int(row.TradeSkillCategoryID),
      reagents: needs,
      tools: tools.get(spellID) ?? [],
      auto: acquire === ACQUIRE_ON_SKILL_VALUE || acquire === ACQUIRE_ON_SKILL_LEARN,
    });
  }

  const used = new Set([...recipes.values()].map((r) => r.skillLineID));
  const skillLines = new Map([...professions].filter(([id]) => used.has(id)));
  for (const [id, category] of categories) if (!skillLines.has(category.skillLineID)) categories.delete(id);

  const names = new Map<string, RecipeNames>();
  for (const [locale, tables] of localeNames) {
    const table: RecipeNames = { skillLines: new Map(), categories: new Map(), tools: new Map() };
    for (const row of tables.skillLine) {
      const id = int(row.ID);
      if (skillLines.has(id) && row.DisplayName_lang) table.skillLines.set(id, row.DisplayName_lang);
    }
    for (const row of tables.tradeSkillCategory) {
      const id = int(row.ID);
      if (categories.has(id) && row.Name_lang) table.categories.set(id, row.Name_lang);
    }
    for (const row of tables.totemCategory) {
      if (row.Name_lang) table.tools.set(int(row.ID), row.Name_lang);
    }
    names.set(locale, table);
  }

  const itemSkills = new Map<number, { skillLineID: number; rank: number }>();
  for (const row of source.itemSparse) {
    const skillLineID = int(row.RequiredSkill);
    if (skillLineID > 0)
      itemSkills.set(int(row.ID), {
        skillLineID: rootOf.get(skillLineID) ?? skillLineID,
        rank: int(row.RequiredSkillRank),
      });
  }

  return { skillLines, categories, recipes, names, itemSkills };
}

/** "Plans: Copper Chain Belt" -> "Copper Chain Belt"; the prefixes of every profession's recipe items. */
const RECIPE_ITEM_NAME = /^(?:Plans|Pattern|Recipe|Formula|Schematic|Manual|Design|Book|Guide): (.+)$/;
const ITEM_CLASS_RECIPE = 9;

/**
 * Links every scanned recipe item ("Plans: X", item class 9) to the recipe it teaches, by name;
 * ItemSparse's skill requirement on the item decides between professions with a recipe of that
 * name and gives the skill needed to learn it. Recomputed from scratch, so it can run again
 * after an import changed the scans.
 */
export function linkRecipeItems(
  tables: Pick<RecipeTables, "recipes" | "itemSkills">,
  items: Map<number, ScannedItem>,
): void {
  const byName = new Map<string, Recipe[]>();
  for (const recipe of tables.recipes.values()) {
    recipe.taughtBy = 0;
    recipe.learnSkill = 0;
    const list = byName.get(recipe.name);
    if (list) list.push(recipe);
    else byName.set(recipe.name, [recipe]);
  }
  for (const itemID of [...items.keys()].sort((a, b) => a - b)) {
    const item = items.get(itemID)!;
    if (item.classID !== ITEM_CLASS_RECIPE) continue;
    const match = RECIPE_ITEM_NAME.exec(item.names[FALLBACK_LOCALE] ?? "");
    if (!match) continue;
    const skill = tables.itemSkills.get(itemID);
    let candidates = byName.get(match[1] ?? "") ?? [];
    if (skill) candidates = candidates.filter((r) => r.skillLineID === skill.skillLineID);
    const recipe = candidates.length === 1 ? candidates[0] : undefined;
    if (!recipe || recipe.taughtBy !== 0) continue; // the lowest item id wins when several teach it (faction versions)
    recipe.taughtBy = itemID;
    if (skill && skill.rank > 0) recipe.learnSkill = skill.rank;
  }
}

/**
 * Whether a recipe belongs in the shipped database: the item it makes must have been scanned
 * (the client's tables also hold recipes of other seasons whose items this server never had);
 * a recipe that makes no item is shipped when every reagent was scanned.
 */
export function shipsRecipe(recipe: Recipe, items: Map<number, ScannedItem>): boolean {
  if (recipe.itemID > 0) return items.has(recipe.itemID);
  return recipe.reagents.every(([itemID]) => items.has(itemID));
}

export async function loadRecipes(config: Config): Promise<RecipeTables> {
  const { build } = config;
  const table = (name: string, locale = FALLBACK_LOCALE) => fetchTable(name, build, locale);
  const [
    skillLine,
    skillLineAbility,
    spellReagents,
    spellEffect,
    spellTotems,
    tradeSkillCategory,
    spellName,
    totemCategory,
    itemSparse,
  ] = await Promise.all([
    table("SkillLine"),
    table("SkillLineAbility"),
    table("SpellReagents"),
    table("SpellEffect"),
    table("SpellTotems"),
    table("TradeSkillCategory"),
    table("SpellName"),
    table("TotemCategory"),
    table("ItemSparse"),
  ]);
  const source: RecipeSource = {
    skillLine,
    skillLineAbility,
    spellReagents,
    spellEffect,
    spellTotems,
    tradeSkillCategory,
    spellName,
    totemCategory,
    itemSparse,
  };

  const localeNames = new Map<string, Pick<RecipeSource, "skillLine" | "tradeSkillCategory" | "totemCategory">>();
  for (const locale of config.locales) {
    if (locale === FALLBACK_LOCALE) {
      localeNames.set(locale, { skillLine, tradeSkillCategory, totemCategory });
      continue;
    }
    const [lSkill, lCategory, lTotem] = await Promise.all([
      table("SkillLine", locale),
      table("TradeSkillCategory", locale),
      table("TotemCategory", locale),
    ]);
    localeNames.set(locale, { skillLine: lSkill, tradeSkillCategory: lCategory, totemCategory: lTotem });
  }
  return buildRecipes(source, localeNames);
}
