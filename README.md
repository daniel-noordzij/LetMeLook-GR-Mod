# LetMeLook

A Grain Rot mod that removes the vertical camera clamp, so you can look straight
up and straight down. That's it!

## What it does

Grain Rot limits how far you can tilt the camera, and it limits it even further
when you're crouched or sprinting. This mod simply changes that limit
to always be close to  the max. (-89.9 down, 89.9 up)

It stops 0.1 degrees short of straight vertical, which is the engine's own
default. That last tenth of a degree is where a camera clamp stops being a clamp
and starts being a gimbal problem, however you can't actually see the difference
so for all purposes it is straight up and straight down.

The ragdoll, cutscene, soul sequence & emote cameras are deliberately left alone
because those clamps are there on purpose, so all of those shots still get framed
the way the game intended. Your character's body also still twists only as far as
it normally does, only the camera goes further.

This is a client-side mod, only you need it and only you are impacted by it.

## Install

Install it through r2modman or the Thunderstore Mod Manager which will pull in
the 2 dependencies for you (unreal_shimloader and the Grain Rot UE4SS overlay).

## License

MIT, see [LICENSE](LICENSE).