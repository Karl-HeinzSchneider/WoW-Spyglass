import assert from "node:assert/strict";
import test from "node:test";
import { type Discovered } from "../../src/discovered.js";
import { type ListFile } from "../../src/lists.js";
import { type Recipe } from "../../src/recipes.js";
import { type Reference } from "../../src/reference.js";
import { importTrainers } from "../../src/trainers.js";

function fixture() {
  const discovered = {
    locale: "enUS",
    items: new Map(),
    loot: new Map(),
    trainers: new Map([
      [
        42,
        {
          id: 42,
          name: "Test Trainer",
          locale: "enUS",
          build: "test",
          services: new Map([
            [
              1,
              {
                name: "Copper Belt",
                type: "unavailable",
                skillName: "Blacksmithing",
                skillRank: 75,
                abilityRequirements: new Map(),
                source: "trainer" as const,
              },
            ],
          ]),
        },
      ],
    ]),
  } satisfies Discovered;
  const recipe = {
    spellID: 100,
    name: "Copper Belt",
    skillLineID: 164,
    itemID: 200,
    reagents: [],
  } as unknown as Recipe;
  const ref = {
    build: "test",
    recipes: new Map([[100, recipe]]),
    items: new Map([[200, {}]]),
    names: new Map([["enUS", { skillLines: new Map([[164, "Blacksmithing"]]) }]]),
  } as unknown as Reference;
  const lists = [{ kind: "crafting", data: { skillLine: 164, recipes: [] } }] as unknown as ListFile[];
  const names = new Map([["enUS", new Map([[100, "Copper Belt"]])]]);
  return { discovered, ref, lists, names };
}

test("trainer services create curated recipe rows with skill and source", () => {
  const { discovered, ref, lists, names } = fixture();
  const lines = importTrainers(discovered, ref, lists, names);
  assert.deepEqual(lists[0]?.data.recipes, [{ spell: 100, item: 200, skill: 75, source: "Trainer" }]);
  assert.match(lines[0] ?? "", /1 new/);
});

test("trainer observations update an existing row and retain its other source", () => {
  const { discovered, ref, lists, names } = fixture();
  lists[0]!.data.recipes = [{ item: 200, skill: 1, source: "Vendor" }];
  importTrainers(discovered, ref, lists, names);
  assert.deepEqual(lists[0]?.data.recipes, [{ item: 200, spell: 100, skill: 75, source: "Vendor; Trainer" }]);
});

test("a snapshot from another build does not change curated recipes", () => {
  const { discovered, ref, lists, names } = fixture();
  discovered.trainers.get(42)!.build = "other";
  const lines = importTrainers(discovered, ref, lists, names);
  assert.deepEqual(lists[0]?.data.recipes, []);
  assert.match(lines[0] ?? "", /differs/);
});

test("ambiguous recipe names are not imported", () => {
  const { discovered, ref, lists, names } = fixture();
  ref.recipes.set(101, { ...ref.recipes.get(100)!, spellID: 101, itemID: 201 });
  ref.items.set(201, {} as never);
  names.get("enUS")!.set(101, "Copper Belt");
  discovered.trainers.get(42)!.services.get(1)!.skillName = undefined;
  const lines = importTrainers(discovered, ref, lists, names);
  assert.deepEqual(lists[0]?.data.recipes, []);
  assert.match(lines[0] ?? "", /ambiguous/);
});
