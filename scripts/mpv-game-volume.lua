-- Volume keys for scripts/play.sh.
-- The capture audio does not pass through mpv: PipeWire loops it from the card
-- to the speakers, so mpv's own volume has nothing to act on. These bindings
-- adjust the loopback's PipeWire stream instead and show the level on screen.
--   9 / WHEEL_DOWN  quieter      0 * WHEEL_UP  louder      m  mute
local utils = require "mp.utils"

local NODE = "output.elgato-capture-audio"
local STEP, MAX = 5, 150

local function run(args)
    local r = mp.command_native({
        name = "subprocess", args = args,
        capture_stdout = true, playback_only = false,
    })
    return r.status == 0 and r.stdout or nil
end

local function stream()
    local out = run({"pactl", "-f", "json", "list", "sink-inputs"})
    local list = out and utils.parse_json(out) or {}
    for _, s in ipairs(list) do
        if s.properties and s.properties["node.name"] == NODE then
            return s
        end
    end
end

local function percent(s)
    for _, ch in pairs(s.volume or {}) do
        return tonumber((ch.value_percent or "100%"):match("%d+"))
    end
    return 100
end

local function change(delta)
    local s = stream()
    if not s then
        mp.osd_message("Game audio is not running")
        return
    end
    local v = math.max(0, math.min(MAX, percent(s) + delta))
    run({"pactl", "set-sink-input-volume", tostring(s.index), v .. "%"})
    mp.osd_message("Game volume: " .. v .. "%")
end

local function toggle_mute()
    local s = stream()
    if not s then
        mp.osd_message("Game audio is not running")
        return
    end
    run({"pactl", "set-sink-input-mute", tostring(s.index), "toggle"})
    mp.osd_message(s.mute and "Game audio: on" or "Game audio: muted")
end

local function bind(keys, name, fn, flags)
    for i, key in ipairs(keys) do
        mp.add_forced_key_binding(key, name .. "-" .. i, fn, flags)
    end
end

bind({"0", "*", "WHEEL_UP"}, "game-volume-up", function() change(STEP) end, {repeatable = true})
bind({"9", "/", "WHEEL_DOWN"}, "game-volume-down", function() change(-STEP) end, {repeatable = true})
bind({"m"}, "game-volume-mute", toggle_mute)
