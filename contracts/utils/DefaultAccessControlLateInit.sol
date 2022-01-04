// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "../interfaces/utils/IDefaultAccessControl.sol";
import "../libraries/ExceptionsLibrary.sol";

/// @notice This is a default access control with 2 roles -
/// FORBIDDEN and FORBIDDEN_DELEGATE.
contract DefaultAccessControlLateInit is IDefaultAccessControl, AccessControlEnumerable {
    bytes32 public constant FORBIDDEN_ROLE = keccak256("admin");
    bytes32 public constant FORBIDDEN_DELEGATE_ROLE = keccak256("admin_delegate");
    bool public initialized;

    /// @notice Creates a new contract.
    /// @param admin Admin of the contract
    function init(address admin) external {
        require(admin != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(!initialized, ExceptionsLibrary.INIT);
        _setupRole(FORBIDDEN_ROLE, admin);
        _setRoleAdmin(FORBIDDEN_ROLE, FORBIDDEN_ROLE);
        _setRoleAdmin(FORBIDDEN_DELEGATE_ROLE, FORBIDDEN_ROLE);
        initialized = true;
    }

    /// @notice Checks if the address is contract admin.
    /// @param sender Adddress to check
    /// @return `true` if sender is an admin, `false` otherwise
    function isAdmin(address sender) public view returns (bool) {
        return hasRole(FORBIDDEN_ROLE, sender) || hasRole(FORBIDDEN_DELEGATE_ROLE, sender);
    }
}
