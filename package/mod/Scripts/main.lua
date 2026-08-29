--[[
    LetMeLook -- removes the vertical camera clamp in Grain Rot, so you can look
    straight up and straight down.

    WHAT IS ACTUALLY CLAMPING THE CAMERA
    ------------------------------------
    Measured live on 2026-08-29 (UE 5.7.4, ++UE5+Release-5.7-CL-51494982). Three
    separate clamps are active at once, and each is narrower than 90 degrees
    somewhere, so all three have to be widened:

      1. APlayerCameraManager.ViewPitchMin / ViewPitchMax   =  -70 / +80
         (the engine default is +/-89.9, so the game deliberately narrowed it)
      2. UHeldenCameraSettings.CameraPitchMin / CameraPitchMax = -60 / +90
         one global asset, /Game/Core/CameraSetings.CameraSetings -- the typo is
         the real asset name
      3. UHeldenCameraPreset.bLimitPitch / LimitPitch, swapped per stance:
              standing  Default_CameraPreset    true  (-80, +90)
              crouched  Crouching_CameraPreset  true  (-60, +90)
              sprinting Sprinting_CameraPreset  true  (-60, +90)

    Which of the three is the binding one at any moment was never established --
    it did not need to be. Widening all three clears the clamp regardless of
    which one would have won.

    WHAT IS DELIBERATELY LEFT ALONE
    -------------------------------
    Only the four movement preset slots are unclamped: Default, Sprint, Crouch
    and Prone. (Prone points at the same asset as Crouch, so it is one object.)

      * Ragdoll_CameraPreset is (-85, -5) -- it forces the view DOWNWARD while
        you are ragdolled, on purpose. Unclamping it would break that shot.
      * Cinematic_CameraPreset already ships bLimitPitch = false.
      * Soul_CameraPreset (-85, +85) frames the soul sequences.
      * Default_Clamped_* presets exist for emotes; those clamps are intended.

    Spine aim (FHeldenSpineAimData, FHeldenAnimAdjustments.SpineAimPitchClamp) is
    NOT touched. Those are animation clamps -- how far the character model twists
    to follow aim -- and they are REPLICATED state that other players see. The
    camera clamp is purely local. So at full look-down your own body does not
    crane to follow, which is what most third-person games do anyway.

    CO-OP
    -----
    Nothing here is replicated or saved. ViewPitchMin/Max live on the local
    player's own camera manager. The settings and preset objects are UDataAssets
    loaded from the pak -- config, not gameplay state: not in UHeldenSaveGame, not
    in GameState.Facts, never sent to the host. Every write is process-local and
    is gone when you quit. Host and guest can run this independently, or not at
    all, with no coordination.

    WRITE IDIOM
    -----------
    bLimitPitch = false is the game's OWN idiom for "no pitch clamp" --
    Cinematic_CameraPreset ships that way. That bool is the load-bearing write.
    Widening the LimitPitch vector on top of it is belt and braces. Every write
    is read back, because a struct write that lands in a by-value copy would
    silently do nothing -- measured 2026-08-29, this one does NOT: the readback
    reports (-89.9, 89.9), so the in-place accessor writes through. ALT+F6 shows
    you that readback.

    WHY IT POLLS RATHER THAN APPLYING ONCE
    --------------------------------------
    Because the game demonstrably puts values back. Measured over a 14-minute
    session: the preset and settings writes stuck, but ViewPitchMin/ViewPitchMax
    were reset twice and had to be rewritten. So a one-shot apply would work
    until the first reset and then quietly stop working, which is the worst
    failure mode available. The state report counts those resets.

    The target is +/-89.9 rather than +/-90 -- the engine's own default. The last
    tenth of a degree is where a pitch clamp stops being a clamp and starts being
    a gimbal problem, and no one can see 0.1 degrees.
]]

local MOD = "LetMeLook"

-- The engine's own default is +/-89.9. Going to exactly +/-90 risks the
-- degenerate straight-up/straight-down case, so match what UE ships.
local PITCH_MIN, PITCH_MAX = -89.9, 89.9

