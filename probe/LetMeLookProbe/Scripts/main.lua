--[[
    LetMeLookProbe -- read-only recon for the Free Look mod. NOT the shipped mod.

    ONE QUESTION: of the three things that could be clamping camera pitch, which
    one actually is, and what are the live numbers?

      1. APlayerCameraManager.ViewPitchMin / ViewPitchMax      (stock engine clamp)
      2. UHeldenCameraSettings.CameraPitchMin / CameraPitchMax (one global asset)
      3. UHeldenCameraPreset.bLimitPitch / LimitPitch          (per-situation)

    This mod WRITES NOTHING to the game. It only reads, and only when you press
    the key. Delete this folder once the question is answered.

    Every class and property name below came out of CXXHeaderDump/Helden.hpp and
    Engine.hpp on this exact build. Nothing here is guessed.

    Output (both in the Win64\ directory, which is the process working dir):
      LetMeLook_probe.txt   the readable dump, APPENDED once per keypress
      LetMeLook_probe.log   flushed crash trace, one line before every risky read

    The trace file exists because reading an FVector2D (LimitPitch) is the one
    documented way this can hard-crash to desktop, and pcall cannot catch an
    access violation -- it catches Lua errors, not access violations. If the game
    dies, the last line in the .log names the exact read that killed it.
]]

local MOD  = "LetMeLookProbe"
local OUT  = "LetMeLook_probe.txt"
local LOG  = "LetMeLook_probe.log"
-- Probe hotkeys are a solo F key or ALT+key -- never CONTROL or SHIFT. Both are
-- held during ordinary play (sprint, crouch, modifier-clicks), so a ctrl/shift
-- combo is ambiguous to press and easy to believe you got wrong.
local KEY  = Key.F6
local MODS = { ModifierKey.ALT }
local PUMP_MS = 100

-- ==========================================================================
-- Trace. Flushed after every line: UE4SS's own log is buffered and loses the
-- last seconds before a crash, which is precisely the part we would need.
-- Append, not truncate, so a crash-then-relaunch does not destroy the evidence
-- of the crash it just took.
-- ==========================================================================

local trace = { file = nil }

function trace.write(text)
    if trace.file == nil then
        trace.file = io.open(LOG, "a") or false
    end
    if not trace.file then return end
    pcall(function()
        trace.file:write(string.format("%s %8.3f  %s\n", os.date("%H:%M:%S"), os.clock(), text))
        trace.file:flush()
    end)
end

local function log(text)
    print("[" .. MOD .. "] " .. text .. "\n")
    trace.write(text)
end

-- ==========================================================================
-- The null-wrapper primitives. A wrapper around null is TRUTHY: FindFirstOf,
-- FindAllOf and property reads all answer with a wrapper whether or not the
-- object is there, so `if not x`, `if x` and `x ~= nil` every one of them wave
-- nothing straight through, and the next line reads out of null.
--
-- "Can this object say its own name" is the only test that works: GetFullName()
-- answers Lua nil for a null wrapper, and fullName turns that into "".
-- ==========================================================================

local function fullName(object)
    local name = nil
    pcall(function() name = object:GetFullName() end)
    if type(name) ~= "string" then return "" end
    return name
end

--- True when `object` is a real, nameable UObject.
local function real(object)
    return object ~= nil and fullName(object) ~= ""
end

-- For a value that should be a number or a bool, the test is its TYPE. Here too,
-- `~= nil` is true for a wrapper around nothing.

local function fmtNum(value)
    if type(value) ~= "number" then return "<not a number: " .. type(value) .. ">" end
    return string.format("%.6f", value)
end

local function fmtBool(value)
    if type(value) ~= "boolean" then return "<not a bool: " .. type(value) .. ">" end
    return tostring(value)
end

--- Read one property off a persistent UObject. Never raises.
local function get(object, property)
    local value = nil
    pcall(function() value = object[property] end)
    return value
end

-- ==========================================================================
-- Report buffer
-- ==========================================================================

local report = {}

