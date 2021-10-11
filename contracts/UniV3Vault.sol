// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/external/univ3/INonfungiblePositionManager.sol";
import "./interfaces/external/univ3/IUniswapV3PoolState.sol";
import "./interfaces/external/univ3/IUniswapV3Factory.sol";
import "./interfaces/IUniV3VaultManager.sol";
import "./libraries/external/TickMath.sol";
import "./libraries/external/LiquidityAmounts.sol";
import "./Vault.sol";

contract UniV3Vault is Vault {
    using EnumerableSet for EnumerableSet.UintSet;
    EnumerableSet.UintSet private _nfts;
    EnumerableSet.UintSet private _cachedNfts;
    IUniswapV3PoolState public pool;

    constructor(
        address[] memory tokens,
        uint256[] memory limits,
        IVaultManager vaultManager,
        address strategyTreasury,
        uint24 fee
    ) Vault(tokens, limits, vaultManager, strategyTreasury) {
        require(tokens.length == 2, "TL");
        pool = IUniswapV3PoolState(IUniswapV3Factory(_positionManager().factory()).getPool(tokens[0], tokens[1], fee));
    }

    function tvl() public view override returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint256[](2);
        for (uint256 i = 0; i < _nfts.length(); i++) {
            uint256 nft = _nfts.at(i);
            uint256[] memory nftTokenAmounts = nftTvl(nft);
            tokenAmounts[0] += nftTokenAmounts[0];
            tokenAmounts[1] += nftTokenAmounts[1];
        }
    }

    function earnings() public view override returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint256[](2);
        for (uint256 i = 0; i < _nfts.length(); i++) {
            uint256 nft = _nfts.at(i);
            uint256[] memory _nftEarnings = nftEarnings(nft);
            tokenAmounts[0] += _nftEarnings[0];
            tokenAmounts[1] += _nftEarnings[1];
        }
    }

    function nftEarnings(uint256 nft) public view returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint256[](2);
        (, , , , , , , , , , uint256 token0Owed, uint256 token1Owed) = _positionManager().positions(nft);
        tokenAmounts[0] = token0Owed;
        tokenAmounts[1] = token1Owed;
    }

    function nftTvl(uint256 nft) public view returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint256[](vaultTokens().length);
        (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = _positionManager().positions(nft);
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

    function nftTvls() public view returns (uint256[][] memory tokenAmounts) {
        tokenAmounts = new uint256[][](_nfts.length());
        for (uint256 i = 0; i < _nfts.length(); i++) {
            uint256 nft = _nfts.at(i);
            tokenAmounts[i] = nftTvl(nft);
        }
    }

    function _push(uint256[] memory tokenAmounts) internal override returns (uint256[] memory actualTokenAmounts) {
        address[] memory tokens = vaultTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            _allowTokenIfNecessary(tokens[i]);
        }
        uint256[][] memory tvls = nftTvls();
        uint256[] memory totalTVL = new uint256[](tokens.length);
        for (uint256 i = 0; i < _nfts.length(); i++) {
            for (uint256 j = 0; j < tokens.length; j++) {
                totalTVL[j] += tvls[i][j];
            }
        }
        actualTokenAmounts = new uint256[](2);
        for (uint256 i = 0; i < _nfts.length(); i++) {
            uint256 nft = _nfts.at(i);
            uint256 a0 = (tokenAmounts[0] * tvls[i][0]) / totalTVL[0];
            uint256 a1 = (tokenAmounts[1] * tvls[i][1]) / totalTVL[1];
            // TODO: add options like minAmount
            (, uint256 amount0, uint256 amount1) = _positionManager().increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams({
                    tokenId: nft,
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

        for (uint256 i = 0; i < _nfts.length(); i++) {
            uint256 nft = _nfts.at(i);
            uint256 liquidity = _getWithdrawLiquidity(nft, tokenAmounts);
            if (liquidity == 0) {
                continue;
            }
            // TODO: add options like minAmount
            (uint256 amount0, uint256 amount1) = _positionManager().decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: nft,
                    liquidity: uint128(liquidity),
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp + 600
                })
            );
            (uint256 actualAmount0, uint256 actualAmount1) = _positionManager().collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: nft,
                    recipient: to,
                    amount0Max: uint128(amount0),
                    amount1Max: uint128(amount1)
                })
            );
            actualTokenAmounts[0] += actualAmount0;
            actualTokenAmounts[1] += actualAmount1;
        }
    }

    function _collectEarnings(address to) internal override returns (uint256[] memory collectedEarnings) {
        address[] memory tokens = vaultTokens();
        collectedEarnings = new uint256[](tokens.length);
        for (uint256 i = 0; i < _nfts.length(); i++) {
            uint256 nft = _nfts.at(i);
            (uint256 collectedEarnings0, uint256 collectedEarnings1) = _positionManager().collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: nft,
                    recipient: to,
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
            collectedEarnings[0] += collectedEarnings0;
            collectedEarnings[1] += collectedEarnings1;
        }
    }

    function _postReclaimTokens(address, address[] memory tokens) internal view override {
        for (uint256 i = 0; i < tokens.length; i++) {
            require(!isVaultToken(tokens[i]), "OWT"); // vault token is part of TVL
        }
    }

    /// TODO: make a virtual function here? Or other better approach
    function _positionManager() internal view returns (INonfungiblePositionManager) {
        return IUniV3VaultManager(address(vaultManager())).positionManager();
    }

    function _getWithdrawLiquidity(uint256 nft, uint256[] memory tokenAmounts) internal view returns (uint256) {
        uint256[] memory totalAmounts = nftTvl(nft);
        (, , , , , , , uint128 totalLiquidity, , , , ) = _positionManager().positions(nft);
        if (totalAmounts[0] == 0) {
            if (tokenAmounts[0] == 0) {
                return (totalLiquidity * tokenAmounts[1]) / totalAmounts[1]; // liquidity1
            } else {
                return 0;
            }
        }
        if (totalAmounts[1] == 0) {
            if (tokenAmounts[1] == 0) {
                return (totalLiquidity * tokenAmounts[0]) / totalAmounts[0]; // liquidity0
            } else {
                return 0;
            }
        }
        uint256 liquidity0 = (totalLiquidity * tokenAmounts[0]) / totalAmounts[0];
        uint256 liquidity1 = (totalLiquidity * tokenAmounts[1]) / totalAmounts[1];
        return liquidity0 < liquidity1 ? liquidity0 : liquidity1;
    }

    function _allowTokenIfNecessary(address token) internal {
        if (IERC20(token).allowance(address(_positionManager()), address(this)) < type(uint256).max / 2) {
            IERC20(token).approve(address(_positionManager()), type(uint256).max);
        }
    }
}
