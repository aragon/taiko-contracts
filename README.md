# Taiko DAO contracts

This reposity contains the codebase of the Taiko DAO, along with its 3 plugins and helper contracts. 

The DAO contract is an [Aragon DAO](https://github.com/aragon/osx), on which an **Optimistic Token Voting plugin** has the permission to execute proposals. Proposals on this plugin can only be created by two distinct multisig plugins, belonging to Taiko's Security Council.

The Security Council has a standard multisig plugin and an emergency variant. The former one is intended to be used most of the time, if not always. A certain majority of Security Council members need to approve it for it to make it to the community vote. The latter, is meant to only be used in exceptional situations, i.e. when a security vulnerability needs to be addressed immediately.

[Learn more about Aragon OSx](#protocol-overview).

See [Deploying the DAO](#deploying-the-dao) below and check out the [latest deployments](./DEPLOYMENTS.md).

## Optimistic Token Voting plugin

This plugin is an adapted version of Aragon's [Optimistic Token Voting plugin](https://github.com/aragon/optimistic-token-voting-plugin). 

Only addresses that have been granted `PROPOSER_PERMISSION_ID` on the plugin can create proposals. These adresses belong to the two multisig's belonging to the Security Council. 

Proposals can only be executed when a certain amount of vetoes hasn't emerged after a given period of time.

The governance settings need to be defined when the plugin is installed but the DAO can update them at any time.

### Permissions

- Only proposers can create proposals on the plugin
- The plugin can execute actions on the DAO
- The DAO can update the plugin settings
- The DAO can upgrade the plugin

## Multisig (standard)

Implements a list of addresses, where proposals can only be relayed to the [Optimistic Token Voting plugin](#optimistic-token-voting-plugin) after being approved.

### Permissions

- Only members can create proposals
- Only members can approve
- The plugin can only create proposals on the [Optimistic Token Voting plugin](#optimistic-token-voting-plugin) provided that the `duration` is equal or greater than the minimum defined

## Emergency Multisig

Same as before, it implements a list of addresses, where proposals can only be relayed to the [Optimistic Token Voting plugin](#optimistic-token-voting-plugin) after being approved.

There are two key differences:
1. The proposal's metadata and the actions to execute are encrypted, only available to the Security Council members
2. When approved by a super majority, the proposal can be executed on the DAO immediately, going through the [Optimistic Token Voting plugin](#optimistic-token-voting-plugin).

## Plugin Installation

### Installing the initial set of plugins on the DAO

This is taken care by the `TaikoDAOFactory` contract. Is is invoked by `scripts/Deploy.s.sol` and it creates an immutable DAO deployment, given a certain settings. To create a DAO with different settings, a new factory needs to be deployed. 

### Installing plugins on the existing DAO

Plugin changes need a proposal to be passed when the DAO already exists.

1. Calling `pluginSetupProcessor.prepareInstallation()`
   - A new plugin instance is deployed with the desired settings
   - The call requests a set of permissions to be applied by the DAO
2. Editors pass a proposal to make the DAO call `applyInstallation()` on the [PluginSetupProcessor](https://devs.aragon.org/docs/osx/how-it-works/framework/plugin-management/plugin-setup/)
   - This applies the requested permissions and the plugin becomes installed

See `OptimisticTokenVotingPluginSetup`.

[Learn more about plugin setup's](https://devs.aragon.org/docs/osx/how-it-works/framework/plugin-management/plugin-setup/) and [preparing installations](https://devs.aragon.org/docs/sdk/examples/client/prepare-installation).

## OSx protocol overview

OSx [DAO's](https://github.com/aragon/osx/blob/develop/packages/contracts/src/core/dao/DAO.sol) are designed to hold all the assets and rights by themselves, while plugins are custom, opt-in pieces of logic that can perform any type of actions governed by the DAO's permission database.

The DAO contract can be deployed by using Aragon's `DAOFactory` contract. This will deploy a new DAO with the desired plugins and settings.

### How permissions work

An Aragon DAO is a set of permissions that are used to restrict who can do what and where.

A permission looks like:

- An address `who` holds `MY_PERMISSION_ID` on a target contract `where`

Brand new DAO's are deployed with a `ROOT_PERMISSION` assigned to its creator, but the DAO will typically deployed by the DAO factory, which will install all the requested plugins and drop the ROOT permission after the set up is done.

Managing permissions is made via two functions that are called on the DAO:

```solidity
function grant(address _where, address _who, bytes32 _permissionId);

function revoke(address _where, address _who, bytes32 _permissionId);
```

### Permission Conditions

For the cases where an unrestricted permission is not derisable, a [Permission Condition](https://devs.aragon.org/docs/osx/how-it-works/core/permissions/conditions) can be used.

Conditional permissions look like this:

- An address `who` holds `MY_PERMISSION_ID` on a target contract `where`, only `when` the condition contract approves it

Conditional permissions are granted like this:

```solidity
function grantWithCondition(
  address _where,
  address _who,
  bytes32 _permissionId,
  IPermissionCondition _condition
);
```

See the condition contract boilerplate. It provides the plumbing to easily restrict what the different multisig plugins can propose on the OptimisticVotingPlugin.

[Learn more about OSx permissions](https://devs.aragon.org/docs/osx/how-it-works/core/permissions/)

### Permissions being used

Below are all the permissions that a [PluginSetup](#plugin-setup-contracts) contract may want to request:

- `EXECUTE_PERMISSION` is required to make the DAO `execute` a set of actions
  - Only governance plugins should have this permission
- `ROOT_PERMISSION` is required to make the DAO `grant` or `revoke` permissions
  - The DAO needs to be ROOT on itself (it is by default)
  - Nobody else should be ROOT on the DAO
- `UPGRADE_PLUGIN_PERMISSION` is required for an address to be able to upgrade a plugin to a newer version published by the developer
  - Typically called by the DAO via proposal
  - Optionally granted to an additional address for convenience
- `PROPOSER_PERMISSION` is required to be able to create optimistic proposals on the governance plugin
- `UPDATE_MULTISIG_SETTINGS_PERMISSION_ID` is used by the DAO to update the settings of a multisig plugin, if the community approves
- `UPDATE_OPTIMISTIC_GOVERNANCE_SETTINGS_PERMISSION_ID` is used by the DAO to update the settings of the optimistic voting plugin, if the community approves

Other DAO specific permissions:

- `UPGRADE_DAO_PERMISSION`
- `SET_METADATA_PERMISSION`
- `SET_TRUSTED_FORWARDER_PERMISSION`
- `SET_SIGNATURE_VALIDATOR_PERMISSION`
- `REGISTER_STANDARD_CALLBACK_PERMISSION`

### Encoding and decoding actions

Making calls to the DAO is straightforward, however making execute arbitrary actions requires them to be encoded, stored on chain and be approved before they can be executed.

To this end, the DAO has a struct called `Action { to, value, data }`, which will make the DAO call the `to` address, with `value` ether and call the given calldata (if any). Such calldata is an ABI encoded array of bytes with the function to call and the parameters it needs. 

### DO's and DONT's

- Never grant `ROOT_PERMISSION` unless you are just trying things out
- Never uninstall all plugins, as this would brick your DAO
- Ensure that there is at least always one plugin with `EXECUTE_PERMISSION` on the DAO
- Ensure that the DAO is ROOT on itself
- Use the `_gap[]` variable for upgradeable plugins, as a way to reserve storage slots for future plugin implementations
  - Decrement the `_gap` number for every new variable you add in the future

### Plugin upgradeability

By default, only the DAO can upgrade plugins to newer versions. This requires passing a proposal.

[Learn more about plugin upgrades](https://devs.aragon.org/docs/osx/how-to-guides/plugin-development/upgradeable-plugin/updating-versions)

## Development

To work with the repository you need to install [Foundry](https://book.getfoundry.sh/getting-started/installation) on your operating system.

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Deploying the DAO

1. Edit `script/multisig-members.json` with the list of addresses to set as signers
2. Run `forge build && forge test`
3. Copy `.env.example` into `.env` and define the settings
4. Run `source .env` to load them
5. Set the RPC URL and run the deployment script

```shell
RPC_URL="https://eth-holesky.g.alchemy.com/v2/${ALCHEMY_API_KEY}"
forge script --chain "$NETWORK" script/Deploy.s.sol:Deploy --rpc-url "$RPC_URL" --broadcast --verify
```

If you get the error `Failed to get EIP-1559 fees`, add `--legacy` to the last command:

```shell
forge script --chain "$NETWORK" script/Deploy.s.sol:Deploy --rpc-url "$RPC_URL" --broadcast --verify --legacy
```

If a some contracts fail to verify on Etherscan, retry with this command:

```shell
forge script --chain "$NETWORK" script/Deploy.s.sol:Deploy --rpc-url "$RPC_URL" --verify --legacy --private-key "$DEPLOYMENT_PRIVATE_KEY" --resume
```

### Formatting the code

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Run a local test EVM

```shell
$ anvil
```

### Cast

```shell
$ cast <subcommand>
```
