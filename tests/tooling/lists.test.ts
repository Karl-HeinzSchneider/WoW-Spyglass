import assert from "node:assert/strict";
import test from "node:test";
import { rowsOf, serializeList, type ListFile } from "../../src/lists.js";

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
