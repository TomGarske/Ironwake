# REQ_02: Game State Machine
**Blacksite Containment State Flow and Transitions**

## Overview

The game progresses through a single mission via a deterministic state machine. All players occupy the same state at all times; state transitions are server-authoritative. Each state has distinct responsibilities, timers, and win/loss conditions.

## State Diagram

```
┌─────────┐
│  LOBBY  │ (awaiting start / player join)
└────┬────┘
     │ (start_mission signal)
     v
┌──────────┐
│ BRIEFING │ (3–5 second intro, sync all players)
└────┬─────┘
     │ (briefing_complete signal)
     v
┌────────────────────────┐
│    PATROL (Loop)       │ (continuous patrol, random/scripted spawns)
├────────────┬───────────┤
│   ALERT    │ (escapee detected, chase timer begins)
│ (Breach    │
│  Attempt)  │
└────────────┴───────────┘
     │ outcome
     ├─────────────────────────┐
     │                         │
     v                         v
┌──────────────┐      ┌─────────────────┐
│   SUCCESS    │      │   BREACH_EVENT  │
│   (wave done)│      │ (perimeter hit)  │
└──────┬───────┘      └────────┬────────┘
       │                       │
       │ (next wave or         │ (repeat patrol if integrity > 0)
       │  mission_end)         └─────────────────┐
       │                                         │
       ├─────────────────────────────────────────┤
       │                                         │
       v                                         v
    [PATROL loop / escalate wave]     [PATROL loop / escalate]
       │                                    OR
       │                              [MISSION_FAILED]
       │
       v (all waves cleared)
┌────────────────────┐
│ MISSION_COMPLETE   │
└────────┬───────────┘
         │ (debrief_start signal)
         v
┌─────────┐
│ DEBRIEF │ (score breakdown, ready for next mission)
└─────────┘
```

## State Descriptions

### LOBBY
**Responsibility**: Awaiting player readiness and mission start input.

**Entry Conditions**:
- Game scene first loads
- All players have connected

**Active Behavior**:
- Display mission briefing UI (optional: allow difficulty selection, team composition preview)
- Accept player ready signals
- Disable all game input (drones not yet controlled)
- Monitor for player join/leave (remove drones gracefully if player disconnects)

**Exit Conditions**:
- Host clicks "Start Mission" (or after timer if all players ready)

**Signals Emitted**:
- `mission_start_requested` → triggers BRIEFING transition

---

### BRIEFING
**Responsibility**: Sync all players, queue audio/visual intro.

**Entry Conditions**:
- `mission_start_requested` signal received
- All player drones spawned at starting positions

**Active Behavior**:
- Play facility lockdown animation (optional: camera pan, warning klaxon)
- Display mission objectives overlay
- Start music fade-in (MusicManager receives briefing cue)
- Hold for 3–5 seconds
- All drones frozen (no input)

**Exit Conditions**:
- Timer expires

**Signals Emitted**:
- `briefing_complete` → transitions to PATROL

---

### PATROL
**Responsibility**: Continuous arena patrol; spawn escapees per wave schedule; maintain threat loop.

**Entry Conditions**:
- `briefing_complete` signal received
- Wave counter = 0 (or increment on re-entry from previous wave)

**Active Behavior**:
- **Spawn System**: EscapeeManager spawns escapees from random spawn points in randomized containment lanes per wave table (see REQ_05).
- **Timing**: Escapees spawn at a frequency defined per wave (e.g., Wave 1: 2 per second, Wave 2: 3 per second).
- **Player Control**: All player drones accept movement, ability, and camera input.
- **Continuous Loop**: As drones destroy escapees, new ones spawn until wave limit is met.
- **Music Reactivity**: Base intensity (1.05), speed (0.95), tone (0.96) maintained.
- **Minimap Active**: All escapees and team positions visible.

**Exit Conditions**:
- Escapee detected in player sensor range (transition to ALERT)
- OR wave spawn quota reached and all escapees destroyed (transition to SUCCESS for wave loop)

**Signals Emitted**:
- `escapee_detected(escapee_node)` → transitions to ALERT
- `wave_complete` → increments wave, re-enters PATROL or ends mission if final wave

---

### ALERT
**Responsibility**: Escalate threat; notify all players; begin chase timer.

