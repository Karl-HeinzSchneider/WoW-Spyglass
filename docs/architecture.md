# Architecture

ForeverLoot is a monorepo containing independently loadable World of Warcraft addons and the
tooling that produces their data. A direct child directory containing a same-named `.toc` file is
an addon distribution unit.

## Addon boundaries

| Addon                  | Owns                                                                                                                                    | Persistent state       | Dependency                            |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- | ------------------------------------- |
| `ForeverLoot`          | Public API, data store and queries, content modules, UI, user settings and loot history                                                 | `ForeverLootDB`        | none                                  |
| `ForeverLoot_Database` | Every scanned item row with its English name, and the `items` module (the searchable, filterable item browser)                          | none                   | `ForeverLoot`                         |
| `ForeverLoot_Locale`   | Additional UI translations, generated localized item, instance and boss names, and the item names a non-English client looks up in-game | `ForeverLootLocaleDB`  | `ForeverLoot`                         |
| `ForeverLoot_Scraper`  | Item scanning, loot observation, contribution exports and scraper commands                                                              | `ForeverLootScraperDB` | `ForeverLoot`, `ForeverLoot_Database` |

The scanned item rows live in the database addon, generated non-English names in the locale
addon. Scanning, discovery state, JSON export, and the export dialog live in the scraper addon.
The core operates independently when any companion is absent or disabled.

## Runtime contract

- `ForeverLoot` must work when any companion addon is absent or disabled. It retains an English
  fallback for instance, boss and crafting names (item names come from the client) and cannot
  reference companion files or private addon tables.
- Companion addons declare `## Dependencies: ForeverLoot`, so the public global exists before they
  load. The scraper also depends on `ForeverLoot_Database`: it tells new items from known ones by
  the item rows (`Data:GetItem`).
- Each addon keeps implementation state in the private table passed through `...`. No addon may
  access another addon's private table or introduce a cross-addon implementation global.
- Companion addons integrate only through the documented global `ForeverLoot` API. A required
  breaking change increments `ForeverLoot.API_VERSION` and updates `docs/API.md`.
- Late data registration uses `ForeverLoot.Data:AddNames`, `AddItems`, `AddBossLoot`,
  `AddTrashLoot`, `AddQuests`, `AddList`, `AddListLoot`, `AddRecipes` or `AddCategories`. These
  calls invalidate affected caches and publish `OnDataChanged`.
- Built-in content modules continue to use the same public API available to third-party addons.

## Localization boundary

The core owns locale selection, English fallback behavior, and the registration surface. It ships
generated `enUS` instance, boss and crafting names so it remains useful without the companion;
item names come from the client in its own language. The locale addon owns every non-fallback
generated name table, the item names it learns in-game for the items those tables lack, and will
own translated UI strings. The core searches an item's client-locale and English names both.
Locale data registers after the core database loads; `OnDataChanged` refreshes visible data.

The generator routes `enUS` instance, boss and crafting names to
`ForeverLoot/db/generated/locales/`, `enUS` item names (with the item rows) to
`ForeverLoot_Database/db/generated/locales/`, and every other configured or scanned locale to
`ForeverLoot_Locale/db/generated/locales/`. The locale addon's TOC lists its files as
`locales\[TextLocale]\<file>.lua`, which the client resolves to its own language, so the other
languages are never read; every client language has all four files (placeholders where there are
no names), because a missing one is a `LUA_WARNING` at login.

## Database boundary

The core owns the item database API (`ForeverLoot.Data`, `Filters`, `Query`) and every list that
shows items, but ships no item rows. `ForeverLoot_Database` adds every scanned item row and its
English name through `Data:AddItems` / `AddNames`, registers the `items` module, and builds the
item browser's sort order at `PLAYER_LOGIN`. Without it the core's lists take an item's name,
quality, icon and kind from the client, fetching what it has not cached yet.

## Scraper boundary

The core owns browsing and durable user-facing loot history. The scraper owns contributor-facing
collection state and transport: scan progress, discovered item rows, observed boss drops, JSON
encoding, exports, the export dialog, and scan/export commands.

The scraper registers `/fl scan` and `/fl export` through the public command-extension API. Its
AceAddon object, database, frames, and modules remain private. It never reads or writes
`ForeverLootDB`; everything it records lives in `ForeverLootScraperDB`, which is also the only
SavedVariables layout the repository import tooling reads.

## Tooling boundary

Root TypeScript tools may read `.contribute/data/` and write generated files inside addon
directories. Runtime addons never import from root `src/` and never read contributor JSON.

Development linking, validation, and packaging discover addon directories rather than maintaining
a hard-coded addon list. Adding a companion addon therefore requires only its directory and
same-named `.toc` manifest.
