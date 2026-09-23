import assert from "node:assert/strict";
import test from "node:test";
import { type ScannedItem } from "../../src/items.js";
import { type RecipeSource, buildRecipes, linkRecipeItems, shipsRecipe, slugOf } from "../../src/recipes.js";

/** A handful of rows shaped like wago.tools' CSV output (every value a string). */
function source(): RecipeSource {
  return {
    skillLine: [
      {
        ID: "164",
        DisplayName_lang: "Blacksmithing",
        CategoryID: "11",
        ParentSkillLineID: "0",
        SpellIconFileID: "136241",
      },
      {
        ID: "2938",
        DisplayName_lang: "Blacksmithing",
        CategoryID: "11",
        ParentSkillLineID: "164",
        SpellIconFileID: "136241",
      },
      { ID: "129", DisplayName_lang: "First Aid", CategoryID: "9", ParentSkillLineID: "0", SpellIconFileID: "135966" },
      { ID: "40", DisplayName_lang: "Poisons", CategoryID: "9", ParentSkillLineID: "0", SpellIconFileID: "136242" },
      { ID: "2988", DisplayName_lang: "Poisons", CategoryID: "9", ParentSkillLineID: "40", SpellIconFileID: "0" },
      { ID: "762", DisplayName_lang: "Riding", CategoryID: "9", ParentSkillLineID: "0", SpellIconFileID: "132164" },
      {
        ID: "2933",
        DisplayName_lang: "Test Profession [DNT]",
        CategoryID: "11",
        ParentSkillLineID: "0",
        SpellIconFileID: "134400",
      },
    ],
    skillLineAbility: [
      // Copper Chain Belt: 1 / 70 / 90 / 110, in "Mail Belts".
      {
        ID: "1",
        SkillLine: "164",
        Spell: "2661",
        MinSkillLineRank: "1",
        ClassMask: "0",
        AcquireMethod: "0",
        TrivialSkillLineRankHigh: "110",
        TrivialSkillLineRankLow: "70",
        TradeSkillCategoryID: "2466",
      },
      // Rough Sharpening Stone: learned with the profession.
      {
        ID: "2",
        SkillLine: "164",
        Spell: "2660",
        MinSkillLineRank: "1",
        ClassMask: "0",
        AcquireMethod: "1",
        TrivialSkillLineRankHigh: "55",
        TrivialSkillLineRankLow: "15",
        TradeSkillCategoryID: "2460",
      },
      // The profession's own skill spell: no reagents, no item -> not a recipe.
      {
        ID: "3",
        SkillLine: "164",
        Spell: "2018",
        MinSkillLineRank: "1",
        ClassMask: "0",
        AcquireMethod: "0",
        TrivialSkillLineRankHigh: "0",
        TrivialSkillLineRankLow: "0",
        TradeSkillCategoryID: "0",
      },
      // An enchant listed under the tier skill line: no item, needs reagents.
      {
        ID: "4",
        SkillLine: "2938",
        Spell: "13380",
        MinSkillLineRank: "1",
        ClassMask: "0",
        AcquireMethod: "0",
        TrivialSkillLineRankHigh: "130",
        TrivialSkillLineRankLow: "90",
        TradeSkillCategoryID: "2502",
      },
      // Instant Poison: a rogue poison, class-restricted but a secondary profession all the same.
      {
        ID: "5",
        SkillLine: "40",
        Spell: "8681",
        MinSkillLineRank: "1",
        ClassMask: "8",
        AcquireMethod: "0",
        TrivialSkillLineRankHigh: "60",
        TrivialSkillLineRankLow: "20",
        TradeSkillCategoryID: "2734",
      },
      // Linen Bandage: a secondary profession's recipe.
      {
        ID: "6",
        SkillLine: "129",
        Spell: "3275",
        MinSkillLineRank: "1",
        ClassMask: "0",
        AcquireMethod: "0",
        TrivialSkillLineRankHigh: "60",
        TrivialSkillLineRankLow: "30",
        TradeSkillCategoryID: "0",
      },
      // Test profession content.
      {
        ID: "7",
        SkillLine: "2933",
        Spell: "1240345",
        MinSkillLineRank: "1",
        ClassMask: "0",
        AcquireMethod: "0",
        TrivialSkillLineRankHigh: "20",
        TrivialSkillLineRankLow: "10",
        TradeSkillCategoryID: "0",
      },
    ],
    spellReagents: [
      { ID: "1", SpellID: "2661", Reagent_0: "2840", ReagentCount_0: "6", Reagent_1: "0", ReagentCount_1: "0" },
      { ID: "2", SpellID: "2660", Reagent_0: "2835", ReagentCount_0: "1" },
      { ID: "3", SpellID: "13380", Reagent_0: "10938", ReagentCount_0: "1", Reagent_1: "10940", ReagentCount_1: "2" },
      { ID: "4", SpellID: "8681", Reagent_0: "2928", ReagentCount_0: "1", Reagent_1: "3371", ReagentCount_1: "1" },
      { ID: "5", SpellID: "3275", Reagent_0: "2589", ReagentCount_0: "1" },
      { ID: "6", SpellID: "1240345", Reagent_0: "2770", ReagentCount_0: "1" },
    ],
    spellEffect: [
      { ID: "1", SpellID: "2661", Effect: "24", EffectItemType: "2851", EffectBasePointsF: "1", Variance: "0" },
      {
        ID: "2",
        SpellID: "2660",
        Effect: "24",
        EffectItemType: "2862",
        EffectBasePointsF: "3",
        Variance: "0.66666668653",
      },
      { ID: "3", SpellID: "2018", Effect: "118", EffectItemType: "0", EffectBasePointsF: "1", Variance: "0" },
      { ID: "4", SpellID: "13380", Effect: "53", EffectItemType: "0", EffectBasePointsF: "0", Variance: "0" },
      { ID: "5", SpellID: "8681", Effect: "24", EffectItemType: "6947", EffectBasePointsF: "1", Variance: "0" },
      { ID: "6", SpellID: "3275", Effect: "24", EffectItemType: "1251", EffectBasePointsF: "1", Variance: "0" },
      { ID: "7", SpellID: "1240345", Effect: "24", EffectItemType: "2840", EffectBasePointsF: "1", Variance: "0" },
    ],
    spellTotems: [
      {
        ID: "1",
        SpellID: "2661",
        RequiredTotemCategoryID_0: "162",
        RequiredTotemCategoryID_1: "0",
        Totem_0: "0",
        Totem_1: "0",
      },
      {
        ID: "2",
        SpellID: "13380",
        RequiredTotemCategoryID_0: "373",
        RequiredTotemCategoryID_1: "0",
        Totem_0: "0",
        Totem_1: "0",
      },
    ],
    tradeSkillCategory: [
      { ID: "2425", Name_lang: "Blacksmithing", ParentTradeSkillCategoryID: "0", SkillLineID: "164", OrderIndex: "0" },
      {
        ID: "2460",
        Name_lang: "Weapon Stones",
        ParentTradeSkillCategoryID: "2425",
        SkillLineID: "2938",
        OrderIndex: "20",
      },
      {
        ID: "2466",
        Name_lang: "Mail Belts",
        ParentTradeSkillCategoryID: "2425",
        SkillLineID: "2938",
        OrderIndex: "160",
      },
      {
        ID: "2502",
        Name_lang: "Weapon Enchants",
        ParentTradeSkillCategoryID: "2427",
        SkillLineID: "2940",
        OrderIndex: "130",
      },
      { ID: "2733", Name_lang: "Poisons", ParentTradeSkillCategoryID: "0", SkillLineID: "40", OrderIndex: "0" },
      { ID: "2734", Name_lang: "Poisons", ParentTradeSkillCategoryID: "2733", SkillLineID: "2988", OrderIndex: "0" },
    ],
    spellName: [
      { ID: "2661", Name_lang: "Copper Chain Belt" },
      { ID: "2660", Name_lang: "Rough Sharpening Stone" },
      { ID: "13380", Name_lang: "Enchant Weapon - Minor Striking" },
      { ID: "3275", Name_lang: "Linen Bandage" },
      { ID: "8681", Name_lang: "Instant Poison" },
    ],
    totemCategory: [
      { ID: "162", Name_lang: "Blacksmith Hammer" },
      { ID: "373", Name_lang: "Runed Copper Rod" },
    ],
    itemSparse: [
      // Plans: Copper Chain Belt (Blacksmithing 20); Pattern of the same name for Leatherworking (does not exist, tests the filter).
      { ID: "3609", RequiredSkill: "2938", RequiredSkillRank: "20" },
      { ID: "3610", RequiredSkill: "165", RequiredSkillRank: "35" },
      { ID: "16072", RequiredSkill: "0", RequiredSkillRank: "0" },
    ],
  };
}

