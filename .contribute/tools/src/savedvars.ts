/**
 * Reader for WoW SavedVariables files (WTF/Account/<ACCOUNT>/SavedVariables/<Addon>.lua).
 *
 * The client writes a very regular Lua subset: `Name = { ... }` per saved global, tables with
 * `["key"] = value`, `[123] = value` or positional entries, double- or single-quoted strings with
 * `\"`, `\\`, `\n`, `\r`, `\t` and `\ddd` escapes, numbers, `true`/`false`/`nil`. That is all
 * this parser understands; it is not a Lua interpreter.
 */

export type LuaValue = string | number | boolean | null | LuaTable;
/** Keys keep their Lua type: `["1"]` and `[1]` stay distinct. */
export type LuaTable = Map<string | number, LuaValue>;

class Parser {
  private pos = 0;
  constructor(private readonly text: string) {}

  /** Every top-level `Name = value` assignment in the file. */
  globals(): Map<string, LuaValue> {
    const result = new Map<string, LuaValue>();
    this.skipSpace();
    while (this.pos < this.text.length) {
      const name = this.identifier();
      this.expect("=");
      result.set(name, this.value());
      this.skipSpace();
    }
    return result;
  }

  private fail(what: string): never {
    const line = this.text.slice(0, this.pos).split("\n").length;
    throw new Error(`SavedVariables: ${what} at line ${line}`);
  }

  private skipSpace(): void {
    for (;;) {
      const c = this.text[this.pos];
      if (c === " " || c === "\t" || c === "\n" || c === "\r") this.pos++;
      else if (c === "-" && this.text[this.pos + 1] === "-") {
        const end = this.text.indexOf("\n", this.pos);
        this.pos = end === -1 ? this.text.length : end;
      } else return;
    }
  }

  private expect(char: string): void {
    this.skipSpace();
    if (this.text[this.pos] !== char) this.fail(`expected "${char}"`);
    this.pos++;
  }

  private identifier(): string {
    this.skipSpace();
    const m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(this.text.slice(this.pos, this.pos + 256));
    if (!m) this.fail("expected a name");
    this.pos += m[0].length;
    return m[0];
  }

  private value(): LuaValue {
    this.skipSpace();
    const c = this.text[this.pos];
    if (c === "{") return this.table();
    if (c === '"' || c === "'") return this.string();
    if (c !== undefined && (c === "-" || (c >= "0" && c <= "9"))) return this.number();
    const word = this.identifier();
    if (word === "true") return true;
    if (word === "false") return false;
    if (word === "nil") return null;
    return this.fail(`unexpected "${word}"`);
  }

  private number(): number {
    const m = /^-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?/.exec(this.text.slice(this.pos, this.pos + 64));
    if (!m) this.fail("malformed number");
    this.pos += m[0].length;
    return Number(m[0]);
  }

  /** Double- or single-quoted; the client uses single quotes for strings that contain a double quote. */
  private string(): string {
    const quote = this.text[this.pos++];
    let out = "";
    for (;;) {
      const c = this.text[this.pos];
      if (c === undefined) this.fail("unterminated string");
      this.pos++;
      if (c === quote) return out;
      if (c !== "\\") {
        out += c;
        continue;
      }
      const e = this.text[this.pos++];
      if (e === "n") out += "\n";
      else if (e === "r") out += "\r";
      else if (e === "t") out += "\t";
      else if (e === "a") out += "\x07";
      else if (e === "b") out += "\b";
      else if (e === "f") out += "\f";
      else if (e === "v") out += "\v";
      else if (e === "\n") out += "\n";
      else if (e !== undefined && e >= "0" && e <= "9") {
        // \ddd: up to three decimal digits, one byte
        const m = /^\d{1,3}/.exec(this.text.slice(this.pos - 1, this.pos + 2))!;
        this.pos += m[0].length - 1;
        out += String.fromCharCode(Number(m[0]));
      } else if (e !== undefined) out += e; // \" \\ \' and anything else literal
      else this.fail("unterminated string");
    }
  }

  private table(): LuaTable {
    this.pos++; // {
    const table: LuaTable = new Map();
    let nextIndex = 1;
    for (;;) {
      this.skipSpace();
      const c = this.text[this.pos];
      if (c === "}") {
        this.pos++;
        return table;
      }
      if (c === undefined) this.fail("unterminated table");
      if (c === "[") {
        this.pos++;
        const key = this.value();
        if (typeof key !== "string" && typeof key !== "number") this.fail("table key must be a string or number");
        this.expect("]");
        this.expect("=");
        table.set(key, this.value());
      } else if (/[A-Za-z_]/.test(c) && /^[A-Za-z_][A-Za-z0-9_]*\s*=[^=]/.test(this.text.slice(this.pos, this.pos + 260))) {
        const key = this.identifier();
        this.expect("=");
        table.set(key, this.value());
      } else {
        table.set(nextIndex++, this.value());
      }
      this.skipSpace();
      const sep = this.text[this.pos];
      if (sep === "," || sep === ";") this.pos++;
      else if (sep !== "}") this.fail(`expected "," or "}"`);
    }
  }
}

/** Parses a whole SavedVariables file into its saved globals. */
export function parseSavedVariables(text: string): Map<string, LuaValue> {
  return new Parser(text.replace(/^﻿/, "")).globals();
}

/** Follows a key path into nested Lua tables; undefined when any step is missing. */
export function luaGet(value: LuaValue | undefined, ...path: (string | number)[]): LuaValue | undefined {
  let current: LuaValue | undefined = value;
  for (const key of path) {
    if (!(current instanceof Map)) return undefined;
    current = current.get(key);
  }
  return current;
}
