# LetMeLook

Grain Rot clamps how far up and down you can look. This removes that clamp, so
you can look straight up and straight down.

That is the whole mod.

## What it changes

The game applies three separate pitch clamps at once, and each one is narrower
than 90 degrees somewhere, so all three have to go:

| Clamp | Stock value | After |
|---|---|---|
| `ViewPitchMin` / `ViewPitchMax` on your camera manager | -70 / +80 | -89.9 / +89.9 |
| `CameraPitchMin` / `CameraPitchMax` on the global camera settings | -60 / +90 | -89.9 / +89.9 |
| `bLimitPitch` / `LimitPitch` on the movement camera presets | clamped | off |

The preset is swapped by stance, which is why the stock limit is tighter when
you are crouched or sprinting (-60) than when you are standing (-80).

It stops at 89.9° rather than a dead-on 90° on purpose — that is the engine's
own default, and the last tenth of a degree is where a camera clamp stops being
a clamp and starts being a gimbal problem. In practice it is straight up and
straight down; you cannot see the difference.

The mod re-checks the values about once a second, because the game does put
`ViewPitchMin`/`ViewPitchMax` back from time to time. Applying once would work
until the first reset and then quietly stop.

## What it deliberately does not change

Only the four movement presets are unclamped — **Default, Sprint, Crouch and
Prone**. These are left exactly as the game shipped them:

- **Ragdoll** deliberately forces the view downward while you are ragdolled.
  Unclamping it would break that shot.
- **Cinematic** is already unclamped by the game.
- **Soul** frames the soul sequences.
- The **emote** presets clamp on purpose, so emotes still frame correctly.

**Spine aim is not touched.** Those are animation clamps — how far your
character's spine and head twist to follow your aim — and they are replicated
state that other players see. Only the camera moves the full range; your body
does not crane to follow it at the extremes, which is what most third-person
games do anyway.

## Co-op

Nothing here is replicated or saved.

`ViewPitchMin` / `ViewPitchMax` live on your own local camera manager. The
settings and preset objects are data assets loaded from the game's paks — config,
not gameplay state. Nothing is written to the save, nothing is sent to the host.
Every change is in memory only and is gone when you quit.

So: host and guest can each run this or not run it, in any combination, with no
coordination. It works in a 20-player lobby exactly as it works alone.

## Diagnostics

Press **Alt+F6** in game. It writes a report to
`Helden\Binaries\Win64\LetMeLook_state.txt` and changes nothing.

The report lists every value the mod touched, what it was, what it is now, and
whether the write actually took — `written`, `already`, `REFUSED` or `missing`.
If the mod does not seem to be working, that file plus `LetMeLook.log` (same
folder) is what to attach to a bug report.

Alt is used rather than Ctrl or Shift because both of those are held during
normal play.

## Install

Install through r2modman or the Thunderstore Mod Manager and it will pull in
`unreal_shimloader` and the Grain Rot UE4SS overlay for you.

## Credits

Camera internals mapped from the game's own header and object dumps. Thanks to
the RE-UE4SS project, and to the Grain Rot UE4SS overlay for the UE 5.7.4
signature work that makes any Lua mod possible on this build.
