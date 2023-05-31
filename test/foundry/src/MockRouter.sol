// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/interfaces/oracles/IOracle.sol";
import "../src/libraries/external/FullMath.sol";

contract MockRouter is Test {

    address[] tokens;
    IOracle oracle;

    uint256 public constant Q96 = 2**96;

    constructor (address[] memory inputTokens, IOracle oracle_) {
        tokens = inputTokens;
        oracle = oracle_;
    }

    function swap(
        uint256 tokenIndex, 
        uint256 amount
    ) external {
        (uint256[] memory pricesX96, ) = oracle.priceX96(tokens[0], tokens[1], 32);

        uint256 amountOut;

        if (tokenIndex == 0) {
            amountOut = FullMath.mulDiv(pricesX96[0], amount, Q96);
        }
        else{
            amountOut = FullMath.mulDiv(amount, Q96, pricesX96[0]);
        }

        IERC20(tokens[tokenIndex]).transferFrom(msg.sender, address(this), amount);
        IERC20(tokens[1 - tokenIndex]).transfer(msg.sender, amountOut);
    }

}