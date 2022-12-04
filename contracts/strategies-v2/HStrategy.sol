// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../utils/UniswapV3Token.sol";
import "../interfaces/oracles/IChainlinkOracle.sol";

contract HStrategy {
    // expected functions

    // check
    // startAuction
    // finishAuction
    // getCurrentRebalanceRestrictions

    IERC20[] public yieldTokens;
    UniswapV3Token[] public uniswapTokens;
    address public immutable vault;

    constructor(address vault_) {
        vault = vault_;
    }

    function calculateCurrentRatios() public view {}

    function rebalanceNeeded() public returns (bool isNeeded) {
        
    }
}
