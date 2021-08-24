// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./ICells.sol";

interface ITokenCells is ICells {
    function claimTokensToCell(
        uint256 nft,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external;
}
