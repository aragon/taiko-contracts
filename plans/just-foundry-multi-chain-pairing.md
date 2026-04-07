# just-foundry: Multi-chain network pairing

## Problem

`just-foundry` loads one network at a time (`just switch hoodi`). Multi-chain scripts need vars from both L1 and L2 simultaneously. Naive merging causes collisions on `RPC_URL`, `CHAIN_ID`, `NETWORK_NAME`, `VERIFIER`, `TAIKO_ERC20_VAULT_ADDRESS`, etc.

## Proposed design

A `switch-pair` command that loads two networks with a prefix:

```bash
just switch-pair hoodi taiko-hoodi
# Produces:
# L1_RPC_URL, L1_CHAIN_ID, L1_NETWORK_NAME, L1_VERIFIER, ...
# L2_RPC_URL, L2_CHAIN_ID, L2_NETWORK_NAME, L2_VERIFIER, ...
```

## Changes needed

### just-foundry lib

- `env.sh`: add `env_load_pair(l1_network, l2_network)` and `_env_load_prefixed(network, prefix)`
- `justfile`: add `switch-pair l1 l2` recipe
- Decide: does `switch-pair` write a `.env.pair` file, or just export at runtime?

### This project (consumer)

- Network `.env` files: remove existing `L1_`/`L2_` prefixes from vars (`L1_TAIKO_BRIDGE` -> `TAIKO_BRIDGE`, `L2_VOTING_TOKEN` -> `VOTING_TOKEN`), since the prefix is now applied by the loader
- Scripts: read `L1_TAIKO_BRIDGE` (which comes from `L1_` + `TAIKO_BRIDGE`) instead of the raw var
- `foundry.toml` `[rpc_endpoints]`: may need updating if scripts use `L1_RPC_URL` / `L2_RPC_URL` instead of chain names

## Open questions

1. Should single-network `switch` still work unprefixed (backwards compat)?
2. How to handle vars that already have `L1_`/`L2_` prefix in the source file -- strip before re-prefixing, or require clean names?
3. Should `L1_CHAIN` / `L2_CHAIN` (the `foundry.toml` fork alias) be derived from `L1_NETWORK_NAME` / `L2_NETWORK_NAME` automatically?
4. Does `vars` (the secret manager) need changes to support prefixed resolution?

## Recommendation

Separate PR on `just-foundry` first, then a follow-up PR here to adopt it. This also resolves the network env naming issue (task #2 from the review) since the env files would drop chain prefixes entirely.
