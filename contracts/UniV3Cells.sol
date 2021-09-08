// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./interfaces/ITokenCells.sol";
import "./libraries/Array.sol";
import "./libraries/external/LiquidityAmounts.sol";
import "./libraries/external/TickMath.sol";
import "./Cells.sol";
import "./interfaces/external/IUniswapV3PoolState.sol";
import "./interfaces/external/IUniswapV3Factory.sol";
import "./interfaces/external/INonfungiblePositionManager.sol";

contract UniV3Cells is IDelegatedCells, Cells {
    INonfungiblePositionManager public positionManager;
    mapping(uint256 => uint256) public uniNfts;

    constructor(
        INonfungiblePositionManager _positionManager,
        string memory name,
        string memory symbol
    ) Cells(name, symbol) {
        positionManager = _positionManager;
    }

    function delegated(uint256 nft)
        external
        view
        override
        returns (address[] memory tokens, uint256[] memory tokenAmounts)
    {
        uint256 uniNft = uniNfts[nft];
        require(uniNft > 0, "UNFT0");
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = positionManager.positions(uniNft);
        IUniswapV3Factory factory = IUniswapV3Factory(positionManager.factory());
        IUniswapV3PoolState pool = IUniswapV3PoolState(factory.getPool(token0, token1, fee));
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            liquidity
        );
        tokenAmounts = new uint256[](2);
        tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;
        tokenAmounts[0] = amount0;
        tokenAmounts[1] = amount1;
    }

    function deposit(
        uint256 nft,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external override returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(_msgSender(), nft), "IO");
        uint256 uniNft = uniNfts[nft];
        require(uniNft > 0, "UNFT0");
        (, , address token0, address token1, uint24 fee, , , , , , , ) = positionManager.positions(uniNft);
    }

    function withdraw(
        uint256 nft,
        address to,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external override returns (uint256[] memory actualTokenAmounts);

    function _mintCellNft(address[] memory tokens, bytes memory params) internal virtual override returns (uint256) {
        require(params.length == 8 * 32, "IP");
        require(tokens.length == 2, "TL");
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
        assembly {
            fee := mload(add(params, 32))
            tickLower := mload(add(params, 64))
            tickUpper := mload(add(params, 96))
            amount0Desired := mload(add(params, 128))
            amount1Desired := mload(add(params, 160))
            amount0Min := mload(add(params, 192))
            amount1Min := mload(add(params, 224))
            deadline := mload(add(params, 256))
        }

        (uint256 uniNft, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: tokens[0],
                token1: tokens[1],
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                recipient: address(this),
                deadline: deadline
            })
        );
        uint256 cellNft = super._mintCellNft(tokens, params);
        uniNfts[cellNft] = uniNft;
        return cellNft;
    }
}
