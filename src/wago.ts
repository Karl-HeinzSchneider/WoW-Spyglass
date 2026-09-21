import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { parse } from "csv-parse/sync";
import { CACHE_DIR } from "./config.js";

/** One DB2 table as rows keyed by column name (all values are strings). */
export type Table = Record<string, string>[];

/**
 * Downloads a DB2 table as CSV from wago.tools for the given build and locale, cached under
 * .cache/<build>/ so repeated runs are offline. Delete the cache to refresh.
 */
export async function fetchTable(table: string, build: string, locale: string): Promise<Table> {
  const dir = resolve(CACHE_DIR, build);
  const file = resolve(dir, `${table}.${locale}.csv`);
  if (!existsSync(file)) {
    const url = `https://wago.tools/db2/${table}/csv?build=${build}&locale=${locale}`;
    process.stderr.write(`downloading ${table} (${locale}) ...\n`);
    const res = await fetch(url);
    if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
    const text = await res.text();
    if (!text.startsWith("ID,") && !text.includes(",ID,")) {
      throw new Error(`${url}: response is not a CSV table (build or table name wrong?)`);
    }
    mkdirSync(dir, { recursive: true });
    writeFileSync(file, text, "utf-8");
  }
  return parse(readFileSync(file, "utf-8"), { columns: true, skip_empty_lines: true }) as Table;
}

export function int(value: string | undefined, fallback = 0): number {
  const n = Number.parseInt(value ?? "", 10);
  return Number.isFinite(n) ? n : fallback;
}
