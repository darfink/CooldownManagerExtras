# Screenshot shot list

Put the files in this folder with these exact names. `docs/CURSEFORGE.md` links to them.

Status: 01, 02, 04, 05 and 08 are done. 03, 06 and 07 are still to do; their image links
were taken out of `docs/CURSEFORGE.md` until the files exist. Add the link back when you
add a file.

The images are labelled cards: the interface is cut out of the game world and placed on
a dark card with short labels. `cards/make.py` builds them from the raw screenshots, as
set up in `cards/cards.json` (what to keep, where the labels go). After a retake, update
`src` and the rectangles there and run `python3 docs/screenshots/cards/make.py`.

For shots that become cards:

- Make the frames big: raise UI Scale, or the frames' Size, before you take the shot.
  Small frames get blurry when the card scales them up.
- Use a plain dark background (a cave wall, the night sky). Parts of the interface that
  are see-through, like the empty part of a bar, show what is behind them.

General rules:

- Take them at 1920×1080 or higher, at your normal UI scale.
- Crop tight to what the shot is about. Keep the same width inside a pair (before/after).
- Use one character and one spec for all shots, so the look is consistent.
- Hide chat and unrelated add-ons. A plain background (sky, a calm zone) reads best.
- PNG for stills. Keep GIFs short (3–6 s), about 800 px wide, under ~5 MB.

| # | File | Shows | How to set it up |
|---|------|-------|------------------|
| 1 | `01-hero.png` | The finished look, in action | In combat on a target dummy. Personal Resource Display with your colors, square icons, a centered Essential row with a custom trinket or potion inside it, Tracked Buffs attached below. Crop to the cooldown area plus a bit of the character. About 1200×500. |
| 2 | `02-edit-mode-panel.png` | Options live in Blizzard's panel | Edit Mode, Essential Cooldowns selected. Blizzard's settings and our sections in the same panel, one section open (Icons or Anchoring). Include the selected frame in the shot. |
| 3 | `03-drag-attach.gif` | Drag to attach | Drag Utility Cooldowns toward Essential Cooldowns. The drop preview and its label show; let go; the row snaps in. Then hold Shift and drag freely once. |
| 4 | `04-cooldown-settings-plus.png` | Custom spells next to Blizzard's | Cooldown Settings open on Essential Cooldowns. A custom trinket or potion in the grid, the **+** tile visible, and the add menu open (Spell, Item, Trinket Slot, From Your Bags). |
| 5 | `05-buff-menu.png` | Buffs from your own casts | Tracked Buffs **+** menu open on "Started by Your Spells and Items", showing names with durations and IDs (use a trinket and a potion once beforehand so the list has entries). |
| 6 | `06-icons-before-after.png` | Square icons | Two rows side by side or stacked: left Blizzard's default round-masked icons, right square icons with borders. Include one debuff with a Magic color border. |
| 7 | `07-prd-before-after.png` | Personal Resource Display colors | Same as 6: Blizzard default left, your textures and colors right (for example turquoise mana). Ideally mid-cast so the cost preview shows. |
| 8 | `08-spell-menu.png` | Per-spell options | Right-click menu on a spell in Cooldown Settings, with "Border Color" or "Gray Out During" opened as a submenu, and "Show cooldown, not buff duration" visible. |

Also upload all of these to the CurseForge gallery with a short caption each. The
gallery thumbnails show on the project page and in search results; use `01-hero.png`
as the first image.
