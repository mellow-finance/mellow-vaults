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
import "../libraries/external/OracleLibrary.sol";

contract SinglePositionRebalancer is DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 1000_000_000;
    uint256 public constant Q96 = 2**96;
    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;

    INonfungiblePositionManager public immutable positionManager;

    /// @param domainLowerTick lower tick of the domain uniV3 position
    /// @param domainUpperTick upper tick of the domain uniV3 position
    /// @param maxTickDeviation upper bound for an absolute deviation between the spot price and the price for a given number of seconds ago
    /// @param averageTickTimespan delta in seconds, passed to the oracle to get the average tick over the last averageTickTimespan seconds
    /// @param erc20Vault erc20Vault of the root vault system
    /// @param uniV3Vault uniV3Vault of the root vault system
    // / @param s uniswapV3 Pool needed to process swaps and for calculations of average tick
    /// @param router uniV3 router for swapping tokens
    /// @param amount0ForMint amount of token0 is tried to be deposited on the new position
    /// @param amount1ForMint amount of token1 is tried to be deposited on the new position
    /// @param erc20CapitalRatioD ratio of tokens kept in the money vault instead of erc20. The ratio is maintained for each token
    /// @param uniV3Weights array of weights for each uniV3Vault of uniV3Vault array, that shows the relative part of liquidity to be added in each uniV3Vault
    /// @param tokens sorted array of length two with addresses of tokens of the strategy
    struct StrategyData {
        int24 lowerTick;
        int24 upperTick;
        int24 maxTickDeviation;
        int24 tickSpacing;
        uint24 swapFee;
        uint32 averageTickTimespan;
        IERC20Vault erc20Vault;
        IUniV3Vault uniV3Vault;
        address router;
        uint256 amount0ForMint;
        uint256 amount1ForMint;
        uint256 erc20CapitalRatioD;
        uint256 swapSlippageD;
        address[] tokens;
    }

    /// @param money spot tvl of moneyVault
    /// @param uniV3 spot tvls of uniV3Vaults
    /// @param erc20 tvl of erc20Vault
    /// @param total total spot tvl of rootVault system
    /// @param totalUniV3 cumulative spot tvl over all uniV3Vault
    struct Tvls {
        uint256[] uniV3;
        uint256[] erc20;
        uint256[] total;
    }

    /// @param newLowerTick expected lower tick of minted positions in UniV3Vault
    /// @param newUpperTick expected upper tick of minted positions in UniV3Vault
    /// @param swappedAmounts the expected amount of tokens swapped through the uniswap router
    /// @param drainedAmounts expected number of tokens transferred from uniV3Vault before burning positions
    /// @param pulledToUniV3 expected amount to be transferred to uniV3Vault
    /// @param pulledFromUniV3 expected amount to be transferred from uniV3Vault
    /// @param deadline deadline for the rebalancing transaction
    struct Restrictions {
        Interval newInterval;
        int256[] swappedAmounts;
        uint256[] drainedAmounts;
        uint256[] pulledToUniV3;
        uint256[] pulledFromUniV3;
        uint256 deadline;
    }

    struct Interval {
        int24 lowerTick;
        int24 upperTick;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @notice constructs a rebalancer
    /// @param positionManager_ Uniswap V3 NonfungiblePositionManager
    constructor(INonfungiblePositionManager positionManager_) {
        require(address(positionManager_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        positionManager = positionManager_;
        DefaultAccessControlLateInit.init(address(this));
    }

    /// @notice initializes the rebalancer
    /// @param strategy address of the strategy for current rebalancer
    function initialize(address strategy) external {
        DefaultAccessControlLateInit.init(strategy);
    }

    /// @notice creates the clone of the rebalancer
    /// @param strategy address of the strategy for new rebalancer
    /// @return rebalancer new cloned rebalancer for given strategy
    function createRebalancer(address strategy) external returns (SinglePositionRebalancer rebalancer) {
        rebalancer = SinglePositionRebalancer(Clones.clone(address(this)));
        rebalancer.initialize(strategy);
    }

    /// @param data structure with all immutable, mutable and internal params of the strategy
    function getTvls(StrategyData memory data) public returns (Tvls memory tvls) {
        (tvls.erc20, ) = IVault(data.erc20Vault).tvl();

        uint256 uniV3Nft = data.uniV3Vault.uniV3Nft();
        if (uniV3Nft > 0) {
            data.uniV3Vault.collectEarnings();
            (, , , , , , , uint128 liquidity, , , , ) = positionManager.positions(uniV3Nft);
            tvls.uniV3 = data.uniV3Vault.liquidityToTokenAmounts(liquidity);
        } else {
            tvls.uniV3 = new uint256[](2);
        }

        tvls.total = new uint256[](2);
        tvls.total[0] = tvls.erc20[0] + tvls.uniV3[0];
        tvls.total[1] = tvls.erc20[1] + tvls.uniV3[1];
    }

    /// @param data structure with all immutable, mutable and internal params of the strategy
    /// @param restrictions rebalance restrictions
    function processRebalance(StrategyData memory data, Restrictions memory restrictions)
        external
        returns (Restrictions memory actualAmounts)
    {
        _requireAdmin();

        // Getting sqrtPriceX96 and spotTick from the swapPool. These parameters will be used for future ratio calculations.
        // It also needs to keep it in mind, that these parameters for different UniV3Vault could be slightly different.
        IUniswapV3Pool pool = data.uniV3Vault.pool();

        (uint160 sqrtPriceX96, int24 spotTick, , , , , ) = pool.slot0();
        {
            (int24 averageTick, , bool withFail) = OracleLibrary.consult(address(pool), data.averageTickTimespan);
            require(!withFail, ExceptionsLibrary.INVALID_STATE);
            int24 tickDelta = spotTick - averageTick;
            if (tickDelta < 0) {
                tickDelta = -tickDelta;
            }
            require(tickDelta < data.maxTickDeviation, ExceptionsLibrary.LIMIT_OVERFLOW);

            checkNewInterval(data.tickSpacing, spotTick, restrictions.newInterval);
        }
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        bool newPositionMinted;
        (newPositionMinted, actualAmounts.newInterval, actualAmounts.drainedAmounts) = _positionsRebalance(
            data,
            restrictions
        );
        if (newPositionMinted) {
            data.lowerTick = actualAmounts.newInterval.lowerTick;
            data.upperTick = actualAmounts.newInterval.upperTick;
        }

        Tvls memory tvls = getTvls(data);
        (uint256[] memory uniV3Expected, uint256 expectedAmountOfToken0) = calculateExpectedAmounts(
            data,
            priceX96,
            sqrtPriceX96,
            tvls.total[0],
            tvls.total[1]
        );

        actualAmounts.pulledFromUniV3 = _pullExtraTokens(data, restrictions, uniV3Expected, tvls.uniV3);
        actualAmounts.swappedAmounts = _swapRebalance(
            data,
            priceX96,
            restrictions,
            tvls.total[0],
            expectedAmountOfToken0
        );
        actualAmounts.pulledToUniV3 = _pullMissingTokens(data, restrictions, uniV3Expected, tvls.uniV3);
    }

    // --------------------  EXTERNAL, VIEW  ----------------------

    /// @param totalToken0 current actual amount of token 0 in the root vault system
    /// @param totalToken1 current actual amount of token 1 in the root vault system
    function calculateExpectedAmounts(
        StrategyData memory data,
        uint256 priceX96,
        uint160 sqrtSpotPriceX96,
        uint256 totalToken0,
        uint256 totalToken1
    ) public pure returns (uint256[] memory uniV3Expected, uint256 expectedAmountOfToken0) {
        uint256 totalCapitalInToken0 = totalToken0 + FullMath.mulDiv(totalToken1, Q96, priceX96);
        uint160 sqrtLowerPriceX96 = TickMath.getSqrtRatioAtTick(data.lowerTick);
        uint160 sqrtUpperPriceX96 = TickMath.getSqrtRatioAtTick(data.upperTick);
        uint256 ratioOfToken0D = FullMath.mulDiv(
            DENOMINATOR,
            sqrtUpperPriceX96 - sqrtSpotPriceX96,
            2 *
                sqrtUpperPriceX96 -
                sqrtSpotPriceX96 -
                FullMath.mulDiv(sqrtLowerPriceX96, sqrtUpperPriceX96, sqrtSpotPriceX96)
        );

        expectedAmountOfToken0 = FullMath.mulDiv(totalCapitalInToken0, ratioOfToken0D, DENOMINATOR);

        uniV3Expected = new uint256[](2);
        uniV3Expected[0] = FullMath.mulDiv(expectedAmountOfToken0, DENOMINATOR - data.erc20CapitalRatioD, DENOMINATOR);
        uniV3Expected[1] = FullMath.mulDiv(
            FullMath.mulDiv(
                totalCapitalInToken0 - expectedAmountOfToken0,
                DENOMINATOR - data.erc20CapitalRatioD,
                DENOMINATOR
            ),
            priceX96,
            Q96
        );
    }

    /// @param tick current spot tick of swapPool
    function checkNewInterval(
        int24 tickSpacing,
        int24 tick,
        Interval memory newInterval
    ) public pure {
        // может быть мы здесь хотим сами передавать определённый тик?
        // чтобы быть уверенным, что позиция отребалансирует более хорошо?..
        // как можно это определить?

        require(newInterval.lowerTick % tickSpacing == 0, ExceptionsLibrary.INVALID_VALUE);
        require(newInterval.upperTick % tickSpacing == 0, ExceptionsLibrary.INVALID_VALUE);
        require(newInterval.lowerTick < newInterval.upperTick, ExceptionsLibrary.INVALID_VALUE);

        require(newInterval.lowerTick <= tick, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(newInterval.upperTick >= tick, ExceptionsLibrary.LIMIT_OVERFLOW);
    }

    // ------------------- INTERNAL, MUTATING  --------------------

    /// @param data structure with all immutable, mutable and internal params of the strategy
    /// @param restrictions rebalance restrictions
    function _positionsRebalance(StrategyData memory data, Restrictions memory restrictions)
        private
        returns (
            bool newPositionMinted,
            Interval memory newInterval,
            uint256[] memory drainedAmounts
        )
    {
        newInterval = restrictions.newInterval;
        if (data.lowerTick == newInterval.lowerTick && data.upperTick == newInterval.upperTick) {
            return (false, Interval({lowerTick: 0, upperTick: 0}), new uint256[](2));
        }

        IERC20(data.tokens[0]).safeIncreaseAllowance(address(positionManager), data.amount0ForMint);
        IERC20(data.tokens[1]).safeIncreaseAllowance(address(positionManager), data.amount1ForMint);

        IUniV3Vault vault = data.uniV3Vault;
        uint256 uniV3Nft = vault.uniV3Nft();

        if (uniV3Nft != 0) {
            drainedAmounts = vault.pull(
                address(data.erc20Vault),
                data.tokens,
                vault.liquidityToTokenAmounts(type(uint128).max),
                ""
            );
        } else {
            drainedAmounts = new uint256[](2);
        }
        _compareAmounts(drainedAmounts, restrictions.drainedAmounts);

        (uint256 newNft, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: data.tokens[0],
                token1: data.tokens[1],
                fee: vault.pool().fee(),
                tickLower: newInterval.lowerTick,
                tickUpper: newInterval.upperTick,
                amount0Desired: data.amount0ForMint,
                amount1Desired: data.amount1ForMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: type(uint256).max
            })
        );
        positionManager.safeTransferFrom(address(this), address(vault), newNft);

        if (uniV3Nft != 0) {
            positionManager.burn(uniV3Nft);
            emit PositionBurned(uniV3Nft);
        }
        emit PositionMinted(newNft);

        IERC20(data.tokens[0]).safeApprove(address(positionManager), 0);
        IERC20(data.tokens[1]).safeApprove(address(positionManager), 0);

        newPositionMinted = true;
    }

    /// @param data structure with all immutable, mutable and internal params of the strategy
    /// @param priceX96 price X96 at current spot tick in swapPool
    /// @param restrictions rebalance restrictions
    /// @param currentAmountOfToken0 current actual amount of token0 in the root vault sytem
    /// @param expectedAmountOfToken0 expected amount of token0 in the root vault system after rebalance
    function _swapRebalance(
        StrategyData memory data,
        uint256 priceX96,
        Restrictions memory restrictions,
        uint256 currentAmountOfToken0,
        uint256 expectedAmountOfToken0
    ) private returns (int256[] memory swappedAmounts) {
        uint256 tokenInIndex;
        uint256 amountIn;
        uint256 expectedAmountOut;
        if (expectedAmountOfToken0 > currentAmountOfToken0) {
            tokenInIndex = 1;
            amountIn = FullMath.mulDiv(expectedAmountOfToken0 - currentAmountOfToken0, priceX96, Q96);
            expectedAmountOut = expectedAmountOfToken0 - currentAmountOfToken0;
        } else {
            tokenInIndex = 0;
            amountIn = currentAmountOfToken0 - expectedAmountOfToken0;
            expectedAmountOut = FullMath.mulDiv(amountIn, priceX96, Q96);
        }

        if (amountIn == 0) {
            require(restrictions.swappedAmounts[tokenInIndex ^ 1] == 0, ExceptionsLibrary.LIMIT_OVERFLOW);
            require(restrictions.swappedAmounts[tokenInIndex] == 0, ExceptionsLibrary.LIMIT_UNDERFLOW);
            return new int256[](2);
        }

        require(
            restrictions.swappedAmounts[tokenInIndex ^ 1] >= 0 && restrictions.swappedAmounts[tokenInIndex] <= 0,
            ExceptionsLibrary.INVARIANT
        );

        bytes memory routerResult;
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: data.tokens[tokenInIndex],
            tokenOut: data.tokens[tokenInIndex ^ 1],
            fee: data.swapFee,
            recipient: address(data.erc20Vault),
            deadline: restrictions.deadline,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        data.erc20Vault.externalCall(data.tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(data.router, amountIn));
        routerResult = data.erc20Vault.externalCall(data.router, EXACT_INPUT_SINGLE_SELECTOR, abi.encode(swapParams));
        data.erc20Vault.externalCall(data.tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(data.router, 0));
        uint256 amountOut = abi.decode(routerResult, (uint256));

        require(restrictions.swappedAmounts[tokenInIndex ^ 1] <= int256(amountOut), ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(restrictions.swappedAmounts[tokenInIndex] >= -int256(amountIn), ExceptionsLibrary.LIMIT_OVERFLOW);
        // additional slippage check to make sure the swap was successful
        // possibly its fail if we use in swap and in uniV3Vault two different pools
        require(
            amountOut >= FullMath.mulDiv(expectedAmountOut, data.swapSlippageD, DENOMINATOR),
            ExceptionsLibrary.LIMIT_UNDERFLOW
        );

        swappedAmounts = new int256[](2);
        swappedAmounts[tokenInIndex ^ 1] = int256(amountOut);
        swappedAmounts[tokenInIndex] = -int256(amountIn);

        emit TokensSwapped(swapParams, amountOut);
    }

    function _pullExtraTokens(
        StrategyData memory data,
        Restrictions memory restrictions,
        uint256[] memory expected,
        uint256[] memory tvl
    ) private returns (uint256[] memory pulledFromUniV3) {
        uint256[] memory amountsToPull = new uint256[](2);
        if (tvl[0] > expected[0]) amountsToPull[0] = tvl[0] - expected[0];
        if (tvl[1] > expected[1]) amountsToPull[1] = tvl[1] - expected[1];
        if (amountsToPull[0] > 0 || amountsToPull[1] > 0) {
            pulledFromUniV3 = data.uniV3Vault.pull(address(data.erc20Vault), data.tokens, amountsToPull, "");
        } else {
            pulledFromUniV3 = new uint256[](2);
        }
        _compareAmounts(pulledFromUniV3, restrictions.pulledFromUniV3);
    }

    function _pullMissingTokens(
        StrategyData memory data,
        Restrictions memory restrictions,
        uint256[] memory expected,
        uint256[] memory tvl
    ) private returns (uint256[] memory pulledToUniV3) {
        uint256[] memory amountsToPull = new uint256[](2);
        if (tvl[0] < expected[0]) amountsToPull[0] = expected[0] - tvl[0];
        if (tvl[1] < expected[1]) amountsToPull[1] = expected[1] - tvl[1];
        if (amountsToPull[0] > 0 || amountsToPull[1] > 0) {
            pulledToUniV3 = data.erc20Vault.pull(address(data.uniV3Vault), data.tokens, amountsToPull, "");
        } else {
            pulledToUniV3 = new uint256[](2);
        }
        _compareAmounts(pulledToUniV3, restrictions.pulledToUniV3);
    }

    // -------------------  INTERNAL, VIEW  -------------------s

    /// @param actual actual pulled or transferred amounts of tokens
    /// @param expected expected pulled or transferred amounts of tokens
    function _compareAmounts(uint256[] memory actual, uint256[] memory expected) private pure {
        require(actual.length == expected.length, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < actual.length; i++) {
            require(actual[i] >= expected[i], ExceptionsLibrary.LIMIT_UNDERFLOW);
        }
    }

    /// @notice Emitted when new positions minted in uniV3Vault
    /// @param uniV3Nft nft of minted positions
    event PositionMinted(uint256 uniV3Nft);

    /// @notice Emitted when old position burned in uniV3Vault
    /// @param uniV3Nft nft of burned positions
    event PositionBurned(uint256 uniV3Nft);

    /// @notice Emitted when a swap is called on the router
    /// @param swapParams parameters to process swap with UniswapV3 router
    /// @param amountOut recived amount of token during the swap
    event TokensSwapped(ISwapRouter.ExactInputSingleParams swapParams, uint256 amountOut);
}
