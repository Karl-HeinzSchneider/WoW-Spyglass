# Inbox

Drop files here to import what the addon recorded in-game, then run

From the repository root:

```sh
npm run import
npm run gen
```

Accepted files (any name):

- `*.lua` — your SavedVariables file, `World of Warcraft/_classic_beta_/WTF/Account/<ACCOUNT>/SavedVariables/ForeverLoot_Scraper.lua`
  (written on logout and `/reload`; copy it here or point `npm run import -- <path>` at it directly)
  Legacy `ForeverLoot.lua` files recorded before the scraper split are also accepted.
- `*.json` — text from `/fl export`, pasted into a file

Files are imported in name order; nothing in this folder is committed (see `.gitignore`).
