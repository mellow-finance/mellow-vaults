// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/IUniV3PositionManager.sol";
import "./Vault.sol";

contract UniV3Vault is Vault {
    using EnumerableSet for EnumerableSet.UintSet;
    EnumerableSet.UintSet private _nfts;
    EnumerableSet.UintSet private _cachedNfts;
    IUniswapV3PoolState public pool;

    constructor(
        address[] memory tokens,
        uint256[] memory limits,
        IVaultManager vaultManager
    ) Vault(tokens, limits, vaultManager) {
        require(tokens.length == 2, "TL");
        pool = IUniswapV3PoolState(IUniswapV3Factory(_positionManager().factory()).getPool(token0, token1, fee));
    }

    function tvl() public view override returns (address[] memory tokens, uint256[] memory tokenAmounts) {
        tokens = vaultTokens();
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < _nfts.length(); i++) {
            nftTokenAmounts = nftTvl(nft);
            tokenAmounts[0] += nftTokenAmounts[0];
            tokenAmounts[1] += nftTokenAmounts[1];
        }
    }

    function nftTvl(uint256 nft) public returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint256[](vaultTokens().length);
        uint256 nft = _nfts.at(i);
        (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = _positionManager().positions(uniNft);
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            liquidity
        );
        tokenAmounts[0] = amount0;
        tokenAmounts[1] = amount1;
    }

    function nftTvls() public returns (uint256[][] memory tokenAmounts) {
        tokenAmounts = new uint256[][](_nfts.length());
        for (uint256 i = 0; i < _nfts.length(); i++) {
            uint256 nft = _nfts.at(i);
            tokenAmounts[i] = nftTvl(nft);
        }
    }

    function _push(uint256[] memory tokenAmounts) internal pure override returns (uint256[] memory actualTokenAmounts) {
        address[] tokens = vaultTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            _allowTokenIfNecessary(tokens[i]);
        }
        uint256[][] memory tvls = nftTvls();
        uint256[] tvl = new uint256[](tokens.length);
        for (uint256 i = 0; i < _nfts.length(); i++) {
            for (uint256 j = 0; j < tokens.length(); j++) {
                tvl[j] += tvls[i][j];
            }
        }
        actualTokenAmounts = new uint256[](2);
        for (uint256 i = 0; i < _nfts.length(); i++) {
            uint256 nft = _nfts.at(i);
            uint256 a0 = (tokenAmounts[0] * tvls[i][0]) / tvl[0];
            uint256 a1 = (tokenAmounts[1] * tvls[i][1]) / tvl[1];
            // TODO: add options like minAmount
            (, uint256 amount0, uint256 amount1) = positionManager.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams({
                    tokenId: uniNft,
                    amount0Desired: a0,
                    amount1Desired: a1,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 600
                })
            );
            actualTokenAmounts[0] += amount0;
            actualTokenAmounts[1] += amount1;
        }
    }

    function _pull(address to, uint256[] memory tokenAmounts)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        actualTokenAmounts = new uint256[](2);
        actualTokenAmounts[0] = actualAmount0;
        actualTokenAmounts[1] = actualAmount1;

        for (uint256 i = 0; i < _nfts.length(); i++) {
            uint256 nft = _nfts.at(i);
            uint256 liquidity = _getWithdrawLiquidity(nft, uniNft, tokens, tokenAmounts);
            if (liquidity == 0) {
                continue;
            }
            // TODO: add options like minAmount
            (uint256 amount0, uint256 amount1) = positionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: nft,
                    liquidity: uint128(liquidity),
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 600
                })
            );
            (uint256 actualAmount0, uint256 actualAmount1) = positionManager.collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: uniNft,
                    recipient: to,
                    amount0Max: uint128(amount0),
                    amount1Max: uint128(amount1)
                })
            );
        }
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

    function _positionManager() internal returns (INonfungiblePositionManager) {
        return IUniV3VaultManager(_vaultManager).positionManager();
    }

    function _allowTokenIfNecessary(address token) internal {
        if (IERC20(token).allowance(address(_positionManager()), address(this)) < type(uint256).max / 2) {
            IERC20(token).approve(address(_positionManager()), type(uint256).max);
        }
    }
}
