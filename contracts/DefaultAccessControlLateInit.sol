// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "./interfaces/IDefaultAccessControl.sol";
import "./libraries/ExceptionsLibrary.sol";

/// @notice This is a default access control with 2 roles -
/// ADMIN and ADMIN_DELEGATE.
contract DefaultAccessControlLateInit is IDefaultAccessControl, AccessControlEnumerable {
    bytes32 public constant ADMIN_ROLE = keccak256("admin");
    bytes32 public constant ADMIN_DELEGATE_ROLE = keccak256("admin_delegate");
    bool public initialized;

    /// @notice Creates a new contract.
    /// @param admin Admin of the contract
    function init(address admin) external {
        require(admin != address(0), ExceptionsLibrary.ADMIN_ADDRESS_ZERO);
        require(!initialized, ExceptionsLibrary.INIT);
        _setupRole(ADMIN_ROLE, admin);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ADMIN_DELEGATE_ROLE, ADMIN_ROLE);
        initialized = true;
    }

    /// @notice Checks if the address is contract admin.
    /// @param sender Adddress to check
    /// @return `true` if sender is an admin, `false` otherwise
    function isAdmin(address sender) public view returns (bool) {
        return hasRole(ADMIN_ROLE, sender) || hasRole(ADMIN_DELEGATE_ROLE, sender);
    }
}
