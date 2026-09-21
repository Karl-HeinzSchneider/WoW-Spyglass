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

for (const savedVariable of ["ForeverLootScraperDB", "ForeverLootDB"] as const) {
  test(`loads ${savedVariable} discovered data`, () => {
    const dir = mkdtempSync(join(tmpdir(), "foreverloot-discovered-"));
    const path = join(dir, `${savedVariable}.lua`);
    try {
      writeFileSync(path, `${savedVariable} = { ["global"] = { ["discovered"] = ${discovered} } }\n`, "utf-8");
      const result = loadDiscovered(path);
      assert.equal(result.locale, "deDE");
      assert.equal(result.items.get(101)?.name, "Test");
      assert.equal(result.loot.get(7)?.kills, 4);
      assert.equal(result.loot.get(7)?.items.get(101), 2);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
}