**Entry Conditions**:
- `escapee_detected` signal received (escapee within detection range of any drone)

**Active Behavior**:
- **Klaxon Audio**: Play alert sound (SFX bus, no music interrupt; music might shift tone up).
- **Visual Alert**: HUD flashes with threat direction and distance.
- **Broadcast**: All drones notified of threat position on minimap (threat marker appears).
- **Chase Timer**: Start 30-second countdown to BREACH_ATTEMPT (if escapee not destroyed in time, mission consequence).
- **Music Escalation**: MusicManager receives ALERT cue (intensity increases slightly, tone more aggressive).
- **Player Focus**: Drones converge on threat; objective is clear.

**Exit Conditions**:
- Escapee destroyed (transition to SUCCESS)
- OR timer expires without destruction (transition to BREACH_ATTEMPT)

**Signals Emitted**:
- `threat_destroyed` → transitions to SUCCESS
- `chase_timer_expired` → transitions to BREACH_ATTEMPT

---

### BREACH_ATTEMPT
**Responsibility**: Escapee reaches perimeter; trigger consequence.

**Entry Conditions**:
- Chase timer expires without escapee destruction
- OR escapee physically enters PerimeterBreach zone

**Active Behavior**:
- **Breach Alarm**: Loud klaxon, red screen flash (brief).
- **Mission Integrity Loss**: MissionIntegrity meter decreases (e.g., 1 point per breach).
- **Broadcast Alert**: All players see breach notification ("BREACH EVENT - Integrity at 75%").
- **Consequence Persistence**: Integrity meter remains reduced; affects final score.
- **Escapee Removal**: Breached escapee is destroyed/removed from arena.
- **Resume Patrol**: Immediately return to PATROL state (unless integrity = 0).

**Exit Conditions**:
- Consequence applied; transition to PATROL (if integrity > 0)
- OR integrity = 0 (transition to MISSION_FAILED)

**Signals Emitted**:
- `breach_occurred(remaining_integrity)` → notifies all players
- `integrity_zero` → transitions to MISSION_FAILED
- `patrol_resume` → transitions to PATROL

---

### SUCCESS (Wave Complete)
**Responsibility**: Brief celebration of wave clear; prepare next wave or mission end.

**Entry Conditions**:
- All escapees in wave destroyed
- No new escapees spawning in current wave

**Active Behavior**:
- **Brief Pause**: 2-second grace period (no spawns).
- **UI Feedback**: "Wave 1 Clear" message, brief audio reward (positive chime or short music crescendo).
- **Difficulty Escalation**: Increment wave counter; adjust spawn frequency and elite ratio for next wave.
- **Music Reset**: MusicManager receives wave_complete cue; music tempo normalizes slightly (speed -> 0.95 constant baseline).

**Exit Conditions**:
- Final wave cleared (transition to MISSION_COMPLETE)
- OR next wave ready (transition back to PATROL)

**Signals Emitted**:
- `next_wave_start` → transitions to PATROL with incremented wave
- `mission_end` → transitions to MISSION_COMPLETE

---

### MISSION_COMPLETE
**Responsibility**: Mission succeeded; integrity > 0, all waves cleared.

**Entry Conditions**:
- Final wave cleared
- Mission integrity > 0

**Active Behavior**:
- **Lock Input**: All drones frozen.
- **Victory Audio**: Triumphant musical cue (MusicManager receives mission_complete signal).
- **Victory Overlay**: Display "Mission Successful" with highlights (no deaths, team bonus, etc.).
- **Score Calculation**: Calculate final score (see REQ_05).
- **Auto-Debrief**: After 3-second delay, transition to DEBRIEF.

**Exit Conditions**:
- Timer expires

**Signals Emitted**:
- `debrief_start` → transitions to DEBRIEF

---

### MISSION_FAILED
**Responsibility**: Mission ended; integrity = 0, breach threshold exceeded.

**Entry Conditions**:
- `integrity_zero` signal received

**Active Behavior**:
- **Alarm Audio**: Continuous breach alarm (not reversed; facility compromised audio).
- **Game Over Overlay**: Display "Mission Failed - Containment Breached" with final integrity and breach count.
- **Lock Input**: All drones frozen.
- **Auto-Debrief**: After 3-second delay, transition to DEBRIEF (for post-game review).

