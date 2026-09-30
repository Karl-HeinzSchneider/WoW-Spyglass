import assert from "node:assert/strict";
import test from "node:test";
import { Checker, type CuratedFile, serialize, validate } from "../../src/curated.js";
import { type Config } from "../../src/config.js";
import { build } from "../../src/generate.js";
import { type CuratedQuest, type QuestFile, serializeQuests, validateQuests } from "../../src/quests.js";
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

function questFile(quests: CuratedQuest[]): QuestFile {
  return { path: ".contribute/data/quests/dungeons/test_dungeon.json", slug: "test_dungeon", quests };
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
  assert.deepEqual(
    checker.problems.filter((p) => !p.fixable && !p.warning),
    [],
  );
});

test("trash and quest rows resolve a name-only row and keep their shape through a fix rewrite", () => {
  const file = dungeonFile({
    trash: [{ name: "Trash Trinket", chance: 0.02 }],
    quests: [26],
  });
  const quests = questFile([{ id: 26, name: "A Test Quest", side: "Alliance", items: [{ item: 200 }] }]);
  const checker = dungeonChecker(true);
  validate([file], checker);
  validateQuests([quests], [file], checker);
  assert.deepEqual(
    checker.problems.filter((p) => !p.fixable && !p.warning),
    [],
  );
  const serialized = JSON.parse(serialize(file.data)) as Record<string, unknown>;
  assert.deepEqual(serialized.trash, [{ item: 100, name: "Trash Trinket", chance: 0.02 }]);
  assert.deepEqual(serialized.quests, [26]);
  assert.deepEqual((JSON.parse(serializeQuests(quests)) as { quests: unknown[] }).quests, [
    { id: 26, name: "A Test Quest", side: "Alliance", items: [{ item: 200, name: "Quest Reward" }] },
  ]);
});

test("a displayName is kept through a fix rewrite and must not be empty", () => {
  const file = dungeonFile({ displayName: "TD" });
  const checker = dungeonChecker(true);
  validate([file], checker);
  assert.deepEqual(
    checker.problems.filter((p) => !p.fixable && !p.warning),
    [],
  );
  assert.equal((JSON.parse(serialize(file.data)) as { displayName?: string }).displayName, "TD");

  const empty = dungeonChecker(false);
  validate([dungeonFile({ displayName: "" })], empty);
  assert.ok(empty.problems.some((p) => !p.warning && p.message.includes("displayName")));
});

test("an entrance is kept through a fix rewrite and must be a map id with coordinates in 0..100", () => {
  const file = dungeonFile({ entrance: [1440, 14.5, 14.2] });
  const checker = dungeonChecker(true);
  validate([file], checker);
  assert.deepEqual(
    checker.problems.filter((p) => !p.fixable && !p.warning),
    [],
  );
  assert.deepEqual((JSON.parse(serialize(file.data)) as { entrance?: number[] }).entrance, [1440, 14.5, 14.2]);

  const wrong = dungeonChecker(false);
  validate([dungeonFile({ entrance: [1440, 145, 14.2] })], wrong);
  assert.ok(wrong.problems.some((p) => !p.warning && p.message.includes("entrance")));
});

test("requiredLevel and zone are kept through a fix rewrite and must be a level and a map id", () => {
  const file = dungeonFile({ requiredLevel: 10, zone: 1440 });
  const checker = dungeonChecker(true);
  validate([file], checker);
  assert.deepEqual(
    checker.problems.filter((p) => !p.fixable && !p.warning),
    [],
  );
  const serialized = JSON.parse(serialize(file.data)) as { requiredLevel?: number; zone?: number };
  assert.deepEqual([serialized.requiredLevel, serialized.zone], [10, 1440]);

  const wrong = dungeonChecker(false);
  validate([dungeonFile({ requiredLevel: 0, zone: 14.4 })], wrong);
  const errors = wrong.problems.filter((p) => !p.warning).map((p) => p.message);
  assert.ok(errors.some((m) => m.includes("requiredLevel")));
  assert.ok(errors.some((m) => m.includes("zone")));
});

