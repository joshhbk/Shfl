# Shfl

Shfl composes deterministic shuffled listening sessions from a user's Apple Music library, loads each session atomically, and then lets the system playback transport advance it.

## Language

**Listening session**:
The songs, queue order, played history, current song, and playback position that together describe one continuous listening context.
_Avoid_: Player state, app state

**Session load**:
The single atomic transport operation that installs an immutable listening-session order, selects its current song and position, and applies play-or-pause intent.
_Avoid_: Queue transition, queue replacement, queue sync call

**Fresh shuffle**:
A newly generated queue order that intentionally discards the previous listening session's ordering and position.
_Avoid_: Resume, restore

**Session restore**:
Reinstatement of a saved listening session, including its exact queue order, current song, played history, and playback position.
_Avoid_: Fresh shuffle, reload

**Session draft**:
The editable song pool and shuffle settings that will be used to compose the next listening session. Changes to the draft do not rewrite a listening session that is already playing.
_Avoid_: Pending queue, deferred transport state

**Session composer**:
The pure domain module that turns a session draft plus a recorded random seed into one complete, reproducible listening-session order.
_Avoid_: Queue engine, shuffle manager

**Transport adapter**:
The module that hides MusicKit-specific queue loading, identifier mapping, playback timing, and event observation behind Shfl's playback interface.
_Avoid_: Music service, queue sync

**Playback scenario**:
A user-visible sequence of actions and outcomes that can run unchanged against the deterministic transport and the real MusicKit transport.
_Avoid_: Unit test case, mock expectation
