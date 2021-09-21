// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./ICells.sol";

interface IDelegatedCells is ICells {
    function delegated(uint256 nft) external view returns (address[] memory tokens, uint256[] memory tokenAmounts);

    function deposit(
        uint256 nft,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external returns (uint256[] memory actualTokenAmounts);

    function withdraw(
        uint256 nft,
        address to,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external returns (uint256[] memory actualTokenAmounts);


    event Deposit(
        uint256 nft,
        address[] tokens,
        uint256[] actualTokenAmounts
    );

    event Withdraw(
        uint256 nft,
        address to,
        address[] tokens,
        uint256[] actualTokenAmounts
    );
    // TODO: add methods for collecting liquidity mining rewards
}
