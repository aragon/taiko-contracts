// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IPermissionCondition} from "@aragon/osx/core/permission/IPermissionCondition.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {OptimisticTokenVotingPlugin} from "../OptimisticTokenVotingPlugin.sol";

/// @title PermissionCondition
/// @author Aragon Association - 2023-2024
/// @notice An abstract contract for non-upgradeable contracts instantiated via the `new` keyword  to inherit from to support customary permissions depending on arbitrary on-chain state.
contract StandardProposalCondition is ERC165, IPermissionCondition {
    uint64 minDuration;

    error EmptyDelay();

    /**
     *
     * @param _minDuration The minimum amount of seconds to enforce for proposals created
     */
    constructor(uint64 _minDuration) {
        if (_minDuration == 0) revert EmptyDelay();

        minDuration = _minDuration;
    }

    /// @notice Checks if an interface is supported by this or its parent contract.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return _interfaceId == type(IPermissionCondition).interfaceId || super.supportsInterface(_interfaceId);
    }

    function isGranted(address _where, address _who, bytes32 _permissionId, bytes calldata _data)
        external
        view
        returns (bool isPermitted)
    {
        (_where, _who, _permissionId);

        // Is it createProposal()?
        if (_getSelector(_data) != OptimisticTokenVotingPlugin.createProposal.selector) {
            return false;
        }

        // Decode proposal params
        (,,, uint64 _duration) = abi.decode(_data[4:], (bytes, IDAO.Action[], uint256, uint64));
        if (_duration < minDuration) return false;

        return true;
    }

    function _getSelector(bytes memory _data) internal pure returns (bytes4 selector) {
        // Slices are only supported for bytes calldata, not bytes memory
        // Bytes memory requires an assembly block
        assembly {
            selector := mload(add(_data, 0x20)) // 32
        }
    }
}
