# CLAUDE.md

Guidance for Claude Code when working in this repository. This file holds the map and the rules
that apply everywhere; each part of the repo has its own `CLAUDE.md` with its rules and file map,
and the detailed descriptions live in `docs/`.

## What this is

ForeverLoot is a World of Warcraft addon for the _WoW Forever_ Classic client
(`## Interface: 16001`), written in Lua 5.1 on top of Ace3, plus the TypeScript tooling that
builds its item database. It is a monorepo of four addon distribution units and one toolchain:

| Part                    | What it is                                                                                                                                                                                       | Details                                                          |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------- |
| `ForeverLoot/`          | The core addon: public `ForeverLoot` API, item database API and queries (no item rows), built-in content modules, the browser window, user settings and (planned) loot history. `ForeverLootDB`. | [ForeverLoot/CLAUDE.md](ForeverLoot/CLAUDE.md)                   |
| `ForeverLoot_Database/` | Companion: every scanned item row with its English name, and the `items` module (the searchable, filterable item browser). No SavedVariables.                                                    | [ForeverLoot_Database/CLAUDE.md](ForeverLoot_Database/CLAUDE.md) |
| `ForeverLoot_Locale/`   | Companion: generated non-English item, instance, boss and crafting names, plus the item names a non-English client looks up in-game. `ForeverLootLocaleDB`.                                      | [ForeverLoot_Locale/CLAUDE.md](ForeverLoot_Locale/CLAUDE.md)     |
| `ForeverLoot_Scraper/`  | Optional contributor companion: `/fl scan` item scanning, loot observation, `/fl export`, the `/fl portrait` studio. Also depends on `ForeverLoot_Database`. `ForeverLootScraperDB`.             | [ForeverLoot_Scraper/CLAUDE.md](ForeverLoot_Scraper/CLAUDE.md)   |
| `.contribute/`          | Everything the database is built from: in-game item scans, curated drops and item lists, the pinned client build. `inbox/` is the gitignored drop folder for `npm run import`.                   | [.contribute/CLAUDE.md](.contribute/CLAUDE.md)                   |
| `src/`                  | Root Node/TypeScript tooling: validate and fix the curated data, import in-game recordings, generate the addon data, check the addons, link them into a client, package releases.                | [src/CLAUDE.md](src/CLAUDE.md)                                   |
| `tests/`                | `tests/tooling/*.test.ts` (node:test, run by `npm run test:tooling`).                                                                                                                            | see `src/CLAUDE.md`                                              |
| `tools/portrait/`       | Python + Pillow: a screenshot of the scraper's `/fl portrait` window -> a boss picture in `ForeverLoot/assets/bosses/`.                                                                          | [tools/portrait/README.md](tools/portrait/README.md)             |
| `docs/`                 | Human-facing documentation, see below.                                                                                                                                                           | —                                                                |

A direct child directory with a same-named `.toc` is an addon; the tooling discovers addons that
way, so adding one needs no registration anywhere.

## Documentation (`docs/`)

| File                                      | Covers                                                                                         |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------- |
| [API.md](docs/API.md)                     | The public `ForeverLoot` contract: modules, nodes, `Data`, `Filters`, `Query`, events.         |
| [architecture.md](docs/architecture.md)   | Which addon owns what, and the integration rules between them.                                 |
| [contributing.md](docs/contributing.md)   | Setup, scanning and importing, and the format of every file under `.contribute/data/`.         |
| [data-pipeline.md](docs/data-pipeline.md) | Where the data comes from and what validation, generation and import do (`src/`).              |
| [ui.md](docs/ui.md)                       | How the core's browser window is built (`ForeverLoot/src/ui/`).                                |
| [scraper.md](docs/scraper.md)             | How the scraper scans, records loot, exports, and the portrait studio.                         |
| [localization.md](docs/localization.md)   | Where every name comes from in each language, and the locale addon's in-game item name lookup. |

Read the matching file before changing what it describes, and update it in the same change when
behavior it describes changes. Every change to the public API updates `docs/API.md`.

## Working on the code

WoW addons are plain Lua/XML files loaded by the game; there is no build step for code. To try a
change: `npm run dev:link -- "<WoW>/Interface/AddOns"` (once; symlinks every addon directory,
also honors `WOW_ADDONS_DIR`) and `/reload` in-game. `/fl` toggles the window.

The one generated part is the item database (`ForeverLoot/db/generated/`,
`ForeverLoot_Database/db/generated/`, `ForeverLoot_Locale/db/generated/`). **Never edit a
generated tree by hand**; change the inputs under `.contribute/data/` and run `npm run gen`.

WoW Forever's items are server-side: wago.tools' item tables are incomplete and wrong for this
client, and item ids from Classic/wowhead do **not** match. The in-game scan (`/fl scan`) is the
only item source, so only scanned items exist in the database. Instances, encounters, profession
recipes and factions _do_ come from wago.tools, for the build pinned in
`.contribute/data/config.json`; `ItemSparse` is read only for recipe skill requirements and
non-English names, never as an item source. Details: `docs/data-pipeline.md`.

## Commands (Node 20+, run from the root after `npm install` once)

