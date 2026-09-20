# Inbox

Drop files here to import what the addon recorded in-game, then run

```sh
cd .contribute/tools
npm run import
npm run gen
```

Accepted files (any name):

- `*.lua` — your SavedVariables file, `World of Warcraft/_classic_beta_/WTF/Account/<ACCOUNT>/SavedVariables/ForeverLoot.lua`
  (written on logout and `/reload`; copy it here or point `npm run import -- <path>` at it directly)
- `*.json` — text from `/fl export`, pasted into a file

Files are imported in name order; nothing in this folder is committed (see `.gitignore`).
