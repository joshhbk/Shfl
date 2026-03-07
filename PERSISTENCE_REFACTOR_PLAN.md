# Persistence Refactor Plan

## Context

Shfl already has a strong core for queue and playback behavior:

- `QueueState` is the main domain state and invariant boundary.
- `QueueEngine` is effectively a reducer/state machine.
- `PlaybackCoordinator` serializes application commands.
- `MusicService` and the repositories act as ports/adapters.

The weaker part of the system is the orchestration around persistence, restore, and app lifecycle. Persistence policy is currently spread across view models, lifecycle callbacks, playback observation, and transport-specific code. That makes some behavior hard to reason about and has already allowed drift between the persisted schema and the actual restore semantics.

## Goals

1. Make persisted session behavior explicit and testable.
2. Reduce temporal coupling between UI events and persistence writes.
3. Shrink objects with too many responsibilities, especially `ShufflePlayer` and `AppPlaybackSessionCoordinator`.
4. Move toward a clearer architecture: reducer/state machine core, explicit use cases, and ports/adapters at the edges.

## Architectural Direction

The target shape is:

- Keep the current reducer/domain model core.
- Introduce explicit session persistence and restore use cases.
- Centralize persistence trigger policy.
- Move transport sync, diagnostics, and lifecycle glue out of `ShufflePlayer`.

This is an incremental refactor. Each stage should leave the app working and improve clarity on its own.

## Stage 1: Fix Playback Restore Semantics

### Why this stage is first

There is already a concrete mismatch in the current implementation:

- `PersistedPlaybackState.wasPlaying` is saved.
- `PersistedPlaybackSnapshot.wasPlaying` is loaded.
- The restore path does not use `wasPlaying`.
- `SessionRestorer` always restores with `.forcePaused`.
- `PlaybackStateObserver` only consumes `pendingRestoreSeek` after a `.playing` transition.

This likely explains the current bug where the correct song and artwork restore, but the elapsed time is lost or visually resets.

### Objective

Make playback restoration semantics explicit and internally consistent:

- Either honor the previous play/pause state during restore, or
- remove `wasPlaying` from the persistence model and guarantee that elapsed time restores correctly while paused.

We should not keep persisting a field whose meaning is undefined in the actual restore flow.

### Scope

- Trace and fix the restore path for:
  - current song
  - album art / metadata
  - elapsed playback time
  - paused vs playing semantics
- Align persistence schema, restore behavior, and tests.

### Likely touch points

- `Shfl/ViewModels/AppPlaybackSessionCoordinator.swift`
- `Shfl/Domain/PlaybackCoordinator.swift`
- `Shfl/Domain/ShufflePlayer.swift`
- `Shfl/Domain/SessionRestorer.swift`
- `Shfl/Domain/PlaybackStateObserver.swift`
- `Shfl/Data/Models/PersistedPlaybackState.swift`
- `Shfl/Data/PlaybackStateRepository.swift`
- playback/session tests

### Deliverables

1. A clear product rule for session restore:
   - restore paused at saved position, or
   - restore prior playing/paused state.
2. A code change that makes the implementation match that rule.
3. Tests covering:
   - paused restore preserves elapsed time
   - playing restore preserves elapsed time
   - stale or invalid snapshots fall back cleanly
4. Removal of any dead persistence fields or restore branches.

### Acceptance criteria

- A persisted playback snapshot restores the same song and the expected elapsed time.
- The behavior is deterministic and backed by tests.
- The persisted schema does not contain fields that are ignored by restore.

## Stage 2: Introduce an Explicit Session Snapshot Boundary

### Objective

Create a single application-level snapshot concept for cross-launch state instead of treating songs and playback as loosely related records.

### Scope

- Introduce an `AppSessionSnapshot` model in the application/domain boundary.
- Have a single service build and restore that snapshot.
- Keep SwiftData repositories as storage adapters behind that service.

### Deliverables

1. `SessionSnapshotService` or similar use-case/service object.
2. One entry point for save/load/clear session data.
3. Fewer direct repository calls from UI-facing types.

### Acceptance criteria

- `AppPlaybackSessionCoordinator` no longer coordinates low-level repository details directly.
- Session persistence reads and writes are routed through one explicit API.

## Stage 3: Centralize Persistence Trigger Policy

### Objective

Stop scattering persistence writes across UI dismissals, lifecycle callbacks, and playback observation in ad hoc ways.

### Scope

- Define which domain/application events should trigger persistence.
- Move that policy into one place.
- Remove direct `persistSongs()` calls from UI closure flows where possible.

### Deliverables

1. A `PersistenceTriggerPolicy` or equivalent application service.
2. A smaller public API on `AppViewModel`.
3. Consistent handling of:
   - app backgrounding
   - queue mutations
   - playback transitions
   - clearing state

### Acceptance criteria

- Persistence behavior can be understood from one policy object rather than by searching the codebase for save calls.
- Clearing queue/library also clears any invalid persisted playback session.

## Stage 4: Break Up `ShufflePlayer`

### Objective

Reduce the number of responsibilities currently concentrated in `ShufflePlayer`.

### Proposed splits

- `QueueStore`
  - owns reducer state
  - applies reductions
  - exposes observable queue/playback state
- `TransportSyncService`
  - executes `TransportCommand`s
  - handles stale revision gating
  - owns retry/recovery behavior
- `BoundarySwapCoordinator`
  - owns deferred queue rebuild at natural playback boundaries
- `QueueDiagnosticsService`
  - owns invariant checks, operation journal, and export

### Acceptance criteria

- `ShufflePlayer` is no longer the owner of unrelated concerns like diagnostics and deferred transport policy.
- Each extracted type has a focused reason to change.

## Stage 5: Separate Lifecycle Bootstrap from Runtime Session Management

### Objective

Untangle startup, authorization, session restore, scrobbling, and UI loading concerns in `AppPlaybackSessionCoordinator`.

### Proposed splits

- `AppSessionBootstrapper`
  - authorization check
  - load persisted session
  - seed songs
  - restore or prepare queue
- `ScrobbleLifecycleCoordinator`
  - playback-driven scrobble behavior
- keep UI-facing loading/auth state in a thinner coordinator or view model adapter

### Acceptance criteria

- Startup logic and runtime persistence logic are not mixed into one large coordinator.
- App lifecycle behavior is easier to test without constructing the full UI layer.

## Stage 6: Harden the Test Matrix

### Objective

Increase confidence as the architecture becomes more explicit.

### Test areas to strengthen

- restore semantics and elapsed time behavior
- clearing state vs stale snapshot deletion
- background persistence policy
- Last.fm disconnect/account-bound queue behavior
- end-to-end startup restore flow

### Acceptance criteria

- Persistence behavior is primarily validated through focused unit/application-service tests rather than only integration coverage.

## Recommended Execution Order

1. Complete Stage 1 and lock down restore semantics.
2. Introduce the explicit session snapshot boundary in Stage 2.
3. Centralize persistence trigger policy in Stage 3.
4. Split `ShufflePlayer` in Stage 4.
5. Split bootstrap/runtime coordinator concerns in Stage 5.
6. Expand and rebalance tests in Stage 6 as the refactor lands.

## Notes for Stage 1

Current working hypothesis:

- `wasPlaying` is the clearest sign of architectural drift.
- The elapsed-time regression may be caused by restore seeking being deferred until playback becomes active, while the restored session is intentionally forced into a paused state.
- The first implementation step should be to confirm the intended product behavior and then make the restore path match it exactly.

The outcome of Stage 1 should decide whether `wasPlaying` remains part of the long-term session model.
