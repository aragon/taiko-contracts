# L2 Veto Aggregation - Design Document

## Overview

This document describes the enhancement to the Taiko DAO governance system, enabling TAIKO token holders on L2 to participate in veto voting for proposals created on L1.

## Current State

Currently, only L1 token holders can participate in veto voting:

```
┌─────────────────────────────────────────────────────────────┐
│                        ETHEREUM L1                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐         ┌──────────────────────────────┐   │
│  │   Token     │ veto()  │  OptimisticTokenVotingPlugin │   │
│  │   Holder    │────────▶│                              │   │
│  │   (L1)      │         │  - Counts L1 votes only      │   │
│  └─────────────┘         │  - Executes if no veto       │   │
│                          └──────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Problem**: ~102M TAIKO tokens are bridged to L2, representing significant voting power that cannot currently participate in governance.

---

## Architecture

The architecture enables L2 token holders to veto by aggregating votes on L2 and bridging them to L1 via a push model:

```
┌─────────────────────────────────────────────────────────────┐
│                         TAIKO L2                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐         ┌──────────────────────────────┐   │
│  │   Token     │ veto()  │      L2VetoAggregator        │   │
│  │   Holder    │────────▶│                              │   │
│  │   (L2)      │         │  - Decodes proposalId        │   │
│  └─────────────┘         │  - Validates veto timing     │   │
│                          │  - Aggregates veto votes     │   │
│  ┌─────────────┐         │  - Tracks who voted          │   │
│  │   Token     │ veto()  │                              │   │
│  │   Holder    │────────▶│                              │   │
│  │   (L2)      │         └───────────────┬──────────────┘   │
│  └─────────────┘                         │                  │
│                                          │ dispatch()       │
│                                          ▼                  │
│                          ┌──────────────────────────────┐   │
│                          │        Taiko Bridge          │   │
│                          │      (sendMessage)           │   │
│                          └───────────────┬──────────────┘   │
│                                          │                  │
└──────────────────────────────────────────┼──────────────────┘
                                           │
                    ═══════════════════════╪═══════════════════
                         CROSS-CHAIN MESSAGE (L2 → L1)
                    ═══════════════════════╪═══════════════════
                                           │
┌──────────────────────────────────────────┼──────────────────┐
│                                          │                  │
│                                          ▼                  │
│                          ┌──────────────────────────────┐   │
│                          │        Taiko Bridge          │   │
│                          │     (delivers message)       │   │
│                          └───────────────┬──────────────┘   │
│                                          │                  │
│                                          ▼                  │
│                          ┌──────────────────────────────┐   │
│                          │      L2VetoReceiver          │   │
│                          │                              │   │
│                          │  - Validates bridge origin   │   │
│                          │  - Validates proposalId      │   │
│                          │  - Pushes L2 tally to plugin │   │
│                          └───────────────┬──────────────┘   │
│                                          │                  │
│                                          │ receiveL2Vetoes()│
│                                          ▼                  │
│  ┌─────────────┐         ┌──────────────────────────────┐   │
│  │   Token     │ veto()  │  OptimisticTokenVotingPlugin │   │
│  │   Holder    │────────▶│                              │   │
│  │   (L1)      │         │  - Counts L1 votes           │   │
│  └─────────────┘         │  - Receives L2 votes (push)  │   │
│                          │  - Combined veto threshold   │   │
│                          └──────────────────────────────┘   │
│                                                             │
│                        ETHEREUM L1                          │
└─────────────────────────────────────────────────────────────┘
```

---

## ProposalId Encoding

The proposalId is a self-describing 256-bit value that embeds all timing information. Both L1 and L2 work with the same raw `uint256 proposalId` — no hashing or cross-chain registration needed.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Bits 192-255    │  Bits 128-191  │  Bits 64-127  │  Bits 0-63              │
│ snapshotTimestamp│   startDate    │    endDate    │  sequential counter     │
│    64 bits       │    64 bits     │    64 bits    │      64 bits            │
└─────────────────────────────────────────────────────────────────────────────┘
```

The L2VetoAggregator decodes timing directly from the proposalId:
- `snapshotTimestamp`: used for `votingToken.getPastVotes(voter, snapshotTimestamp)`
- `startDate` / `endDate`: used to validate veto window (`startDate <= now < endDate`)