local PUMP_MS     = 100   -- the single-append pump
local APPLY_EVERY = 10    -- every 10th tick -> one object-array scan per second

local KEY   = Key.F6
local MODS  = { ModifierKey.ALT }   -- never CONTROL or SHIFT: both are held during play

local LOG_FILE   = "LetMeLook.log"
local STATE_FILE = "LetMeLook_state.txt"

-- The preset slots on the settings asset that we unclamp. Everything not named
-- here is left exactly as the game shipped it.
local MOVEMENT_SLOTS = {
    "CameraPreset_Default",
    "CameraPreset_Sprint",
    "CameraPreset_Crouch",
    "CameraPreset_Prone",
}

-- ==========================================================================
-- Event log. Flushed, because UE4SS's own log is buffered and loses the last
-- seconds before a crash. Events only -- applications, refusals, world changes.
-- A line per poll would be a megabyte an hour and tell you nothing.
-- ==========================================================================

local diag = { file = nil }

function diag.write(text)
    if diag.file == nil then
        diag.file = io.open(LOG_FILE, "a") or false
    end
    if not diag.file then return end
    pcall(function()
        diag.file:write(string.format("%s %8.3f  %s\n", os.date("%H:%M:%S"), os.clock(), text))
        diag.file:flush()
    end)
end

local function log(text)
    print("[" .. MOD .. "] " .. text .. "\n")
    diag.write(text)
end

--- Say a thing once per distinct reason. A guard that can silently do nothing
--- has to say so, or "the fix never ran" and "the fix ran and did nothing" look
--- identical -- but saying it every second is its own kind of silence.
local said = {}
local function logOnce(key, text)
    if said[key] then return end
    said[key] = true
    log(text)
end

-- ==========================================================================
-- Null-wrapper primitives.
--
-- A wrapper around null is TRUTHY. FindFirstOf, FindAllOf and property reads
-- all answer with a wrapper whether or not the object exists, so `if x`,
-- `if not x` and `x ~= nil` every one of them wave nothing straight through and
-- the next line writes into null. "Can this object say its own name" is the
-- only test that works: GetFullName() answers Lua nil for a null wrapper.
-- ==========================================================================

local function fullName(object)
    local name = nil
    pcall(function() name = object:GetFullName() end)
    if type(name) ~= "string" then return "" end
    return name
end

local function real(object)
    return object ~= nil and fullName(object) ~= ""
end

local function get(object, property)
    local value = nil
    pcall(function() value = object[property] end)
    return value
end

-- For values that should be numbers or bools the test is the TYPE. `~= nil` is
-- true for a wrapper around nothing here too.

local function isNum(value) return type(value) == "number" end
local function near(a, b) return isNum(a) and math.abs(a - b) < 0.01 end

-- ==========================================================================
-- Writes, every one of them read back.
--
-- Returns one of:
--   "already"  the value was already what we want; nothing was written
--   "written"  written, and the readback agrees
--   "REFUSED"  written, and the readback does NOT agree -- the write did nothing
--   "missing"  the property did not read as the expected type at all
-- ==========================================================================

local function setNumber(object, property, target)
    local before = get(object, property)
    if not isNum(before) then return "missing", before, before end
    if near(before, target) then return "already", before, before end
    pcall(function() object[property] = target end)
    local after = get(object, property)
    if near(after, target) then return "written", before, after end
    return "REFUSED", before, after
end

local function setBool(object, property, target)
    local before = get(object, property)
    if type(before) ~= "boolean" then return "missing", before, before end
    if before == target then return "already", before, before end
    pcall(function() object[property] = target end)
    local after = get(object, property)
    if after == target then return "written", before, after end
    return "REFUSED", before, after
end

