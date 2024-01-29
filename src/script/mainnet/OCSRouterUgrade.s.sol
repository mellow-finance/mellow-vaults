// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/src/Script.sol";
import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";
import "forge-std/src/console2.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../strategies/BasePulseStrategyUpgradable.sol";
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

import "../../interfaces/external/univ3/IV3SwapRouter.sol";
import "../../interfaces/external/univ3/IQuoter.sol";

import "../../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../../interfaces/external/univ3/IMulticall.sol";

contract Deploy is Script {
    using SafeERC20 for IERC20;

    INonfungiblePositionManager public positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    function removePosition(address owner, uint256 tokenId) public {
        // vm.startPrank(owner);
        // (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(tokenId);
        // positionManager.decreaseLiquidity(
        //     INonfungiblePositionManager.DecreaseLiquidityParams({
        //         tokenId: tokenId,
        //         liquidity: liquidity,
        //         deadline: type(uint256).max,
        //         amount0Min: 0,
        //         amount1Min: 0
        //     })
        // );
        // positionManager.collect(
        //     INonfungiblePositionManager.CollectParams({
        //         tokenId: tokenId,
        //         amount0Max: type(uint128).max,
        //         amount1Max: type(uint128).max,
        //         recipient: address(this)
        //     })
        // );
        // vm.stopPrank();
    }

    IMulticall public swapRouter02 = IMulticall(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    IQuoterV2 public quoter = IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);

    function findOpt(
        uint256 tokenId,
        address owner,
        uint256 amountIn,
        bytes memory path1,
        bytes memory path2
    )
        public
        returns (
            uint256[] memory amountsIn,
            uint256 maxAmountOut,
            uint256[] memory amountOuts,
            bytes[] memory paths
        )
    {
        removePosition(owner, tokenId);

        uint256 left = 1;
        uint256 right = amountIn;
        uint256 mid1;
        uint256 mid2;

        paths = new bytes[](2);
        paths[0] = path1;
        paths[1] = path2;
        amountsIn = new uint256[](2);
        amountOuts = new uint256[](2);

        uint256 optimal = 0;
        while (left <= right) {
            mid1 = left + (right - left) / 3;
            mid2 = right - (right - left) / 3;

            uint256 amountOut1;
            {
                amountsIn[0] = mid1;
                amountsIn[1] = amountIn - mid1;
                (uint256 firstPart, , , ) = quoter.quoteExactInput(paths[0], amountsIn[0]);
                (uint256 secondPart, , , ) = quoter.quoteExactInput(paths[1], amountsIn[1]);
                amountOut1 = firstPart + secondPart;
                if (amountOut1 > maxAmountOut) {
                    maxAmountOut = amountOut1;
                    optimal = mid1;
                    amountOuts[0] = firstPart;
                    amountOuts[1] = secondPart;
                }
            }

            uint256 amountOut2;
            {
                amountsIn[0] = mid2;
                amountsIn[1] = amountIn - mid2;
                (uint256 firstPart, , , ) = quoter.quoteExactInput(paths[0], amountsIn[0]);
                (uint256 secondPart, , , ) = quoter.quoteExactInput(paths[1], amountsIn[1]);
                amountOut2 = firstPart + secondPart;
                if (amountOut2 > maxAmountOut) {
                    maxAmountOut = amountOut2;
                    optimal = mid2;
                    amountOuts[0] = firstPart;
                    amountOuts[1] = secondPart;
                }
            }
            if (amountOut1 > amountOut2) {
                right = mid2 - 1;
            } else {
                left = mid1 + 1;
            }
        }
        amountsIn[0] = optimal;
        amountsIn[1] = amountIn - optimal;

        {
            (uint256 amountOut1, , , ) = quoter.quoteExactInput(path1, amountIn);
            if (amountOut1 > maxAmountOut) {
                maxAmountOut = amountOut1;
                amountsIn = new uint256[](1);
                amountsIn[0] = amountIn;
                paths = new bytes[](1);
                paths[0] = path1;
                amountOuts = new uint256[](1);
                amountOuts[0] = amountOut1;
            }
        }
        {
            (uint256 amountOut2, , , ) = quoter.quoteExactInput(path2, amountIn);
            if (amountOut2 > maxAmountOut) {
                maxAmountOut = amountOut2;
                amountsIn = new uint256[](1);
                amountsIn[0] = amountIn;
                paths = new bytes[](1);
                paths[0] = path2;
                amountOuts = new uint256[](1);
                amountOuts[0] = amountOut2;
            }
        }
    }

    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public ohm = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function getSwapData(
        address vault,
        uint256 tokenId,
        address erc20Vault,
        uint256 amountIn,
        bytes memory path1,
        bytes memory path2
    ) public returns (bytes memory) {
        (uint256[] memory amountsIn, uint256 amountOut, uint256[] memory amountsOut, bytes[] memory paths) = findOpt(
            tokenId,
            vault,
            amountIn,
            path1,
            path2
        );

        console2.log("Amount out:", amountOut);

        bytes[] memory calls = new bytes[](paths.length);
        for (uint256 i = 0; i < paths.length; i++) {
            calls[i] = abi.encodeWithSelector(
                IV3SwapRouter.exactInput.selector,
                IV3SwapRouter.ExactInputParams({
                    path: paths[i],
                    amountIn: amountsIn[i],
                    recipient: erc20Vault,
                    amountOutMinimum: amountsOut[i]
                })
            );
        }

        return abi.encodeWithSelector(IMulticall.multicall.selector, type(uint256).max, calls);
    }

    address public protocolAdmin = 0x565766498604676D9916D4838455Cc5fED24a5B3;
    address public proxy = 0xB7D15488C8d702cBBd5870b7907FCD877d7a1C4B;

    address public helper = 0x7c59Aae0Ee2EeEdeC34d235FeAF91A45CcAE2cb5;
    address public operatorStrategy = 0x8E7900eb386faBc74f7b166fFda693cB03326Dfe;
    BasePulseStrategyUpgradable public baseStrategy =
        BasePulseStrategyUpgradable(0x94aB171819bE4a9bb349a34C8F47087d4FFE046F);

    function run() external {
        vm.startBroadcast(uint256(bytes32(vm.envBytes("DEPLOYER_PK"))));

        BasePulseStrategyUpgradable.MutableParams memory mutableParams;
        (
            mutableParams.priceImpactD6,
            mutableParams.maxDeviationForVaultPool,
            mutableParams.timespanForAverageTick,
            mutableParams.swapSlippageD,
            mutableParams.swappingAmountsCoefficientD
        ) = BasePulseStrategyUpgradable(proxy).mutableParams();

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e9 * 100;
        amounts[1] = 1e6 * 1000;
        mutableParams.minSwapAmounts = amounts;
        mutableParams.swapSlippageD = 1e7;
        BasePulseStrategyUpgradable(proxy).updateMutableParams(mutableParams);
        BasePulseStrategyUpgradable(proxy).setRouter(address(swapRouter02));
        vm.stopBroadcast();

        IUniV3Vault uniV3Vault = IUniV3Vault(0x1b504f17192d58b2e457A4814E4bC0d261421B49);

        BasePulseStrategy.Interval memory newInterval = OlympusConcentratedStrategy(operatorStrategy)
            .calculateInterval();

        console2.log("new interval:", vm.toString(newInterval.lowerTick), vm.toString(newInterval.upperTick));
        {
            (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = positionManager.positions(uniV3Vault.uniV3Nft());
            console2.log("current interval:", vm.toString(tickLower), vm.toString(tickUpper));
        }
        (uint256 amountIn, address tokenIn, , ) = BasePulseStrategyHelper(helper).calculateAmountForSwap(
            BasePulseStrategy(proxy),
            newInterval
        );

        bytes memory data;
        if (tokenIn == usdc) {
            data = getSwapData(
                address(uniV3Vault),
                uniV3Vault.uniV3Nft(),
                0x13CF9c3c1bF0FCCF72E64Bc19F2e74b809E9B56D,
                amountIn,
                abi.encodePacked(usdc, uint24(3000), ohm),
                abi.encodePacked(usdc, uint24(500), weth, uint24(3000), ohm)
            );
        } else {
            data = getSwapData(
                address(uniV3Vault),
                uniV3Vault.uniV3Nft(),
                0x13CF9c3c1bF0FCCF72E64Bc19F2e74b809E9B56D,
                amountIn,
                abi.encodePacked(ohm, uint24(3000), usdc),
                abi.encodePacked(ohm, uint24(3000), weth, uint24(500), usdc)
            );
        }

        vm.startBroadcast(uint256(bytes32(vm.envBytes("OPERATOR_PK"))));
        OlympusConcentratedStrategy(operatorStrategy).rebalance(type(uint256).max, data, 0);
        vm.stopBroadcast();

        // revert("passed.");
    }
}
