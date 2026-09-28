import assert from "node:assert/strict";
import test from "node:test";
import { Checker, type CuratedFile } from "../../src/curated.js";
import { type QuestFile, serializeQuestFile, validateQuests } from "../../src/quests.js";
import { type Reference } from "../../src/reference.js";

function checker(): Checker {
  return new Checker(
    {
      items: new Map([[200, {}]]),
      names: new Map([
        [
          "enUS",
          {
            items: new Map([[200, "Quest Reward"]]),
            instances: new Map(),
            encounters: new Map(),
            skillLines: new Map(),
            categories: new Map(),
            tools: new Map(),
          },
        ],
      ]),
    } as unknown as Reference,
    false,
  );
}

function questFile(quests: QuestFile["data"]["quests"]): QuestFile {
  return { path: ".contribute/data/quests/test.json", slug: "test", data: { quests } };
}

function instance(quests: CuratedFile["data"]["quests"]): CuratedFile {
  return {
    path: ".contribute/data/dungeons/test.json",
    folder: "dungeon",
    slug: "test",
    data: { map: 36, encounters: [], quests },
  };
}

test("global quest definitions validate references, locations and serialize in stable shape", () => {
  const file = questFile([
    { id: 25, name: "First", items: [] },
    {
      id: 26,
      name: "Second",
      class: "Warlock",
      requires: [25],
      breadcrumbs: [24],
      start: { npc: 100, name: "Quest Giver", map: [1436, 10.5, 20.5] },
      items: [{ item: 200 }],
    },
    { id: 24, name: "Breadcrumb", items: [] },
  ]);
  const sink = checker();
  validateQuests([file], [instance([{ id: 26, role: "inside" }])], sink);
  assert.deepEqual(
    sink.problems.filter((problem) => !problem.fixable && !problem.warning),
    [],
  );
  const data = JSON.parse(serializeQuestFile(file)) as QuestFile["data"];
  assert.deepEqual(data.quests[1]?.requires, [25]);
  assert.deepEqual(data.quests[1]?.breadcrumbs, [24]);
  assert.deepEqual(data.quests[1]?.start?.map, [1436, 10.5, 20.5]);
});

test("quest validation rejects missing references, bad roles and prerequisite cycles", () => {
  const file = questFile([
    { id: 25, name: "First", requires: [26], items: [] },
    { id: 26, name: "Second", requires: [25, 99], items: [] },
  ]);
  const sink = checker();
  validateQuests([file], [instance([{ id: 26, role: "unknown" as "inside" }, { id: 88 }])], sink);
  const errors = sink.problems.filter((problem) => !problem.warning).map((problem) => problem.message);
  assert.ok(errors.some((message) => message.includes("prerequisite 99 has no definition")));
  assert.ok(errors.some((message) => message.includes("relationship cycle")));
  assert.ok(errors.some((message) => message.includes("role")));
  assert.ok(errors.some((message) => message.includes("quest 88 has no definition")));
});

test("quest validation reports malformed graph and contact fields without crashing", () => {
  const file = questFile([
    {
      id: 25,
      name: "Malformed",
      requires: 26 as unknown as number[],
      start: [] as unknown as { name: string },
      items: [],
    },
  ]);
  const sink = checker();
  validateQuests([file], [], sink);
  const errors = sink.problems.filter((problem) => !problem.warning).map((problem) => problem.message);
  assert.ok(errors.some((message) => message.includes("`requires` must be an array")));
  assert.ok(errors.some((message) => message.includes("`start` must be an object")));
});