**Exit Conditions**:
- Timer expires

**Signals Emitted**:
- `debrief_start` → transitions to DEBRIEF

---

### DEBRIEF
**Responsibility**: Display mission stats, score breakdown, and readiness for next mission or exit.

**Entry Conditions**:
- `debrief_start` signal received (from SUCCESS or FAILED)

**Active Behavior**:
- **Score Breakdown Screen**: See REQ_05 for details.
- **Team Stats**: Aggregate kills, assists, breaches prevented, cooperation bonuses.
- **Input Readiness**: Allow players to select "Next Mission" or "Exit to Lobby".
- **Persist State**: Keep mission data in memory for potential replay or statistics tracking.

**Exit Conditions**:
- Host selects "Next Mission" (transition to LOBBY for new mission)
- OR all players select "Exit" (return to main menu or lobby)

**Signals Emitted**:
- `next_mission_requested` → transitions to LOBBY
- `exit_requested` → unload scene, return to hub

---

## Patrol Loop Detail: Escapee Spawning

During PATROL state, escapees spawn according to a **wave configuration** (data-driven):

```
Wave 1: 20 Basic Runners over 60 seconds (spawn rate: 0.33/sec)
Wave 2: 25 Runners + 5 Evaders over 45 seconds (spawn rate: 0.67/sec)
Wave 3: 30 mixed + 3 Tanks over 40 seconds (spawn rate: 0.83/sec)
...
```

**Spawn Algorithm**:
1. EscapeeManager maintains a `spawn_queue` per wave.
2. Every frame, check if enough time has elapsed since last spawn.
3. If time threshold met and queue not empty, dequeue one escapee definition, instantiate it at a random spawn point, register it with EscapeeManager.
4. Repeat until queue empty.

**Randomization**:
- Spawn point varies per escapee (across multiple lanes).
- Elite type distribution randomized (e.g., 10% elite per wave).
- Patrol path variation: escapees don't all take identical routes.

---

## AFK / Disconnect Handling

**Player Disconnect**:
1. If a player's drone loses network connection, their drone is **not destroyed** but transitions to **AI ghost state** (basic patrol, no damage dealt, no input accepted).
2. If player reconnects within 10 seconds, control is restored; ghost state ends.
3. If player remains disconnected after 10 seconds, drone is gradually faded out and removed from arena; no impact to other players' scoring.
4. Mission does not pause or fail due to a single disconnect.

**AFK (Player Idle)**:
1. If a drone receives no input for 30 seconds, an AFK warning appears on that player's HUD.
2. After 45 seconds, the drone transitions to AI ghost state (same as disconnect above).
3. AFK state is reversed if any input is detected.

---

## Signals Summary

| Signal Name            | Emitted From | Received By | Payload                              |
|------------------------|--------------|-------------|--------------------------------------|
| `mission_start_requested` | LOBBY UI | StateManager | (none)                              |
| `briefing_complete`    | BRIEFING timer | StateManager | (none)                              |
| `escapee_detected`     | EscapeeManager | StateManager | escapee_node reference              |
| `threat_destroyed`     | EscapeeEntity | StateManager | (none)                              |
| `chase_timer_expired`  | ALERT timer | StateManager | (none)                              |
| `breach_occurred`      | BREACH_ATTEMPT | StateManager & HUD | remaining_integrity (int) |
| `integrity_zero`       | MissionIntegrity | StateManager | (none)                              |
| `wave_complete`        | EscapeeManager | StateManager | current_wave (int)                  |
| `next_wave_start`      | SUCCESS logic | StateManager | next_wave_number (int)              |
| `mission_end`          | Wave system | StateManager | (none)                              |
| `debrief_start`        | Mission outcome | StateManager | outcome_type ("success"/"failed")  |

---

**Implementation Notes:**
- All state transitions are server-authoritative; the host executes state changes and broadcasts to clients.
- Use Godot 4 `State` pattern or a simple enum-based state dispatcher for clarity.
- Each state should be its own node or script with `_enter()`, `_exit()`, `_process()` lifecycle.
- Signals should use Godot's built-in `signal` system for loose coupling.
- Music manager integration: each state change should call `MusicManager.set_profile()` with appropriate intensity/speed/tone deltas.
