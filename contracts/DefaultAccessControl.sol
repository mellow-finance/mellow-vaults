// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract DefaultAccessControl is AccessControlEnumerable {
    bytes32 internal constant SUPER_ADMIN_ROLE = keccak256("super_admin");
    bytes32 internal constant SUPER_ADMIN_DELEGATE_ROLE = keccak256("super_admin_delegate");
    bytes32 internal constant ADMIN_ROLE = keccak256("admin");

    constructor(address superAdmin, address admin) {
        _setupRole(SUPER_ADMIN_ROLE, superAdmin);
        _setupRole(SUPER_ADMIN_DELEGATE_ROLE, superAdmin);
        if (admin != address(0)) {
            _setupRole(ADMIN_ROLE, admin);
        }
        _setRoleAdmin(SUPER_ADMIN_ROLE, SUPER_ADMIN_ROLE);
        _setRoleAdmin(SUPER_ADMIN_DELEGATE_ROLE, SUPER_ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, SUPER_ADMIN_DELEGATE_ROLE);
    }

    function _isAdmin() internal view returns (bool) {
        return hasRole(ADMIN_ROLE, _msgSender()) || _isSuperAdmin();
    }

    function _isSuperAdmin() internal view returns (bool) {
        return hasRole(SUPER_ADMIN_ROLE, _msgSender()) || hasRole(SUPER_ADMIN_DELEGATE_ROLE, _msgSender());
    }

    function _isGovernance() internal view returns (bool) {
        return hasRole(SUPER_ADMIN_ROLE, _msgSender());
    }

    function governance() public view returns (address) {
        return getRoleMember(SUPER_ADMIN_ROLE, 0);
    }
}
