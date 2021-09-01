// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./IDelegatedCells.sol";

interface ITokenCells is IDelegatedCells {
    function claimTokensToCell(
        uint256 nft,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external;
}
