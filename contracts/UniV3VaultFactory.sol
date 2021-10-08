// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/external/univ3/INonfungiblePositionManager.sol";
import "./interfaces/IVaultFactory.sol";
import "./VaultManager.sol";
import "./UniV3Vault.sol";

contract UniV3VaultFactory is IVaultFactory {
    function deployVault(
        address[] calldata tokens,
        uint256[] calldata limits,
        address strategyTreasury,
        bytes calldata options
    ) external override returns (address) {
        uint256 fee;
        // TODO: Figure out why calldataload don't need a 32 bytes offset for the bytes length like mload
        // probably due to how .offset works
        assembly {
            fee := calldataload(options.offset)
        }
        UniV3Vault vault = new UniV3Vault(tokens, limits, IVaultManager(msg.sender), strategyTreasury, uint24(fee));
        return address(vault);
    }
}
