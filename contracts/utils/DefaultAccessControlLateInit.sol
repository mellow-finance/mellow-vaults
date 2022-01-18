// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "../interfaces/utils/IDefaultAccessControl.sol";
import "../libraries/ExceptionsLibrary.sol";

/// @notice This is a default access control with 2 roles -
/// FORBIDDEN and FORBIDDEN_DELEGATE.
contract DefaultAccessControlLateInit is IDefaultAccessControl, AccessControlEnumerable {
    bool public initialized;

    bytes32 public constant OPERATOR = keccak256("operator");
    bytes32 public constant ADMIN_ROLE = keccak256("admin");
    bytes32 public constant ADMIN_DELEGATE_ROLE = keccak256("admin_delegate");

    // -------------------------  EXTERNAL, VIEW  ------------------------------

    /// @notice Checks if the address is contract admin.
    /// @param sender Adddress to check
    /// @return `true` if sender is an admin, `false` otherwise
    function isAdmin(address sender) public view returns (bool) {
        return hasRole(ADMIN_ROLE, sender) || hasRole(ADMIN_DELEGATE_ROLE, sender);
    }

    function isOperator(address sender) public view returns (bool) {
        return hasRole(OPERATOR, sender);
    }

    // -------------------------  EXTERNAL, MUTATING  ------------------------------

    /// @notice Creates a new contract.
    /// @param admin Admin of the contract
    function init(address admin) external {
        require(admin != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(!initialized, ExceptionsLibrary.INIT);
        
        _setupRole(OPERATOR, admin);
        _setupRole(ADMIN_ROLE, admin);

        _setRoleAdmin(OPERATOR, ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ADMIN_DELEGATE_ROLE, ADMIN_ROLE);

        initialized = true;
    }
}
