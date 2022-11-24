// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./DefaultAccessControlLateInit.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/vaults/IAaveVault.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";

contract MultiPoolHStrategyRebalancer is DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 1000_000_000;
    uint256 public constant Q96 = 2**96;
    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;

    INonfungiblePositionManager public immutable positionManager;

    /// @notice all data that needed to process rebalance
    struct StrategyData {
        int24 halfOfShortInterval;
        int24 domainLowerTick;
        int24 domainUpperTick;
        int24 shortLowerTick;
        int24 shortUpperTick;
        IERC20Vault erc20Vault;
        IIntegrationVault moneyVault;
        address router;
        uint256 amount0ForMint;
        uint256 amount1ForMint;
        uint256 erc20CapitalRatioD;
        uint256[] uniV3Weights;
        address[] tokens;
        IUniV3Vault[] uniV3Vaults;
    }

    /// @param money tvl of moneyVault
    /// @param uniV3 arrays of tvls of UniV3Vaults calculated by spot price
    /// @param erc20 tvl of erc20Vault
    /// @param total tvl of erc20RootVault calculated by spot price
    /// @param totalUniV3 cumulative tvl over all UniV3Vaults calculated by spot price
    struct Tvls {
        uint256[] money;
        uint256[][] uniV3;
        uint256[] erc20;
        uint256[] total;
        uint256[] totalUniV3;
    }

    /// @notice rebalance parameters restricting the tokens transfer
    struct Restrictions {
        int24 newShortLowerTick;
        int24 newShortUpperTick;
        int256[] swappedAmounts;
        uint256[][] drainedAmounts;
        uint256[][] pulledToUniV3;
        uint256[][] pulledFromUniV3;
        uint256 deadline;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------
    /// @notice constructs rebalancer
    /// @param positionManager_ NonfungiblePositionManager of UniswapV3 protocol
    /// @param strategy address of the strategy
    constructor(INonfungiblePositionManager positionManager_, address strategy) {
        require(address(positionManager_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(strategy != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        positionManager = positionManager_;
        DefaultAccessControlLateInit.init(strategy);
    }

    /// @param strategy address of the strategy
    function initialize(address strategy) external {
        DefaultAccessControlLateInit.init(strategy);
    }

    /// @param strategy address of the strategy
    /// @return rebalancer new instance of rebalances for given strategy
    function createRebalancer(address strategy) external returns (MultiPoolHStrategyRebalancer rebalancer) {
        rebalancer = MultiPoolHStrategyRebalancer(Clones.clone(address(this)));
        rebalancer.initialize(strategy);
    }

    /// @param data all needed data (addresses, ticks, amounts and ratios) to process rebalance
    /// @return tvls structure with information about tvls of all vaults of the system
    function getTvls(StrategyData memory data) public returns (Tvls memory tvls) {
        bool hasUniV3Nft = data.uniV3Vaults[0].uniV3Nft() != 0;
        {
            for (uint256 i = 0; i < data.uniV3Vaults.length; ++i) {
                if (hasUniV3Nft) {
                    data.uniV3Vaults[i].collectEarnings();
                }
            }

            if (IVault(data.moneyVault).supportsInterface(type(IAaveVault).interfaceId)) {
                IAaveVault(address(data.moneyVault)).updateTvls();
            }
        }

        (tvls.erc20, ) = IVault(data.erc20Vault).tvl();
        (tvls.money, ) = IVault(data.moneyVault).tvl();

        tvls.total = new uint256[](2);
        tvls.totalUniV3 = new uint256[](2);
        tvls.total[0] = tvls.erc20[0] + tvls.money[0];
        tvls.total[1] = tvls.erc20[1] + tvls.money[1];

        tvls.uniV3 = new uint256[][](data.uniV3Vaults.length);
        for (uint256 i = 0; i < data.uniV3Vaults.length; ++i) {
            if (hasUniV3Nft) {
                uint256 uniV3Nft = data.uniV3Vaults[i].uniV3Nft();
                (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(uniV3Nft);
                tvls.uniV3[i] = data.uniV3Vaults[i].liquidityToTokenAmounts(liquidity);
                tvls.totalUniV3[0] += tvls.uniV3[i][0];
                tvls.totalUniV3[1] += tvls.uniV3[i][1];
            }
        }

        tvls.total[0] += tvls.totalUniV3[0];
        tvls.total[1] += tvls.totalUniV3[1];
    }

    /// @param sqrtSpotPriceX96 sqrt ratio X96 at spot tick
    /// @param lowerTick lower tick of position
    /// @param upperTick upper tick of position
    function _calculateRatioOfToken0D(
        uint160 sqrtSpotPriceX96,
        int24 lowerTick,
        int24 upperTick
    ) private pure returns (uint256 ratioOfToken0D) {
        uint160 sqrtLowerPriceX96 = TickMath.getSqrtRatioAtTick(lowerTick);
        uint160 sqrtUpperPriceX96 = TickMath.getSqrtRatioAtTick(upperTick);
        ratioOfToken0D = FullMath.mulDiv(
            DENOMINATOR,
            sqrtUpperPriceX96 - sqrtSpotPriceX96,
            2 *
                sqrtUpperPriceX96 -
                sqrtSpotPriceX96 -
                FullMath.mulDiv(sqrtLowerPriceX96, sqrtUpperPriceX96, sqrtSpotPriceX96)
        );
    }

    /// @param data all needed data (addresses, ticks, amounts and ratios) to process rebalance
    function calculateNewPosition(StrategyData memory data, int24 tick)
        public
        pure
        returns (int24 newShortLowerTick, int24 newShortUpperTick)
    {
        int24 lowerTick = tick - (tick % data.halfOfShortInterval);
        int24 upperTick = lowerTick + data.halfOfShortInterval;

        if (tick - lowerTick <= upperTick - tick) {
            newShortLowerTick = lowerTick - data.halfOfShortInterval;
            newShortUpperTick = lowerTick + data.halfOfShortInterval;
        } else {
            newShortLowerTick = upperTick - data.halfOfShortInterval;
            newShortUpperTick = upperTick + data.halfOfShortInterval;
        }

        if (newShortLowerTick < data.domainLowerTick) {
            newShortLowerTick = data.domainLowerTick;
            newShortUpperTick = newShortLowerTick + data.halfOfShortInterval * 2;
        } else if (newShortUpperTick > data.domainUpperTick) {
            newShortUpperTick = data.domainUpperTick;
            newShortLowerTick = newShortUpperTick - data.halfOfShortInterval * 2;
        }
    }

    function _positionsRebalance(
        StrategyData memory data,
        int24 tick,
        Restrictions memory restrictions
    )
        private
        returns (
            bool needToMintNewPositions,
            int24 newShortLowerTick,
            int24 newShortUpperTick,
            uint256[][] memory drainedAmounts
        )
    {
        (newShortLowerTick, newShortUpperTick) = calculateNewPosition(data, tick);

        require(
            restrictions.newShortLowerTick == newShortLowerTick && restrictions.newShortUpperTick == newShortUpperTick,
            ExceptionsLibrary.INVARIANT
        );

        if (data.shortLowerTick == newShortLowerTick && data.shortUpperTick == newShortUpperTick) {
            drainedAmounts = new uint256[][](restrictions.drainedAmounts.length);
            for (uint256 i = 0; i < drainedAmounts.length; i++) {
                drainedAmounts[i] = new uint256[](2);
            }
            return (false, 0, 0, drainedAmounts);
        }

        data.shortLowerTick = newShortLowerTick;
        data.shortUpperTick = newShortUpperTick;
        drainedAmounts = _updatePositions(data, restrictions);
        needToMintNewPositions = true;
    }

    function _updatePositions(StrategyData memory data, Restrictions memory restrictions)
        private
        returns (uint256[][] memory drainedAmounts)
    {
        IERC20(data.tokens[0]).safeIncreaseAllowance(
            address(positionManager),
            data.amount0ForMint * data.uniV3Vaults.length
        );
        IERC20(data.tokens[1]).safeIncreaseAllowance(
            address(positionManager),
            data.amount1ForMint * data.uniV3Vaults.length
        );

        uint256[] memory mintedPositions = new uint256[](data.uniV3Vaults.length);
        uint256[] memory burntPositions = new uint256[](data.uniV3Vaults.length);
        drainedAmounts = new uint256[][](data.uniV3Vaults.length);
        for (uint256 i = 0; i < data.uniV3Vaults.length; ++i) {
            IUniV3Vault vault = IUniV3Vault(data.uniV3Vaults[i]);
            uint256 uniV3Nft = vault.uniV3Nft();

            if (uniV3Nft != 0) {
                drainedAmounts[i] = vault.pull(
                    address(data.erc20Vault),
                    data.tokens,
                    vault.liquidityToTokenAmounts(type(uint128).max),
                    ""
                );
            } else {
                drainedAmounts[i] = new uint256[](2);
            }

            _compareAmounts(drainedAmounts[i], restrictions.drainedAmounts[i]);
            (uint256 newNft, , , ) = positionManager.mint(
                INonfungiblePositionManager.MintParams({
                    token0: data.tokens[0],
                    token1: data.tokens[1],
                    fee: vault.pool().fee(),
                    tickLower: data.shortLowerTick,
                    tickUpper: data.shortUpperTick,
                    amount0Desired: data.amount0ForMint,
                    amount1Desired: data.amount1ForMint,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: type(uint256).max
                })
            );

            uint256 oldNft = vault.uniV3Nft();
            positionManager.safeTransferFrom(address(this), address(vault), newNft);
            mintedPositions[i] = newNft;
            if (oldNft != 0) {
                positionManager.burn(oldNft);
                burntPositions[i] = oldNft;
            }
        }
        IERC20(data.tokens[0]).safeApprove(address(positionManager), 0);
        IERC20(data.tokens[1]).safeApprove(address(positionManager), 0);

        emit PositionsMinted(mintedPositions);
        if (burntPositions[0] > 0) {
            emit PositionsBurned(burntPositions);
        }
    }

    function _swapRebalance(
        StrategyData memory data,
        uint160 sqrtPriceX96,
        Restrictions memory restrictions,
        uint256 currentAmount0,
        uint256 expectedAmount0
    ) private returns (int256[] memory swappedAmounts) {
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        uint256[] memory amountsForSwap = new uint256[](2);
        if (expectedAmount0 > currentAmount0) {
            amountsForSwap[1] = FullMath.mulDiv(expectedAmount0 - currentAmount0, priceX96, Q96);
        } else {
            amountsForSwap[0] = currentAmount0 - expectedAmount0;
        }

        if (amountsForSwap[0] > 0 || amountsForSwap[1] > 0) {
            swappedAmounts = _swapOneToAnother(data, amountsForSwap, restrictions);
        } else {
            swappedAmounts = new int256[](2);
        }
    }

    function _swapOneToAnother(
        StrategyData memory data,
        uint256[] memory amountsForSwap,
        Restrictions memory restrictions
    ) private returns (int256[] memory swappedAmounts) {
        uint256 tokenInIndex;
        uint256 amountIn;
        if (amountsForSwap[0] > 0) {
            amountIn = amountsForSwap[0];
            tokenInIndex = 0;
        } else {
            amountIn = amountsForSwap[1];
            tokenInIndex = 1;
        }

        if (amountIn == 0) {
            require(restrictions.swappedAmounts[tokenInIndex ^ 1] == 0, ExceptionsLibrary.LIMIT_OVERFLOW);
            require(restrictions.swappedAmounts[tokenInIndex] == 0, ExceptionsLibrary.LIMIT_UNDERFLOW);
            return new int256[](2);
        }

        IERC20Vault erc20Vault = IERC20Vault(data.erc20Vault);
        bytes memory routerResult;
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: data.tokens[tokenInIndex],
            tokenOut: data.tokens[tokenInIndex ^ 1],
            fee: IUniswapV3Pool(data.uniV3Vaults[0].pool()).fee(),
            recipient: address(data.erc20Vault),
            deadline: restrictions.deadline,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        bytes memory routerData = abi.encode(swapParams);
        erc20Vault.externalCall(data.tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(data.router, amountIn));
        routerResult = erc20Vault.externalCall(data.router, EXACT_INPUT_SINGLE_SELECTOR, routerData);
        erc20Vault.externalCall(data.tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(data.router, 0));
        uint256 amountOut = abi.decode(routerResult, (uint256));

        require(
            restrictions.swappedAmounts[tokenInIndex ^ 1] >= 0 && restrictions.swappedAmounts[tokenInIndex] <= 0,
            ExceptionsLibrary.INVARIANT
        );
        require(restrictions.swappedAmounts[tokenInIndex ^ 1] <= int256(amountOut), ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(restrictions.swappedAmounts[tokenInIndex] >= -int256(amountIn), ExceptionsLibrary.LIMIT_OVERFLOW);

        swappedAmounts = new int256[](2);
        swappedAmounts[tokenInIndex ^ 1] = int256(amountOut);
        swappedAmounts[tokenInIndex] = -int256(amountIn);

        emit TokensSwapped(swapParams, amountOut);
    }

    function _calculateUniV3RatioD(StrategyData memory data, uint160 sqrtPriceX96)
        private
        pure
        returns (uint256 uniV3RatioD)
    {
        uniV3RatioD = FullMath.mulDiv(
            DENOMINATOR,
            2 *
                Q96 -
                FullMath.mulDiv(TickMath.getSqrtRatioAtTick(data.shortLowerTick), Q96, sqrtPriceX96) -
                FullMath.mulDiv(sqrtPriceX96, Q96, TickMath.getSqrtRatioAtTick(data.shortUpperTick)),
            2 *
                Q96 -
                FullMath.mulDiv(TickMath.getSqrtRatioAtTick(data.domainLowerTick), Q96, sqrtPriceX96) -
                FullMath.mulDiv(sqrtPriceX96, Q96, TickMath.getSqrtRatioAtTick(data.domainUpperTick))
        );
    }

    /// @dev method calculated expected amounts after rebalance according to current tvl, spot tick and intervals
    function calculateExpectedAmounts(
        StrategyData memory data,
        uint160 sqrtPriceX96,
        uint256 totalToken0,
        uint256 totalToken1
    )
        public
        view
        returns (
            uint256[] memory moneyExpected,
            uint256[][] memory uniV3Expected,
            uint256 expectedAmount0
        )
    {
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        uint256 totalCapitalInToken0 = totalToken0 + FullMath.mulDiv(totalToken1, Q96, priceX96);
        uint256[] memory totalUniV3Expected = new uint256[](2);
        {
            uint256 uniV3RatioD = _calculateUniV3RatioD(data, sqrtPriceX96);
            uint256 uniCapitalInToken0 = FullMath.mulDiv(totalCapitalInToken0, uniV3RatioD, DENOMINATOR);
            uint256 ratioOfToken0D = _calculateRatioOfToken0D(sqrtPriceX96, data.shortLowerTick, data.shortUpperTick);

            totalUniV3Expected[0] = FullMath.mulDiv(uniCapitalInToken0, ratioOfToken0D, DENOMINATOR);
            totalUniV3Expected[1] = FullMath.mulDiv(uniCapitalInToken0 - totalUniV3Expected[0], priceX96, Q96);
            uint128 totalExpectedLiqudity = data.uniV3Vaults[0].tokenAmountsToLiquidity(totalUniV3Expected);
            // totalUniV3Expected calculated by liquidity may differ slightly from totalUniV3Expected calculated
            // by price from the `pool`. But according to our logic, the domain interval is much larger
            // than the short interval, so we store much fewer tokens (10-20% of the total capital) in UniV3 positions.
            // So we can compute this part a bit less accurately.

            (uniV3Expected, totalUniV3Expected) = _calculateUniV3VaultsExpectedAmounts(totalExpectedLiqudity, data);
        }

        expectedAmount0 = FullMath.mulDiv(
            totalCapitalInToken0,
            _calculateRatioOfToken0D(sqrtPriceX96, data.domainLowerTick, data.domainUpperTick),
            DENOMINATOR
        );

        moneyExpected = new uint256[](2);
        moneyExpected[0] = FullMath.mulDiv(
            expectedAmount0 - totalUniV3Expected[0],
            DENOMINATOR - data.erc20CapitalRatioD,
            DENOMINATOR
        );

        uint256 expectedAmount1 = FullMath.mulDiv(totalCapitalInToken0 - expectedAmount0, priceX96, Q96);
        moneyExpected[1] = FullMath.mulDiv(
            expectedAmount1 - totalUniV3Expected[1],
            DENOMINATOR - data.erc20CapitalRatioD,
            DENOMINATOR
        );
    }

    /// @dev method calculated expected amounts after rebalance on UniV3Vaults according to weights and expected total tvl on UniV3Vaults
    function _calculateUniV3VaultsExpectedAmounts(uint128 totalExpectedLiquidity, StrategyData memory data)
        private
        view
        returns (uint256[][] memory expectedTokenAmounts, uint256[] memory totalAmount)
    {
        uint256 totalWeight = 0;
        uint256 maxWeight = 0;
        uint256 indexOfVaultWithMaxWeight = 0;
        for (uint256 i = 0; i < data.uniV3Weights.length; ++i) {
            uint256 weight = data.uniV3Weights[i];
            totalWeight += weight;
            if (weight > maxWeight) {
                indexOfVaultWithMaxWeight = i;
                maxWeight = weight;
            }
        }

        totalAmount = new uint256[](2);
        expectedTokenAmounts = new uint256[][](data.uniV3Weights.length);
        for (uint256 i = 0; i < data.uniV3Weights.length; ++i) {
            uint256 weight = data.uniV3Weights[i];
            if (weight == 0) continue;
            uint128 expectedLiquidityOnVault = uint128(FullMath.mulDiv(weight, totalExpectedLiquidity, totalWeight));
            expectedTokenAmounts[i] = data.uniV3Vaults[i].liquidityToTokenAmounts(expectedLiquidityOnVault);
            totalAmount[0] += expectedTokenAmounts[i][0];
            totalAmount[1] += expectedTokenAmounts[i][1];
        }
    }

    /// @dev method transfers extra tokens from subvaults to erc20Vault according to current and expected amounts
    function _pullExtraTokens(
        StrategyData memory data,
        uint256[][] memory uniV3Expected,
        uint256[] memory moneyExpected,
        Restrictions memory restrictions,
        Tvls memory tvls
    ) private returns (uint256[][] memory pulledFromUniV3) {
        pulledFromUniV3 = new uint256[][](data.uniV3Vaults.length);
        for (uint256 i = 0; i < pulledFromUniV3.length; ++i) {
            pulledFromUniV3[i] = _pullTokens(
                data.tokens,
                data.uniV3Vaults[i],
                data.erc20Vault,
                uniV3Expected[i],
                tvls.uniV3[i],
                restrictions.pulledFromUniV3[i],
                true
            );
        }

        _pullTokens(data.tokens, data.moneyVault, data.erc20Vault, moneyExpected, tvls.money, new uint256[](2), true);
    }

    function _pullMissingTokens(
        StrategyData memory data,
        uint256[][] memory uniV3Expected,
        uint256[] memory moneyExpected,
        Restrictions memory restrictions,
        Tvls memory tvls
    ) private returns (uint256[][] memory pulledToUniV3) {
        pulledToUniV3 = new uint256[][](data.uniV3Vaults.length);
        for (uint256 i = 0; i < pulledToUniV3.length; ++i) {
            pulledToUniV3[i] = _pullTokens(
                data.tokens,
                data.uniV3Vaults[i],
                data.erc20Vault,
                uniV3Expected[i],
                tvls.uniV3[i],
                restrictions.pulledToUniV3[i],
                false
            );
        }

        _pullTokens(data.tokens, data.moneyVault, data.erc20Vault, moneyExpected, tvls.money, new uint256[](2), false);
    }

    /// @notice function for transfer tokens from one subvault like uniV3Vault or moneyVault to
    function _pullTokens(
        address[] memory tokens,
        IIntegrationVault vault,
        IERC20Vault erc20Vault,
        uint256[] memory expected,
        uint256[] memory tvl,
        uint256[] memory restrictions,
        bool isExtra
    ) private returns (uint256[] memory pulledAmounts) {
        if (isExtra) {
            uint256[] memory amountsToPull = new uint256[](2);
            if (tvl[0] > expected[0]) {
                amountsToPull[0] = tvl[0] - expected[0];
            }
            if (tvl[1] > expected[1]) {
                amountsToPull[1] = tvl[1] - expected[1];
            }
            if (amountsToPull[0] > 0 || amountsToPull[1] > 0) {
                pulledAmounts = vault.pull(address(erc20Vault), tokens, amountsToPull, "");
                _compareAmounts(pulledAmounts, restrictions);
            }
        } else {
            uint256[] memory amountsToPull = new uint256[](2);
            if (tvl[0] < expected[0]) {
                amountsToPull[0] = expected[0] - tvl[0];
            }
            if (tvl[1] < expected[1]) {
                amountsToPull[1] = expected[1] - tvl[1];
            }
            if (amountsToPull[0] > 0 || amountsToPull[1] > 0) {
                pulledAmounts = erc20Vault.pull(address(vault), tokens, amountsToPull, "");
                _compareAmounts(pulledAmounts, restrictions);
            }
        }
        if (pulledAmounts.length == 0) {
            pulledAmounts = new uint256[](2);
        }
    }

    /// @notice main method to process rebalance in strategy
    /// @param data structure with all needed addresses, intervals parameters, token amounts and ratios that set during deploy and initializing of the strategy needed to process the rebalance
    /// @param restrictions restrictions for token amounts to be transfered and new short interval to be minted
    /// @return actualAmounts actual transferred amounts and new minted short intervals
    function processRebalance(StrategyData memory data, Restrictions memory restrictions)
        external
        returns (Restrictions memory actualAmounts)
    {
        _requireAdmin();

        // Getting sqrtPriceX96 and spotTick from pool of the first UniV3Vault. These parameters will be used for future ratio calculations.
        // It is also need to keep it in mind, that these parameters for different UniV3Vault could be slightly different.
        (uint160 sqrtPriceX96, int24 spotTick, , , , , ) = data.uniV3Vaults[0].pool().slot0();
        bool newPositionMinted = false;
        int24 newLowerTick;
        int24 newUpperTick;
        {
            (newPositionMinted, newLowerTick, newUpperTick, actualAmounts.drainedAmounts) = _positionsRebalance(
                data,
                spotTick,
                restrictions
            );
            if (newPositionMinted) {
                data.shortLowerTick = newLowerTick;
                data.shortUpperTick = newUpperTick;
                actualAmounts.newShortLowerTick = newLowerTick;
                actualAmounts.newShortUpperTick = newUpperTick;
            }
        }

        Tvls memory tvls = getTvls(data);
        (
            uint256[] memory moneyExpected,
            uint256[][] memory uniV3Expected,
            uint256 expectedAmount0
        ) = calculateExpectedAmounts(data, sqrtPriceX96, tvls.total[0], tvls.total[1]);

        actualAmounts.pulledFromUniV3 = _pullExtraTokens(data, uniV3Expected, moneyExpected, restrictions, tvls);
        actualAmounts.swappedAmounts = _swapRebalance(data, sqrtPriceX96, restrictions, tvls.total[0], expectedAmount0);
        actualAmounts.pulledToUniV3 = _pullMissingTokens(data, uniV3Expected, moneyExpected, restrictions, tvls);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    /// @notice method comparing needed amount of tokens and actual. Reverts in for any elent holds needed[i] > actual[i]
    /// @param expected the needed amount of tokens from some action
    /// @param actual actual amount of tokens from the action
    function _compareAmounts(uint256[] memory actual, uint256[] memory expected) private pure {
        require(actual.length == expected.length, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < actual.length; i++) {
            require(actual[i] >= expected[i], ExceptionsLibrary.LIMIT_UNDERFLOW);
        }
    }

    // EVENTS

    event PositionsMinted(uint256[] uniV3Nfts);

    event PositionsBurned(uint256[] uniV3Nfts);

    /// @notice Emitted when tokens swapped via uniswap router
    /// @param swapParams Swap domainPositionParams
    /// @param amountOut recieved amount of token during the swap
    event TokensSwapped(ISwapRouter.ExactInputSingleParams swapParams, uint256 amountOut);
}
