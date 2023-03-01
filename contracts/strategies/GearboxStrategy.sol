// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/vaults/IGearboxERC20Vault.sol";
import "../utils/DefaultAccessControl.sol";

contract GearboxStrategy is DefaultAccessControl {
    IGearboxERC20Vault gearboxERC20Vault;

    constructor(address admin_, address vault) DefaultAccessControl(admin_) {
        require(address(vault) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        gearboxERC20Vault = IGearboxERC20Vault(vault);
    }

    function adjustPositions(uint256[] memory indices) external {
        _requireAtLeastOperator();
        gearboxERC20Vault.adjustPositions(indices);
    }

    function addSubvault(address addr, uint256 limit) external {
        _requireAtLeastOperator();
        gearboxERC20Vault.addSubvault(addr, limit);
    }

    function changeLimit(uint256 index, uint256 limit) external {
        _requireAtLeastOperator();
        gearboxERC20Vault.changeLimit(index, limit);
    }

    function changeLimitAndFactor(
        uint256 index,
        uint256 limit,
        uint256 factor
    ) external {
        _requireAtLeastOperator();
        gearboxERC20Vault.changeLimitAndFactor(index, limit, factor);
    }

    function distributeDeposits() external {
        _requireAtLeastOperator();
        gearboxERC20Vault.distributeDeposits();
    }

    function setAdapters(address curveAdapter_, address convexAdapter_) external {
        _requireAtLeastOperator();
        gearboxERC20Vault.setAdapters(curveAdapter_, convexAdapter_);
    }
}