---

## Voting Flow

### Step 1: Proposal Creation (L1)

```
┌────────────────┐      ┌─────────────────┐      ┌─────────────────────────────┐
│   Multisig     │      │  Optimistic     │      │   Proposal Created          │
│   Committee    │─────▶│  Token Voting   │─────▶│   proposalId: encoded       │
│                │      │  Plugin         │      │   endDate: start + duration │
└────────────────┘      └─────────────────┘      └─────────────────────────────┘
                         createProposal()

proposalId encodes: snapshotTimestamp | startDate | endDate | counter
```

### Step 2: L2 Voting Period

L2 voters call `veto(proposalId)` on the L2VetoAggregator using the L1 proposalId directly. The contract decodes the snapshot timestamp from the ID to look up voting power.

```
┌─────────────┐                              ┌──────────────────────────┐
│  L2 Token   │     veto(proposalId)         │    L2VetoAggregator      │
│  Holder A   │─────────────────────────────▶│                          │
│  100K TAIKO │                              │  proposalId: 0x123...    │
└─────────────┘                              │  ├─ vetoTally: 350K      │
                                             │  ├─ Holder A: ✓          │
┌─────────────┐     veto(proposalId)         │  ├─ Holder B: ✓          │
│  L2 Token   │─────────────────────────────▶│  └─ Holder C: ✓          │
│  Holder B   │                              │                          │
│  150K TAIKO │                              │  Votes aggregated on L2  │
└─────────────┘                              │  (gas efficient)         │
                                             │                          │
┌─────────────┐     veto(proposalId)         │                          │
│  L2 Token   │─────────────────────────────▶│                          │
│  Holder C   │                              │                          │
│  100K TAIKO │                              └──────────────────────────┘
└─────────────┘
```

### Step 3: Vote Dispatch (L2 → L1)

Anyone can call `dispatch(proposalId)` at any time, paying the bridge relayer
fee with `msg.value` (capped at `type(uint64).max`). Multiple dispatches are
allowed — each sends the current cumulative tally. Replay/regression protection
is split across two layers:

- The **receiver** rejects messages whose `dispatchedAt` is not strictly newer
  than the previously stored timestamp (`StaleVetoMessage`).
- The **plugin** rejects tallies that are not strictly larger than the
  previously aggregated L2 balance (`L2VetoTallyNotIncreased`), and tallies
  that exceed the bridged voting power held in the vault at the snapshot
  (`L2VetoTallyExceedsVaultBalance`).

```
┌──────────────┐      ┌──────────────────┐      ┌─────────────────┐
│   Anyone     │      │ L2VetoAggregator │      │  Taiko Bridge   │
│   (Relayer)  │─────▶│                  │─────▶│                 │
│              │      │  Encodes:        │      │  sendMessage()  │
└──────────────┘      │  - proposalId    │      │                 │
                      │  - vetoTally     │      │  L2 → L1        │
 dispatch()           │  - timestamp     │      └────────┬────────┘
                      └──────────────────┘               │
                                                         ▼
                                              ┌─────────────────┐
                                              │ Cross-chain Msg │
                                              │ to L1 Receiver  │
                                              └─────────────────┘
```

### Step 4: L1 Vote Application (Push Model)

The L2VetoReceiver validates the bridge message and immediately pushes the tally into the plugin's `proposal_.vetoTally`. If the push fails, `submitL2Vetoes()` can be retried later.

```
┌─────────────────┐      ┌──────────────────┐      ┌────────────────────────┐
│  Taiko Bridge   │      │  L2VetoReceiver  │      │  Optimistic Token      │
│  (L1)           │─────▶│                  │─────▶│  Voting Plugin         │
│                 │      │  Validates:      │      │                        │
│  onMessageInv.  │      │  1. Caller is    │      │  L1 vetoes:  200K      │
└─────────────────┘      │     bridge       │      │  L2 vetoes:  350K      │
                         │  2. Sender is    │      │  ─────────────────     │
                         │     trusted agg. │      │  Total:      550K      │
                         │  3. Chain ID     │      │                        │
                         │  4. ProposalId   │      │  Threshold:  500K  ✓   │
                         │     is valid     │      │  VETO SUCCESSFUL       │
                         │  5. Not stale    │      │                        │
                         │                  │      │  vetoTally updated     │
                         │ receiveL2Vetoes()│      │  via push model        │
                         └──────────────────┘      └────────────────────────┘
```

