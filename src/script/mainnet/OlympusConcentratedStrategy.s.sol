// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";
import "forge-std/src/console2.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../strategies/BasePulseStrategy.sol";
import "../../strategies/OlympusConcentratedStrategy.sol";

import "../../utils/DepositWrapper.sol";
import "../../utils/BasePulseStrategyHelper.sol";
import "../../utils/UniV3Helper.sol";

import "../../vaults/ERC20Vault.sol";
import "../../vaults/ERC20VaultGovernance.sol";

import "../../vaults/ERC20RootVault.sol";
import "../../vaults/ERC20RootVaultGovernance.sol";

import "../../vaults/UniV3Vault.sol";
import "../../vaults/UniV3VaultGovernance.sol";

import "../../interfaces/external/univ3/ISwapRouter.sol";

contract Deploy is Script {
    address public ohm = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    INonfungiblePositionManager public positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    BasePulseStrategyHelper public strategyHelper = BasePulseStrategyHelper(0x7c59Aae0Ee2EeEdeC34d235FeAF91A45CcAE2cb5);

    uint256 public constant Q96 = 2**96;
    address public proxy = 0xB7D15488C8d702cBBd5870b7907FCD877d7a1C4B;
    address public operatorStrategy = 0x8E7900eb386faBc74f7b166fFda693cB03326Dfe;

    address public factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public router = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    bytes4 public constant UNISWAP_V3_SWAP_SELECTOR = bytes4(0xe449022e);

    function getSwapData(
        address tokenIn,
        address[] memory pools,
        uint256 amountIn
    ) public view returns (bytes memory) {
        uint256[] memory poolsData = new uint256[](pools.length);

        for (uint256 i = 0; i < pools.length; i++) {
            poolsData[i] = uint160(pools[i]);
            if (IUniswapV3Pool(pools[i]).token1() == tokenIn) {
                poolsData[i] += 1 << 255;
                tokenIn = IUniswapV3Pool(pools[i]).token0();
            } else {
                tokenIn = IUniswapV3Pool(pools[i]).token1();
            }
        }
        return
            abi.encodePacked(
                abi.encodeWithSelector(UNISWAP_V3_SWAP_SELECTOR, amountIn, 0, poolsData),
                type(uint32).max
            );
    }

    function run() external {
        BasePulseStrategy.Interval memory interval = OlympusConcentratedStrategy(operatorStrategy).calculateInterval();

        (uint256 amountIn, address fromToken, , ) = strategyHelper.calculateAmountForSwap(
            BasePulseStrategy(proxy),
            interval
        );

        address[] memory pools = new address[](2);
        pools[0] = IUniswapV3Factory(factory).getPool(usdc, weth, 500);
        pools[1] = IUniswapV3Factory(factory).getPool(weth, ohm, 3000);

        bytes memory swapData;
        if (fromToken == usdc) {
            swapData = getSwapData(usdc, pools, amountIn);
        } else {
            (pools[0], pools[1]) = (pools[1], pools[0]);
            swapData = getSwapData(ohm, pools, amountIn);
        }

        vm.startBroadcast(uint256(bytes32(vm.envBytes("OPERATOR_PK"))));
        OlympusConcentratedStrategy(operatorStrategy).rebalance(
            type(uint256).max,
            swapData,
            0 // TODO set minAmountOut
        );
        vm.stopBroadcast();
        revert("passed");
    }
}