--- An FVector2D, written IN PLACE on the persistent UObject.
---
--- Never through a by-value getter: a struct that crosses the Lua/native
--- boundary by value is the documented way to hard-crash this game, and pcall
--- cannot catch an access violation. The other failure mode is quieter -- if the
--- accessor hands back a copy, the write lands in the copy and vanishes. That is
--- exactly why this reads back, and why bLimitPitch (a plain bool, and the
--- game's own idiom) is the write we actually depend on.
local function setVector2D(object, property, x, y)
    local vector = get(object, property)
    if vector == nil then return "missing", "nil", "nil" end

    local beforeX, beforeY
    pcall(function() beforeX = vector.X end)
    pcall(function() beforeY = vector.Y end)
    local before = string.format("(%s, %s)", tostring(beforeX), tostring(beforeY))
    if near(beforeX, x) and near(beforeY, y) then return "already", before, before end

    pcall(function() vector.X = x end)
    pcall(function() vector.Y = y end)

    local afterX, afterY
    pcall(function() afterX = vector.X end)
    pcall(function() afterY = vector.Y end)
    local after = string.format("(%s, %s)", tostring(afterX), tostring(afterY))

    if near(afterX, x) and near(afterY, y) then return "written", before, after end
    return "REFUSED", before, after
end

-- ==========================================================================
-- What the mod believes. Read by the ALT+F6 dump, which changes nothing.
-- ==========================================================================

local state = {
    passes      = 0,     -- apply passes that found a world
    skipped     = 0,     -- apply passes that found nothing to work on
    reapplied   = 0,     -- times the game had put a value back
    lastSkip    = nil,
    targets     = {},    -- name -> {status, before, after}
    order       = {},    -- stable print order for `targets`
}

local function record(name, status, before, after)
    local previous = state.targets[name]
    if previous == nil then
        state.order[#state.order + 1] = name
        -- One line the first time each target is touched, and then silence. The
        -- apply pass runs every second forever, so anything logged
        -- unconditionally from inside it is not instrumentation -- it is 24,000
        -- lines an hour that say the same thing. Everything after this point is
        -- an EVENT: a value the game put back, a write that would not take.
        log(string.format("%s: %s (%s -> %s)", name, status, tostring(before), tostring(after)))
    elseif status == "written"
            and (previous.status == "written" or previous.status == "already") then
        -- We had this value correct, and this pass had to write it AGAIN -- so
        -- the game put it back in between. That is real information: it means
        -- the poll is load-bearing rather than just a backstop. (A pass that
        -- finds the value already correct reports "already", so reaching
        -- "written" a second time is the only way this can happen.)
        state.reapplied = state.reapplied + 1
        logOnce("reapply:" .. name, "the game put " .. name
            .. " back; the poll rewrote it (expected, and is why the poll exists)")
    end
    state.targets[name] = { status = status, before = tostring(before), after = tostring(after) }
    if status == "REFUSED" or status == "missing" then
        logOnce("bad:" .. name .. ":" .. status,
            name .. ": " .. status .. " (was " .. tostring(before) .. ", now " .. tostring(after) .. ")")
    end
end

-- ==========================================================================
-- Resolution.
--
-- Walking the global object array is the largest crash exposure there is -- it
-- races GC and is documented returning text fragments as object pointers. So it
-- happens at most ONCE PER SECOND, and nothing is cached between passes: a
-- rescan is exposure to a race, but a held pointer across a level change is a
-- certainty, and the cache-clear always loses that race.
-- ==========================================================================

local function localControllers()
    local found = {}
    pcall(function()
        for _, pc in ipairs(FindAllOf("HeldenPlayerController") or {}) do
            if real(pc) then
                local isLocal = nil
                pcall(function() isLocal = pc:IsLocalController() end)
                -- Splitscreen has more than one. Every local player gets the fix.
                if isLocal == true then found[#found + 1] = pc end
            end
        end
    end)
    return found
end

-- ==========================================================================
-- The fix
-- ==========================================================================

local function unclampPreset(label, preset)
    if not real(preset) then
        record(label, "missing", "null", "null")
        return
    end
    -- The load-bearing write. bLimitPitch = false is the game's own way of
    -- saying "no pitch clamp" -- Cinematic_CameraPreset ships exactly this.
    local status, before, after = setBool(preset, "bLimitPitch", false)
    record(label .. ".bLimitPitch", status, before, after)

    -- Belt and braces, in place. Measured on 2026-08-29: this write DOES take --
    -- the readback shows (-89.9, 89.9) rather than REFUSED -- so the in-place
    -- struct accessor writes through rather than handing back a copy.
    status, before, after = setVector2D(preset, "LimitPitch", PITCH_MIN, PITCH_MAX)
    record(label .. ".LimitPitch", status, before, after)
end

local function applyOnce()
    local controllers = localControllers()
    if #controllers == 0 then
        -- Rule: gate on a FACT, not a timer. "No local player controller" is
        -- the menu and the level transition both, and doing nothing is correct
        -- in both -- but say so, or a mod that never ran looks like one that did.
        state.skipped = state.skipped + 1
        state.lastSkip = "no local player controller (menu, or a level transition)"
        logOnce("noworld", "waiting: " .. state.lastSkip)
        return
    end
    said["noworld"] = nil   -- so the next transition says it again
    state.passes = state.passes + 1

    -- 1. The engine clamp, on every local player's own camera manager. --------
    local arms = {}
    for index, pc in ipairs(controllers) do
        local manager = get(pc, "PlayerCameraManager")
        if not real(manager) then
            record("player" .. index .. ".PlayerCameraManager", "missing", "null", "null")
        else
            local tag = (#controllers > 1) and ("player" .. index .. ".") or ""
            local status, before, after = setNumber(manager, "ViewPitchMin", PITCH_MIN)
            record(tag .. "ViewPitchMin", status, before, after)
            status, before, after = setNumber(manager, "ViewPitchMax", PITCH_MAX)
            record(tag .. "ViewPitchMax", status, before, after)

            local arm = get(manager, "CameraArm")
            if real(arm) then arms[#arms + 1] = arm end
        end
    end

    -- 2. The global settings asset, reached down from an arm we already hold. -
    -- One asset shared by every arm, so the first one that resolves is enough.
    local settings = nil
    for _, arm in ipairs(arms) do
        local candidate = get(arm, "CameraSettings")
        if real(candidate) then settings = candidate break end
    end

    if settings == nil then
        record("CameraSettings", "missing", "null", "null")
        return
    end

    local status, before, after = setNumber(settings, "CameraPitchMin", PITCH_MIN)
    record("CameraPitchMin", status, before, after)
    status, before, after = setNumber(settings, "CameraPitchMax", PITCH_MAX)
    record("CameraPitchMax", status, before, after)

    -- 3. The four movement presets named on that asset. ----------------------
    -- Prone and Crouch are the same object; writing it twice is harmless and
    -- the second pass reports "already", which is the honest answer.
    for _, slot in ipairs(MOVEMENT_SLOTS) do
        unclampPreset(slot, get(settings, slot))
    end

    -- 4. Whatever preset the arm is holding RIGHT NOW, if it is one of ours. --
    -- Covers the case where the arm has been handed a movement preset that the
    -- settings asset does not name. Presets we deliberately leave clamped
    -- (Ragdoll, Soul, Cinematic, the Default_Clamped_* emote presets) are
    -- skipped here by name, so their framing keeps working.
    for _, arm in ipairs(arms) do
        local live = get(arm, "CameraPreset")
        if real(live) then
            local name = fullName(live)
            local isMovement = name:find("Default_CameraPreset")
                or name:find("Sprinting_CameraPreset")
                or name:find("Crouching_CameraPreset")
            if isMovement then
                unclampPreset("live:" .. name:gsub("^.*[%.%/]", ""), live)
            end
        end
    end
end

-- ==========================================================================
-- The diagnostic keybind. Writes state to a file and changes NOTHING. It is the
-- only instrument a tester has.
-- ==========================================================================

local function dumpState()
    local out = {}
    local function say(text) out[#out + 1] = text end

    say("")
    say(string.format("======== %s state   %s ========", MOD, os.date("%Y-%m-%d %H:%M:%S")))
    say(string.format("target pitch range     %.1f .. %.1f", PITCH_MIN, PITCH_MAX))
    say(string.format("apply passes           %d", state.passes))
    say(string.format("passes with no world   %d", state.skipped))
    say(string.format("values the game reset  %d", state.reapplied))
    if state.lastSkip then say("last skip reason       " .. state.lastSkip) end
    say("")

    if #state.order == 0 then
        say("NOTHING HAS BEEN APPLIED YET.")
        say("If you are in a level and this is empty, the mod is not running its")
        say("apply pass -- check LetMeLook.log.")
    else
        say(string.format("%-34s %-8s %-22s %s", "target", "status", "was", "now"))
        for _, name in ipairs(state.order) do
            local entry = state.targets[name]
            say(string.format("%-34s %-8s %-22s %s", name, entry.status, entry.before, entry.after))
        end
        say("")
        say("status: written = we set it and the readback agrees")
        say("        already = it was already correct this pass")
        say("        REFUSED = the write did not take (tell the mod author)")
        say("        missing = that property was not there to write")
    end

    -- Live readback, straight off the objects, so the file shows the game's
    -- current truth and not only what the mod believes it did.
    say("")
    say("-- live readback --")
    local controllers = localControllers()
    if #controllers == 0 then
        say("  no local player controller right now (menu, or a level transition)")
    else
        for index, pc in ipairs(controllers) do
            local manager = get(pc, "PlayerCameraManager")
            if not real(manager) then
                say(string.format("  player %d: camera manager is null", index))
            else
                local min, max = get(manager, "ViewPitchMin"), get(manager, "ViewPitchMax")
                say(string.format("  player %d ViewPitch   %s .. %s", index, tostring(min), tostring(max)))
                local arm = get(manager, "CameraArm")
                if real(arm) then
                    local settings = get(arm, "CameraSettings")
                    if real(settings) then
                        say(string.format("  CameraPitch          %s .. %s",
                            tostring(get(settings, "CameraPitchMin")),
                            tostring(get(settings, "CameraPitchMax"))))
                    end
                    local live = get(arm, "CameraPreset")
                    if real(live) then
                        say("  live preset          " .. fullName(live))
                        say("  live bLimitPitch     " .. tostring(get(live, "bLimitPitch")))
                    end
                end
            end
        end
    end
    say(string.format("======== end of %s state ========", MOD))

    local handle = io.open(STATE_FILE, "a")
    if not handle then
        log("could not open " .. STATE_FILE .. "; writing state to the UE4SS log instead")
        for _, line in ipairs(out) do print(line .. "\n") end
        return
    end
    handle:write(table.concat(out, "\n") .. "\n")
    handle:close()
    log("state written to " .. STATE_FILE)
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
-- Keybind callbacks do not run on the game thread either. This one therefore
-- does no work at all -- it sets a flag, and the pump does the reading.
-- ==========================================================================

local pending  = false
local inFlight = false
local ticks    = 0

pcall(function()
    LoopAsync(PUMP_MS, function()
        if inFlight then return false end
        inFlight = true
        ExecuteInGameThread(function()
            inFlight = false

            if pending then
                pending = false
                local ok, err = pcall(dumpState)
                if not ok then log("state dump error: " .. tostring(err)) end
            end

            ticks = ticks + 1
            if ticks % APPLY_EVERY == 0 then
                local ok, err = pcall(applyOnce)
                if not ok then logOnce("apply:" .. tostring(err), "apply error: " .. tostring(err)) end
            end
        end)
        return false
    end)
end)

local bound = pcall(function()
    RegisterKeyBind(KEY, MODS, function() pending = true end)
end)

diag.write("---- " .. MOD .. " loaded ----")
log("loaded. Look straight up and straight down.")
log(bound and "ALT+F6 writes a diagnostic report to " .. STATE_FILE .. " and changes nothing."
           or "ALT+F6 could not be registered; the mod still works, but you have no report key.")
