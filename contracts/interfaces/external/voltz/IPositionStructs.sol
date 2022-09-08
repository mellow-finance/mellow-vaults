// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.9;

interface IPositionStructs {
    struct ModifyPositionParams {
        // the address that owns the position
        address owner;
        // the lower and upper tick of the position
        int24 tickLower;
        int24 tickUpper;
        // any change in liquidity
        int128 liquidityDelta;
    }
}
