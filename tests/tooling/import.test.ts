import assert from "node:assert/strict";
import test from "node:test";
import { type CuratedFile } from "../../src/curated.js";
import { type Discovered, type DiscoveredItem } from "../../src/discovered.js";
import { importDiscovered } from "../../src/import.js";
import { type Reference } from "../../src/reference.js";

function fixture(): { discovered: Discovered; ref: Reference; files: CuratedFile[] } {
  const discovered: Discovered = {
    locale: "enUS",
    items: new Map([[101, { id: 101, name: "Scanned Item", quality: 2 } as DiscoveredItem]]),
    loot: new Map([[7, { kills: 12, items: new Map([[101, 3]]) }]]),
  };
  const ref = {
    build: "test",
    items: new Map(),
    itemLocales: ["enUS"],
    wagoItemNames: new Map(),
    instances: new Map([[36, { id: 36, type: "dungeon", expansionID: 0, encounters: [7] }]]),
    encounters: new Map([[7, { id: 7, mapID: 36, order: 0 }]]),
    names: new Map([
      [
        "enUS",
        { items: new Map(), instances: new Map([[36, "Test Dungeon"]]), encounters: new Map([[7, "Test Boss"]]) },
      ],
    ]),
  } as unknown as Reference;
  const files: CuratedFile[] = [
    {
      path: "test.json",
      folder: "dungeon",
      slug: "test",
      data: { map: 36, encounters: [{ id: 7, loot: [] }] },
    },
  ];
  return { discovered, ref, files };
}

test("importing scanned items leaves observed loot alone by default", () => {
  const { discovered, ref, files } = fixture();
  importDiscovered(discovered, ref, files);
  assert.equal(ref.items.get(101)?.names.enUS, "Scanned Item");
  assert.deepEqual(files[0].data.encounters[0].loot, []);
});

test("observed loot is imported when requested", () => {
  const { discovered, ref, files } = fixture();
  importDiscovered(discovered, ref, files, true);
  assert.deepEqual(files[0].data.encounters[0].loot, [{ item: 101, name: "Scanned Item", chance: 0.25 }]);
});
