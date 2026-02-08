# Offline Mode Manual QA Checklist

## Setup
- Launch Shfl with at least 10 songs available in the pool/library.
- Open Xcode Network Link Conditioner (or disable Wi-Fi/cellular) so you can toggle offline/online quickly.
- Ensure Last.fm is connected in Settings if validating scrobble behavior.

## Queue + Playback
- Start playback, then go offline.
- Add one song from the picker while playback is active.
- Verify the app does not crash and shows a non-blocking failure message if queue sync cannot complete.
- Verify the newly added song remains in the local song pool (it should not silently disappear).
- Remove an upcoming song while playback is active and offline.
- Verify the app does not crash and shows a non-blocking failure message if transport update fails.
- Stop playback while still offline, add multiple songs, then press play.
- Verify queue rebuild succeeds locally and all newly added songs appear in the rebuilt queue.

## Recovery
- Return online.
- Press play again (or reshuffle) to force a queue sync.
- Verify queue order and song pool realign with no duplicate IDs and no silently dropped songs.

## Last.fm
- While offline, play a track long enough to scrobble.
- Verify the app remains stable and the track is queued for later scrobble (not lost).
- Return online and continue playback.
- Verify queued scrobbles flush successfully.

## Regression Spot Checks
- Add/remove songs while online during active playback and confirm no regressions.
- Change shuffle algorithm while online and confirm reshuffle still works.
