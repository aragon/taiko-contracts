// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

interface IEncryptionRegistry {
    /// @notice Emitted when a public key is defined
    event PublicKeySet(address account, bytes32 publicKey);

    /// @notice Emitted when an externally owned wallet is appointed as the encryption agent
    event AgentAppointed(address account, address agent);

    /// @notice Raised when the caller is not an addresslist member
    error MustBeListed();

    /// @notice Raised when attempting to register a contract instead of a wallet
    error CannotAppointContracts();

    /// @notice Raised when attempting to appoint an address which is already a listed signer
    error AlreadyListed();

    /// @notice Raised when attempting to appoint an already appointed address
    error AlreadyAppointed();

    /// @notice Raised when a wallet not appointed as an agent tries to define a public key
    error MustBeAppointed();

    /// @notice Raised when an agent is appointed and the account owner tries to override the account's public key. The appointed value should be set to address(0) or msg.sender first.
    error MustResetAppointedAgent();

    /// @notice Raised when the caller is not an AddressList compatible contract
    error InvalidAddressList();

    /// @notice Registers the given address as the account's encryption agent. This allows smart contract accounts to appoint an EOA that can decrypt data on their behalf.
    /// @dev NOTE: calling this function will wipe any previously registered public key.
    /// @param newAgent The address of an EOA to define as the new agent.
    function appointAgent(address newAgent) external;

    /// @notice Registers the given public key as the account's target for decrypting messages.
    /// @dev NOTE: Calling this function from a smart contracts will revert.
    /// @param publicKey The libsodium public key to register
    function setOwnPublicKey(bytes32 publicKey) external;

    /// @notice Registers the given public key as the agent's target for decrypting messages. Only if the sender is an appointed agent.
    /// @param accountOwner The address of the account to set the public key for. The sender must be appointed or the transaction will revert.
    /// @param publicKey The libsodium public key to register
    function setPublicKey(address accountOwner, bytes32 publicKey) external;

    /// @notice Returns the address of the account that appointed the given agent, if any.
    /// @return owner The address of the owner who appointed the given agent, or zero.
    function appointerOf(address agent) external returns (address owner);

    /// @notice Returns the address of the account registered at the given index
    function accountList(uint256) external view returns (address);

    /// @notice Returns the list of addresses on the registry
    /// @dev Use this function to get all addresses in a single call. You can still call accountList[idx] to resolve them one by one.
    function getRegisteredAccounts() external view returns (address[] memory);

    /// @notice Returns the address of the account's encryption agent, or the account itself if no agent is appointed.
    function getAppointedAgent(address account) external view returns (address agent);
}
