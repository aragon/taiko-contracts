# Test tree definitions

Below is the graphical definition of the contract tests implemented on [the test folder](./test)

```
EmergencyMultisigTest
├── Given a newly deployed contract
│   └── Given calling initialize
│       ├── It should initialize the first time
│       ├── It should refuse to initialize again
│       ├── It should set the DAO address
│       ├── It should set the minApprovals
│       ├── It should set onlyListed
│       ├── It should set signerList
│       ├── It should set proposalExpirationPeriod
│       ├── It should emit MultisigSettingsUpdated
│       ├── When minApprovals is greater than signerList length on initialize
│       │   ├── It should revert
│       │   ├── It should revert (with onlyListed false)
│       │   └── It should not revert otherwise
│       ├── When minApprovals is zero on initialize
│       │   ├── It should revert
│       │   ├── It should revert (with onlyListed false)
│       │   └── It should not revert otherwise
│       └── When signerList is invalid on initialize
│           └── It should revert
├── When calling upgradeTo
│   ├── It should revert when called without the permission
│   └── It should work when called with the permission
├── When calling upgradeToAndCall
│   ├── It should revert when called without the permission
│   └── It should work when called with the permission
├── When calling supportsInterface
│   ├── It does not support the empty interface
│   ├── It supports IERC165Upgradeable
│   ├── It supports IPlugin
│   ├── It supports IProposal
│   └── It supports IEmergencyMultisig
├── When calling updateSettings
│   ├── Given caller has no permission
│   │   ├── It should revert
│   │   └── It otherwise it should just work
│   ├── It should set the minApprovals
│   ├── It should set onlyListed
│   ├── It should set signerList
│   ├── It should set proposalExpirationPeriod
│   ├── It should emit MultisigSettingsUpdated
│   ├── When minApprovals is greater than signerList length on updateSettings
│   │   ├── It should revert
│   │   ├── It should revert (with onlyListed false)
│   │   └── It should not revert otherwise
│   ├── When minApprovals is zero on updateSettings
│   │   ├── It should revert
│   │   ├── It should revert (with onlyListed false)
│   │   └── It should not revert otherwise
│   └── When signerList is invalid on updateSettings
│       └── It should revert
├── When calling createProposal
│   ├── It increments the proposal counter
│   ├── It creates and return unique proposal IDs
│   ├── It emits the ProposalCreated event
│   ├── It creates a proposal with the given values
│   ├── Given settings changed on the same block
│   │   ├── It reverts
│   │   └── It does not revert otherwise
│   ├── Given onlyListed is false
│   │   └── It allows anyone to create
│   ├── Given onlyListed is true
│   │   ├── Given creation caller is not listed or appointed
│   │   │   └── It reverts
│   │   ├── Given creation caller is appointed by a former signer
│   │   │   └── It reverts
│   │   ├── Given creation caller is listed and self appointed
│   │   │   └── It creates the proposal
│   │   ├── Given creation caller is listed appointing someone else now
│   │   │   └── It creates the proposal
│   │   └── Given creation caller is appointed by a current signer
│   │       └── It creates the proposal
│   ├── Given approveProposal is true
│   │   └── It creates and calls approval in one go
│   └── Given approveProposal is false
│       └── It only creates the proposal
├── When calling hashActions
│   ├── It returns the right result
│   ├── It reacts to any of the values changing
│   └── It same input produces the same output
├── Given The proposal is not created
│   ├── When calling getProposal uncreated
│   │   └── It should return empty values
│   ├── When calling canApprove and approve uncreated
│   │   ├── It canApprove should return false (when currently listed and self appointed)
│   │   ├── It approve should revert (when currently listed and self appointed)
│   │   ├── It canApprove should return false (when currently listed, appointing someone else now)
│   │   ├── It approve should revert (when currently listed, appointing someone else now)
│   │   ├── It canApprove should return false (when appointed by a listed signer)
│   │   ├── It approve should revert (when appointed by a listed signer)
│   │   ├── It canApprove should return false (when currently unlisted and unappointed)
│   │   └── It approve should revert (when currently unlisted and unappointed)
│   ├── When calling hasApproved uncreated
│   │   └── It hasApproved should always return false
│   └── When calling canExecute and execute uncreated
│       └── It canExecute should always return false
├── Given The proposal is open
│   ├── When calling getProposal open
│   │   └── It should return the right values
│   ├── When calling canApprove and approve open
│   │   ├── It canApprove should return true (when listed on creation, self appointed now)
│   │   ├── It approve should work (when listed on creation, self appointed now)
│   │   ├── It approve should emit an event (when listed on creation, self appointed now)
│   │   ├── It canApprove should return false (when listed on creation, appointing someone else now)
│   │   ├── It approve should revert (when listed on creation, appointing someone else now)
│   │   ├── It canApprove should return true (when currently appointed by a signer listed on creation)
│   │   ├── It approve should work (when currently appointed by a signer listed on creation)
│   │   ├── It approve should emit an event (when currently appointed by a signer listed on creation)
│   │   ├── It canApprove should return false (when unlisted on creation, unappointed now)
│   │   └── It approve should revert (when unlisted on creation, unappointed now)
│   ├── When calling hasApproved open
│   │   └── It hasApproved should return false until approved
│   └── When calling canExecute and execute open
│       ├── It canExecute should return false (when listed on creation, self appointed now)
│       ├── It execute should revert (when listed on creation, self appointed now)
│       ├── It canExecute should return false (when listed on creation, appointing someone else now)
│       ├── It execute should revert (when listed on creation, appointing someone else now)
│       ├── It canExecute should return false (when currently appointed by a signer listed on creation)
│       ├── It execute should revert (when currently appointed by a signer listed on creation)
│       ├── It canExecute should return false (when unlisted on creation, unappointed now)
│       └── It execute should revert (when unlisted on creation, unappointed now)
├── Given The proposal was approved by the address
│   ├── When calling getProposal approved
│   │   └── It should return the right values
│   ├── When calling canApprove and approve approved
│   │   ├── It canApprove should return false (when listed on creation, self appointed now)
│   │   ├── It approve should revert (when listed on creation, self appointed now)
│   │   ├── It canApprove should return false (when currently appointed by a signer listed on creation)
│   │   └── It approve should revert (when currently appointed by a signer listed on creation)
│   ├── When calling hasApproved approved
│   │   └── It hasApproved should return false until approved
│   └── When calling canExecute and execute approved
│       ├── It canExecute should return false (when listed on creation, self appointed now)
│       ├── It execute should revert (when listed on creation, self appointed now)
│       ├── It canExecute should return false (when currently appointed by a signer listed on creation)
│       └── It execute should revert (when currently appointed by a signer listed on creation)
├── Given The proposal passed
│   ├── When calling getProposal passed
│   │   └── It should return the right values
│   ├── When calling canApprove and approve passed
│   │   ├── It canApprove should return false (when listed on creation, self appointed now)
│   │   ├── It approve should revert (when listed on creation, self appointed now)
│   │   ├── It canApprove should return false (when listed on creation, appointing someone else now)
│   │   ├── It approve should revert (when listed on creation, appointing someone else now)
│   │   ├── It canApprove should return false (when currently appointed by a signer listed on creation)
│   │   ├── It approve should revert (when currently appointed by a signer listed on creation)
│   │   ├── It canApprove should return false (when unlisted on creation, unappointed now)
│   │   └── It approve should revert (when unlisted on creation, unappointed now)
│   ├── When calling hasApproved passed
│   │   └── It hasApproved should return false until approved
│   ├── When calling canExecute and execute with modified data passed
│   │   ├── It execute should revert with modified metadata
│   │   ├── It execute should revert with modified actions
│   │   └── It execute should work with matching data
│   ├── When calling canExecute and execute passed
│   │   ├── It canExecute should return true, always
│   │   ├── It execute should work, when called by anyone with the actions
│   │   ├── It execute should emit an event, when called by anyone with the actions
│   │   ├── It execute recreates the proposal on the destination plugin
│   │   ├── It The parameters of the recreated proposal match the hash of the executed one
│   │   ├── It A ProposalCreated event is emitted on the destination plugin
│   │   └── It Execution is immediate on the destination plugin
│   └── Given TaikoL1 is incompatible
│       └── It executes successfully, regardless
├── Given The proposal is already executed
│   ├── When calling getProposal executed
│   │   └── It should return the right values
│   ├── When calling canApprove and approve executed
│   │   ├── It canApprove should return false (when listed on creation, self appointed now)
│   │   ├── It approve should revert (when listed on creation, self appointed now)
│   │   ├── It canApprove should return false (when listed on creation, appointing someone else now)
│   │   ├── It approve should revert (when listed on creation, appointing someone else now)
│   │   ├── It canApprove should return false (when currently appointed by a signer listed on creation)
│   │   ├── It approve should revert (when currently appointed by a signer listed on creation)
│   │   ├── It canApprove should return false (when unlisted on creation, unappointed now)
│   │   └── It approve should revert (when unlisted on creation, unappointed now)
│   ├── When calling hasApproved executed
│   │   └── It hasApproved should return false until approved
│   └── When calling canExecute and execute executed
│       ├── It canExecute should return false (when listed on creation, self appointed now)
│       ├── It execute should revert (when listed on creation, self appointed now)
│       ├── It canExecute should return false (when listed on creation, appointing someone else now)
│       ├── It execute should revert (when listed on creation, appointing someone else now)
│       ├── It canExecute should return false (when currently appointed by a signer listed on creation)
│       ├── It execute should revert (when currently appointed by a signer listed on creation)
│       ├── It canExecute should return false (when unlisted on creation, unappointed now)
│       └── It execute should revert (when unlisted on creation, unappointed now)
└── Given The proposal expired
    ├── When calling getProposal expired
    │   └── It should return the right values
    ├── When calling canApprove and approve expired
    │   ├── It canApprove should return false (when listed on creation, self appointed now)
    │   ├── It approve should revert (when listed on creation, self appointed now)
    │   ├── It canApprove should return false (when listed on creation, appointing someone else now)
    │   ├── It approve should revert (when listed on creation, appointing someone else now)
    │   ├── It canApprove should return false (when currently appointed by a signer listed on creation)
    │   ├── It approve should revert (when currently appointed by a signer listed on creation)
    │   ├── It canApprove should return false (when unlisted on creation, unappointed now)
    │   └── It approve should revert (when unlisted on creation, unappointed now)
    ├── When calling hasApproved expired
    │   └── It hasApproved should return false until approved
    └── When calling canExecute and execute expired
        ├── It canExecute should return false (when listed on creation, self appointed now)
        ├── It execute should revert (when listed on creation, self appointed now)
        ├── It canExecute should return false (when listed on creation, appointing someone else now)
        ├── It execute should revert (when listed on creation, appointing someone else now)
        ├── It canExecute should return false (when currently appointed by a signer listed on creation)
        ├── It execute should revert (when currently appointed by a signer listed on creation)
        ├── It canExecute should return false (when unlisted on creation, unappointed now)
        └── It execute should revert (when unlisted on creation, unappointed now)
```

