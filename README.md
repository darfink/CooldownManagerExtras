# Cooldown Manager Extras

More Edit Mode options for Blizzard's Cooldown Manager. No replacement frames.

Blizzard's Cooldown Manager still decides what is tracked, in what order and with which
icons. This add-on adds the options it lacks, in the place you already use: select a
cooldown viewer (or the Personal Resource Display) in Edit Mode and the extra settings
show in its settings panel.

Made for WoW Forever.

## Features

- **Layout:** center a row, or let it grow from its left or right edge. Rows of buffs
  close the gaps of inactive icons.
- **Anchoring:** attach a viewer to another viewer or to the Personal Resource Display,
  on any side, with a gap. Snapping two frames together in Edit Mode attaches them. An
  attachment stays when its target hides.
- **Width matching:** make a viewer, the Tracked Bars or the Personal Resource Display as
  wide as another one.
- **Square icons:** pixel-exact borders, icon zoom, and square cooldown swipes. Debuff-type
  colors (Magic, Curse, ...) stay visible.
- **Custom spells and items:** add your own spells, items (potions, healthstones) and
  trinket slots to Essential or Utility Cooldowns, with the + tile in Cooldown Settings or
  by dropping a spell or item on it. They show in the same row as Blizzard's icons, at the
  place you pick, in the same look. Potions can stay visible with none left in your bags.
- **Custom buffs in Tracked Buffs:** add any buff, also ones other players give you (pick
  from the buffs seen on you). Shown while it is on you. When the game hides a buff from
  add-ons in combat, a buff you start yourself (trinket, potion, spell) is timed from your
  cast instead.
- **Per-spell borders:** right-click a spell in Cooldown Settings to give it its own
  border color.
- **Fonts and textures:** timer and count fonts, Tracked Bars and Personal Resource Display
  bar textures (LibSharedMedia and Blizzard textures), square bar style.
- **Personal Resource Display bars:** the health and power bars each get their own
  texture; health in class color or your own; each power type (Mana, Rage, Energy, ...)
  its own color; the cast cost preview's texture and color.
- **Debuff timers:** Tracked Buffs show a timer on debuffs such as Weakened Soul, also in
  combat.
- **Show cooldown, not buff duration:** per spell, for spells that put a buff on you.
- **Gray out during a debuff:** per spell, for example Power Word: Shield while you have
  Weakened Soul.
- **Keybind text** on cooldown icons, read from Blizzard's action bars.
- **Five-second rule** spark on the Personal Resource Display's mana bar.
- **Profiles:** share a setup between characters and talent groups, and import or export
  it as text.
- **Masque:** if Masque skins the viewers, the icon look is left to Masque.

## Commands

- `/cme` lists the commands. `/cme options` opens profiles and import/export.
- `/cme status`, `/cme probe`, `/cme timers`, `/cme rings` and `/cme blocked` print what
  the add-on sees, for bug reports.
- `/cme probe spell|item|slot|aura <id>` shows what the game lets add-ons read about one
  cooldown or buff right now. Run it in combat.

`/cmp` works too.

## Development

The tests run outside the game, against a mock of the WoW client:

```sh
luajit tests/run.lua
```

See [tests/README.md](tests/README.md).

### Releasing

Push a version tag. GitHub Actions runs the tests, then
[BigWigsMods/packager](https://github.com/BigWigsMods/packager) builds the zip and uploads
it to CurseForge and GitHub Releases.

```sh
git tag v0.1.0
git push origin v0.1.0
```

Tags with `alpha` or `beta` in them are uploaded as alpha or beta files.

## License

MIT. The bundled [LibEditMode](https://github.com/p3lim-wow/LibEditMode) keeps its own
license (`Libs/LibEditMode/LICENSE.txt`).
