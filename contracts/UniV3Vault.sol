// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./Vault.sol";

contract UniV3Vault is Vault {
    using EnumerableSet for EnumerableSet.UintSet;
    EnumerableSet.UintSet private _nfts;
    EnumerableSet.UintSet private _cachedNfts;

    constructor(
        address[] memory tokens,
        uint256[] memory limits,
        IVaultManager vaultManager
    ) Vault(tokens, limits, vaultManager) {}

    function tvl() public view override returns (address[] memory tokens, uint256[] memory tokenAmounts) {
        tokens = vaultTokens();
        for (uint256 i = 0; i < _nfts.length(); i++) {
            uint256 nft = _nfts.at(i);
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
            IUniswapV3PoolState pool = IUniswapV3PoolState(
                IUniswapV3Factory(positionManager.factory()).getPool(token0, token1, fee)
            );
            (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
            uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
            uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                sqrtPriceAX96,
                sqrtPriceBX96,
                liquidity
            );
        }
        tokens = vaultTokens();
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAmounts[i] = IERC20(tokens[i]).balanceOf(address(this));
        }
    }

    function _push(uint256[] memory tokenAmounts) internal pure override returns (uint256[] memory actualTokenAmounts) {
        // no-op, tokens are already on balance
        return tokenAmounts;
    }

    function _pull(address to, uint256[] memory tokenAmounts)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        for (uint256 i = 0; i < tokenAmounts.length; i++) {
            IERC20(vaultTokens()[i]).transfer(to, tokenAmounts[i]);
        }
        actualTokenAmounts = tokenAmounts;
    }

    function _collectEarnings(address, address[] memory tokens)
        internal
        pure
        override
        returns (uint256[] memory collectedEarnings)
    {
        // no-op, no earnings here
        collectedEarnings = new uint256[](tokens.length);
    }

    function _postReclaimTokens(address, address[] memory tokens) internal view override {
        for (uint256 i = 0; i < tokens.length; i++) {
            require(!isVaultToken(tokens[i]), "OWT"); // vault token is part of TVL
        }
    }
}
