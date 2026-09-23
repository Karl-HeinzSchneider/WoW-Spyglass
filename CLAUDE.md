# CLAUDE.md

Guidance for Claude Code when working in this repository. Each part of the repo has its own
`CLAUDE.md` with the details; this file holds the map and the rules that apply everywhere.

## What this is

ForeverLoot is a World of Warcraft addon for the *WoW Forever* Classic client
(`## Interface: 16001`), written in Lua 5.1 on top of Ace3, plus the TypeScript tooling that
builds its item database. It is a monorepo of three addon distribution units and one toolchain:

| Part | What it is | Details |
|---|---|---|
| `ForeverLoot/` | The core addon: public `ForeverLoot` API, item database and queries, built-in content modules, the browser window, user settings and (planned) loot history. `ForeverLootDB`. | [ForeverLoot/CLAUDE.md](ForeverLoot/CLAUDE.md) |
| `ForeverLoot_Locale/` | Companion: generated non-English item/instance/boss names, registered through the core API, plus the item names a non-English client looks up in-game. `ForeverLootLocaleDB`. | [ForeverLoot_Locale/CLAUDE.md](ForeverLoot_Locale/CLAUDE.md) |
| `ForeverLoot_Scraper/` | Optional contributor companion: `/fl scan` item scanning, loot observation, `/fl export`. `ForeverLootScraperDB`. | [ForeverLoot_Scraper/CLAUDE.md](ForeverLoot_Scraper/CLAUDE.md) |
| `.contribute/` | Everything the database is built from: in-game item scans, curated drops and item lists, the pinned client build. `inbox/` is the gitignored drop folder for `npm run import`. | [.contribute/CLAUDE.md](.contribute/CLAUDE.md) |
| `src/` | Root Node/TypeScript tooling: validate and fix the curated data, import in-game recordings, generate the addon data, check the addons, link them into a client, package releases. | [src/CLAUDE.md](src/CLAUDE.md) |
| `tests/` | `tests/tooling/*.test.ts` (node:test, run by `npm run test:tooling`). | see `src/CLAUDE.md` |
| `tools/portrait/` | Python + Pillow: a screenshot of the scraper's `/fl portrait` window -> a boss picture in `ForeverLoot/assets/bosses/`. | [tools/portrait/README.md](tools/portrait/README.md) |
| `docs/` | Human-facing documentation: `docs/API.md` (the public `ForeverLoot` contract, must be updated with every API change) and `docs/architecture.md` (addon ownership and integration rules). | — |

A direct child directory with a same-named `.toc` is an addon; the tooling discovers addons that
way, so adding one needs no registration anywhere.

## Working on the code

WoW addons are plain Lua/XML files loaded by the game; there is no build step for code. To try a
change: `npm run dev:link -- "<WoW>/Interface/AddOns"` (once; symlinks every addon directory,
also honors `WOW_ADDONS_DIR`) and `/reload` in-game. `/fl` toggles the window.

The one generated part is the item database (`ForeverLoot/db/generated/`,
`ForeverLoot_Locale/db/generated/`). **Never edit either generated tree by hand**; change the
inputs under `.contribute/data/` and run `npm run gen`.

WoW Forever's items are server-side: wago.tools' item tables are incomplete and wrong for this
client and item ids from Classic/wowhead do **not** match. The in-game scan (`/fl scan`, scraper
addon) is the only item source. Only scanned items exist in the DB; a curated loot row may
reference an unscanned id (warning, not error). Instances and encounters *do* come from
wago.tools' `Map` + `DungeonEncounter` tables for the build pinned in `.contribute/data/config.json`
(instance ids = `Map` ids, boss ids = `DungeonEncounter` ids), and so do profession recipes
(`SkillLineAbility`, `SpellReagents`, `SpellEffect`, …; recipe ids = spell ids), shipped only
when the scans confirm the item they make, and the `Faction` list. `ItemSparse` agrees with the
scans on the items it has but lacks thousands of this server's items, so it is read only for
recipe items' skill requirements and for the non-English names of scanned items whose English
name it matches — never as an item source.

## Commands (Node 20+, run from the root after `npm install` once)

| Command | Does |
|---|---|
| `npm run check` | Everything below that validates, in order: typecheck, tooling tests, addon boundaries, data, generated staleness, Lua syntax, XML schema. Run it before finishing a change. |
| `npm run check:data` | Validates the curated JSON against the game tables and the scans. |
| `npm run fix` | Same, and rewrites names, resolves name-only rows to ids, adds missing encounters. |
| `npm run format` | Prettier (`.prettierrc.json`, `.prettierignore`) on TS/JSON/Markdown, then StyLua (`stylua.toml`, `.styluaignore`) on Lua. Leaves `.contribute/data/` to `fix`/`import`, and XML to the editor. |
| `npm run gen` (`generate`) | Writes both generated trees. `npm run generate:check` fails when they are stale (CI). |
| `npm run import` | Merges what the scraper recorded (every `.lua` and `.json` in `.contribute/inbox/`, or one file given as `-- <path>`) into the scans and curated files; then `npm run gen`. |
| `npm run check:addons` | TOC entries exist, companions depend on `ForeverLoot`, no dependency cycles, and **no file under `ForeverLoot/` contains the string `ForeverLoot_Locale` or `ForeverLoot_Scraper`** (comments included). |
| `npm run check:lua` | `luac -p` on every addon Lua file (needs a Lua 5.1 `luac` on PATH). |
| `npm run check:xml` | Validates every addon XML against Blizzard's `UI.xsd` via python + lxml; skipped when `../_data/BlizzardInterfaceCode` is absent. |
| `npm run test:tooling` / `typecheck` | The node:test suite, `tsc --noEmit`. |
| `npm run dev:link -- <AddOns dir>` | Symlink every addon into a client. |
| `npm run package:addons` | Deterministic `dist/ForeverLoot-<version>.zip` of all addons (gitignored). |

