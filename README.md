# Taiko DAO contracts

This OSx plugin is an instance of the Optimistic Dual Governance model, where selected groups or members can submit proposals and token holders can veto them. Proposals that have not been vetoed after a period of time can be eventually executed by anyone. 

OSx plugins are designed to encapsulate custom behaviour and permissions so that they can be installed on any Aragon DAO.

[Learn more about Aragon OSx](#protocol-overview).


## Optimistic Token Voting plugin

This plugin is an adapted version of Aragon's [TokenVoting plugin](https://github.com/aragon/osx/blob/develop/packages/contracts/src/plugins/governance/majority-voting/token/TokenVoting.sol). 

Only addresses that have been granted `PROPOSER_PERMISSION_ID` on the plugin can create proposals. These adresses could belong to another plugin, an external multisig or even a plain wallet.

Proposals can only be executed when a certain amount of vetoes hasn't emerged after a given period of time.

The governance settings need to be defined when the plugin is installed but the DAO can update them at any time.

#### Methods

- `function initialize(IDAO dao, governanceSettings, IVotesUpgradeable token)`
- `function createProposal(bytes metadata, IDAO.Action[] actions, uint256 allowFailureMap, uint64 startDate, uint64 endDate) returns (uint256 proposalId)`
- `function veto(uint256 proposalId)`
- `function execute(uint256 proposalId)`
- `function updateOptimisticGovernanceSettings(OptimisticGovernanceSettings governanceSettings)`

Inherited:

- `function upgradeTo(address newImplementation)`
- `function upgradeToAndCall(address newImplementation, bytes data)`

#### Getters

- `function getVotingToken() returns (IVotesUpgradeable)`
- `function totalVotingPower(uint256 blockNumber) returns (uint256)`
- `function isMember(address account) returns (bool)`
- `function hasVetoed(uint256 proposalId, address voter) returns (bool)`
- `function canVeto(uint256 proposalId, address voter) returns (bool)`
- `function canExecute(uint256 proposalId) returns (bool)`
- `function isMinVetoRatioReached(uint256 proposalId) returns (bool)`
- `function minVetoRatio() returns (uint32)`
- `function minDuration() returns (uint64)`
- `function minProposerVotingPower() returns (uint256)`
- `function getProposal(uint256 proposalId) returns (bool open, bool executed, ProposalParameters memory parameters, uint256 vetoTally, IDAO.Action[] memory actions, uint256 allowFailureMap)`
- `function supportsInterface(bytes4 interfaceId) returns (bool)`

Inherited:

- `function implementation() returns (address)`

#### Events

- `event VetoCast(uint256 proposalId, address voter, uint256 votingPower)`
- `event OptimisticGovernanceSettingsUpdated(uint32 minVetoRatio, uint64 minDuration, uint256 minProposerVotingPower)`

Inherited:

- `event ProposalCreated(uint256 proposalId, address creator, uint64 startDate, uint64 endDate, bytes metadata, IDAO.Action[] actions, uint256 allowFailureMap)`
- `event ProposalExecuted(uint256 proposalId)`

#### Permissions

- Only proposers can create proposals on the plugin
- The plugin can execute actions on the DAO
- The DAO can update the plugin settings
- The DAO can upgrade the plugin

## Plugin Setup contract

Getting a plugin installed on a DAO requires two steps: 

1. An unprivileged step to prepare the plugin and request any privileged changes
2. An approval step after which, the DAO executes an action that applies the requested installation, upgrade or uninstallation

This requires that there is a contract that acts as the install script. It receives the parameters that the deployer wants the new plugin to have, it deploys the new instances and requests the permissions that the new plugin will need to be fully operational.

As soon as the installation is applied by the DAO, the plugin can be considered as installed. 

[Learn more](https://devs.aragon.org/docs/osx/how-to-guides/plugin-development/upgradeable-plugin/setup)

### Installing plugins when deploying the DAO

This is taken care by the `DAOFactory`. The DAO creator calls `daoFactory.createDao()`:

- The call contains:
  - The DAO settings
  - An array with the details and the settings of the desired plugins
- The method will deploy a new DAO and set itself as ROOT
- It will then call `prepareInstallation()` on all plugins and `applyInstallation()` right away
- It will finally drop `ROOT_PERMISSION` on itself

[See a JS example of installing plugins during a DAO's deployment](https://devs.aragon.org/docs/sdk/examples/client/create-dao#create-a-dao)

### Installing plugins afterwards

Plugin changes need a proposal to be passed when the DAO already exists.

1. Calling `pluginSetup.prepareInstallation()`
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
- `PROPOSER_PERMISSION_ID` is required to be able to create optimistic proposals on the governance plugin

Other DAO specific permissions:

- `UPGRADE_DAO_PERMISSION`
- `SET_METADATA_PERMISSION`
- `SET_TRUSTED_FORWARDER_PERMISSION`
- `SET_SIGNATURE_VALIDATOR_PERMISSION`
- `REGISTER_STANDARD_CALLBACK_PERMISSION`

### Encoding and decoding actions

Making calls to the DAO is straightforward, however making execute arbitrary actions requires them to be encoded, stored on chain and be approved before they can be executed.

To this end, the DAO has a struct called `Action { to, value, data }`, which will make the DAO call the `to` address, with `value` ether and call the given calldata (if any). Such calldata is an ABI encoded array of bytes with the function to call and the parameters it needs. 

### Deploying a DAO

The recommended way to create a DAO is by using `@aragon/sdk-client`. It uses the `DAOFactory` under the hood and it reduces the amount of low level interactions with the protocol.

[See an example](https://devs.aragon.org/docs/sdk/examples/client/create-dao)

In the example, the code is making use of the existing JS client for [Aragon's Token Voting plugin](https://github.com/aragon/sdk/tree/develop/modules/client/src/tokenVoting). They encapsulate all the Typechain and Subgraph calls and provide a high level library.

#### Installation parameters

In order for the PluginSetup contract to receive an arbitrary set of parameters, `prepareInstallation(address dao, bytes memory installationParameters)` needs to receive an ABI encoded byte array as the second argument.

To this end, the plugin provides a helper called `encodeInstallationParams()`, which receives the specific parameters for this plugin and returns a standard `bytes memory` that can later be passed around and decoded. 

JS clients also need to be able to handle data related to installations and uninstallations. To this end, every contract has a build metadata file containing the ABI of the parameters that need to be passed. 
- The format of these settings is defined in the `src/metadata/*-build.metadata.json` file.
- See `OptimisticTokenVotingPluginSetup::prepareInstallation()` as well.

The PluginSetup's `prepareInstallation()` will typically create a new instance of the plugin and call the  `initialize()` method, which acts as the constructor. This method will also be passed the DAO's address, in adition to its respective `bytes memory data` parameter, with all the initial settings, again ABI-encoded. The parameters for the plugin `initialize` function don't have to be necessarily the same as the ones for the PluginSetup.

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

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Example.s.sol:ExampleScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
