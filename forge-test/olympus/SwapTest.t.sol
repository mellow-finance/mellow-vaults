// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";
import "forge-std/src/console2.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../src/interfaces/external/univ3/IUniswapV3Pool.sol";
import "../../src/interfaces/external/univ3/IUniswapV3Factory.sol";

contract OlympusConcentratedTest is Test {
    using SafeERC20 for IERC20;

    address public factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    address public owner = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public router = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    address public ohm = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

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

    function test() external {
        vm.startPrank(owner);
        // uint256 amountIn = 1e5 * 1e6;
        // deal(usdc, owner, amountIn);
        // IERC20(usdc).safeApprove(router, type(uint256).max);

        // address[] memory pools = new address[](2);
        // pools[0] = IUniswapV3Factory(factory).getPool(usdc, weth, 500);
        // pools[1] = IUniswapV3Factory(factory).getPool(weth, ohm, 3000);

        // (bool success, ) = router.call(getSwapData(usdc, pools, amountIn));

        // console2.log(success);
        vm.stopPrank();
    }
}