```
MultisigTest
├── Given a newly deployed contract
│   └── Given calling initialize
│       ├── It should initialize the first time
│       ├── It should refuse to initialize again
│       ├── It should set the DAO address
│       ├── It should set the minApprovals
│       ├── It should set onlyListed
│       ├── It should set signerList
│       ├── It should set destinationProposalDuration
│       ├── It should set proposalExpirationPeriod
│       ├── It should emit MultisigSettingsUpdated
│       ├── When minApprovals is greater than signerList length on initialize
│       │   ├── It should revert
│       │   ├── It should revert (with onlyListed false)
│       │   └── It should not revert otherwise
│       ├── When minApprovals is zero on initialize
│       │   ├── It should revert
│       │   ├── It should revert (with onlyListed false)
│       │   └── It should not revert otherwise
│       └── When signerList is invalid on initialize
│           └── It should revert
├── When calling upgradeTo
│   ├── It should revert when called without the permission
│   └── It should work when called with the permission
├── When calling upgradeToAndCall
│   ├── It should revert when called without the permission
│   └── It should work when called with the permission
├── When calling supportsInterface
│   ├── It does not support the empty interface
│   ├── It supports IERC165Upgradeable
│   ├── It supports IPlugin
│   ├── It supports IProposal
│   └── It supports IMultisig
├── When calling updateSettings
│   ├── Given caller has no permission
│   │   ├── It should revert
│   │   └── It otherwise it should just work
│   ├── It should set the minApprovals
│   ├── It should set onlyListed
│   ├── It should set signerList
│   ├── It should set destinationProposalDuration
│   ├── It should set proposalExpirationPeriod
│   ├── It should emit MultisigSettingsUpdated
│   ├── When minApprovals is greater than signerList length on updateSettings
│   │   ├── It should revert
│   │   ├── It should revert (with onlyListed false)
│   │   └── It should not revert otherwise
│   ├── When minApprovals is zero on updateSettings
│   │   ├── It should revert
│   │   ├── It should revert (with onlyListed false)
│   │   └── It should not revert otherwise
│   └── When signerList is invalid on updateSettings
│       └── It should revert
├── When calling createProposal
│   ├── It increments the proposal counter
│   ├── It creates and return unique proposal IDs
│   ├── It emits the ProposalCreated event
│   ├── It creates a proposal with the given values
│   ├── Given settings changed on the same block
│   │   ├── It reverts
│   │   └── It does not revert otherwise
│   ├── Given onlyListed is false
│   │   └── It allows anyone to create
│   ├── Given onlyListed is true
│   │   ├── Given creation caller is not listed or appointed
│   │   │   └── It reverts
│   │   ├── Given creation caller is appointed by a former signer
│   │   │   └── It reverts
│   │   ├── Given creation caller is listed and self appointed
│   │   │   └── It creates the proposal
│   │   ├── Given creation caller is listed appointing someone else now
│   │   │   └── It creates the proposal
│   │   └── Given creation caller is appointed by a current signer
│   │       └── It creates the proposal
│   ├── Given approveProposal is true
│   │   └── It creates and calls approval in one go
│   └── Given approveProposal is false
│       └── It only creates the proposal
├── Given The proposal is not created
│   ├── When calling getProposal uncreated
│   │   └── It should return empty values
│   ├── When calling canApprove and approve uncreated
│   │   ├── It canApprove should return false (when currently listed and self appointed)
│   │   ├── It approve should revert (when currently listed and self appointed)
│   │   ├── It canApprove should return false (when currently listed, appointing someone else now)
│   │   ├── It approve should revert (when currently listed, appointing someone else now)
│   │   ├── It canApprove should return false (when appointed by a listed signer)
│   │   ├── It approve should revert (when appointed by a listed signer)
│   │   ├── It canApprove should return false (when currently unlisted and unappointed)
│   │   └── It approve should revert (when currently unlisted and unappointed)
│   ├── When calling hasApproved uncreated
│   │   └── It hasApproved should always return false
│   └── When calling canExecute and execute uncreated
│       ├── It canExecute should return false (when currently listed and self appointed)
│       ├── It execute should revert (when currently listed and self appointed)
│       ├── It canExecute should return false (when currently listed, appointing someone else now)
│       ├── It execute should revert (when currently listed, appointing someone else now)
│       ├── It canExecute should return false (when appointed by a listed signer)
│       ├── It execute should revert (when appointed by a listed signer)
│       ├── It canExecute should return false (when currently unlisted and unappointed)
│       └── It execute should revert (when currently unlisted and unappointed)
├── Given The proposal is open
│   ├── When calling getProposal open
│   │   └── It should return the right values
│   ├── When calling canApprove and approve open
│   │   ├── It canApprove should return true (when listed on creation, self appointed now)
│   │   ├── It approve should work (when listed on creation, self appointed now)
│   │   ├── It approve should emit an event (when listed on creation, self appointed now)
│   │   ├── It canApprove should return false (when listed on creation, appointing someone else now)
│   │   ├── It approve should revert (when listed on creation, appointing someone else now)
│   │   ├── It canApprove should return true (when currently appointed by a signer listed on creation)
│   │   ├── It approve should work (when currently appointed by a signer listed on creation)
│   │   ├── It approve should emit an event (when currently appointed by a signer listed on creation)
│   │   ├── It canApprove should return false (when unlisted on creation, unappointed now)
│   │   └── It approve should revert (when unlisted on creation, unappointed now)
│   ├── When calling approve with tryExecution and almost passed open
│   │   ├── It approve should also execute the proposal
│   │   ├── It approve should emit an Executed event
│   │   ├── It approve recreates the proposal on the destination plugin
│   │   ├── It The parameters of the recreated proposal match those of the approved one
│   │   └── It A ProposalCreated event is emitted on the destination plugin
│   ├── When calling hasApproved open
│   │   └── It hasApproved should return false until approved
│   └── When calling canExecute and execute open
│       ├── It canExecute should return false (when listed on creation, self appointed now)
│       ├── It execute should revert (when listed on creation, self appointed now)
│       ├── It canExecute should return false (when listed on creation, appointing someone else now)
│       ├── It execute should revert (when listed on creation, appointing someone else now)
│       ├── It canExecute should return false (when currently appointed by a signer listed on creation)
│       ├── It execute should revert (when currently appointed by a signer listed on creation)
│       ├── It canExecute should return false (when unlisted on creation, unappointed now)
│       └── It execute should revert (when unlisted on creation, unappointed now)
├── Given The proposal was approved by the address
│   ├── When calling getProposal approved
│   │   └── It should return the right values
│   ├── When calling canApprove and approve approved
│   │   ├── It canApprove should return false (when listed on creation, self appointed now)
│   │   ├── It approve should revert (when listed on creation, self appointed now)
│   │   ├── It canApprove should return false (when currently appointed by a signer listed on creation)
│   │   └── It approve should revert (when currently appointed by a signer listed on creation)
│   ├── When calling hasApproved approved
│   │   └── It hasApproved should return false until approved
│   └── When calling canExecute and execute approved
│       ├── It canExecute should return false (when listed on creation, self appointed now)
│       ├── It execute should revert (when listed on creation, self appointed now)
│       ├── It canExecute should return false (when currently appointed by a signer listed on creation)
│       └── It execute should revert (when currently appointed by a signer listed on creation)
├── Given The proposal passed
│   ├── When calling getProposal passed
│   │   └── It should return the right values
│   ├── When calling canApprove and approve passed
│   │   ├── It canApprove should return false (when listed on creation, self appointed now)
│   │   ├── It approve should revert (when listed on creation, self appointed now)
│   │   ├── It canApprove should return false (when listed on creation, appointing someone else now)
│   │   ├── It approve should revert (when listed on creation, appointing someone else now)
│   │   ├── It canApprove should return false (when currently appointed by a signer listed on creation)
│   │   ├── It approve should revert (when currently appointed by a signer listed on creation)
│   │   ├── It canApprove should return false (when unlisted on creation, unappointed now)
│   │   └── It approve should revert (when unlisted on creation, unappointed now)
│   ├── When calling hasApproved passed
│   │   └── It hasApproved should return false until approved
│   ├── When calling canExecute and execute passed
│   │   ├── It canExecute should return true, always
│   │   ├── It execute should work, when called by anyone
│   │   ├── It execute should emit an event, when called by anyone
│   │   ├── It execute recreates the proposal on the destination plugin
│   │   ├── It The parameters of the recreated proposal match those of the executed one
│   │   ├── It The proposal duration on the destination plugin matches the multisig settings
│   │   └── It A ProposalCreated event is emitted on the destination plugin
│   └── Given TaikoL1 is incompatible
│       └── It executes successfully, regardless
├── Given The proposal is already executed
│   ├── When calling getProposal executed
│   │   └── It should return the right values
│   ├── When calling canApprove and approve executed
│   │   ├── It canApprove should return false (when listed on creation, self appointed now)
│   │   ├── It approve should revert (when listed on creation, self appointed now)
│   │   ├── It canApprove should return false (when listed on creation, appointing someone else now)
│   │   ├── It approve should revert (when listed on creation, appointing someone else now)
│   │   ├── It canApprove should return false (when currently appointed by a signer listed on creation)
│   │   ├── It approve should revert (when currently appointed by a signer listed on creation)
│   │   ├── It canApprove should return false (when unlisted on creation, unappointed now)
│   │   └── It approve should revert (when unlisted on creation, unappointed now)
│   ├── When calling hasApproved executed
│   │   └── It hasApproved should return false until approved
│   └── When calling canExecute and execute executed
│       ├── It canExecute should return false (when listed on creation, self appointed now)
│       ├── It execute should revert (when listed on creation, self appointed now)
│       ├── It canExecute should return false (when listed on creation, appointing someone else now)
│       ├── It execute should revert (when listed on creation, appointing someone else now)
│       ├── It canExecute should return false (when currently appointed by a signer listed on creation)
│       ├── It execute should revert (when currently appointed by a signer listed on creation)
│       ├── It canExecute should return false (when unlisted on creation, unappointed now)
│       └── It execute should revert (when unlisted on creation, unappointed now)
└── Given The proposal expired
    ├── When calling getProposal expired
    │   └── It should return the right values
    ├── When calling canApprove and approve expired
    │   ├── It canApprove should return false (when listed on creation, self appointed now)
    │   ├── It approve should revert (when listed on creation, self appointed now)
    │   ├── It canApprove should return false (when listed on creation, appointing someone else now)
    │   ├── It approve should revert (when listed on creation, appointing someone else now)
    │   ├── It canApprove should return false (when currently appointed by a signer listed on creation)
    │   ├── It approve should revert (when currently appointed by a signer listed on creation)
    │   ├── It canApprove should return false (when unlisted on creation, unappointed now)
    │   └── It approve should revert (when unlisted on creation, unappointed now)
    ├── When calling hasApproved expired
    │   └── It hasApproved should return false until approved
    └── When calling canExecute and execute expired
        ├── It canExecute should return false (when listed on creation, self appointed now)
        ├── It execute should revert (when listed on creation, self appointed now)
        ├── It canExecute should return false (when listed on creation, appointing someone else now)
        ├── It execute should revert (when listed on creation, appointing someone else now)
        ├── It canExecute should return false (when currently appointed by a signer listed on creation)
        ├── It execute should revert (when currently appointed by a signer listed on creation)
        ├── It canExecute should return false (when unlisted on creation, unappointed now)
        └── It execute should revert (when unlisted on creation, unappointed now)
```

