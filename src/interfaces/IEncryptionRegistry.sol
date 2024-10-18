// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

interface IEncryptionRegistry {
    /// @notice Emitted when a public key is defined
    event PublicKeySet(address account, bytes32 publicKey);

    /// @notice Emitted when an externally owned wallet is appointed
    event WalletAppointed(address account, address appointedWallet);

    /// @notice Raised when the caller is not an addresslist member
    error MustBeListed();

    /// @notice Raised when attempting to register a contract instead of a wallet
    error CannotAppointContracts();

    /// @notice Raised when attempting to appoint an already appointed address
    error AlreadyAppointed();

    /// @notice Raised when a non appointed wallet tries to define the public key
    error MustBeAppointed();

    /// @notice Raised when an account attempts to define the public key of the appointed wallet
    error CannotSetPubKeyForAppointedWallets();

    /// @notice Raised when the caller is not an addresslist compatible contract
    error InvalidAddressList();

    /// @notice Registers the externally owned wallet's address to use for encryption. This allows smart contracts to appoint an EOA that can decrypt data.
    /// @dev NOTE: calling this function will wipe any existing public key previously registered.
    function appointWallet(address newWallet) external;

    /// @notice Registers the given public key as the account's target for decrypting messages.
    /// @dev NOTE: Calling this function from a smart contracts will revert.
    function setOwnPublicKey(bytes32 publicKey) external;

    /// @notice Registers the given public key as the member's target for decrypting messages. Only if the sender is appointed.
    /// @param account The address of the account to set the public key for. The sender must be appointed or the transaction will revert.
    /// @param publicKey The libsodium public key to register
    function setPublicKey(address account, bytes32 publicKey) external;

    /// @notice Returns the address of the account that appointed the given wallet, if any.
    /// @return appointerAddress The address of the appointer account or zero.
    function appointedBy(address wallet) external returns (address appointerAddress);

    /// @notice Returns the list of addresses on the registry
    /// @dev Use this function to get all addresses in a single call. You can still call registeredAccounts[idx] to resolve them one by one.
    function getRegisteredAccounts() external view returns (address[] memory);

    /// @notice Returns the address of the wallet appointed for encryption purposes
    function getAppointedWallet(address member) external view returns (address);
}
