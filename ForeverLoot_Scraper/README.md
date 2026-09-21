# ForeverLoot Scraper

This companion addon owns item scanning, loot observation, export commands, and contributor data
collection. It depends on `ForeverLoot` and communicates with it only through the public API.

Its state lives in `ForeverLootScraperDB`. On the first load after upgrading from the combined
addon, existing `ForeverLootDB.global.discovered` and `global.scan` state is copied here and
removed from the old database. Both new and legacy SavedVariables files remain importable by the
repository tooling.

The companion registers `/fl scan` and `/fl export` through the core command API. Disabling it
leaves the database browser, UI, user settings, and loot history in the core fully functional.
