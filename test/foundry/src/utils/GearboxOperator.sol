// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "../interfaces/vaults/IGearboxRootVault.sol";
import "./DefaultAccessControl.sol";

contract GearboxOperator is DefaultAccessControl {
    IGearboxRootVault public immutable rootVault;

    constructor(address admin, address rootVault_) DefaultAccessControl(admin) {
        rootVault = IGearboxRootVault(rootVault_);
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    function shutdown() external {
        _requireAtLeastOperator();
        rootVault.shutdown();
    }

    function reopen() external {
        _requireAtLeastOperator();
        rootVault.reopen();
    }

    function addDepositorsToAllowlist(address[] calldata depositors) external {
        _requireAtLeastOperator();
        rootVault.addDepositorsToAllowlist(depositors);
    }

    function removeDepositorsFromAllowlist(address[] calldata depositors) external {
        _requireAtLeastOperator();
        rootVault.removeDepositorsFromAllowlist(depositors);
    }

    function invokeExecution() external {
        _requireAtLeastOperator();
        rootVault.invokeExecution();
    }
}
