# Boss portrait converter

Turns a screenshot of the scraper's `/sg portrait` window into a boss picture for the browser's
boss cards: `Spyglass/assets/bosses/<name>.blp`, 128x64 with transparency, the same format as
the client's own Encounter Journal boss art.

Needs Python 3 with Pillow (`pip install pillow`).

## Steps

1. In game, with `Spyglass_Scraper` enabled: `/sg portrait <displayID>` (or walk the bosses
   with `< Boss` / `Boss >`). Frame the model with zoom / turn / offset; keep the defaults
   (`Reset`) unless the boss doesn't fit, so all pictures look alike.
2. Take a screenshot (Print Screen) with the whole window visible. A lossless PNG gives the
   cleanest edges; JPEG works, but its artifacts show at the transparent border.
3. Convert it:

   ```text
   python tools/portrait/portrait.py <screenshot> <name> [--preview <png>]
   ```

   `<name>` is the file name without extension, lowercase with underscores like the boss
   (`magmatus` -> `Spyglass/assets/bosses/magmatus.blp`); a path ending in `.blp` writes
   there instead. `--preview` also writes a 4x PNG on grey to look at the result.

4. The script prints the line for the boss in its instance file under
   `.contribute/data/dungeons/` (or `raids/`); add it to the encounter:

   ```json
   "portrait": "Interface\\AddOns\\Spyglass\\assets\\bosses\\magmatus.blp",
   ```

5. `npm run gen`, and restart the game client: it only finds new files on startup, `/reload`
   is not enough.

## How it works

- Finds the two magenta frames (the window draws them just outside the captured area): the
  left one holds the boss on black, the right one on white.
- Transparency comes from the pair: alpha = 1 - (white - black). The shot on black is the color
  already multiplied by alpha.
- Takes the largest 2:1 area inside the frames, scales it to 128x64 (premultiplied, so edges
  don't get dark fringes), and writes a BLP2 file: uncompressed BGRA, 8-bit alpha, no mipmaps.
