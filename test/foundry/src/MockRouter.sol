// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/interfaces/oracles/IOracle.sol";
import "../src/interfaces/utils/ISwapper.sol";
import "../src/libraries/external/FullMath.sol";

contract MockRouter is Test, ISwapper {

    address[] tokens;
    IOracle oracle;

    uint256 public constant Q96 = 2**96;

    constructor (address[] memory inputTokens, IOracle oracle_) {
        tokens = inputTokens;
        oracle = oracle_;
    }

    function swap(address token0, address token1, uint256 amountIn, uint256 minAmountOut, bytes memory data) external {

        (uint256[] memory pricesX96, ) = oracle.priceX96(token0, token1, 32);

        uint256 amountOut;
        if (token0 == tokens[0]) {
            amountOut = FullMath.mulDiv(pricesX96[0], amountIn, Q96);
        }
        
        else {
            amountOut = FullMath.mulDiv(amountIn, Q96, pricesX96[0]);
        }

        IERC20(token0).transferFrom(msg.sender, address(this), amountIn);
        IERC20(token1).transfer(msg.sender, amountOut);
    }

}