-- Re-sync key for scripts/play.sh.
-- A capture restart can come up in the wrong phase: every frame wrapped
-- vertically (the top of the picture shown below a seam), and it stays that
-- way until the capture restarts. Closing and reopening the device makes the
-- driver stop and restart its DMA, which normally lands in phase. That only
-- happens when mpv is the last program capturing from the card; with OBS or
-- ffmpeg also open the DMA keeps running and this changes nothing.
--
-- mpv cannot reopen the device in-process: `loadfile` on av://v4l2 frees the
-- capture buffers while decoded packets still reference them, and mpv crashes
-- in av_packet_unref (seen with mpv on FFmpeg 8, 2026-09-27). So this quits
-- with an exit code that tells play.sh to start mpv again.
--   r  re-sync
local EXIT_RESYNC, EXIT_RESYNC_FS = 42, 43   -- must match play.sh

local function resync()
    mp.osd_message("Re-syncing capture...")
    local code = mp.get_property_bool("fullscreen") and EXIT_RESYNC_FS or EXIT_RESYNC
    mp.commandv("quit", tostring(code))
end

mp.add_forced_key_binding("r", "capture-resync", resync)
