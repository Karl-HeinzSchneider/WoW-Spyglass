import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { loadDiscovered } from "../../src/discovered.js";

const discovered = `{
  ["locale"] = "deDE",
  ["items"] = {
    [101] = { ["id"] = 101, ["name"] = "Test", ["quality"] = 2 },
  },
  ["loot"] = {
    [7] = { ["id"] = 7, ["kills"] = 4, ["items"] = { [101] = 2 } },
  },
  ["trainers"] = {
    [42] = { ["id"] = 42, ["name"] = "Teacher", ["locale"] = "deDE", ["build"] = "test", ["services"] = {
      [1] = { ["name"] = "Copper Belt", ["type"] = "unavailable", ["skillName"] = "Schmiedekunst", ["skillRank"] = 75, ["requiredLevel"] = 10, ["source"] = "trainer", ["abilityRequirements"] = { [1] = "Apprentice Blacksmithing" } },
    } },
  },
}`;

test("loads SpyglassScraperDB discovered data", () => {
  const dir = mkdtempSync(join(tmpdir(), "spyglass-discovered-"));
  const path = join(dir, "Spyglass_Scraper.lua");
  try {
    writeFileSync(path, `SpyglassScraperDB = { ["global"] = { ["discovered"] = ${discovered} } }\n`, "utf-8");
    const result = loadDiscovered(path);
    assert.equal(result.locale, "deDE");
    assert.equal(result.items.get(101)?.name, "Test");
    assert.equal(result.loot.get(7)?.kills, 4);
    assert.equal(result.loot.get(7)?.items.get(101), 2);
    assert.equal(result.trainers.get(42)?.services.get(1)?.skillRank, 75);
    assert.equal(result.trainers.get(42)?.services.get(1)?.requiredLevel, 10);
    assert.equal(result.trainers.get(42)?.services.get(1)?.abilityRequirements.get(1), "Apprentice Blacksmithing");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("rejects a SavedVariables file without scraper data", () => {
  const dir = mkdtempSync(join(tmpdir(), "spyglass-discovered-"));
  const path = join(dir, "Spyglass.lua");
  try {
    writeFileSync(path, `SpyglassDB = { ["global"] = { ["discovered"] = ${discovered} } }\n`, "utf-8");
    assert.throws(() => loadDiscovered(path), /no SpyglassScraperDB\.global\.discovered/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
