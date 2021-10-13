// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract VaultAccessControl is AccessControlEnumerable {
    bytes32 internal constant GOVERNANCE_ROLE = keccak256("governance");
    bytes32 internal constant GOVERNANCE_DELEGATE_ROLE = keccak256("governance_delegate");

    constructor() {
        _setupRole(GOVERNANCE_ROLE, _msgSender());
        _setRoleAdmin(GOVERNANCE_ROLE, GOVERNANCE_ROLE);
        _setupRole(GOVERNANCE_DELEGATE_ROLE, _msgSender());
        _setRoleAdmin(GOVERNANCE_DELEGATE_ROLE, GOVERNANCE_ROLE);
    }

    function _isGovernanceOrDelegate() internal view returns (bool) {
        return hasRole(GOVERNANCE_ROLE, _msgSender()) || hasRole(GOVERNANCE_DELEGATE_ROLE, _msgSender());
    }

    function _isGovernance() internal view returns (bool) {
        return hasRole(GOVERNANCE_ROLE, _msgSender());
    }
}
