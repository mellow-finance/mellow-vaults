// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.9;

import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "./MockUniswapV3Factory.sol";

contract MockNonfungiblePositionManager is INonfungiblePositionManager {
    MockUniswapV3Factory uniV3Factory;

    constructor(MockUniswapV3Factory factory_) {
        uniV3Factory = factory_;
    }

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {}

    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {}

    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {}

    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1)
    {}

    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1) {}

    function burn(uint256 tokenId) external payable {}

    function balanceOf(address owner) external view returns (uint256 balance) {}

    function ownerOf(uint256 tokenId) external view returns (address owner) {}

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external {}

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external {}

    function approve(address to, uint256 tokenId) external {}

    function getApproved(uint256 tokenId) external view returns (address operator) {}

    function setApprovalForAll(address operator, bool _approved) external {}

    function isApprovedForAll(address owner, address operator) external view returns (bool) {}

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external {}

    function factory() external view returns (address) {
        return address(uniV3Factory);
    }

    function WETH9() external view returns (address) {}

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}
