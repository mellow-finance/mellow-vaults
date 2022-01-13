// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./MockERC165.sol";
import "../interfaces/vaults/IVault.sol";

contract MockERC165Vault is MockERC165 {
    function allowInterfaceIVault() external {
        allowInterfaceId(type(IVault).interfaceId);
    }

    function denyInterfaceIVault() external {
        denyInterfaceId(type(IVault).interfaceId);
    }
}
