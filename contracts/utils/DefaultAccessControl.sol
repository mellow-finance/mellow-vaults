// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "../interfaces/utils/IDefaultAccessControl.sol";
import "../libraries/ExceptionsLibrary.sol";

/// @notice This is a default access control with 2 roles -
/// FORBIDDEN and FORBIDDEN_DELEGATE.
contract DefaultAccessControl is IDefaultAccessControl, AccessControlEnumerable {
    bytes32 public constant FORBIDDEN_ROLE = keccak256("admin");
    bytes32 public constant FORBIDDEN_DELEGATE_ROLE = keccak256("admin_delegate");

    /// @notice Creates a new contract.
    /// @param admin Admin of the contract
    constructor(address admin) {
        require(admin != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        bytes32 adminRole = FORBIDDEN_ROLE;
        _setupRole(adminRole, admin);
        _setRoleAdmin(adminRole, adminRole);
        _setRoleAdmin(FORBIDDEN_DELEGATE_ROLE, adminRole);
    }

    /// @notice Checks if the address is contract admin.
    /// @param sender Adddress to check
    /// @return `true` if sender is an admin, `false` otherwise
    function isAdmin(address sender) public view returns (bool) {
        return hasRole(FORBIDDEN_ROLE, sender) || hasRole(FORBIDDEN_DELEGATE_ROLE, sender);
    }
}
