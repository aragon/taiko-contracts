// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

interface ISignerList {
    /// @notice Emitted when signers are added to the DAO plugin.
    /// @param signers The list of new signers being added.
    event SignersAdded(address[] signers);

    /// @notice Emitted when signers are removed from the DAO plugin.
    /// @param signers The list of existing signers being removed.
    event SignersRemoved(address[] signers);

    /// @notice Adds new signers to the address list. Previously, it checks if the new address list length would be greater than `type(uint16).max`, the maximal number of approvals.
    /// @param signers The addresses of the signers to be added.
    function addSigners(address[] calldata signers) external;

    /// @notice Removes existing signers from the address list. Previously, it checks if the new address list length is at least as long as the minimum approvals parameter requires. Note that `minApprovals` is must be at least 1 so the address list cannot become empty.
    /// @param signers The addresses of the signers to be removed.
    function removeSigners(address[] calldata signers) external;

    /// @notice Given an address, determines whether it is a listed signer or a wallet appointed by a listed owner.
    /// @dev NOTE: This function will only resolve based on the current state. Do not use it as an alias of `isListedAtBock()`.
    /// @return listedOrAppointedByListed If resolved, whether the given address is currently listed as a member. False otherwise.
    function isListedOrAppointedByListed(address _address) external returns (bool listedOrAppointedByListed);

    /// @notice Given an address, determines the corresponding (listed) owner account and the appointed agent, if any.
    /// @param addr The address to check within the list of signers or appointed agents.
    /// @param blockNumber The block at which the list should be checked
    /// @return owner If resolved to an account, it contains the encryption owner's address. Returns address(0) otherwise.
    function getListedEncryptionOwnerAtBlock(address addr, uint256 blockNumber) external returns (address owner);

    /// @notice Given an address, determines the corresponding (listed) owner account and the appointed agent, if any.
    /// @param addr The address to check within the list of signers or appointed agents.
    /// @param blockNumber The block at which the list should be checked
    /// @return owner If addr is listed or appointed, it contains the encryption owner's address. Returns address(0) otherwise.
    /// @return agent If addr is listed or appointed, it contains the appointed agent's address, if any. Returns address(0) otherwise.
    function resolveEncryptionAccountAtBlock(address addr, uint256 blockNumber)
        external
        returns (address owner, address agent);

    /// @notice Among the SignerList's members registered on the EncryptionRegistry, return the effective address they use for encryption
    function getEncryptionAgents() external view returns (address[] memory);
}
