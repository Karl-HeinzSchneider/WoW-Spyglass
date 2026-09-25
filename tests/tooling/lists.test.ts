import assert from "node:assert/strict";
import test from "node:test";
import { Checker } from "../../src/curated.js";
import { rowsOf, serializeList, validateLists, type ListFile, type ListSection } from "../../src/lists.js";
import { type Reference } from "../../src/reference.js";

function reputationFile(): ListFile {
  return {
    path: ".contribute/data/reputation/test_faction.json",
    kind: "reputation",
    slug: "test_faction",
    data: {
      name: "Test Faction",
      faction: 42,
      rewards: {
        Friendly: [{ item: 100, name: "Friendly Reward" }],
        Exalted: [{ item: 200, name: "Exalted Reward", side: "Alliance" }],
      },
    },
  };
}

test("reputation reward groups flatten to rows with their standing", () => {
  assert.deepEqual(rowsOf(reputationFile()), [
    { item: 100, name: "Friendly Reward", standing: "Friendly" },
    { item: 200, name: "Exalted Reward", side: "Alliance", standing: "Exalted" },
  ]);
});

test("reputation serialization keeps standing as the group instead of a row field", () => {
  const serialized = JSON.parse(serializeList(reputationFile())) as Record<string, unknown>;
  assert.deepEqual(serialized.rewards, {
    Friendly: [{ item: 100, name: "Friendly Reward" }],
    Exalted: [{ item: 200, name: "Exalted Reward", side: "Alliance" }],
  });
});

/** A crafting file with the subheaders that group a profession's category folders. */
function craftingFile(sections: ListSection[]): ListFile {
  return {
    path: ".contribute/data/crafting/blacksmithing.json",
    kind: "crafting",
    slug: "blacksmithing",
    data: { name: "Blacksmithing", skillLine: 164, sections, recipes: [] },
  };
}

/** The reference data a crafting file without rows is checked against. */
function sectionChecker(fix: boolean): Checker {
  const categories = new Map([
    [2469, { id: 2469, skillLineID: 164, order: 30, name: "Plate Helmets" }],
    [2470, { id: 2470, skillLineID: 164, order: 40, name: "Plate Pauldrons" }],
    [2553, { id: 2553, skillLineID: 165, order: 50, name: "Leather Helmets" }],
  ]);
  const skillLines = new Map([[164, { id: 164, name: "Blacksmithing", icon: 0, slug: "blacksmithing" }]]);
  return new Checker({ categories, skillLines, recipes: new Map(), items: new Map() } as Reference, fix);
}

test("crafting sections keep their shape through a fix rewrite", () => {
  const sections = [{ name: "Plate Armor", categories: [2469, 2470] }];
  const serialized = JSON.parse(serializeList(craftingFile(sections))) as Record<string, unknown>;
  assert.deepEqual(serialized.sections, sections, "fix must not drop the sections it rewrites");
});

test("a section's categories may be named and are resolved to ids by fix", () => {
  const file = craftingFile([{ name: "Plate Armor", categories: ["Plate Helmets", 2470] }]);
  const checker = sectionChecker(true);
  validateLists([file], checker);
  assert.deepEqual(file.data.sections?.[0]?.categories, [2469, 2470]);
  assert.deepEqual(
    checker.problems.filter((p) => !p.fixable && !p.warning),
    [],
  );
});

test("sections reject other professions' categories, unknown names and doubled categories", () => {
  const file = craftingFile([
    { name: "Plate Armor", categories: [2469, 2553, "Nope"] },
    { name: "Also Plate", categories: [2469] },
  ]);
  const checker = sectionChecker(false);
  validateLists([file], checker);
  const errors = checker.problems.filter((p) => !p.fixable && !p.warning).map((p) => p.message);
  assert.equal(errors.length, 3, errors.join("\n"));
  assert.match(errors[0]!, /category 2553 is not a category of skillLine 164/);
  assert.match(errors[1]!, /no category of this profession is named "Nope"/);
  assert.match(errors[2]!, /category 2469 is already in section "Plate Armor"/);
});

/** A collections file carrying a panel, checked against the other lists' ids. */
function panelFile(panel: unknown[]): ListFile {
  return {
    path: ".contribute/data/collections/mounts.json",
    kind: "collections",
    slug: "mounts",
    data: { name: "Mounts", panel: panel as ListFile["data"]["panel"], items: [] },
  };
}

test("a panel keeps its widgets through a fix rewrite", () => {
  const panel = [{ header: "Where" }, { button: "Show on map", map: [1451, 51.2, 38.3] }];
  const serialized = JSON.parse(serializeList(panelFile(panel))) as Record<string, unknown>;
  assert.deepEqual(serialized.panel, panel, "fix must not drop the panel it rewrites");
});

test("panel widgets are checked against the list's kind and the other lists", () => {
  const file = panelFile([
    { header: "Fine" },
    { checkbox: "Only my faction", filter: "side" },
    { dropdown: "Source", field: "source" },
    { button: "Pets", open: "collections/mounts" },
    { bar: "reputation" },
    { checkbox: "Reached", filter: "standing" },
    { dropdown: "Rank", field: "rank" },
    { button: "Nowhere", open: "collections/pets" },
    { button: "Both", open: "raids", map: [1451, 1, 2] },
    { text: "Two types", header: "at once" },
  ]);
  const checker = sectionChecker(false);
  validateLists([file], checker);
  const errors = checker.problems.filter((p) => !p.fixable && !p.warning).map((p) => p.message);
  assert.equal(errors.length, 6, errors.join("\n"));
  assert.match(errors[0]!, /panel\[4\]: a reputation bar needs the list's `faction`/);
  assert.match(errors[1]!, /panel\[5\]: filter `standing` only works in reputation lists/);
  assert.match(errors[2]!, /panel\[6\]: `field` must be a row field of collections lists/);
  assert.match(errors[3]!, /panel\[7\]: `open` names no list "pets" in collections/);
  assert.match(errors[4]!, /panel\[8\]: a button needs exactly one action/);
  assert.match(errors[5]!, /panel\[9\]: needs exactly one of/);
});
