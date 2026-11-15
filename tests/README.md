# Offline tests

Runs the addon in a mock WoW client. Needs only `luajit`.

```sh
cd <addon root>
luajit tests/run.lua            # all tests
luajit tests/run.lua lockouts   # only tests whose name contains "lockouts"
luajit tests/run.lua -v         # also print the failure line of known-bug tests
```

The runner loads the addon through `CooldownManagerPlus.toc` (read at run time, so new files are
picked up), fires `ADDON_LOADED`, `PLAYER_LOGIN` and `PLAYER_ENTERING_WORLD`, runs every
`tests/cases/*.lua`, prints `PASS` / `FAIL` / `KNOWN BUG` per test and a summary, and exits non-zero
on any failure. Every test boots a fresh client and addon.

## Layout

| File | What |
|---|---|
| `run.lua` | entry point |
| `harness.lua` | `.toc`/XML loader, `boot`, assertions (`T.eq`, `T.truthy`, `T.near`, `T.errors`, ...), runner |
| `mock/wow.lua` | the client API: frames and regions, scripts and hooks, anchors/geometry, timers, events, `C_*` tables, secret values |
| `mock/blizzard.lua` | the four Cooldown Manager viewers and their items (modelled on `CooldownViewer.xml/lua`), Personal Resource Display, Edit Mode manager and settings dialog |
| `cases/NN_*.lua` | the tests |

Unknown globals **fail loudly**: the mock raises and records "unknown global 'X'". Globals the addon
probes on purpose (`if C_EncodingUtil then`) are listed in `OPTIONAL` in `mock/wow.lua`. Unknown
templates in `CreateFrame` fail the same way; add them to `H.templates` or `H.ignoredTemplates`.

Any Lua error that the client would route to the error handler (event/script handlers, hooks,
timers, `CMP.Safe`) is recorded in `H.errors`, and **a test fails if the list is not empty** when it
ends (set `allowErrors = true` in the test options to opt out).

## Adding a test

Create or edit a file in `tests/cases/`. Each file receives the assertion table `T`:

```lua
local T = ...

T.test("what it checks", function(H, T)
	local item = H.viewers.BuffIcon:AddItem({ spellID = 17, linkedSpellID = 6788 })
	H.setItemAura(item, H.addAura("player", { spellId = 6788, isHarmful = true, duration = 15, expirationTime = H.now + 15 }))
	H.fireEvent("UNIT_AURA", "player", {})
	H.flush()                                  -- run zero-delay C_Timer callbacks
	T.truthy(item:GetChildren())
end)
```

`T.test(name, opts, fn)` takes boot options as `opts`: `saved` (value of `CooldownManagerPlusDB`
before load), `setup = function(H)` (runs after Blizzard's frames exist, before the addon loads),
`combat = true`, `viewers = {...}`, `prd = false`.

Useful `H` helpers:

* `H.CMP`, `H.ns`: the addon's table and namespace. `H.viewers.Essential|Utility|BuffIcon|BuffBar|PRD`.
* `viewer:AddItem{ spellID, linkedSpellID, overrideSpellID, shown }` acquires an item the way Blizzard does.
* `H.setItemAura(item, aura, unit)`, `H.addAura(unit, aura)`, `H.removeAura(unit, id)`; `H.spells[id] = {name, helpful, hasRange, usable}`.
* `H.fireEvent(event, ...)` delivers to registered frames (honours `RegisterUnitEvent`).
* `H.advance(seconds)` moves `GetTime()` and runs due timers; `H.flush()` runs zero-delay timers (returns `drained, rounds`; `drained == false` means something keeps re-queuing itself); `H.inCombat = true`.
* Edit Mode: `H.enterEditMode()`, `H.select("BuffBar")`, `H.placeDialog(left, top, w, h)`, `H.extension()`, `H.widget("Grow From")`, `H.clickExpander("Bar Look")`, `H.wheel(-1)`.
* `H.state(obj)` returns the mock's private state for a widget (cooldown start/duration, swipe texture, ...). `H.raw.SetPoint(frame, ...)` calls the C method the way the addon does; calling `viewer:SetPoint` goes through Blizzard's Edit Mode override and is recorded in `H.violations`.
* Secret values: `H.secret(v)` (raises on arithmetic, ordering, `..`, `#`, indexing, calling; `issecretvalue` is true, `type()` still reports the real type), `H.secretFields(tbl[, names...])`, `H.secretReturn(owner, "Method", "whole"|"fields")` to make an API's results secret.
* `H.output`: lines passed to `print`; `T.printed(H, "text")` searches them.

## Known addon bugs

A test that documents an addon bug carries `knownBug = "file:line and scenario"` in its options. It
prints `KNOWN BUG` and does not fail the run; when the bug is fixed the test passes, the runner
reports `UNEXPECTED PASS` (a failure) and the `knownBug` option should be removed. The runner lists
all of them at the end.
