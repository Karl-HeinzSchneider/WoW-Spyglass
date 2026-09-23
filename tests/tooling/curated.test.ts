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

/** The game tables and scans the file above is checked against: one map, one encounter, two items. */
function dungeonChecker(fix: boolean): Checker {
  const names = new Map([
    [
      "enUS",
      {
        items: new Map([
          [100, "Trash Trinket"],
          [200, "Quest Reward"],
        ]),
        instances: new Map([[36, "Test Dungeon"]]),
        encounters: new Map([[2747, "Test Boss"]]),
        skillLines: new Map(),
        categories: new Map(),
        tools: new Map(),
      },
    ],
  ]);
  const ref = {
    build: "1.0.0",
    instances: new Map([[36, { id: 36, type: "dungeon", expansionID: 0, encounters: [2747] }]]),
    encounters: new Map([[2747, { id: 2747, mapID: 36, order: 0 }]]),
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
