import assert from "node:assert/strict";
import test from "node:test";
import { Checker, type CuratedFile } from "../../src/curated.js";
import { importDungeonLevels, parseDungeonLevelScan, validateDungeonLevels } from "../../src/dungeon-levels.js";
import { type Reference } from "../../src/reference.js";

function dungeon(slug: string, map: number, id?: number, name?: string): CuratedFile {
  return {
    path: `.contribute/data/dungeons/${slug}.json`,
    folder: "dungeon",
    slug,
    data: { map, id, name, minLevel: 1, maxLevel: 2, encounters: [] },
  };
}

test("imports normal and split dungeon brackets by map and activity name", () => {
  const scan = parseDungeonLevelScan({
    kind: "dungeon-levels",
    build: "1.60.1.69913",
    activities: {
      100: {
        id: 100,
        name: "Wailing Caverns",
        mapID: 43,
        difficultyID: 1,
        minLevelSuggestion: 17,
        maxLevelSuggestion: 25,
      },
      101: {
        id: 101,
        name: "Scarlet Monastery - Graveyard",
        mapID: 189,
        difficultyID: 1,
        minLevelSuggestion: 26,
        maxLevelSuggestion: 36,
      },
      102: {
        id: 102,
        name: "Scarlet Monastery - Armory",
        mapID: 189,
        difficultyID: 1,
        minLevelSuggestion: 35,
        maxLevelSuggestion: 42,
      },
      103: {
        id: 103,
        name: "Scarlet Monastery (Raid)",
        mapID: 189,
        difficultyID: 14,
        minLevelSuggestion: 40,
        maxLevelSuggestion: 40,
      },
    },
  });
  const files = [
    dungeon("wailing_caverns", 43, undefined, "Wailing Caverns"),
    dungeon("scarlet_monastery_graveyard", 189, 18901, "Scarlet Monastery: Graveyard"),
    dungeon("scarlet_monastery_armory", 189, 18903, "Scarlet Monastery: Armory"),
  ];
  const { levels } = importDungeonLevels(scan, files);
  assert.deepEqual(Object.keys(levels.dungeons).sort(), ["18901", "18903", "43"].sort());
  assert.deepEqual(levels.dungeons[18903], {
    activityID: 102,
    name: "Scarlet Monastery - Armory",
    minLevel: 35,
    maxLevel: 42,
  });

  const ref = { build: scan.build } as Reference;
  const check = new Checker(ref, false);
  validateDungeonLevels(levels, files, check);
  assert.ok(check.problems.some((p) => p.message.includes("levels 1-2 -> 17-25")));

  const fix = new Checker(ref, true);
  validateDungeonLevels(levels, files, fix);
  assert.equal(files[0]!.data.minLevel, 17);
  assert.equal(files[1]!.data.maxLevel, 36);
  assert.equal(files[2]!.data.maxLevel, 42);
});

test("unscanned dungeons keep their curated levels", () => {
  const file = dungeon("wailing_caverns", 43);
  const checker = new Checker({ build: "1.60.1.69913" } as Reference, false);
  validateDungeonLevels({ build: "1.60.1.70058", dungeons: {} }, [file], checker);
  assert.equal(checker.problems.length, 0);
  assert.equal(file.data.minLevel, 1);
});
