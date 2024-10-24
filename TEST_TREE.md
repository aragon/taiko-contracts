# Test tree definitions

Below is the graphical definition of the contract tests implemented on [the test folder](./test)

```
SignerListTest
├── When deploying the contract
│   └── It should initialize normally
├── Given a deployed contract
│   └── It should fail to initialize again
├── Given a new instance
│   └── Given calling initialize
│       ├── It should set the DAO address
│       ├── It should set the addresses as signers
│       ├── It settings should match the given ones
│       ├── It should emit the SignersAdded event
│       ├── It should emit the SignerListSettingsUpdated event
│       └── Given passing more addresses than supported
│           └── It should revert
├── When calling addSigners
│   ├── When addSigners without the permission
│   │   └── It should revert
│   ├── Given passing more addresses than allowed
│   │   └── It should revert
│   ├── Given duplicate addresses
│   │   └── It should revert
│   ├── It should append the new addresses to the list
│   └── It should emit the SignersAddedEvent
├── When calling removeSigners
│   ├── When removeSigners without the permission
│   │   └── It should revert
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
├── When calling getEncryptionRecipients
│   ├── Given the encryption registry has no accounts
│   │   ├── It returns an empty list, even with signers
│   │   └── It returns an empty list, without signers
│   └── Given the encryption registry has accounts
│       ├── Given no overlap between registry and signerList // Some are on the encryption registry only and some are on the signerList only
│       │   └── It returns an empty list
│       └── Given some addresses are registered everywhere
│           ├── It returns a list containing the overlapping addresses
│           ├── It the result has the correct resolved addresses // appointed wallets are present, not the owner
│           ├── It result does not contain unregistered addresses
│           ├── It result does not contain unlisted addresses
│           └── It result does not contain non appointed addresses
└── When calling supportsInterface
    ├── It supports ISignerList
    ├── It supports Addresslist
    └── It supports the parents interfaces
```