| Command                              | Does                                                                                                                                                                                                                                               |
| ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `npm run check`                      | Everything below that validates, in order: typecheck, tooling tests, addon boundaries, data, generated staleness, Lua syntax, XML schema. Run it before finishing a change.                                                                        |
| `npm run check:data`                 | Validates the curated JSON against the game tables and the scans.                                                                                                                                                                                  |
| `npm run fix`                        | Same, and rewrites names, resolves name-only rows to ids, adds missing encounters.                                                                                                                                                                 |
| `npm run format`                     | Prettier (`.prettierrc.json`, `.prettierignore`) on TS/JSON/Markdown, then StyLua (`stylua.toml`, `.styluaignore`) on Lua. Includes `.contribute/data/`, which `fix`/`import` already write in the same Prettier layout; leaves XML to the editor. |
| `npm run gen` (`generate`)           | Writes the three generated trees. `npm run generate:check` fails when they are stale (CI).                                                                                                                                                         |
| `npm run import`                     | Merges what the scraper recorded (every `.lua` and `.json` in `.contribute/inbox/`, or one file given as `-- <path>`) into the scans and curated files; then `npm run gen`.                                                                        |
| `npm run check:addons`               | TOC entries exist, companions depend on `ForeverLoot`, no dependency cycles, and **no `.lua`/`.xml`/`.toc` under `ForeverLoot/` contains a companion's name** (`ForeverLoot_Database`, `_Locale`, `_Scraper`; comments included).                  |
| `npm run check:lua`                  | `luac -p` on every addon Lua file (needs a Lua 5.1 `luac` on PATH).                                                                                                                                                                                |
| `npm run check:xml`                  | Validates every addon XML against Blizzard's `UI.xsd` via python + lxml; skipped when `../_data/BlizzardInterfaceCode` is absent.                                                                                                                  |
| `npm run test:tooling` / `typecheck` | The node:test suite, `tsc --noEmit`.                                                                                                                                                                                                               |
| `npm run dev:link -- <AddOns dir>`   | Symlink every addon into a client.                                                                                                                                                                                                                 |
| `npm run package:addons`             | Deterministic `dist/ForeverLoot-<version>.zip` of all addons (gitignored).                                                                                                                                                                         |

Static checks also used ad hoc: `lua-language-server --check` (config in `.luarc.json`;
`lib/`, the generated trees and `.contribute` are excluded from LuaLS and StyLua).

## Addon boundaries (the contract, in one paragraph)

Companions depend on the core (`## Dependencies: ForeverLoot`) and use **only** the documented
public global `ForeverLoot` (`docs/API.md`); the scraper also depends on `ForeverLoot_Database`.
The core must work with every companion absent and never references them — not even by name. No
addon reads another addon's private table (the `...` table each file receives) or adds a
cross-addon global. Built-in content modules use the same public API a third-party addon would;
never give them private hooks. Late data goes in through the `ForeverLoot.Data:Add*` calls, which
invalidate caches and fire `OnDataChanged`. A breaking API change bumps
`ForeverLoot.API_VERSION` and updates `docs/API.md`. Full rules: `docs/architecture.md`.

## WoW addon constraints

- Lua 5.1 with Blizzard's restricted API. No `require`, `io`, `os`, or `loadstring` of external
  files; every code file must be listed in its addon's TOC, in dependency order, or it will not
  load.
- Addons share one global namespace. Keep state in the private table passed to each file. A file
  that uses it starts with

  ```lua
  ---@type string, ForeverLoot
  local appName, app = ...
  ```

  (`local _, app = ...` when the name is unused, or LuaLS flags it; the class is
  `ForeverLootScraper` / `ForeverLootLocale` in the companions). The `---@type` line gives the
  language server completion on `app.*`. When a file adds a member to `app`, add a matching
  `---@field` where the class is declared: the core's `src/types.lua`, or the companion's
  bootstrap file (`ForeverLoot_Scraper.lua`, `ForeverLoot_Locale.lua`). The built-in modules
  and `ForeverLoot_Database.lua` don't touch the private table at all: they use only the global
  `ForeverLoot`, as a third-party addon would.

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
`npm run check:xml`. Lua mixin files must be listed in the TOC _before_ the XML that references
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
  (`atlas="..."`) are _not_ in the export — find them in XML usages under `BlizzardInterfaceCode`.

Never list anything from these folders in a TOC or copy files out of them into the repo.

## Textures and Blizzard frames: reuse art, remake code

- **Don't create new textures unless there is no other way.** Prefer the game's own textures
  and atlases (they scale with the frame and need no shipping; the client does not load `.png`).
  If something really must be drawn, ask first.
- **Don't hard-reference a frame from retail or Classic WoW.** Don't inherit its templates, call
  its mixins, anchor to its frames or name it as the thing being copied in comments or docs.
  Learn how it is built, then remake the look with our own template and mixin; naming it as "an
  example" in a comment is fine. Its _art_ (atlases, textures) may be reused freely.
- Code the Forever/"Camelot" client itself ships (`Blizzard_*/Camelot/` and shared templates it
  loads such as `Blizzard_SharedXML`) may be leaned on directly: inheriting from e.g.
  `PortraitFrameBaseTemplate`, `LargeSideTabButtonTemplate` or `PagingControlsTemplate` is fine.
  Verify the file is loaded by this client (Camelot/Mainline TOC) before depending on it.
- A screenshot the user shares is a look reference, not a template to reproduce pixel by pixel.
