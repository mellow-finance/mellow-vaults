// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";
import "forge-std/src/console2.sol";

import "../../../src/interfaces/external/pancakeswap/ISmartRouter.sol";

import "../../../src/strategies/PancakeSwapPulseStrategyV2.sol";

import "../../../src/test/MockRouter.sol";

import "../../../src/utils/DepositWrapper.sol";
import "../../../src/utils/PancakeSwapHelper.sol";
import "../../../src/utils/PancakeSwapPulseV2Helper.sol";

import "../../../src/vaults/ERC20Vault.sol";
import "../../../src/vaults/ERC20VaultGovernance.sol";

import "../../../src/vaults/ERC20RootVault.sol";
import "../../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../../src/vaults/PancakeSwapVault.sol";
import "../../../src/vaults/PancakeSwapVaultGovernance.sol";

contract PancakePulseV2Test is Test {
    PancakeSwapHelper vaultHelper =
        new PancakeSwapHelper(IPancakeNonfungiblePositionManager(0x46A15B0b27311cedF172AB29E4f4766fbE7F4364));

    function testUSDT() external {
        {
            IPancakeSwapVault pancakeSwapVault = IPancakeSwapVault(0x2dB60F8Fa3f56be410CAB44acD1Ab29E5B3a3ea9);
            uint256 calculatedRewards = vaultHelper.calculateActualPendingCake(
                pancakeSwapVault.masterChef(),
                pancakeSwapVault.uniV3Nft()
            );
            uint256 actualRewards = pancakeSwapVault.compound();
            console2.log(calculatedRewards, actualRewards);
        }

        skip(60 * 60);

        {
            IPancakeSwapVault pancakeSwapVault = IPancakeSwapVault(0x2dB60F8Fa3f56be410CAB44acD1Ab29E5B3a3ea9);
            uint256 calculatedRewards = vaultHelper.calculateActualPendingCake(
                pancakeSwapVault.masterChef(),
                pancakeSwapVault.uniV3Nft()
            );
            uint256 actualRewards = pancakeSwapVault.compound();
            console2.log(calculatedRewards, actualRewards);
        }
    }

    function testUSDC() external {
        skip(160 * 60 * 60);

        {
            IPancakeSwapVault pancakeSwapVault = IPancakeSwapVault(0x956729900f48508016377FA2Ed17438612C183F9);
            uint256 calculatedRewards = vaultHelper.calculateActualPendingCake(
                pancakeSwapVault.masterChef(),
                pancakeSwapVault.uniV3Nft()
            );
            uint256 actualRewards = pancakeSwapVault.compound();
            console2.log(calculatedRewards, actualRewards);
        }

        skip(160 * 60 * 60);

        {
            IPancakeSwapVault pancakeSwapVault = IPancakeSwapVault(0x956729900f48508016377FA2Ed17438612C183F9);
            uint256 calculatedRewards = vaultHelper.calculateActualPendingCake(
                pancakeSwapVault.masterChef(),
                pancakeSwapVault.uniV3Nft()
            );
            uint256 actualRewards = pancakeSwapVault.compound();
            console2.log(calculatedRewards, actualRewards);
        }
    }
}
