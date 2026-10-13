import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";
import { CACHE_DIR } from "../../src/config.js";
import { fetchTable, WagoUnavailableError } from "../../src/wago.js";

test("Wago server outages produce actionable errors and are not cached", async (t) => {
  const build = `test-wago-outage-${process.pid}`;
  for (const status of [500, 502, 503, 504]) {
    t.mock.method(globalThis, "fetch", async () => new Response("Maintenance", { status }));
    await assert.rejects(fetchTable("Map", build, "enUS"), (error: unknown) => {
      assert.ok(error instanceof WagoUnavailableError);
      assert.match(error.message, new RegExp(`HTTP ${status}`));
      assert.match(error.message, /maintenance/);
      assert.match(error.message, /try again later/);
      return true;
    });
    assert.equal(existsSync(resolve(CACHE_DIR, build, "Map.enUS.csv")), false);
    t.mock.restoreAll();
  }
});

test("Wago client errors retain their original diagnostic", async (t) => {
  t.mock.method(globalThis, "fetch", async () => new Response("Not found", { status: 404 }));
  await assert.rejects(fetchTable("Map", `test-wago-missing-${process.pid}`, "enUS"), (error: unknown) => {
    assert.ok(error instanceof Error);
    assert.ok(!(error instanceof WagoUnavailableError));
    assert.match(error.message, /Map\/csv.*HTTP 404/);
    return true;
  });
});