test("a rare encounter keeps its flag through fix and generation, and rejects non-booleans", () => {
  const file = dungeonFile({
    encounters: [{ id: 2747, name: "Test Boss", level: 19, rare: true, loot: [] }],
  });
  const checker = dungeonChecker(true);
  validate([file], checker);
  assert.deepEqual(
    checker.problems.filter((p) => !p.fixable && !p.warning),
    [],
  );
  assert.equal((JSON.parse(serialize(file.data)) as CuratedFile["data"]).encounters[0]?.rare, true);

  const ref = { ...checker.ref, recipes: new Map(), skillLines: new Map(), categories: new Map() } as Reference;
  const config: Config = { build: "test", locales: ["enUS"], excludeMaps: [], itemsPerFile: 100 };
  const generated = build(ref, [file], [], [], config).core.get("instances.lua") ?? "";
  assert.match(generated, /Data:AddBoss\(2747, \{[^}]*level = 19, rare = true/);

  const invalid = dungeonFile({
    encounters: [{ id: 2747, name: "Test Boss", rare: "yes" as unknown as boolean, loot: [] }],
  });
  const wrong = dungeonChecker(false);
  validate([invalid], wrong);
  assert.ok(wrong.problems.some((p) => !p.warning && p.message.includes("`rare` must be a boolean")));
});

test("a quest needs an id, a known side and no duplicate", () => {
  const quests = questFile([
    { id: 0, items: [] },
    { id: 26, name: "A Test Quest", side: "Neutral", items: [] },
    { id: 26, name: "A Test Quest", items: [] },
  ]);
  const checker = dungeonChecker(false);
  validateQuests([quests], [], checker);
  const errors = checker.problems.filter((p) => !p.fixable && !p.warning).map((p) => p.message);
  assert.equal(errors.length, 3, errors.join("\n"));
  assert.match(errors[0]!, /quest without a positive integer `id`/);
  assert.match(errors[1]!, /quest 26: `side` must be one of Alliance, Horde, Both/);
  assert.match(errors[2]!, /quest 26 is also defined/);
});

test("a quest without a name is only a warning: no game table can supply one", () => {
  const quests = questFile([{ id: 26, items: [{ item: 200, name: "Quest Reward" }] }]);
  const checker = dungeonChecker(false);
  validateQuests([quests], [], checker);
  assert.deepEqual(
    checker.problems.filter((p) => !p.fixable && !p.warning),
    [],
  );
  assert.equal(checker.problems.filter((p) => p.warning).length, 1);
  assert.match(checker.problems.find((p) => p.warning)!.message, /quest 26: no `name`/);
});

test("a quest without an id is only a warning: the id is added by hand later", () => {
  const quests = questFile([{ name: "A Test Quest", items: [{ item: 200, name: "Quest Reward" }] }]);
  const checker = dungeonChecker(false);
  validateQuests([quests], [], checker);
  assert.deepEqual(
    checker.problems.filter((p) => !p.fixable && !p.warning),
    [],
  );
  assert.deepEqual(
    checker.problems.filter((p) => p.warning).map((p) => p.message),
    ['quest "A Test Quest": no `id`; it isn\'t shipped until it has one'],
  );
});

test("a class quest names one of the classes, and keeps it through a fix rewrite", () => {
  const quests = questFile([
    { id: 26, name: "A Test Quest", class: "Warlock", items: [] },
    { id: 27, name: "Another Quest", class: "Necromancer", items: [] },
  ]);
  const checker = dungeonChecker(false);
  validateQuests([quests], [], checker);
  const errors = checker.problems.filter((p) => !p.fixable && !p.warning).map((p) => p.message);
  assert.equal(errors.length, 1, errors.join("\n"));
  assert.match(errors[0]!, /quest 27: `class` must be one of Warrior, .*Warlock, Druid/);
  const serialized = JSON.parse(serializeQuests(quests)) as { quests: unknown[] };
  assert.deepEqual(serialized.quests[0], { id: 26, name: "A Test Quest", class: "Warlock", items: [] });
});

test("a shared quest has one definition and may appear in several dungeons", () => {
  const first = dungeonFile({ quests: [26] });
  const second = { ...dungeonFile({ quests: [26] }), path: ".contribute/data/dungeons/other.json" };
  const checker = dungeonChecker(false);
  validateQuests([questFile([{ id: 26, name: "Shared Quest", items: [] }])], [first, second], checker);
  assert.deepEqual(
    checker.problems.filter((p) => !p.warning),
    [],
  );
});

test("quest references, prerequisites and follow-ups must resolve to one catalog definition", () => {
  const file = dungeonFile({ quests: [26, 99] });
  const quests = questFile([{ id: 26, name: "A Test Quest", requires: [98], followUps: [97], items: [] }]);
  const checker = dungeonChecker(false);
  validateQuests([quests], [file], checker);
  const errors = checker.problems.filter((p) => !p.warning).map((p) => p.message);
  assert.ok(errors.some((m) => m.includes("prerequisite 98 has no quest definition")));
  assert.ok(errors.some((m) => m.includes("follow-up 97 has no quest definition")));
  assert.ok(errors.some((m) => m.includes("quest 99 has no definition")));
});

test("questline details survive a fix rewrite", () => {
  const quests = questFile([
    { id: 25, name: "Earlier Quest", items: [] },
    {
      id: 26,
      name: "Dungeon Quest",
      description: "More context",
      requires: [25],
      followUps: [27],
      start: { npc: "Quest Giver", npcID: 123, location: [1436, 43, 72], description: "Upstairs." },
      turnIn: { npc: "Quest Turn-in", location: [1436, 50, 60], description: "Inside the inn." },
      items: [],
    },
    { id: 27, name: "Later Quest", items: [] },
  ]);
  quests.npcs = { "Quest Giver": { location: [1436, 43, 72], description: "Upstairs." } };
  const checker = dungeonChecker(true);
  validateQuests([quests], [dungeonFile({ quests: [26] })], checker);
  assert.deepEqual(
    checker.problems.filter((p) => !p.warning),
    [],
  );
  const serialized = JSON.parse(serializeQuests(quests)) as { npcs: QuestFile["npcs"]; quests: CuratedQuest[] };
  assert.deepEqual(serialized.npcs, quests.npcs);
  assert.deepEqual(serialized.quests[1], quests.quests[1]);
});

test("unlisted prerequisite and follow-up quests ship without becoming dungeon quests", () => {
  const names = {
    items: new Map(),
    encounters: new Map(),
    instances: new Map([[36, "Test Dungeon"]]),
    skillLines: new Map(),
    categories: new Map(),
    tools: new Map(),
  };
  const ref = {
    build: "test",
    instances: new Map([[36, { id: 36, type: "dungeon", expansionID: 0, encounters: [] }]]),
    encounters: new Map(),
    items: new Map(),
    itemLocales: [],
    names: new Map([["enUS", names]]),
    recipes: new Map(),
    skillLines: new Map(),
    categories: new Map(),
  } as unknown as Reference;
  const config: Config = { build: "test", locales: ["enUS"], excludeMaps: [], itemsPerFile: 100 };
  const quests = questFile([
    { id: 25, name: "Earlier Quest", items: [] },
    {
      id: 26,
      name: "Dungeon Quest",
      requires: [25],
      followUps: [27],
      start: { npc: "Quest Giver" },
      turnIn: { npc: "Quest Giver", description: "Outside." },
      items: [],
    },
    { id: 27, name: "Later Quest", items: [] },
  ]);
  quests.npcs = { "Quest Giver": { location: [1436, 43, 72], description: "Upstairs." } };
  const output = build(ref, [dungeonFile({ encounters: [], quests: [26] })], [quests], [], config);
  assert.match(output.core.get("quest-definitions.lua") ?? "", /Data:AddQuestDefinitions\(\{/);
  assert.match(output.core.get("generated.xml") ?? "", /quest-definitions.lua/);
  assert.match(output.core.get("quest-definitions.lua") ?? "", /^    \{ id = 25/m);
  assert.match(output.core.get("quest-definitions.lua") ?? "", /^    \{ id = 27/m);
  assert.doesNotMatch(output.core.get("loot/test_dungeon.lua") ?? "", /^    \{ id = 25/m);
  assert.doesNotMatch(output.core.get("loot/test_dungeon.lua") ?? "", /^    \{ id = 27/m);
  assert.match(output.core.get("loot/test_dungeon.lua") ?? "", /^    \{ id = 26/m);
  assert.match(output.core.get("loot/test_dungeon.lua") ?? "", /followUps = \{ 27 \}/);
  assert.match(
    output.core.get("loot/test_dungeon.lua") ?? "",
    /start = \{ description = "Upstairs\.", location = \{ 1436, 43, 72 \}, npc = "Quest Giver" \}/,
  );
  assert.match(
    output.core.get("loot/test_dungeon.lua") ?? "",
    /turnIn = \{ description = "Outside\.", location = \{ 1436, 43, 72 \}, npc = "Quest Giver" \}/,
  );
});

test("a split map: each file needs an id, a boss may be in one of them only, one in none is a warning", () => {
  const part = (slug: string, data: Partial<CuratedFile["data"]>): CuratedFile => ({
    ...dungeonFile({ trash: [], ...data }),
    slug,
    path: `.contribute/data/dungeons/${slug}.json`,
  });
  const east = part("test_east", {
    id: 3601,
    name: "Test Dungeon: East",
    encounters: [{ id: 2747, name: "Test Boss", loot: [] }],
  });
  const west = part("test_west", {
    name: "Test Dungeon: West",
    encounters: [{ id: 2747, name: "Test Boss", loot: [] }],
  });
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
