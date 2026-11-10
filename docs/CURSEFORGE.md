**A fishing hook on your screen: left-click casts, right-click hooks the fish. And the catch of the session.**

> **Early development.** Easy Fishing is young. If something looks wrong or you miss a feature, please tell me
> in the comments or on [GitHub](https://github.com/v-gachkovsky/easy-fishing/issues): no report is too small.

No more hunting for the bobber with the mouse. Take a fishing pole in hand and a hook appears on the screen.
Click it to cast; when the fish bites, right-click it to reel in. Next to it, a see-through grid counts what
you've caught.

**For WoW Forever.**

---

## How it works

- **The hook shows up with the pole.** Put a fishing pole on and the hook appears: the same hook as the cursor
  over a bobber, on a clear background. Take the pole off or change it for a weapon (even in combat) and it's gone.
- **Left-click** casts Fishing. It can clear your target first, so the hook goes to the bobber.
- **Right-click** while the line is out hooks the fish, wherever the bobber landed. The hook pulses gold while
  the line is out, so you know a right click now reels in.
- **The catch of the session**: the total on top, then one cell per kind of fish or item with how many, in the
  order you caught them. Hover a cell for the item's tooltip. No frame and no background, unless you want one.
- **A session** lasts from putting the pole on to taking it off. It survives a `/reload` or a quick relog, and
  a summary goes to chat at the end if you like.
- **Move** the hook and the grid with **Alt + left-drag** (or Ctrl, Shift, Cmd on a Mac), **resize** them by the
  corner, and **lock** each one separately.
- **Minimap button**: click for the settings, right-click to show the frames without a pole, to place them.

## How the hook works

An addon can't click the bobber itself, so Easy Fishing uses the game's own **soft targeting**: for the session
it lets the game target objects, which makes your bobber the interact target, and the right click on the hook
becomes the game's **Interact with Target**. When the pole comes off, those game settings go back to what they
were. Addons that keep the setting in their own profile (Plater does) are handled: it's set again before every
cast.

The game doesn't tell addons when a fish bites; watch the bobber or listen for the splash, then right-click.

## Settings (`/ef`)

Showing and locking the hook and the grid, the hook's size, clearing the target when casting, the grid's
scale, columns and background, the chat summary, the minimap button, the key that moves the frames, the
language (English or Ukrainian).

## Commands

- `/ef`: settings
- `/ef lock`, `/ef unlock`: lock or unlock both frames
- `/ef place`: show the frames without a fishing pole, to place them
- `/ef stats`: print the catch of this session
- `/ef clear`: start the catch of this session over
- `/ef reset`: put the frames back in their default places
- `/ef minimap`: show or hide the minimap button
