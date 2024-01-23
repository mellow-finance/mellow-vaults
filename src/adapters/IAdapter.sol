// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IAdapter.sol";

interface IAdapter {
    function mint(
        address poolAddress,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        address recipient
    ) external returns (uint256 tokenId);

    function swapNft(
        address from,
        address vault,
        uint256 newNft
    ) external returns (uint256 oldNft);

    function compound(address vault) external;

    function positionInfo(uint256 tokenId)
        external
        view
        returns (
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity
        );

    function slot0EnsureNoMEV(address poolAddress, bytes memory securityParams)
        external
        view
        returns (uint160 sqrtPriceX96, int24 spotTick);

    function slot0(address poolAddress) external view returns (uint160 sqrtPriceX96, int24 spotTick);

    function tokenId(address vault) external view returns (uint256);

    function validateSecurityParams(bytes memory securityParams) external view;
}
