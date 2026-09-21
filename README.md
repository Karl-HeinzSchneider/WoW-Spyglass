# WoW-ForeverLoot

ForeverLoot is a World of Warcraft addon and its supporting data toolchain, maintained as a
monorepo.

## Repository layout

- `ForeverLoot/` — the distributable core addon.
- `ForeverLoot_Locale/` — additional generated locale data loaded through the public core API.
- `ForeverLoot_Scraper/` — optional in-game scanning, loot observation and contribution exports.
- `.contribute/data/` — canonical item scans and curated game data.
- `.contribute/inbox/` — ignored SavedVariables and JSON exports waiting to be imported.
- `src/` — the Node.js/TypeScript validation, import, generation, development and packaging tools.
- `docs/` — public API and project documentation.

Root tooling discovers any direct child directory with a same-named `.toc`, including both
companion addon shells.

## Tooling

Node.js 20 or newer is required. Run every command from the repository root.

```sh
npm install
npm run check
npm run generate
```

Useful commands:

- `npm run check:data` validates curated data.
- `npm run check:addons` validates addon manifests, dependencies and core/companion boundaries.
- `npm run generate:check` verifies that generated addon data is current.
- `npm run import` imports every supported file in `.contribute/inbox/`.
- `npm run fix` fills resolvable IDs/names and missing encounters.
- `npm run dev:link -- "<WoW>/Interface/AddOns"` links every addon into a client installation.
- `npm run package:addons` creates a release ZIP under `dist/`.

See [.contribute/README.md](.contribute/README.md) for the data contribution workflow and
[docs/API.md](docs/API.md) for the addon API. The ownership and integration rules between addons
are documented in [docs/architecture.md](docs/architecture.md).
