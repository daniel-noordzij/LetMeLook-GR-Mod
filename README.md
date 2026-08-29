# LetMeLook

A Grain Rot mod that removes the vertical camera clamp, so you can look straight
up and straight down.

That's the whole mod. It is client-side, it changes nothing else, and it needs no
coordination in co-op.

## What it does

Grain Rot limits how far you can tilt the camera, and limits it further still
when you are crouched or sprinting. This widens that range to the engine maximum
in every stance.

It stops a tenth of a degree short of dead vertical, which is the engine's own
default — that last tenth is where a camera clamp stops being a clamp and starts
being a gimbal problem. In practice it is straight up and straight down.

Ragdoll, cutscene, soul-sequence and emote cameras are deliberately left alone,
so those shots still frame the way the game intended. Your character's body also
still twists only as far as it normally does; only the camera goes further.

## Install

Install through r2modman or the Thunderstore Mod Manager and it will pull in the
dependencies for you — `unreal_shimloader` and the Grain Rot UE4SS overlay.

## Co-op

Nothing is replicated and nothing is saved. Every change lives in memory on your
own machine and is gone when you quit, so the host and each guest can run this or
not run it in any combination, with no coordination.

## If something looks wrong

Press **Alt+F6** in game. It writes a report to
`Helden\Binaries\Win64\LetMeLook_state.txt` and changes nothing.

That file, plus `LetMeLook.log` in the same folder, is what to attach to a bug
report — between them they show every value the mod touched and whether the
change actually took.

## Building

```bash
bash tools/package.sh
```

That produces `dist/LetMeLook-<version>.zip`, ready to upload to the **grain-rot**
community on Thunderstore.

To try a change in game, deploy it into an r2modman profile:

```bash
bash tools/deploy.sh package/mod <profile-name> LetMeLook
```

Both refuse to run if the mod does not parse. Everything that ships lives in
`package/`; [package/README.md](package/README.md) is the text Thunderstore
displays.

## Licence

MIT — see [LICENSE](LICENSE).
