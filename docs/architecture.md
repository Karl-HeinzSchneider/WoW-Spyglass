# Architecture

ForeverLoot is a monorepo containing independently loadable World of Warcraft addons and the
tooling that produces their data. A direct child directory containing a same-named `.toc` file is
an addon distribution unit.

## Addon boundaries

| Addon | Owns | Persistent state | Dependency |
|---|---|---|---|
| `ForeverLoot` | Public API, data store and queries, content modules, UI, user settings and loot history | `ForeverLootDB` | none |
| `ForeverLoot_Locale` | Additional UI translations and generated localized item, instance and boss names | none planned | `ForeverLoot` |
| `ForeverLoot_Scraper` | Item scanning, loot observation, contribution exports and scraper commands | `ForeverLootScraperDB` | `ForeverLoot` |

Generated non-English names have been extracted into the locale addon. The scraper implementation
has not been extracted yet; its shell establishes the future distribution and state boundary.

## Runtime contract

- `ForeverLoot` must work when either companion addon is absent or disabled. It retains an English
  fallback and cannot reference companion files or private addon tables.
- Companion addons declare `## Dependencies: ForeverLoot`, so the public global exists before they
  load.
- Each addon keeps implementation state in the private table passed through `...`. No addon may
  access another addon's private table or introduce a cross-addon implementation global.
- Companion addons integrate only through the documented global `ForeverLoot` API. A required
  breaking change increments `ForeverLoot.API_VERSION` and updates `docs/API.md`.
- Late data registration uses `ForeverLoot.Data:AddNames`, `AddItems`, `AddBossLoot`, `AddList`, or
  `AddListLoot`. These calls invalidate affected caches and publish `OnDataChanged`.
- Built-in content modules continue to use the same public API available to third-party addons.

## Localization boundary

The core owns locale selection, English fallback behavior, and the registration surface. It ships
generated `enUS` names so it remains useful without the companion. The locale addon owns every
non-fallback generated name table and will own translated UI strings. Locale data registers after
the core database loads; `OnDataChanged` refreshes visible data.

The generator routes `enUS` names to `ForeverLoot/db/generated/locales/` and every other configured
or scanned locale to `ForeverLoot_Locale/db/generated/locales/`. Each non-English file guards
itself with `GetLocale()`, so installing the complete locale addon has negligible runtime work on
other clients.

## Scraper boundary

The core owns browsing and durable user-facing loot history. The scraper owns contributor-facing
collection state and transport: scan progress, discovered item rows, observed boss drops, JSON
encoding, exports, and scan/export commands.

Until extraction, discovery code and its existing data remain in `ForeverLoot`. Step 10 must
migrate or read `ForeverLootDB.global.discovered` and `ForeverLootDB.global.scan` before new state
is written exclusively to `ForeverLootScraperDB`.

## Tooling boundary

Root TypeScript tools may read `.contribute/data/` and write generated files inside addon
directories. Runtime addons never import from root `src/` and never read contributor JSON.

Development linking, validation, and packaging discover addon directories rather than maintaining
a hard-coded addon list. Adding a companion addon therefore requires only its directory and
same-named `.toc` manifest.
