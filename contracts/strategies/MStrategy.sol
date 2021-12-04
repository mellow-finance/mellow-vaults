// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "../DefaultAccessControl.sol";

contract MStrategy is DefaultAccessControl {
    struct Params {
        uint256 oraclePriceTimespan;
        uint256 oraclePriceMinTimespan;
    }

    struct ImmutableParams {
        address token0;
        address token1;
        address uniV3Pool;
    }

    address public uinV3Quoter;

    constructor(address owner) DefaultAccessControl(owner) {}

    Params[] private _params;
    ImmutableParams[] private _immutableParams;
    mapping(address => mapping(address => uint256)) public paramsIndex;

    function addTokenPair(address token0, address token1) external {}
}
