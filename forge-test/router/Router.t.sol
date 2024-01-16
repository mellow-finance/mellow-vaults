// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";

import "../../src/interfaces/external/univ3/ISwapRouter.sol";
import "../../src/interfaces/external/univ3/INonfungiblePositionManager.sol";

import "../../src/utils/MultiPathUniswapRouter.sol";

contract Router is Test {
    using SafeERC20 for IERC20;

    INonfungiblePositionManager public positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    function removePosition(address owner, uint256 tokenId) public {
        vm.startPrank(owner);
        (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(tokenId);
        positionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                deadline: type(uint256).max,
                amount0Min: 0,
                amount1Min: 0
            })
        );
        positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max,
                recipient: address(this)
            })
        );
        vm.stopPrank();
    }

    MultiPathUniswapRouter router =
        new MultiPathUniswapRouter(
            ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564),
            IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e)
        );

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
            bytes[] memory paths
        )
    {
        removePosition(owner, tokenId);

        uint256 left = 0;
        uint256 right = amountIn;
        uint256 mid1;
        uint256 mid2;

        paths = new bytes[](2);
        paths[0] = path1;
        paths[1] = path2;
        amountsIn = new uint256[](2);

        uint256 optimal = 0;
        while (left <= right) {
            mid1 = left + (right - left) / 3;
            mid2 = right - (right - left) / 3;

            uint256 amountOut1;
            {
                amountsIn[0] = mid1;
                amountsIn[1] = amountIn - mid1;
                amountOut1 = router.quote(paths, amountsIn);
            }

            uint256 amountOut2;
            {
                amountsIn[0] = mid2;
                amountsIn[1] = amountIn - mid2;
                amountOut2 = router.quote(paths, amountsIn);
            }

            if (amountOut1 > maxAmountOut) {
                maxAmountOut = amountOut1;
                optimal = mid1;
            }
            if (amountOut2 > maxAmountOut) {
                maxAmountOut = amountOut2;
                optimal = mid2;
            }

            if (amountOut1 > amountOut2) {
                right = mid2 - 1;
            } else {
                left = mid1 + 1;
            }
        }
        amountsIn[0] = optimal;
        amountsIn[1] = amountIn - optimal;
    }

    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public ohm = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function test() external {
        uint256 amountIn = 95000 * 1e6;

        (uint256[] memory amountsIn, uint256 amountOut, bytes[] memory paths) = findOpt(
            648375,
            0x1b504f17192d58b2e457A4814E4bC0d261421B49,
            95000 * 1e6,
            abi.encodePacked(usdc, uint24(3000), ohm),
            abi.encodePacked(usdc, uint24(500), weth, uint24(3000), ohm)
        );

        console2.log(amountsIn[0], amountsIn[1]);
        console2.log("Amount out:", amountOut);

        address testUser = address(uint160(bytes20(keccak256("test-user"))));
        vm.startPrank(testUser);

        deal(usdc, testUser, amountIn);
        IERC20(usdc).safeApprove(address(router), amountIn);
        uint256 actualAmountOut = router.swap(usdc, paths, amountsIn, amountOut);
        console2.log("Actual amount out:", actualAmountOut);

        vm.stopPrank();
    }
}