function scannedItem(name: string, classID = 9): ScannedItem {
  return { names: { enUS: name }, classID } as ScannedItem;
}

function build() {
  const s = source();
  return buildRecipes(
    s,
    new Map([
      ["enUS", { skillLine: s.skillLine, tradeSkillCategory: s.tradeSkillCategory, totemCategory: s.totemCategory }],
    ]),
  );
}

test("recipes come from profession abilities that make or enchant items", () => {
  const { recipes, skillLines } = build();
  assert.deepEqual(
    [...recipes.keys()].sort((a, b) => a - b),
    [2660, 2661, 3275, 8681, 13380],
  );
  // Skill spells and test professions are left out, and so are professions without recipes;
  // class-restricted abilities are not (rogue poisons are the "Poisons" secondary profession).
  assert.deepEqual(
    [...skillLines.keys()].sort((a, b) => a - b),
    [40, 129, 164],
  );
  assert.equal(skillLines.get(129)?.slug, "first_aid");
  const poison = recipes.get(8681)!;
  assert.deepEqual([poison.skillLineID, poison.itemID, poison.categoryID], [40, 6947, 2734]);
});

test("thresholds, reagents, tools and categories are read from the client's tables", () => {
  const { recipes, categories } = build();
  const belt = recipes.get(2661)!;
  assert.equal(belt.name, "Copper Chain Belt");
  assert.equal(belt.skillLineID, 164);
  assert.equal(belt.itemID, 2851);
  assert.equal(belt.count, 1);
  assert.deepEqual([belt.minSkill, belt.yellow, belt.green, belt.grey], [1, 70, 90, 110]);
  assert.deepEqual(belt.reagents, [[2840, 6]]);
  assert.deepEqual(belt.tools, [162]);
  assert.equal(belt.categoryID, 2466);
  assert.equal(belt.auto, false);
  // Categories of the tier skill line belong to the root profession.
  assert.deepEqual(categories.get(2466), { id: 2466, skillLineID: 164, order: 160, name: "Mail Belts" });
  assert.equal(categories.has(2502), false, "categories of professions without recipes are dropped");
});

