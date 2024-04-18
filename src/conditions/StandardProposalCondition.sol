// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IPermissionCondition} from "@aragon/osx/core/permission/IPermissionCondition.sol";
// import {PermissionCondition} from "@aragon/osx/core/permission/PermissionCondition.sol";

/// @title PermissionCondition
/// @author Aragon Association - 2023
/// @notice An abstract contract for non-upgradeable contracts instantiated via the `new` keyword  to inherit from to support customary permissions depending on arbitrary on-chain state.
abstract contract StandardProposalCondition is ERC165, IPermissionCondition {
    /// @notice Checks if an interface is supported by this or its parent contract.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(
        bytes4 _interfaceId
    ) public view virtual override returns (bool) {
        return
            _interfaceId == type(IPermissionCondition).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    function isGranted(
        address _where,
        address _who,
        bytes32 _permissionId,
        bytes calldata _data
    ) external view returns (bool isPermitted) {
        // TODO
        return false;
    }
}
