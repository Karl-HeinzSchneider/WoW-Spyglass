# ForeverLoot Scraper

This companion addon will own item scanning, loot observation, export commands, and contributor
data collection. It depends on `ForeverLoot` and may communicate with it only through the public
`ForeverLoot` API.

Discovery behavior remains in the core addon until the scraper extraction milestone. New scraper
state will live in `ForeverLootScraperDB`; migration of existing discovery state will happen as
part of that extraction.