Static checks also used ad hoc: `lua-language-server --check` (config in `.luarc.json`;
`lib/`, both generated trees and `.contribute` are excluded from LuaLS and StyLua).

## Addon boundaries (the contract, in one paragraph)

Companions depend on the core (`## Dependencies: ForeverLoot`) and use **only** the documented
public global `ForeverLoot` (`docs/API.md`). The core must work with both companions absent and
never references them — not even by name. No addon reads another addon's private table
(the `...` table each file receives) or adds a cross-addon global. Built-in content modules use
the same public API a third-party addon would; never give them private hooks. Late data goes in
through `ForeverLoot.Data:AddNames/AddItems/AddBossLoot/AddTrashLoot/AddQuests/AddList/AddListLoot`, which invalidate
caches and fire `OnDataChanged`. A breaking API change bumps `ForeverLoot.API_VERSION` and
updates `docs/API.md`. Full rules: `docs/architecture.md`.

## WoW addon constraints

- Lua 5.1 with Blizzard's restricted API. No `require`, `io`, `os`, or `loadstring` of external
  files; every code file must be listed in its addon's TOC, in dependency order, or it will not
  load.
- Addons share one global namespace. Keep state in the private table passed to each file. Every
  file starts with

  ```lua
  ---@type string, ForeverLoot
  local appName, app = ...
  ```

  (`local _, app = ...` when the name is unused, or LuaLS flags it; the class is
  `ForeverLootScraper` / `ForeverLootLocale` in the companions). The `---@type` line gives the
  language server completion on `app.*`. When a file adds a member to `app`, add a matching
  `---@field` to that addon's annotations-only `types.lua`.
- The only sanctioned globals are the public `ForeverLoot` table, the SavedVariables tables, and
  XML-required mixins/frames prefixed `ForeverLoot…` (`ForeverLootScraper…` in the scraper).
- Persistent state lives only in tables declared via `## SavedVariables`; they are populated after
  `ADDON_LOADED`, not at file-load time (AceDB `OnInitialize` is the first safe place).
- Ace3 types (`AceAddon`, `AceDBObject-3.0`, `AceDB.Schema`, …) come from the `ketho.wow-api`
  VS Code extension (`.vscode/settings.json` → `Lua.workspace.library`), not from `lib/`;
  inherit from them rather than redeclaring the API.

## XML files

Every XML file starts with `<Ui xmlns="http://www.blizzard.com/wow/ui/">` and **no**
`xsi:schemaLocation` — the client ignores it and a wrong path makes the VS Code XML extension
report errors. Schema validation comes from `xml.fileAssociations` in `.vscode/settings.json`
(mapping `**/*.xml` to `../_data/BlizzardInterfaceCode/.../Blizzard_SharedXML/UI.xsd`) and from
`npm run check:xml`. Lua mixin files must be listed in the TOC *before* the XML that references
them.

## Files with backslashes

Lua strings for texture paths need `\\` (`"Interface\\Icons\\INV_Misc_Bag_10"`), and so do the
JSON files under `.contribute/data/`. Shell heredocs and inline Python strip the doubled
backslash; write such files with the Write/Edit tools (or a script file with raw strings).

## Optional: Blizzard's own UI source and art for reference

A developer may place Blizzard's exported interface files in `../_data/` (a sibling of the repo,
`E:\Projects\_data\` here — outside the repo, so nothing needs gitignoring), typically as
symlinks to what the client writes next to the WoW install:

- `../_data/BlizzardInterfaceCode/` — from `/run ExportInterfaceFiles("code")`: Lua/XML of all
  FrameXML/AddOns.
- `../_data/BlizzardInterfaceArt/` — from `/run ExportInterfaceFiles("art")`: every texture as
  `.blp` under `BlizzardInterfaceArt/Interface/...`.

If they exist, **read them, never edit them**:

- Code: look up exact API signatures/return values, event payloads, frame templates and global
  strings. Prefer it over memory; this client's API differs from retail and from Classic.
- Art: verify that a texture path used in code exists (case-insensitive) and browse for suitable
  icons/textures by name. `.blp` can't be viewed; the file list is what matters. Atlas names
  (`atlas="..."`) are *not* in the export — find them in XML usages under `BlizzardInterfaceCode`.

Never list anything from these folders in a TOC or copy files out of them into the repo.

## Textures and Blizzard frames: reuse art, remake code

- **Don't create new textures unless there is no other way.** Prefer the game's own textures
  and atlases (they scale with the frame and need no shipping; the client does not load `.png`).
  If something really must be drawn, ask first.
- **Don't hard-reference a frame from retail or Classic WoW.** Don't inherit its templates, call
  its mixins, anchor to its frames or name it as the thing being copied in comments or docs.
  Learn how it is built, then remake the look with our own template and mixin; naming it as "an
  example" in a comment is fine. Its *art* (atlases, textures) may be reused freely.
- Code the Forever/"Camelot" client itself ships (`Blizzard_*/Camelot/` and shared templates it
  loads such as `Blizzard_SharedXML`) may be leaned on directly: inheriting from e.g.
  `PortraitFrameBaseTemplate`, `LargeSideTabButtonTemplate` or `PagingControlsTemplate` is fine.
  Verify the file is loaded by this client (Camelot/Mainline TOC) before depending on it.
- A screenshot the user shares is a look reference, not a template to reproduce pixel by pixel.