---

## Contract Changes Summary

| Contract | Chain | Change Type | Description |
|----------|-------|-------------|-------------|
| `OptimisticTokenVotingPlugin` | L1 | **Upgrade** | Renamed `taikoBridge` → `taikoERC20Vault`, added `l2VetoReceiver` storage, `receiveL2Vetoes()`, `setL2VetoReceiver()`, `parseProposalId()`, embedded `snapshotTimestamp` in proposalId |
| `L2VetoReceiver` | L1 | **New** | Receives bridged votes, validates, pushes to plugin |
| `L2VetoAggregator` | L2 | **New** | Aggregates L2 vetoes, dispatches to L1 via bridge |

---

## Security Model

### L2VetoReceiver (5 validation layers)

1. **Caller check**: Only the Taiko Bridge contract can call `onMessageInvocation()`
2. **Sender check**: Bridge context `from` must be the `trustedL2Aggregator`
3. **Chain ID check**: Bridge context `srcChainId` must match expected L2
4. **ProposalId validation**: Timestamps in proposalId must match plugin's stored proposal data
5. **Staleness check**: `dispatchedAt` must be strictly greater than the previous dispatch timestamp

### L2VetoAggregator (3 validation layers)

1. **Timing check**: `startDate <= block.timestamp < endDate` (decoded from proposalId)
2. **Double-vote prevention**: Each address can only veto once per proposal
3. **Voting power check**: Voter must have non-zero power at `snapshotTimestamp`

### Plugin `receiveL2Vetoes()` (5 validation layers)

1. **Caller check**: Only the configured `l2VetoReceiver` address
2. **Existence check**: Proposal must exist (`snapshotTimestamp != 0`)
3. **Timing check**: Proposal must still accept L2 vetoes (not executed, aggregation window open)
4. **Monotonic tally**: New L2 tally must be strictly greater than the previous one
5. **Vault cap**: New L2 tally cannot exceed the bridged voting power held in the `taikoERC20Vault` at the snapshot timestamp

### Cross-cutting

- **Double-voting (L1+L2)**: The `taikoERC20Vault` address is excluded from L1 `canVeto()`, so bridged tokens can only vote via the L2 path
- **Flash loan protection**: Voting power uses snapshot-based `getPastVotes()` on both chains
- **L2 unavailability**: Grace period, `skipL2` flag, and `unavailableL2` per-proposal flag handle L2 downtime

---

## Timeline Visualization

The L2 aggregation grace period runs **inside** the timelock, not after it.
The settings enforce `timelockPeriod >= l2AggregationGracePeriod` so that L2
vetoes always resolve before execution becomes possible.

