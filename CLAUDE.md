# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ForeverLoot is a World of Warcraft addon (Classic client, `## Interface: 16001`) written in Lua
on top of Ace3. It is early: the core skeleton (logger, AceAddon object, AceDB) exists; loot
tracking itself does not yet.

## No build, lint, or test tooling (yet)

There is no build step, package manager, linter, or test runner in this repo. WoW addons are
plain Lua files loaded directly by the game client. To try changes, copy or symlink the repo
into `World of Warcraft/_retail_/Interface/AddOns/ForeverLoot/` and run `/reload` in-game.
If tooling (e.g. luacheck, a packager) is added later, document the commands here.

## Layout

- `ForeverLoot.toc` — the addon manifest. The game reads it to learn the addon's metadata
  (`## Interface`, `## Title`, `## SavedVariables`, …) and the ordered list of files to load.
  **Every new Lua/XML file must be listed here, in dependency order, or it will not load.**
  Libraries under `lib/` load before `src/`; `locales/` load before code that uses strings.
- `embeds.xml` — loads every vendored library in dependency order (LibStub → CallbackHandler →
  Ace* → LibDataBroker/LibDBIcon). Listed first in the TOC.
- `src/core/logger.lua` — `app.logger`. Leveled, colored chat logging; `log("x")` is `log:info("x")`.
- `src/core/db.lua` — `app.dbDefaults`, the AceDB-3.0 defaults. `profile` = user settings,
  `char` = per-character data (loot history), `global` = account-wide. Change the schema here.
- `src/core/ace.lua` — `app.addon`, the AceAddon-3.0 object (mixins: AceConsole, AceEvent).
  `OnInitialize` creates `app.db` from `ForeverLootDB`, wires profile-change callbacks to
  `OnProfileRefresh`, and registers `/fl` + `/foreverloot`. Register game events in `OnEnable`.
- `src/types.lua` — LuaLS annotations only (not in the TOC). `lib/` is excluded from the language
  server, so the Ace/AceDB methods the addon uses are declared by hand here.
- `ForeverLoot.lua` — root entry file, loaded last.
- `lib/` — vendored Ace3, LibStub, CallbackHandler, LibDBIcon. Excluded from LuaLS and StyLua.
- `locales/` — localization string tables.
- `db/` — data tables (static data shipped with the addon).
- `assets/` — textures, icons, sounds referenced from code.

## WoW addon constraints to keep in mind

- The runtime is Lua 5.1 with Blizzard's restricted API. No `require`, `io`, `os`, or
  `loadstring` of external files; all code must be listed in the TOC.
- Addons share a single global namespace. Keep the addon's state in the private table passed
  to each file rather than globals. Every file starts with:
  ```lua
  ---@type string, ForeverLoot
  local appName, app = ...
  ```
  (Use `local _, app = ...` when the name is unused, or LuaLS flags it.) The `---@type` line is
  what gives the Lua language server completion on `app.*`; without it `...` is untyped. `src/types.lua` declares the `ForeverLoot` class — when a file adds a member
  to `app`, add a matching `---@field` there. That file is annotations only and is not in the TOC.
- Persistent state lives only in tables declared via `## SavedVariables` in the TOC; they are
  populated after `ADDON_LOADED` fires, not at file-load time.
