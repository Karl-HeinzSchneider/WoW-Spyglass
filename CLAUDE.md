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
- `src/core/registry.lua` — `app.api`, also the **public global `ForeverLoot`** (contract in
  `docs/API.md`). `RegisterModule(def)` validates and stores module definitions; `GetRootNode()`
  builds the virtual tree the window browses (one node per module, sorted by `order`). Events via
  CallbackHandler-1.0 (`OnModuleRegistered/Unregistered/OnModulesChanged`). Defines the
  `ForeverLoot.Node` and `ForeverLoot.ModuleDef` types. Changing the API means updating `docs/API.md`.
- `modules/<name>/` — one folder per built-in content module (`raids`, `dungeons`, …), each with a
  `<name>.xml` loader listed in `modules/modules.xml`. `<name>.lua` only registers the module
  (metadata, `children = {}`, `sortChildren = true`); **each instance is its own file** (e.g.
  `dungeons/deadmines.lua`) that builds a folder with all of its bosses and calls
  `ForeverLoot:AddToModule("<name>", folder)`. The XML lists the module file first. Modules use
  only the public API a third-party addon would use, so never give them private hooks. Current
  data is placeholder.
- `src/core/ace.lua` — `app.addon`, the AceAddon-3.0 object (mixins: AceConsole, AceEvent).
  `OnInitialize` creates `app.db` from `ForeverLootDB`, wires profile-change callbacks to
  `OnProfileRefresh`, and registers `/fl` + `/foreverloot`. Register game events in `OnEnable`.
- `src/types.lua` — LuaLS annotations only (not in the TOC). Declares the `ForeverLoot` namespace
  class and `ForeverLoot.DB`. Ace3 types (`AceAddon`, `AceDBObject-3.0`, `AceDB.Schema`, …) come
  from the `ketho.wow-api` VS Code extension, not from `lib/` (which is excluded from LuaLS) —
  inherit from them rather than redeclaring the API.
- `src/ui/` — the main window, Blizzard-style **XML layout + Lua mixin** so the exported Blizzard
  code (see below) maps 1:1. XML `mixin=`/`name=` attributes need globals, so mixins and the window
  frame are globals prefixed `ForeverLoot…` (also on `app.ui.*`). Together with the public
  `ForeverLoot` API table these are the only sanctioned globals. Lua mixin files must be listed in the TOC *before* the XML that
  references them, and `templates.xml` before `mainwindow.xml`.
  - `mainwindow.lua/.xml` — `ForeverLootMainWindow`: `PortraitFrameTemplate` + `TabSystemOwnerTemplate`
    (modeled on `PlayerSpellsFrame`). Browser-style tabs: one per open *view*, plus a `+` tab;
    right-click closes. The Blizzard tab strip can only append/clear, so `RebuildTabs()` redoes the
    whole strip. Draggable; position saved to `profile.window`. `/fl` and the minimap button toggle it.
  - `view.lua` + `templates.xml` — a view is a breadcrumb bar + two spellbook-art pages of rows with
    Blizzard `PagingControls`. Navigation is a `path` stack over `ForeverLoot.Node` trees
    (`Push`/`PopTo`/`Back` → `Refresh`).
  - The window's root comes from `app.api:GetRootNode()`; it listens to `OnModulesChanged`.
- `ForeverLoot.lua` — root entry file, loaded last.
- `lib/` — vendored Ace3, LibStub, CallbackHandler, LibDBIcon. Excluded from LuaLS and StyLua.
- `locales/` — localization string tables.
- `db/` — data tables (static data shipped with the addon).
- `assets/` — textures, icons, sounds referenced from code.

## XML files

Every XML file starts with `<Ui xmlns="http://www.blizzard.com/wow/ui/">` and **no**
`xsi:schemaLocation` — the client ignores that hint and a wrong path makes the VS Code XML
extension report errors. Schema validation instead comes from `xml.fileAssociations` in
`.vscode/settings.json`, which maps `**/*.xml` to `BlizzardInterfaceCode/.../Blizzard_SharedXML/UI.xsd`
(so it only works when the optional `BlizzardInterfaceCode/` symlink exists). To validate from
the command line: `python -c "from lxml import etree; ..."` against that XSD, as in this session.

## Optional: Blizzard's own UI source and art for reference

A developer may place Blizzard's exported interface files in the repo root, typically as
symlinks to the folders the game client writes next to the WoW install:

- `BlizzardInterfaceCode/` — from `/run ExportInterfaceFiles("code")`. Lua/XML for all of
  Blizzard's FrameXML/AddOns.
- `BlizzardInterfaceArt/` — from `/run ExportInterfaceFiles("art")`. Every texture as `.blp`
  under `BlizzardInterfaceArt/Interface/...` (e.g. `Interface/Icons/INV_Misc_Bag_10.blp`).

Both are gitignored and excluded from LuaLS/StyLua. If they exist, Claude should **read them,
never edit them**:

- Code: look up exact API signatures/return values, event payloads, frame templates and global
  strings. Prefer it over guessing from memory, since the Classic client's API differs from retail.
- Art: verify that a texture path used in code exists (paths are case-insensitive in-game, so
  match case-insensitively), and browse for suitable icons/textures by name. `.blp` files can't
  be viewed directly; the file list is what matters. Atlas names (`atlas="..."`) are *not* in
  this export — they're looked up from XML usages in `BlizzardInterfaceCode` instead.

Never list anything from these folders in the TOC or copy files out of them into `src/`.

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