test("a varying amount becomes a range and auto-learned recipes are flagged", () => {
  const stone = build().recipes.get(2660)!;
  assert.deepEqual(stone.count, [2, 4]);
  assert.equal(stone.auto, true);
});

test("an enchant listed under the tier skill line is a recipe of the root profession without an item", () => {
  const enchant = build().recipes.get(13380)!;
  assert.equal(enchant.skillLineID, 164);
  assert.equal(enchant.itemID, 0);
  assert.deepEqual(enchant.reagents, [
    [10938, 1],
    [10940, 2],
  ]);
  assert.deepEqual(enchant.tools, [373]);
});

test("names are collected per locale for the shipped professions, categories and tools", () => {
  const names = build().names.get("enUS")!;
  assert.deepEqual(
    [...names.skillLines],
    [
      [164, "Blacksmithing"],
      [129, "First Aid"],
      [40, "Poisons"],
    ],
  );
  assert.deepEqual(
    [...names.categories],
    [
      [2460, "Weapon Stones"],
      [2466, "Mail Belts"],
      [2734, "Poisons"],
    ],
  );
  assert.equal(names.tools.get(162), "Blacksmith Hammer");
});

test("a recipe ships when its item was scanned; an enchant when all its reagents were", () => {
  const { recipes } = build();
  const scanned = (ids: number[]) => new Map(ids.map((id) => [id, {} as ScannedItem]));
  assert.equal(shipsRecipe(recipes.get(2661)!, scanned([2851])), true);
  assert.equal(shipsRecipe(recipes.get(2661)!, scanned([2840])), false, "reagents alone don't confirm an item recipe");
  assert.equal(shipsRecipe(recipes.get(13380)!, scanned([10938, 10940])), true);
  assert.equal(shipsRecipe(recipes.get(13380)!, scanned([10938])), false);
});

test("scanned recipe items are linked to the recipe they teach, with the skill to learn it", () => {
  const tables = build();
  const items = new Map<number, ScannedItem>([
    [3609, scannedItem("Plans: Copper Chain Belt")],
    [3610, scannedItem("Pattern: Copper Chain Belt")], // Leatherworking has no such recipe
    [16072, scannedItem("Formula: Enchant Weapon - Minor Striking")], // not in ItemSparse: matched by name alone
    [2851, scannedItem("Copper Chain Belt", 4)], // the product, not a recipe item
  ]);
  linkRecipeItems(tables, items);
  const belt = tables.recipes.get(2661)!;
  assert.equal(belt.taughtBy, 3609);
  assert.equal(belt.learnSkill, 20);
  const enchant = tables.recipes.get(13380)!;
  assert.equal(enchant.taughtBy, 16072);
  assert.equal(enchant.learnSkill, 0);
  assert.equal(tables.recipes.get(2660)!.taughtBy, 0);

  // Linking again after the scans changed starts from scratch.
  items.delete(3609);
  linkRecipeItems(tables, items);
  assert.equal(belt.taughtBy, 0);
  assert.equal(belt.learnSkill, 0);
});

test("slugs are file names", () => {
  assert.equal(slugOf("First Aid"), "first_aid");
  assert.equal(slugOf("Test Profession [DNT]"), "test_profession_dnt");
});