```
        Proposal Lifecycle with L2 Voting (L2 available)

                              vetoEndDate + gracePeriod        vetoEndDate +
  start                vetoEndDate     │                       timelockPeriod
    │                       │          │                            │
    ▼                       ▼          ▼                            ▼
    ╠═══════════════════════╬══════════╪════════════════════════════╣
    ║     Veto Window       ║   L2     │   Remaining Timelock       ║──► execute()
    ║                       ║  Grace   │   (within Exit Window)     ║    or
    ║  L1: veto()           ║  Period  │                            ║    Defeated
    ║  L2: veto()           ║          │                            ║
    ║  L2: dispatch()       ║          │                            ║
    ║  L2: dispatch()       ║          │                            ║
    ╠═══════════════════════╩══════════╪════════════════════════════╣
    │                                  │                            │
    │◀──── duration ──────►│           │                            │
    │                      │◀ grace ──►│                            │
    │                      │◀────────── timelockPeriod ────────────►│
    │                      │                                        │
    │  L1+L2 vetoes allowed│ no new vetoes,        no veto updates, │
    │  L2 dispatches OK    │ L2 dispatches OK      no execution     │
    │                      │◀────────── Exit Window ───────────────►│


Example with the deployment defaults from `.env.example`
(duration=14d, grace=2d, timelock=7d):

Day 0                    Day 14    Day 16             Day 21
  │                         │        │                   │
  ▼                         ▼        ▼                   ▼
  ╠═════════════════════════╬════════╬═══════════════════╣
  ║       Veto Window       ║L2 Grace║  Remaining        ║──► execute()
  ║       (L1 + L2)         ║(bridge)║  Timelock         ║
  ╠═════════════════════════╬════════╩═══════════════════╣
  │                         │◄ grace►│                   │
  │                         │◄──── timelock (7d) ───────►│
  │                         │                            │
  Total: 14d + 7d = 21 days


        Proposal Lifecycle (L2 unavailable at creation)

  When L2 is down at proposal creation (skipL2 set, bridge paused, or
  Taiko L1 stale beyond l2InactivityPeriod):
    → unavailableL2 = true
    → Grace period is skipped entirely
    → Total time is still duration + timelockPeriod

  start              vetoEndDate     vetoEndDate + timelockPeriod
    │                     │                      │
    ▼                     ▼                      ▼
    ╠═════════════════════╬══════════════════════╣
    ║    Veto Window      ║      Timelock        ║──► execute()
    ║    (L1 only)        ║    (exit window)     ║
    ╠═════════════════════╬══════════════════════╣
    │◄──── duration ──────►│◄──── timelock ─────►│


        Proposal Lifecycle (emergency, duration == 0)

  Emergency-multisig proposals (duration == 0) bypass the entire window:
    → unavailableL2 = true (also marked, though irrelevant)
    → executed = true is set inside createProposal()
    → Actions execute synchronously in the same transaction

  createProposal()  ──►  executed = true  ──►  actions executed
       │                                              │
       └────────── single transaction ────────────────┘
```

- Multiple dispatches can happen during the veto period and grace period
- Each dispatch sends the cumulative tally at that point in time
- Grace period allows final L2 messages to be relayed after the L1 veto period ends
- The grace period is nested inside the timelock — **it does not extend total duration**

---

## Deployment Order

The `L2VetoAggregator` has **no owner** — all its addresses (`bridge`, `l1ChainId`,
`votingToken`, `l1Receiver`) are immutable and set at construction. The
`L2VetoReceiver` uses Aragon `DaoAuthorizable`, with its `trustedL2Aggregator`
gated by the `SET_TRUSTED_L2_AGGREGATOR_PERMISSION` held by the DAO.

```
1. Deploy L2VetoReceiver on L1
   (immutable: bridge, l2ChainId, votingPlugin; trustedL2Aggregator unset)
2. Deploy L2VetoAggregator on L2
   (immutable: bridge, l1ChainId, votingToken, l1Receiver = L2VetoReceiver address)
3. DAO proposal (single batch via UpgradeOptimisticTokenVotingPluginFactory):
   a. Upgrade the plugin from Build 1 to Build 2 (PSP applyUpdate)
   b. Call plugin.setL2VetoReceiver(L2VetoReceiver)
   c. Call L2VetoReceiver.setTrustedL2Aggregator(L2VetoAggregator)
```

No `renounceOwnership()` step is needed: the aggregator has no admin surface,
and the receiver's only mutable parameter (`trustedL2Aggregator`) is governed
by the DAO permission system.

---

## Configuration Changes

Because the aggregator's `l1Receiver` and the receiver's `bridge`/`l2ChainId`/
`votingPlugin` are immutable, rotating either contract requires redeploying
both:

1. Deploy a new L2VetoReceiver on L1
2. Deploy a new L2VetoAggregator on L2 (with the new receiver address baked in)
3. DAO proposal:
   a. `plugin.setL2VetoReceiver(newReceiver)`
   b. `newReceiver.setTrustedL2Aggregator(newAggregator)` (auth-gated by DAO permission)
4. The old receiver remains usable for in-flight proposals already mid-flight
5. New proposals dispatch through the new aggregator → new receiver

This keeps each cross-chain endpoint immutable end-to-end and centralizes
governance control in the plugin and the DAO permission system.