```
SignerListTest
├── When deploying the contract
│   └── It should initialize normally
├── Given a deployed contract
│   └── It should refuse to initialize again
├── Given a new instance
│   └── Given calling initialize
│       ├── It should set the DAO address
│       ├── It should set the addresses as signers
│       ├── It settings should match the given ones
│       ├── It should emit the SignersAdded event
│       ├── It should emit the SignerListSettingsUpdated event
│       └── Given passing more addresses than supported
│           └── It should revert
├── When calling updateSettings
│   ├── When updateSettings without the permission
│   │   └── It should revert
│   ├── When encryptionRegistry is not compatible
│   │   └── It should revert
│   ├── When setting a minSignerListLength lower than the current list size
│   │   └── It should revert
│   ├── It set the new encryption registry
│   ├── It set the new minSignerListLength
│   └── It should emit a SignerListSettingsUpdated event
├── When calling supportsInterface
│   ├── It does not support the empty interface
│   ├── It supports IERC165Upgradeable
│   ├── It supports IPlugin
│   ├── It supports IProposal
│   └── It supports IMultisig
├── When calling addSigners
│   ├── When adding without the permission
│   │   └── It should revert
│   ├── Given passing more addresses than allowed
│   │   └── It should revert
│   ├── Given duplicate addresses
│   │   └── It should revert
│   ├── It should append the new addresses to the list
│   └── It should emit the SignersAddedEvent
├── When calling removeSigners
│   ├── When removing without the permission
│   │   └── It should revert
│   ├── When removing an unlisted address
│   │   └── It should continue gracefully
│   ├── Given removing too many addresses // The new list will be smaller than minSignerListLength
│   │   └── It should revert
│   ├── It should more the given addresses
│   └── It should emit the SignersRemovedEvent
├── When calling isListed
│   ├── Given the member is listed
│   │   └── It returns true
│   └── Given the member is not listed
│       └── It returns false
├── When calling isListedAtBlock
│   ├── Given the member was listed
│   │   ├── Given the member is not listed now
│   │   │   └── It returns true
│   │   └── Given the member is listed now
│   │       └── It returns true
│   └── Given the member was not listed
│       ├── Given the member is delisted now
│       │   └── It returns false
│       └── Given the member is enlisted now
│           └── It returns false
├── When calling resolveEncryptionAccountStatus
│   ├── Given the caller is a listed signer
│   │   ├── It ownerIsListed should be true
│   │   └── It isAppointed should be false
│   ├── Given the caller is appointed by a signer
│   │   ├── It ownerIsListed should be true
│   │   └── It isAppointed should be true
│   └── Given the caller is not listed or appointed
│       ├── It ownerIsListed should be false
│       └── It isAppointed should be false
├── When calling resolveEncryptionOwner
│   ├── Given the resolved owner is listed
│   │   ├── When the given address is appointed
│   │   │   ├── It owner should be the resolved owner
│   │   │   └── It appointedWallet should be the caller
│   │   └── When the given address is not appointed
│   │       ├── It owner should be the caller
│   │       └── It appointedWallet should be resolved appointed wallet
│   └── Given the resolved owner is not listed
│       ├── It should return a zero owner
│       └── It should return a zero appointedWallet
└── When calling getEncryptionRecipients
    ├── Given the encryption registry has no accounts
    │   ├── It returns an empty list, even with signers
    │   └── It returns an empty list, without signers
    └── Given the encryption registry has accounts
        ├── Given no overlap between registry and signerList // Some are on the encryption registry only and some are on the signerList only
        │   └── It returns an empty list
        └── Given some addresses are registered everywhere
            ├── It returns a list containing the overlapping addresses
            ├── It the result has the correct resolved addresses // appointed wallets are present, not the owner
            ├── It result does not contain unregistered addresses
            ├── It result does not contain unlisted addresses
            └── It result does not contain non appointed addresses
```

