# Reading the Bridge Vault's Voting Power

## Problem

`OptimisticTokenVotingPlugin.bridgedVotingPower(timestamp)` is intended to
return the voting power held by the L1 `ERC20Vault` (the address that
custodies TAIKO bridged to L2) at a given snapshot. Today it calls:

```solidity
votingToken.getPastVotes(taikoERC20Vault, _timestamp);
```

…which always returns `0`, because L1 `TaikoToken` overrides `getPastVotes` to
zero-out "non-voting accounts" (the vault is on that list).

Consequences while this returns `0`:

- In `createProposal`, the `_enableL2` flag is always `false`, so L2 vetoes are
  never aggregated.
- `effectiveVotingPower(ts, false)` does not subtract the vault balance from
  total supply, so the L1 quorum denominator is inflated.

`TaikoToken` overrides only three functions:

| Function                     | Overridden? | Behavior for the vault                              |
| ---------------------------- | ----------- | --------------------------------------------------- |
| `getPastVotes(account, ts)`  | Yes         | Returns `0` for non-voting accounts                 |
| `getPastTotalSupply(ts)`     | Yes         | Subtracts non-voting accounts' `super.getPastVotes` |
| `delegate()`                 | Yes         | Blocks delegation to/from non-voting accounts       |
| `getVotes(account)`          | No          | Real current voting power (~102.8M)                 |
| `balanceOf(account)`         | No          | Real current balance (~102.8M)                      |
| `checkpoints(account, pos)`  | No          | Real historical checkpoint data                     |
| `numCheckpoints(account)`    | No          | Real count (currently 351)                          |

Because the vault self-delegates, every transfer in/out triggers
`_afterTokenTransfer → _moveVotingPower`, which writes a new entry to the
vault's checkpoint array. The historical voting power is fully recorded —
`getPastVotes` just hides it behind the override.

## Options

### Option 1 — Upgrade `TaikoToken` to expose the vault's real voting power

Upgrade the L1 `TaikoToken` so that the vault's historical voting power is
queryable through standard `IVotesUpgradeable` calls. Two viable shapes:

- Remove the vault from `getNonVotingAccounts()` so `getPastVotes(vault, ts)`
  returns the real value via the standard ERC20Votes path, **or**
- Add a dedicated read function (e.g. `getBridgedPastVotes(ts)`) that bypasses
  the non-voting filter for the vault address.

`bridgedVotingPower` then keeps using a single, standard call.

**Pros**
- Fix at the source — no workaround in plugin code.
- Single external call, minimal gas.
- Standard `IVotesUpgradeable` semantics.

**Cons**
- Requires a token contract upgrade and the associated governance /
  coordination process.
- Until the upgrade lands, `bridgedVotingPower` returns `0` and L2 vetoes
  remain disabled.

### Option 2 — Plugin-side binary search over `checkpoints`

Replace the `getPastVotes(vault, ts)` call inside `bridgedVotingPower` with a
binary search over the vault's checkpoint array. Because `checkpoints` and
`numCheckpoints` are not overridden, the data is fully accessible from the
plugin — this replicates what `getPastVotes` would do internally.

```solidity
function _vaultPastVotes(uint256 _timestamp) internal view returns (uint256) {
    uint32 nCheckpoints = votingToken.numCheckpoints(taikoERC20Vault);
    if (nCheckpoints == 0) return 0;

    IVotesUpgradeable.Checkpoint memory latest =
        votingToken.checkpoints(taikoERC20Vault, nCheckpoints - 1);
    if (latest.fromBlock <= _timestamp) return latest.votes;

    IVotesUpgradeable.Checkpoint memory first =
        votingToken.checkpoints(taikoERC20Vault, 0);
    if (first.fromBlock > _timestamp) return 0;

    uint32 low = 0;
    uint32 high = nCheckpoints;
    while (low < high) {
        uint32 mid = (low + high) / 2;
        if (votingToken.checkpoints(taikoERC20Vault, mid).fromBlock > _timestamp) {
            high = mid;
        } else {
            low = mid + 1;
        }
    }
    return votingToken.checkpoints(taikoERC20Vault, high - 1).votes;
}
```

**Pros**
- Snapshot-accurate — uses the same checkpoint data `getPastVotes` would.
- No token contract change required; ships entirely from the plugin.
- No manipulation window: values are locked at checkpoint time.

**Cons**
- ~9 external `staticcall`s per query (log₂(351)). Runs once in
  `createProposal` and on view functions.
- Plugin code carries a workaround that exists only because of the
  `getPastVotes` override.
