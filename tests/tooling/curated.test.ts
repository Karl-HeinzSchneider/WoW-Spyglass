import assert from "node:assert/strict";
import test from "node:test";
import { Checker, type CuratedFile, serialize, validate } from "../../src/curated.js";
import { type Reference } from "../../src/reference.js";

/** A one-boss dungeon file; `data` is spread over the defaults so a test only states what it cares about. */
function dungeonFile(data: Partial<CuratedFile["data"]> = {}): CuratedFile {
  return {
    path: ".contribute/data/dungeons/test_dungeon.json",
    folder: "dungeon",
    slug: "test_dungeon",
    data: { map: 36, name: "Test Dungeon", encounters: [{ id: 2747, name: "Test Boss", loot: [] }], ...data },
  };
}

/** The game tables and scans the file above is checked against: one map, its encounters (one by default), two items. */
function dungeonChecker(fix: boolean, encounters = [2747]): Checker {
  const names = new Map([
    [
      "enUS",
      {
        items: new Map([
          [100, "Trash Trinket"],
          [200, "Quest Reward"],
        ]),
        instances: new Map([[36, "Test Dungeon"]]),
        encounters: new Map(encounters.map((id) => [id, "Test Boss"])),
        skillLines: new Map(),
        categories: new Map(),
        tools: new Map(),
      },
    ],
  ]);
  const ref = {
    build: "1.0.0",
    instances: new Map([[36, { id: 36, type: "dungeon", expansionID: 0, encounters }]]),
    encounters: new Map(encounters.map((id) => [id, { id, mapID: 36, order: 0 }])),
    items: new Map([
      [100, {}],
      [200, {}],
    ]),
    itemLocales: ["enUS"],
    names,
  } as unknown as Reference;
  return new Checker(ref, fix);
}

test("fix gives an instance without a trash list an empty one", () => {
  const file = dungeonFile();
  const checker = dungeonChecker(true);
  validate([file], checker);
  assert.deepEqual(file.data.trash, []);
  assert.deepEqual(checker.problems.filter((p) => !p.fixable && !p.warning), []);
});

test("trash and quest rows resolve a name-only row and keep their shape through a fix rewrite", () => {
  const file = dungeonFile({
    trash: [{ name: "Trash Trinket", chance: 0.02 }],
    quests: [{ id: 26, name: "A Test Quest", side: "Alliance", items: [{ item: 200 }] }],
  });
  const checker = dungeonChecker(true);
  validate([file], checker);
  assert.deepEqual(checker.problems.filter((p) => !p.fixable && !p.warning), []);
  const serialized = JSON.parse(serialize(file.data)) as Record<string, unknown>;
  assert.deepEqual(serialized.trash, [{ item: 100, name: "Trash Trinket", chance: 0.02 }]);
  assert.deepEqual(serialized.quests, [
    { id: 26, name: "A Test Quest", side: "Alliance", items: [{ item: 200, name: "Quest Reward" }] },
  ]);
});

test("a quest needs an id, a known side and no duplicate", () => {
  const file = dungeonFile({
    quests: [
      { id: 0, items: [] },
      { id: 26, name: "A Test Quest", side: "Neutral", items: [] },
      { id: 26, name: "A Test Quest", items: [] },
    ],
  });
  const checker = dungeonChecker(false);
  validate([file], checker);
  const errors = checker.problems.filter((p) => !p.fixable && !p.warning).map((p) => p.message);
  assert.equal(errors.length, 3, errors.join("\n"));
  assert.match(errors[0]!, /quest without a positive integer `id`/);
  assert.match(errors[1]!, /quest 26: `side` must be one of Alliance, Horde, Both/);
  assert.match(errors[2]!, /quest 26 listed twice/);
});

test("a quest without a name is only a warning: no game table can supply one", () => {
  const file = dungeonFile({ trash: [], quests: [{ id: 26, items: [{ item: 200, name: "Quest Reward" }] }] });
  const checker = dungeonChecker(false);
  validate([file], checker);
  assert.deepEqual(checker.problems.filter((p) => !p.fixable && !p.warning), []);
  assert.equal(checker.problems.filter((p) => p.warning).length, 1);
  assert.match(checker.problems.find((p) => p.warning)!.message, /quest 26: no `name`/);
});

test("a quest without an id is only a warning: the id is added by hand later", () => {
  const file = dungeonFile({ trash: [], quests: [{ name: "A Test Quest", items: [{ item: 200, name: "Quest Reward" }] }] });
  const checker = dungeonChecker(false);
  validate([file], checker);
  assert.deepEqual(checker.problems.filter((p) => !p.fixable && !p.warning), []);
  assert.deepEqual(
    checker.problems.filter((p) => p.warning).map((p) => p.message),
    ['quest "A Test Quest": no `id`; it isn\'t shipped until it has one'],
  );
});

test("a class quest names one of the classes, and keeps it through a fix rewrite", () => {
  const file = dungeonFile({
    trash: [],
    quests: [
      { id: 26, name: "A Test Quest", class: "Warlock", items: [] },
      { id: 27, name: "Another Quest", class: "Necromancer", items: [] },
    ],
  });
  const checker = dungeonChecker(false);
  validate([file], checker);
  const errors = checker.problems.filter((p) => !p.fixable && !p.warning).map((p) => p.message);
  assert.equal(errors.length, 1, errors.join("\n"));
  assert.match(errors[0]!, /quest 27: `class` must be one of Warrior, .*Warlock, Druid/);
  const serialized = JSON.parse(serialize(file.data)) as { quests: unknown[] };
  assert.deepEqual(serialized.quests[0], { id: 26, name: "A Test Quest", class: "Warlock", items: [] });
});

test("a split map: each file needs an id, a boss may be in one of them only, one in none is a warning", () => {
  const part = (slug: string, data: Partial<CuratedFile["data"]>): CuratedFile => ({ ...dungeonFile({ trash: [], ...data }), slug, path: `.contribute/data/dungeons/${slug}.json` });
  const east = part("test_east", { id: 3601, name: "Test Dungeon: East", encounters: [{ id: 2747, name: "Test Boss", loot: [] }] });
  const west = part("test_west", { name: "Test Dungeon: West", encounters: [{ id: 2747, name: "Test Boss", loot: [] }] });
  const checker = dungeonChecker(false, [2747, 2748]);
  validate([east, west], checker);
  const errors = checker.problems.filter((p) => !p.fixable && !p.warning).map((p) => p.message);
  assert.equal(errors.length, 2, errors.join("\n"));
  assert.match(errors[0]!, /map 36 is split into several files; each needs its own `id`/);
  assert.match(errors[1]!, /encounter 2747 \(Test Boss\) is also listed in .*test_east\.json/);
  const warnings = checker.problems.filter((p) => p.warning).map((p) => p.message);
  assert.deepEqual(warnings, ["map 36: encounters in none of its files: 2748 (Test Boss)"]);
  assert.equal(east.data.name, "Test Dungeon: East", "a part's name is its own, not the map's");
});
