# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).

## [0.2.0] - 2026-11-20

### Added
- **Key bindings** (Key Bindings > AddOns > Cozy Fishing): one key casts, another hooks the fish. Separate, so
  a cast that missed the school can be cast again at once. The hook key's keys turn into Interact with Target
  only while a fishing pole is in hand. Gamepad buttons can be bound too.
- **Fishing trip**: a start button begins a trip and turns into stop, with the trip's time under it. The
  sessions in between add up; the stop (after a question) shows a report with the totals, everything caught and
  each session. A trip lasts over reloads and logouts until stopped; past trips are on a new tab of the history.
- **Swap button and key**: takes a fishing pole from the bags, then puts back the weapon you had (off hand too).
  The weapons are remembered whenever a pole goes on, by the button or by hand. Works in combat.
- **Keys in the settings**: cast, hook and swap each get a key or combination of your own right in the addon's
  settings (a mouse button, a gamepad button or a combination with the gamepad's modifiers too). The first click
  on a key button explains how it works, and only one key is taken, within 10 seconds. A key that already does
  something asks first, and does it again once the addon's binding lets it go. Once, after the first login, a
  message tells that the keys can be set.
- **Hide the swap button with a key** (off by default): with a key to swap, the button can go.
- **Hide the hook with keys** (off by default): with keys to cast and to hook, the hook icon can go, with its
  cast timer; the lure button stays where it was.
- **Cast timer**: a bar over the hook counts down while the line is out.
- **Lure reminder**: while the pole has no lure and there's one in the bags, a button by the hook puts the best
  one the Fishing skill allows on the pole. The icon's tooltip shows the lure's time left.
- **Fishing skill** under the catch total: rank, the bonus of the pole and the lure, the points gained this
  session.
- **Dimming junk**: a right click on an item in the catch dims it and puts it at the end; another brings it
  back. Every item caught is always shown.
- **History** (`/cf history`, Shift-click on the minimap button): the catch of each zone over all sessions, with
  each item's share, how many casts caught something and catches an hour; and the last 100 sessions.
- luacheck and tests (the whole addon against a fake WoW API) on every push and before every release.

### Fixed
- The catch grid's frame was sized from an undefined value when created (found by luacheck).

## [0.1.1] - 2026-11-13

### Fixed
- The hook could stay on screen after changing the fishing pole for a weapon, until a `/reload`. Out of combat
  the addon now checks the main hand itself on every equipment change; the game's `[equipped:]` condition is
  only relied on in combat, and everything is checked again when combat ends.

## [0.1.0] - 2026-11-10

The first version, for WoW Forever.

### Added
- **Hook icon**: the bobber cursor's fishing hook on a clear background, shown while a fishing pole is in hand
  (a state driver, so a weapon swap in combat hides it too), drawn without the cursor's arrow. Left-click casts
  Fishing, optionally clearing the target first; right-click hooks the fish while the line is out (soft targeting
  of objects for the session; while the line is out the icon lets clicks through to the world, where the mouse
  buttons are bound to Interact with Target and to casting again while the cursor is over the icon). The soft
  targeting setting is set again before every cast, as Plater puts back its own saved value. A gold pulse while
  the line is out.
- **Catch grid**: the total caught and a cell per kind of item with its count, with item tooltips. Scale, columns
  and background opacity; can be turned off.
- **Sessions** from putting a pole on to taking it off; kept over a reload or a relog within 30 minutes; an
  optional summary in chat at the end.
- Moving with a modifier + left-drag (Alt by default; Ctrl, Shift, Cmd), resizing with a corner grip, separate
  locks, placing without a pole (`/cf place`), English and Ukrainian.
- `/cf debug`: a trace of the hook in chat and in the saved variables.
- The logo, in the addon list, the settings and on a minimap button (left-click: settings, right-click: show
  the frames for placing; drag it around the minimap; `/cf minimap` hides it).
