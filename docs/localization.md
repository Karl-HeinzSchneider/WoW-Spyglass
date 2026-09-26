# Names in every language

Where the addons' item, instance, boss and profession names come from in each language, and how
`Spyglass_Locale` fills the gaps in-game. The ownership rules are in
[architecture.md](architecture.md#localization-boundary); the generator side is in
[data-pipeline.md](data-pipeline.md).

## Where each name lives

| Names                                                         | enUS                                                                      | Every other language                                                          |
| ------------------------------------------------------------- | ------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Instances, bosses, professions, trade skill categories, tools | the core, `Spyglass/db/generated/locales/enUS/` (its standalone fallback) | `Spyglass_Locale/db/generated/locales/<locale>/`                              |
| Items                                                         | `Spyglass_Database/db/generated/locales/enUS/`, with the item rows        | `Spyglass_Locale/db/generated/locales/<locale>/`, plus what it learns in-game |

Instance, boss, profession, category and tool names come from wago.tools for the locales
configured in `.contribute/data/config.json`. Item names come from wago.tools' `ItemSparse` for
the configured locales, for the scanned items whose English name there matches the scan (most of
them), and from in-game scans on a client of that language (a deDE scan adds German names next
to the English ones in `.contribute/data/items/*.json`), which win over the table's. The items
this server added or changed are missing from `ItemSparse`; at runtime the locale addon looks
those up (below).

The locale addon's TOC lists its four files as `db\generated\locales\[TextLocale]\<file>.lua`, a
path variable the client resolves to its text locale, so only the client's own language is read
at all. A missing file is a `LUA_WARNING` at login, so every client language (`enUS` and `enGB`
included, whose English names live in the core and the database addon) has all four files, as
comment-only placeholders where there are no names; `npm run check:addons` enforces it. Each file
with names still starts with `if GetLocale() ~= "<locale>" then return end`.

## How the core resolves a name

An item name: client locale → enUS → `C_Item.GetItemInfo` → `"Item #id"`. The other kinds stop at
enUS. Search matches both the client-locale and the English name. `Data:AddNames` fires
`OnDataChanged`, so names registered late refresh the open views.

## Learning item names in-game (`Spyglass_Locale/src/itemnames.lua`)

The client knows the names `ItemSparse` lacks in its own language once it has fetched the items,
so on a non-English client `app.itemNames` asks for them and keeps the answers in
`SpyglassLocaleDB.global.locales[locale]` (`{ build?, items = { [itemID] = name }, missing = { [itemID] = true } }`):

- `OnInitialize` (`ADDON_LOADED`, after every generated file has run): clears `missing` when the
  client build changed, drops saved names the shipped files now have, and registers the rest with
  one `Data:AddNames(locale, "items", …)`.
- `OnEnable` (`PLAYER_LOGIN`) starts a lookup `START_DELAY` = 15 s later, for every id from
  `Data:GetItemIDs()` without a name in `Data.names[locale].items` and not `missing`. Those ids
  are the rows `Spyglass_Database` adds; without that addon nothing is looked up.
- `BATCH` = 5 ids per `INTERVAL` = 0.5 s (10 per second, a tenth of `/sg scan`), none while
  `InCombatLockdown()`. A cached item is read at once, others through
  `C_Item.RequestLoadItemDataByID` and `ITEM_DATA_LOAD_RESULT`.
- A name from `C_Item.GetItemInfo` goes into the saved table right away, and to `Data:AddNames`
  every `FLUSH_INTERVAL` = 30 s and at the end (each call invalidates the core's search and sort
  caches). A failed load marks the id `missing`. `SETTLE` = 5 s waits for the last answers; ids
  that never answered are asked again next session.
- `info` lines say how many names a lookup asks for and how many it learned. `/sg locale` prints
  the progress or the saved counts; `/sg locale rescan` clears `missing` and asks for every
  learned item again too.

English clients (`GetLocale() == "enUS"`) keep no state and run nothing; at login they get one
`info` line saying the addon isn't needed there and can be disabled.

## Adding a locale

Add it to `locales` in `.contribute/data/config.json` (instance, boss, profession and item names
from wago.tools) and/or scan items on a client of that language and `npm run import`, then
`npm run gen`. A client language that is not configured still gets its item names from
`itemnames.lua`, all of them looked up in-game.
