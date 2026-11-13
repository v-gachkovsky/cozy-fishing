# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).

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
