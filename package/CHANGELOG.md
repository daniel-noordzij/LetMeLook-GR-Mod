# Changelog

## 1.0.0

First release.

- Removes the vertical camera clamp: look straight up and straight down.
- Widens all three clamps the game applies at once — the engine
  `ViewPitchMin`/`ViewPitchMax`, the global `CameraPitchMin`/`CameraPitchMax`,
  and `bLimitPitch` on the movement camera presets.
- Leaves the Ragdoll, Cinematic, Soul and emote presets alone, so those shots
  still frame the way the game intended.
- Leaves the spine aim animation clamps alone. They are replicated state that
  other players see; the camera clamp is purely local.
- Alt+F6 writes a diagnostic report to `LetMeLook_state.txt` and changes nothing.
