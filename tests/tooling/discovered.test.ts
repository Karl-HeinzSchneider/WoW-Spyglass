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
}`;

test("loads ForeverLootScraperDB discovered data", () => {
  const dir = mkdtempSync(join(tmpdir(), "foreverloot-discovered-"));
  const path = join(dir, "ForeverLoot_Scraper.lua");
  try {
    writeFileSync(path, `ForeverLootScraperDB = { ["global"] = { ["discovered"] = ${discovered} } }\n`, "utf-8");
    const result = loadDiscovered(path);
    assert.equal(result.locale, "deDE");
    assert.equal(result.items.get(101)?.name, "Test");
    assert.equal(result.loot.get(7)?.kills, 4);
    assert.equal(result.loot.get(7)?.items.get(101), 2);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("rejects a SavedVariables file without scraper data", () => {
  const dir = mkdtempSync(join(tmpdir(), "foreverloot-discovered-"));
  const path = join(dir, "ForeverLoot.lua");
  try {
    writeFileSync(path, `ForeverLootDB = { ["global"] = { ["discovered"] = ${discovered} } }\n`, "utf-8");
    assert.throws(() => loadDiscovered(path), /no ForeverLootScraperDB\.global\.discovered/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
