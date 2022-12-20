// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "../interfaces/vaults/IUniV3VaultGovernance.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/external/LiquidityAmounts.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";
import "../utils/UniV3Helper.sol";

/// @notice Vault that interfaces UniswapV3 protocol in the integration layer.
contract UniV3Vault is IUniV3Vault, IntegrationVault {
    using SafeERC20 for IERC20;

    struct Pair {
        uint256 a0;
        uint256 a1;
    }

    /// @inheritdoc IUniV3Vault
    IUniswapV3Pool public pool;
    /// @inheritdoc IUniV3Vault
    uint256 public uniV3Nft;
    INonfungiblePositionManager private _positionManager;
    UniV3Helper private _uniV3Helper;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        if (uniV3Nft == 0) {
            return (new uint256[](2), new uint256[](2));
        }

        minTokenAmounts = new uint256[](2);
        maxTokenAmounts = new uint256[](2);
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        {
            IUniV3VaultGovernance.DelayedProtocolParams memory params = IUniV3VaultGovernance(address(_vaultGovernance))
                .delayedProtocolParams();
            {
                uint128 tokensOwed0;
                uint128 tokensOwed1;

                (tickLower, tickUpper, liquidity, tokensOwed0, tokensOwed1) = _uniV3Helper.calculatePositionInfo(
                    _positionManager,
                    pool,
                    uniV3Nft
                );

                minTokenAmounts[0] = tokensOwed0;
                maxTokenAmounts[0] = tokensOwed0;
                minTokenAmounts[1] = tokensOwed1;
                maxTokenAmounts[1] = tokensOwed1;
            }
            {
                uint256 amountMin0;
                uint256 amountMax0;
                uint256 amountMin1;
                uint256 amountMax1;
                uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
                uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
                (uint256 minPriceX96, uint256 maxPriceX96) = _getMinMaxPrice(params.oracle);
                {
                    uint256 minSqrtPriceX96 = CommonLibrary.sqrtX96(minPriceX96);
                    (amountMin0, amountMin1) = LiquidityAmounts.getAmountsForLiquidity(
                        uint160(minSqrtPriceX96),
                        sqrtPriceAX96,
                        sqrtPriceBX96,
                        liquidity
                    );
                }
                {
                    uint256 maxSqrtPriceX96 = CommonLibrary.sqrtX96(maxPriceX96);
                    (amountMax0, amountMax1) = LiquidityAmounts.getAmountsForLiquidity(
                        uint160(maxSqrtPriceX96),
                        sqrtPriceAX96,
                        sqrtPriceBX96,
                        liquidity
                    );
                }
                minTokenAmounts[0] += amountMin0 < amountMax0 ? amountMin0 : amountMax0;
                minTokenAmounts[1] += amountMin1 < amountMax1 ? amountMin1 : amountMax1;
                maxTokenAmounts[0] += amountMin0 < amountMax0 ? amountMax0 : amountMin0;
                maxTokenAmounts[1] += amountMin1 < amountMax1 ? amountMax1 : amountMin1;
            }
        }
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IUniV3Vault).interfaceId);
    }

    /// @inheritdoc IUniV3Vault
    function positionManager() external view returns (INonfungiblePositionManager) {
        return _positionManager;
    }

    /// @inheritdoc IUniV3Vault
    function liquidityToTokenAmounts(uint128 liquidity) external view returns (uint256[] memory tokenAmounts) {
        tokenAmounts = _uniV3Helper.liquidityToTokenAmounts(liquidity, pool, uniV3Nft, _positionManager);
    }

    /// @inheritdoc IUniV3Vault
    function tokenAmountsToLiquidity(uint256[] memory tokenAmounts) public view returns (uint128 liquidity) {
        liquidity = _uniV3Helper.tokenAmountsToLiquidity(tokenAmounts, pool, uniV3Nft, _positionManager);
    }

    // -------------------  EXTERNAL, MUTATING  -------------------
    /// @inheritdoc IUniV3Vault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        uint24 fee_,
        address uniV3Hepler_
    ) external {
        require(vaultTokens_.length == 2, ExceptionsLibrary.INVALID_VALUE);
        _initialize(vaultTokens_, nft_);
        _positionManager = IUniV3VaultGovernance(address(_vaultGovernance)).delayedProtocolParams().positionManager;
        pool = IUniswapV3Pool(
            IUniswapV3Factory(_positionManager.factory()).getPool(_vaultTokens[0], _vaultTokens[1], fee_)
        );
        _uniV3Helper = UniV3Helper(uniV3Hepler_);
        require(address(pool) != address(0), ExceptionsLibrary.NOT_FOUND);
    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory
    ) external returns (bytes4) {
        require(msg.sender == address(_positionManager), ExceptionsLibrary.FORBIDDEN);
        require(_isStrategy(operator), ExceptionsLibrary.FORBIDDEN);
        (, , address token0, address token1, uint24 fee, , , , , , , ) = _positionManager.positions(tokenId);
        // new position should have vault tokens
        require(
            token0 == _vaultTokens[0] && token1 == _vaultTokens[1] && fee == pool.fee(),
            ExceptionsLibrary.INVALID_TOKEN
        );

        if (uniV3Nft != 0) {
            (, , , , , , , uint128 liquidity, , , uint128 tokensOwed0, uint128 tokensOwed1) = _positionManager
                .positions(uniV3Nft);
            require(liquidity == 0 && tokensOwed0 == 0 && tokensOwed1 == 0, ExceptionsLibrary.INVALID_VALUE);
            // return previous uni v3 position nft
            _positionManager.transferFrom(address(this), from, uniV3Nft);
        }

        uniV3Nft = tokenId;
        return this.onERC721Received.selector;
    }

    /// @inheritdoc IUniV3Vault
    function collectEarnings() external nonReentrant returns (uint256[] memory collectedEarnings) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        address owner = registry.ownerOf(_nft);
        address to = _root(registry, _nft, owner).subvaultAt(0);
        collectedEarnings = new uint256[](2);
        (uint256 collectedEarnings0, uint256 collectedEarnings1) = _positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: uniV3Nft,
                recipient: to,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        collectedEarnings[0] = collectedEarnings0;
        collectedEarnings[1] = collectedEarnings1;
        emit CollectedEarnings(tx.origin, msg.sender, to, collectedEarnings0, collectedEarnings1);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _parseOptions(bytes memory options) internal view returns (Options memory) {
        if (options.length == 0) return Options({amount0Min: 0, amount1Min: 0, deadline: block.timestamp + 600});

        require(options.length == 32 * 3, ExceptionsLibrary.INVALID_VALUE);
        return abi.decode(options, (Options));
    }

    function _isStrategy(address addr) internal view returns (bool) {
        return _vaultGovernance.internalParams().registry.getApproved(_nft) == addr;
    }

    function _isReclaimForbidden(address) internal pure override returns (bool) {
        return false;
    }

    function _getMinMaxPrice(IOracle oracle) internal view returns (uint256 minPriceX96, uint256 maxPriceX96) {
        (uint256[] memory prices, ) = oracle.priceX96(_vaultTokens[0], _vaultTokens[1], 0x2A);
        require(prices.length > 1, ExceptionsLibrary.INVARIANT);
        minPriceX96 = prices[0];
        maxPriceX96 = prices[0];
        for (uint32 i = 1; i < prices.length; ++i) {
            if (prices[i] < minPriceX96) {
                minPriceX96 = prices[i];
            } else if (prices[i] > maxPriceX96) {
                maxPriceX96 = prices[i];
            }
        }
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        actualTokenAmounts = new uint256[](2);
        if (uniV3Nft == 0) return actualTokenAmounts;

        uint128 liquidity = tokenAmountsToLiquidity(tokenAmounts);

        if (liquidity == 0) return actualTokenAmounts;
        else {
            address[] memory tokens = _vaultTokens;
            for (uint256 i = 0; i < tokens.length; ++i) {
                IERC20(tokens[i]).safeIncreaseAllowance(address(_positionManager), tokenAmounts[i]);
            }

            Options memory opts = _parseOptions(options);
            Pair memory amounts = Pair({a0: tokenAmounts[0], a1: tokenAmounts[1]});
            Pair memory minAmounts = Pair({a0: opts.amount0Min, a1: opts.amount1Min});
            (, uint256 amount0, uint256 amount1) = _positionManager.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams({
                    tokenId: uniV3Nft,
                    amount0Desired: amounts.a0,
                    amount1Desired: amounts.a1,
                    amount0Min: minAmounts.a0,
                    amount1Min: minAmounts.a1,
                    deadline: opts.deadline
                })
            );

            actualTokenAmounts[0] = amount0;
            actualTokenAmounts[1] = amount1;

            for (uint256 i = 0; i < tokens.length; ++i) {
                IERC20(tokens[i]).safeApprove(address(_positionManager), 0);
            }
        }
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        // UniV3Vault should have strictly 2 vault tokens
        actualTokenAmounts = new uint256[](2);
        if (uniV3Nft == 0) return actualTokenAmounts;

        Options memory opts = _parseOptions(options);
        Pair memory amounts = _pullUniV3Nft(tokenAmounts, to, opts);
        actualTokenAmounts[0] = amounts.a0;
        actualTokenAmounts[1] = amounts.a1;
    }

    function _getMaximalLiquidityForAmounts(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount0);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint128 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(sqrtRatioX96, sqrtRatioBX96, amount0);
            uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioX96, amount1);

            liquidity = liquidity0 > liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount1);
        }
    }

    function _pullUniV3Nft(
        uint256[] memory tokenAmounts,
        address to,
        Options memory opts
    ) internal returns (Pair memory) {
        uint128 liquidityToPull;
        // scope the code below to avoid stack-too-deep exception
        {
            (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = _positionManager.positions(
                uniV3Nft
            );
            (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
            uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
            uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
            liquidityToPull = _getMaximalLiquidityForAmounts(
                sqrtPriceX96,
                sqrtPriceAX96,
                sqrtPriceBX96,
                tokenAmounts[0],
                tokenAmounts[1]
            );
            liquidityToPull = liquidity < liquidityToPull ? liquidity : liquidityToPull;
        }
        if (liquidityToPull != 0) {
            Pair memory minAmounts = Pair({a0: opts.amount0Min, a1: opts.amount1Min});
            _positionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: uniV3Nft,
                    liquidity: liquidityToPull,
                    amount0Min: minAmounts.a0,
                    amount1Min: minAmounts.a1,
                    deadline: opts.deadline
                })
            );
        }
        (uint256 amount0Collected, uint256 amount1Collected) = _positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: uniV3Nft,
                recipient: to,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        amount0Collected = amount0Collected > tokenAmounts[0] ? tokenAmounts[0] : amount0Collected;
        amount1Collected = amount1Collected > tokenAmounts[1] ? tokenAmounts[1] : amount1Collected;
        return Pair({a0: amount0Collected, a1: amount1Collected});
    }

    // --------------------------  EVENTS  --------------------------

    /// @notice Emitted when earnings are collected
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param to Receiver of the fees
    /// @param amount0 Amount of token0 collected
    /// @param amount1 Amount of token1 collected
    event CollectedEarnings(
        address indexed origin,
        address indexed sender,
        address indexed to,
        uint256 amount0,
        uint256 amount1
    );
}
