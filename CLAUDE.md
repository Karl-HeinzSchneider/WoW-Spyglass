# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ForeverLoot is a World of Warcraft addon written in Lua. The repository is currently a skeleton:
`ForeverLoot.toc`, `ForeverLoot.lua`, and every directory are empty placeholders. Nothing below
describes existing behavior; it describes the layout the project has committed to and the
constraints of the WoW addon runtime.

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
- `ForeverLoot.lua` — root entry file at the repo top level.
- `src/` — addon code.
- `lib/` — third-party libraries vendored into the addon (loaded first via the TOC).
- `locales/` — localization string tables.
- `db/` — data tables (static data shipped with the addon).
- `assets/` — textures, icons, sounds referenced from code.

## WoW addon constraints to keep in mind

- The runtime is Lua 5.1 with Blizzard's restricted API. No `require`, `io`, `os`, or
  `loadstring` of external files; all code must be listed in the TOC.
- Addons share a single global namespace. Keep the addon's state in the private table passed
  to each file (`local addonName, ns = ...`) rather than globals.
- Persistent state lives only in tables declared via `## SavedVariables` in the TOC; they are
  populated after `ADDON_LOADED` fires, not at file-load time.
