// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract OwnerAccessControl is AccessControlEnumerable {
    bytes32 internal constant OWNER_ROLE = keccak256("owner");

    constructor() {
        _setupRole(OWNER_ROLE, _msgSender());
        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);
    }

    function _requireOwner() internal view {
        require(hasRole(OWNER_ROLE, _msgSender()), "RO");
    }
}
