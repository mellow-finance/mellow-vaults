// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ERC20} from "./ERC20.sol";

interface IOlympusRange {
    function ohm() external view returns (ERC20);

    function price(bool wall_, bool high_) external view returns (uint256);
}
