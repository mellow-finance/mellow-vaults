// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/external/univ3/INonfungiblePositionManager.sol";
import "./interfaces/external/univ3/IUniswapV3PoolState.sol";
import "./interfaces/external/univ3/IUniswapV3Factory.sol";
import "./interfaces/IUniV3VaultGovernance.sol";
import "./libraries/external/TickMath.sol";
import "./libraries/external/LiquidityAmounts.sol";
import "./Vault.sol";

/// @notice Vault that interfaces UniswapV3 protocol in the integration layer.
contract UniV3Vault is Vault {
    using EnumerableSet for EnumerableSet.UintSet;

    struct Options {
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct Pair {
        uint256 a0;
        uint256 a1;
    }

    EnumerableSet.UintSet private _nfts;
    EnumerableSet.UintSet private _cachedNfts;
    IUniswapV3PoolState public pool;

    /// @notice Creates a new contract.
    /// @param vaultGovernance_ Reference to VaultGovernance for this vault
    /// @param vaultTokens_ ERC20 tokens under Vault management
    /// @param fee Fee of the underlying UniV3 pool
    constructor(
        IVaultGovernance vaultGovernance_,
        address[] memory vaultTokens_,
        uint24 fee
    ) Vault(vaultGovernance_, vaultTokens_) {
        require(_vaultTokens.length == 2, "TL");
        pool = IUniswapV3PoolState(
            IUniswapV3Factory(_positionManager().factory()).getPool(_vaultTokens[0], _vaultTokens[1], fee)
        );
    }

    /// @inheritdoc Vault
    function tvl() public view override returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint256[](2);
        for (uint256 i = 0; i < _nfts.length(); i++) {
            uint256 nft = _nfts.at(i);
            uint256[] memory nftTokenAmounts = nftTvl(nft);
            tokenAmounts[0] += nftTokenAmounts[0];
            tokenAmounts[1] += nftTokenAmounts[1];
        }
    }

    function nftTvl(uint256 nft) public view returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint256[](_vaultTokens.length);
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

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        address[] memory tokens = _vaultTokens;
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
        Options memory opts = _parseOptions(options);
        for (uint256 i = 0; i < _nfts.length(); i++) {
            uint256 nft = _nfts.at(i);
            Pair memory amounts = Pair({
                a0: (tokenAmounts[0] * tvls[i][0]) / totalTVL[0],
                a1: (tokenAmounts[1] * tvls[i][1]) / totalTVL[1]
            });
            Pair memory minAmounts = Pair({
                a0: (opts.amount0Min * tvls[i][0]) / totalTVL[0],
                a1: (opts.amount1Min * tvls[i][1]) / totalTVL[1]
            });
            (, uint256 amount0, uint256 amount1) = _positionManager().increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams({
                    tokenId: nft,
                    amount0Desired: amounts.a0,
                    amount1Desired: amounts.a1,
                    amount0Min: minAmounts.a0,
                    amount1Min: minAmounts.a1,
                    deadline: opts.deadline
                })
            );
            actualTokenAmounts[0] += amount0;
            actualTokenAmounts[1] += amount1;
        }
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](2);
        uint256[][] memory tvls = nftTvls();
        address[] memory tokens = _vaultTokens;
        uint256[] memory totalTVL = new uint256[](tokens.length);
        for (uint256 i = 0; i < _nfts.length(); i++) {
            for (uint256 j = 0; j < tokens.length; j++) {
                totalTVL[j] += tvls[i][j];
            }
        }
        Options memory opts = _parseOptions(options);
        for (uint256 i = 0; i < _nfts.length(); i++) {
            Pair memory amounts = _pullForOneNft(i, tokenAmounts, tvls, totalTVL, to, opts);
            actualTokenAmounts[0] += amounts.a0;
            actualTokenAmounts[1] += amounts.a1;
        }
    }

    function _pullForOneNft(
        uint256 i,
        uint256[] memory tokenAmounts,
        uint256[][] memory tvls,
        uint256[] memory totalTVL,
        address to,
        Options memory opts
    ) internal returns (Pair memory) {
        uint256 nft = _nfts.at(i);
        Pair memory amounts = Pair({
            a0: (tokenAmounts[0] * tvls[i][0]) / totalTVL[0],
            a1: (tokenAmounts[1] * tvls[i][1]) / totalTVL[1]
        });
        Pair memory minAmounts = Pair({
            a0: (opts.amount0Min * tvls[i][0]) / totalTVL[0],
            a1: (opts.amount1Min * tvls[i][1]) / totalTVL[1]
        });

        uint256 liquidity = _getWithdrawLiquidity(nft, amounts, totalTVL);
        if (liquidity == 0) {
            return Pair({a0: 0, a1: 0});
        }
        (uint256 amount0, uint256 amount1) = _positionManager().decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: nft,
                liquidity: uint128(liquidity),
                amount0Min: minAmounts.a0,
                amount1Min: minAmounts.a1,
                deadline: opts.deadline
            })
        );
        (amount0, amount1) = _positionManager().collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: nft,
                recipient: to,
                amount0Max: uint128(amount0),
                amount1Max: uint128(amount1)
            })
        );
        return Pair({a0: amount0, a1: amount1});
    }

    function _postReclaimTokens(address, address[] memory tokens) internal view override {
        for (uint256 i = 0; i < tokens.length; i++) {
            require(!_isVaultToken(tokens[i]), "OWT"); // vault token is part of TVL
        }
    }

    /// TODO: make a virtual function here? Or other better approach
    function _positionManager() internal view returns (INonfungiblePositionManager) {
        return IUniV3VaultGovernance(address(_vaultGovernance)).delayedProtocolParams().positionManager;
    }

    function _getWithdrawLiquidity(
        uint256 nft,
        Pair memory amounts,
        uint256[] memory totalAmounts
    ) internal view returns (uint256) {
        (, , , , , , , uint128 totalLiquidity, , , , ) = _positionManager().positions(nft);
        if (totalAmounts[0] == 0) {
            if (amounts.a0 == 0) {
                return (totalLiquidity * amounts.a1) / totalAmounts[1]; // liquidity1
            } else {
                return 0;
            }
        }
        if (totalAmounts[1] == 0) {
            if (amounts.a1 == 0) {
                return (totalLiquidity * amounts.a0) / totalAmounts[0]; // liquidity0
            } else {
                return 0;
            }
        }
        uint256 liquidity0 = (totalLiquidity * amounts.a0) / totalAmounts[0];
        uint256 liquidity1 = (totalLiquidity * amounts.a1) / totalAmounts[1];
        return liquidity0 < liquidity1 ? liquidity0 : liquidity1;
    }

    function _allowTokenIfNecessary(address token) internal {
        if (IERC20(token).allowance(address(_positionManager()), address(this)) < type(uint256).max / 2) {
            IERC20(token).approve(address(_positionManager()), type(uint256).max);
        }
    }

    function _parseOptions(bytes memory options) internal view returns (Options memory) {
        if (options.length == 0) {
            return Options({amount0Min: 0, amount1Min: 0, deadline: block.timestamp + 600});
        }
        require(options.length == 32 * 3, "IOL");
        return abi.decode(options, (Options));
    }
}
