# LetMeLook-GR-Mod

A 'Grain Rot' mod to allow you to look completely up and down, removing the default clamp.

The user-facing description lives in [package/README.md](package/README.md) — that
is what Thunderstore renders. This file is for working on the mod.

## Layout

```
package/            everything that ships, and nothing else
  manifest.json     name, version, dependencies
  README.md         the Thunderstore page
  CHANGELOG.md
  icon.png          256x256, the mod icon Thunderstore shows
  mod/
    enabled.txt     empty; UE4SS enables a mod folder by its presence
    Scripts/main.lua

probe/              dev-only recon. NEVER ships.
  LetMeLookProbe/   read-only dump of every camera clamp, on ALT+F6
  results/          the actual measurements the numbers below came from

tools/
  luasyntax.py      Lua syntax gate; exit 0 only if every file parses
  deploy.sh         syntax-gated copy into an r2modman profile, then md5 both
  package.sh        builds dist/LetMeLook-<version>.zip
```

## Working on it

Deploy to the test profile and verify it landed:

```bash
bash tools/deploy.sh package/mod LetMeLookTest LetMeLook
```

Build the upload zip:

```bash
bash tools/package.sh
```

Both gate on `tools/luasyntax.py`'s **own exit code** — never on a pipeline
through `grep`, which tests grep's exit code and has shipped a broken file
before. `package.sh` additionally refuses to build if `Scripts/` holds anything
besides `main.lua`, so a probe cannot ship by accident.

There is no Lua interpreter on the dev machine; the gate uses the `luaparser`
Python package in place of `luac -p`.

## What was measured

Live on UE 5.7.4 (`++UE5+Release-5.7-CL-51494982`), 2026-08-29. Three pitch
clamps are active at once:

| Source | Stock |
|---|---|
| `APlayerCameraManager.ViewPitchMin` / `ViewPitchMax` | -70 / +80 |
| `UHeldenCameraSettings.CameraPitchMin` / `CameraPitchMax` | -60 / +90 |
| `UHeldenCameraPreset.LimitPitch` (with `bLimitPitch` true) | per stance |

The preset is swapped by stance — `Default_CameraPreset` standing (-80/+90),
`Crouching_CameraPreset` crouched (-60/+90), `Sprinting_CameraPreset` sprinting
(-60/+90). Which of the three is the *binding* clamp was never established and
did not need to be: widening all three clears it regardless.

Also confirmed: `manager.CameraArm` and `pawn:GetCameraArm()` are the same
object; `arm.CameraSettings` and `UHeldenDataSingleton.CameraSettings` are the
same asset instance (`/Game/Core/CameraSetings` — the typo is the real asset
name); `PrevCampreset` is null during normal play.

## Constraints this code is built around

- **A wrapper around null is truthy.** `fullName(x) == ""` is the only test that
  separates a real UObject from a wrapper around nothing.
- **One `ExecuteInGameThread`, ever**, from a `LoopAsync` pump with an in-flight
  guard. RE-UE4SS #1180 corrupts Lua registry refs when anything appends to the
  engine-tick action vector from inside a drained callback. Keybind callbacks do
  not run on the game thread either, so the keybind only sets a flag.
- **The object array is walked at most once per second**, and nothing is cached
  between passes — a rescan risks a race, but a held pointer across a level
  change is a certainty.
- **Every write is read back**, because a struct write that lands in a by-value
  copy silently does nothing. `bLimitPitch = false` (a plain bool, and the game's
  own idiom — `Cinematic_CameraPreset` ships that way) is the load-bearing write;
  widening the `LimitPitch` vector is belt and braces.

## Publishing

Upload `dist/LetMeLook-<version>.zip` to the **grain-rot** community on
Thunderstore. Dependencies are declared in `package/manifest.json`:
`Thunderstore-unreal_shimloader-1.1.7` and `Thunderstore-GrainRot_UE4SS-1.0.1`.