local function say(text)
    report[#report + 1] = text
end

local function field(indent, label, value)
    say(string.format("%s%-22s %s", indent, label, value))
end

--- Log a skip AND say what was skipped. A guard that can silently do nothing
--- makes "the read never ran" and "the read ran and found nothing" identical.
local function skip(label, why)
    say(string.format("  %-22s SKIPPED -- %s", label, why))
    trace.write("skip: " .. label .. " -- " .. why)
end

-- ==========================================================================
-- Reading an FVector2D in place.
--
-- The rule that costs a process: fields of persistent UObjects are safe to read,
-- but fields of a struct returned BY VALUE across the Lua/native boundary are
-- not. LimitPitch is an FVector2D, so it is read as a property off the preset
-- object itself, never through a getter that would hand back a copy.
--
-- Traced in three steps so a hard crash names which one died.
-- ==========================================================================

local function sayVector2D(indent, label, object, property, ownerName)
    trace.write("about to read struct " .. property .. " on " .. ownerName)
    local vector = get(object, property)
    if vector == nil then
        skip(label, "property read returned nil")
        return
    end
    trace.write("got " .. property .. " wrapper, about to read .X")
    local x = nil
    pcall(function() x = vector.X end)
    trace.write("read " .. property .. ".X = " .. tostring(x) .. ", about to read .Y")
    local y = nil
    pcall(function() y = vector.Y end)
    trace.write("read " .. property .. ".Y = " .. tostring(y))
    field(indent, label, "X=" .. fmtNum(x) .. "  Y=" .. fmtNum(y))
end

-- ==========================================================================
-- Blocks
-- ==========================================================================

--- One UHeldenCameraPreset: its identity, and both of its clamp pairs.
local function sayPreset(label, preset)
    if not real(preset) then
        skip(label, "null or unnameable (slot empty, or nothing set right now)")
        return
    end
    local name = fullName(preset)
    say(string.format("  %s", label))
    field("    ", "asset", name)
    trace.write("preset " .. label .. " = " .. name)
    field("    ", "bLimitPitch", fmtBool(get(preset, "bLimitPitch")))
    sayVector2D("    ", "LimitPitch", preset, "LimitPitch", name)
    field("    ", "bLimitYaw", fmtBool(get(preset, "bLimitYaw")))
    sayVector2D("    ", "LimitYaw", preset, "LimitYaw", name)
end

--- One UHeldenCameraSettings asset, plus the seven preset slots it names.
local function saySettings(label, settings, withSlots)
    if not real(settings) then
        skip(label, "null or unnameable")
        return
    end
    local name = fullName(settings)
    say(string.format("  %s", label))
    field("    ", "asset", name)
    trace.write("settings " .. label .. " = " .. name)
    field("    ", "CameraPitchMin", fmtNum(get(settings, "CameraPitchMin")))
    field("    ", "CameraPitchMax", fmtNum(get(settings, "CameraPitchMax")))

    if not withSlots then return end
    local slots = {
        "CameraPreset_Default", "CameraPreset_Sprint", "CameraPreset_Crouch",
        "CameraPreset_Prone", "CameraPreset_Cinematic", "CameraPreset_Ragdoll",
        "CameraPreset_Soul",
    }
    say("")
    say("  -- the preset slots named on that settings asset --")
    for _, slot in ipairs(slots) do
        sayPreset(slot, get(settings, slot))
    end
end

-- ==========================================================================
-- Resolution.
--
-- Walking the global object array is the largest crash exposure there is -- it
-- races GC and has been documented returning text fragments as object pointers.
-- So it happens ONCE per keypress (a human pressing a key cannot outrun the
-- one-scan-per-second throttle) and everything else is a property walk down
-- from what that scan returned.
-- ==========================================================================

--- The LOCAL player controller. On a listen-server host every player's
--- controller is in the object array, so the first one found is not necessarily
--- ours; IsLocalController is what separates them.
local function localController()
    local found, seen = nil, 0
    pcall(function()
        for _, pc in ipairs(FindAllOf("HeldenPlayerController") or {}) do
            if real(pc) then
                seen = seen + 1
                local isLocal = nil
                pcall(function() isLocal = pc:IsLocalController() end)
                if isLocal == true then found = pc break end
            end
        end
    end)
    return found, seen
end

local function findFirst(class)
    local found = nil
    pcall(function() found = FindFirstOf(class) end)
    if not real(found) then return nil end
    return found
end

-- ==========================================================================
-- The dump. Runs on the game thread, inside the single pump callback.
-- ==========================================================================

local presses = 0

local function dump()
    presses = presses + 1
    report = {}
    trace.write("======== press " .. presses .. " ========")

    say("")
    say(string.format("======== press %d   %s ========", presses, os.date("%Y-%m-%d %H:%M:%S")))
    say("(stance is whatever you were doing when you pressed the key)")
    say("")

    -- 1. The local player controller, and the camera manager it owns. -------
    local controller, seen = localController()
    if controller == nil then
        skip("HeldenPlayerController", seen == 0
            and "none in the object array -- not in a level yet?"
            or ("none of the " .. seen .. " found says it is the local one"))
    else
        field("  ", "local controller", fullName(controller))
    end

    -- Prefer the manager hanging off OUR controller. Fall back to a class scan
    -- only if that failed, and say which one was used -- on a host they can differ.
    local manager, via = nil, nil
    if controller ~= nil then
        local owned = get(controller, "PlayerCameraManager")
        if real(owned) then manager, via = owned, "local controller" end
    end
    if manager == nil then
        local scanned = findFirst("HeldenCameraManager")
        if scanned ~= nil then manager, via = scanned, "FindFirstOf(HeldenCameraManager)" end
    end

    say("")
    say("[1] APlayerCameraManager -- the stock engine clamp")
    if manager == nil then
        skip("camera manager", "not resolvable from the controller or by class scan")
    else
        trace.write("camera manager = " .. fullName(manager))
        field("  ", "object", fullName(manager))
        field("  ", "resolved via", via)
        field("  ", "ViewPitchMin", fmtNum(get(manager, "ViewPitchMin")))
        field("  ", "ViewPitchMax", fmtNum(get(manager, "ViewPitchMax")))
        field("  ", "ViewYawMin", fmtNum(get(manager, "ViewYawMin")))
        field("  ", "ViewYawMax", fmtNum(get(manager, "ViewYawMax")))
        field("  ", "ViewRollMin", fmtNum(get(manager, "ViewRollMin")))
        field("  ", "ViewRollMax", fmtNum(get(manager, "ViewRollMax")))
    end

    -- 2/3. The spring arm, reached down from the manager. -------------------
    local arm = nil
    if manager ~= nil then
        local candidate = get(manager, "CameraArm")
        if real(candidate) then arm = candidate end
    end

    say("")
    say("[2/3] UHeldenCharacterSpringArm -- settings and presets hang off this")
    if arm == nil then
        skip("CameraArm", manager == nil
            and "no camera manager to read it from"
            or "AHeldenCameraManager.CameraArm is null right now")
    else
        trace.write("camera arm = " .. fullName(arm))
        field("  ", "object", fullName(arm))
        say("")
        saySettings("[2] arm.CameraSettings", get(arm, "CameraSettings"), true)
        say("")
        say("  -- the two presets the arm is holding right now --")
        sayPreset("[3] arm.CameraPreset", get(arm, "CameraPreset"))
        sayPreset("[3] arm.PrevCampreset", get(arm, "PrevCampreset"))
    end

    -- Cross-checks. Cheap, and they answer "is the settings asset shared". ---
    say("")
    say("[x] cross-checks")

    local character = nil
    if controller ~= nil then
        local pawn = get(controller, "Pawn")
        if real(pawn) then character = pawn end
    end
    if character == nil then
        skip("controller.Pawn", "null -- cannot call GetCameraArm()")
    else
        field("  ", "local pawn", fullName(character))
        -- GetCameraArm returns a POINTER, not a struct by value, so it is safe.
        trace.write("about to call GetCameraArm() on " .. fullName(character))
        local armFromPawn = nil
        pcall(function() armFromPawn = character:GetCameraArm() end)
        trace.write("GetCameraArm() returned")
        if not real(armFromPawn) then
            skip("pawn:GetCameraArm()", "returned null or unnameable")
        else
            field("  ", "pawn GetCameraArm()", fullName(armFromPawn))
            field("  ", "same arm as manager?",
                tostring(arm ~= nil and fullName(armFromPawn) == fullName(arm)))
        end
    end

    local singleton = findFirst("HeldenDataSingleton")
    if singleton == nil then
        skip("UHeldenDataSingleton", "not in the object array")
    else
        field("  ", "data singleton", fullName(singleton))
        say("")
        saySettings("singleton.CameraSettings", get(singleton, "CameraSettings"), false)
    end

    say("")
    say(string.format("======== end of press %d ========", presses))

    -- Append, so standing / crouched / sprinting all land in ONE file.
    local handle = io.open(OUT, "a")
    if not handle then
        log("could not open " .. OUT .. " for append -- dumping to the UE4SS log instead")
        for _, line in ipairs(report) do print(line .. "\n") end
        return
    end
    handle:write(table.concat(report, "\n") .. "\n")
    handle:close()

    log("press " .. presses .. " written to " .. OUT)
    trace.write("press " .. presses .. " complete")
end

-- ==========================================================================
-- The pump.
--
-- NEVER SCHEDULE THROUGH UE4SS. RE-UE4SS #1180 drains the engine-tick action
-- vector with erase_if under a recursive mutex, so an ExecuteInGameThread or
-- ExecuteWithDelay issued from inside a drained callback appends mid-iteration
-- and corrupts the stored Lua registry refs -- "Abort signal received", or
-- "Ref was not function", at random, worst on a slow or unfocused machine.
--
-- So: exactly one ExecuteInGameThread in the whole file, made from a LoopAsync
-- thread, with one item in flight at a time so a game that falls behind DROPS
-- passes rather than stacking them.
--
-- Keybind callbacks do not run on the game thread. This one therefore does no
-- work at all -- it sets a flag, and the pump below does the reading.
-- ==========================================================================

local pending  = false
local inFlight = false

pcall(function()
    LoopAsync(PUMP_MS, function()
        if inFlight then return false end
        inFlight = true
        ExecuteInGameThread(function()
            inFlight = false
            if not pending then return end
            pending = false
            local ok, err = pcall(dump)
            if not ok then log("dump error: " .. tostring(err)) end
        end)
        return false
    end)
end)

local bound = pcall(function()
    RegisterKeyBind(KEY, MODS, function() pending = true end)
end)

trace.write("---- " .. MOD .. " loaded ----")
log("loaded. Press ALT+F6 in game to dump the camera clamp state.")
log(bound and "keybind registered: ALT+F6"
           or "KEYBIND REGISTRATION FAILED -- the probe cannot be triggered")
log("this probe writes nothing to the game. Output appends to " .. OUT)
