import { existsSync, readFileSync, writeFileSync } from "node:fs";
import * as prettier from "prettier";

/**
 * Writes JSON text in the repo's Prettier style (`.prettierrc.json`), so a file the tools wrote is
 * exactly what `npm run format` and format-on-save make of it. Prettier keeps an object expanded
 * when its input has a line break after `{`, so the layout of `json` matters: pass
 * `JSON.stringify(value, null, 2)` (every object expanded, arrays joined when they fit).
 * A file whose content is already that (CRLF from a `core.autocrlf` checkout aside) is left
 * untouched, so git doesn't list it as modified.
 */
export async function writeJson(path: string, json: string): Promise<void> {
  const options = (await prettier.resolveConfig(path)) ?? {};
  const text = await prettier.format(json, { ...options, filepath: path });
  if (existsSync(path) && readFileSync(path, "utf-8").replace(/\r\n/g, "\n") === text) return;
  writeFileSync(path, text, "utf-8");
}
