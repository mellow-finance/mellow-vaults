// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";

import "../../src/interfaces/external/univ3/IV3SwapRouter.sol";
import "../../src/interfaces/external/univ3/IQuoter.sol";

import "../../src/interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../../src/interfaces/external/univ3/IMulticall.sol";

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

        uint256 left = 0;
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

        console2.log(amountsIn[0], amountsIn[1]);
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

    function _test() external {
        uint256 tokenId = 648375;
        address vault = 0x1b504f17192d58b2e457A4814E4bC0d261421B49;
        address erc20Vault = address(uint160(bytes20(keccak256("erc20vault"))));
        uint256 amountIn = 95000 * 1e6;

        bytes memory data = getSwapData(
            vault,
            tokenId,
            erc20Vault,
            amountIn,
            abi.encodePacked(usdc, uint24(3000), ohm),
            abi.encodePacked(usdc, uint24(500), weth, uint24(3000), ohm)
        );

        deal(usdc, erc20Vault, amountIn);
        vm.startPrank(erc20Vault);
        IERC20(usdc).safeApprove(address(swapRouter02), amountIn);
        (bool success, ) = address(swapRouter02).call(data);
        require(success);
        vm.stopPrank();
    }
}
