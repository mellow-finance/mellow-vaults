// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

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

contract MultiPoolHStrategyRebalancer is DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 1000_000_000;
    uint256 public constant Q96 = 2 ** 96;
    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;

    INonfungiblePositionManager public immutable positionManager;

    /// @param halfOfShortInterval half of the width of the uniV3 position measured in the strategy in ticks
    /// @param domainLowerTick lower tick of the domain uniV3 position
    /// @param domainUpperTick upper tick of the domain uniV3 position
    /// @param shortLowerTick lower tick of the short uniV3 positions
    /// @param shortUpperTick upper tick of the short uniV3 positions
    /// @param maxTickDeviation upper bound for an absolute deviation between the spot price and the price for a given number of seconds ago
    /// @param averageTickTimespan delta in seconds, passed to the oracle to get the average tick over the last averageTickTimespan seconds
    /// @param erc20Vault erc20Vault of the root vault system
    /// @param moneyVault erc20Vault of the root vault system
    /// @param swapPool uniswapV3 Pool needed to process swaps and for calculations of average tick
    /// @param router uniV3 router for swapping tokens
    /// @param amount0ForMint amount of token0 is tried to be deposited on the new position
    /// @param amount1ForMint amount of token1 is tried to be deposited on the new position
    /// @param erc20CapitalRatioD ratio of tokens kept in the money vault instead of erc20. The ratio is maintained for each token
    /// @param uniV3Weights array of weights for each uniV3Vault of uniV3Vault array, that shows the relative part of liquidity to be added in each uniV3Vault
    /// @param tokens sorted array of length two with addresses of tokens of the strategy
    /// @param uniV3Vaults array of uniV3Vault of the root vault system sorted by fees of pools
    struct StrategyData {
        int24 halfOfShortInterval;
        int24 domainLowerTick;
        int24 domainUpperTick;
        int24 shortLowerTick;
        int24 shortUpperTick;
        int24 maxTickDeviation;
        uint32 averageTickTimespan;
        IERC20Vault erc20Vault;
        IIntegrationVault moneyVault;
        IUniswapV3Pool swapPool;
        address router;
        uint256 amount0ForMint;
        uint256 amount1ForMint;
        uint256 erc20CapitalRatioD;
        uint256[] uniV3Weights;
        address[] tokens;
        IUniV3Vault[] uniV3Vaults;
    }

    /// @param money spot tvl of moneyVault
    /// @param uniV3 spot tvls of uniV3Vaults
    /// @param erc20 tvl of erc20Vault
    /// @param total total spot tvl of rootVault system
    /// @param totalUniV3 cumulative spot tvl over all uniV3Vault
    struct Tvls {
        uint256[] money;
        uint256[][] uniV3;
        uint256[] erc20;
        uint256[] total;
        uint256[] totalUniV3;
    }

    /// @param sqrtShortLowerX96 sqrt price X96 at lower tick in the short position
    /// @param sqrtShortUpperX96 sqrt price X96 at upper tick in the short position
    /// @param sqrtDomainLowerX96 sqrt price X96 at lower tick in the domain position
    /// @param sqrtDomainUpperX96 sqrt price X96 at upper tick in the domain position
    struct SqrtRatios {
        uint160 sqrtShortLowerX96;
        uint160 sqrtShortUpperX96;
        uint160 sqrtDomainLowerX96;
        uint160 sqrtDomainUpperX96;
    }

    /// @param newShortLowerTick expected lower tick of minted positions in each UniV3Vault
    /// @param newShortUpperTick expected upper tick of minted positions in each UniV3Vault
    /// @param swappedAmounts the expected amount of tokens swapped through the uniswap router
    /// @param drainedAmounts expected number of tokens transferred from uniV3Vault before burning positions
    /// @param pulledToUniV3 expected amount to be transferred to each uniV3Vault
    /// @param pulledFromUniV3 expected amount to be transferred from each uniV3Vault
    /// @param deadline deadline for the rebalancing transaction
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
    function createRebalancer(address strategy) external returns (MultiPoolHStrategyRebalancer rebalancer) {
        rebalancer = MultiPoolHStrategyRebalancer(Clones.clone(address(this)));
        rebalancer.initialize(strategy);
    }

    /// @param data structure with all immutable, mutable and internal params of the strategy
    function getTvls(StrategyData memory data) public returns (Tvls memory tvls) {
        bool hasUniV3Nft = data.uniV3Vaults[0].uniV3Nft() != 0;
        {
            if (hasUniV3Nft) {
                for (uint256 i = 0; i < data.uniV3Vaults.length; ++i) {
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
        if (hasUniV3Nft) {
            for (uint256 i = 0; i < data.uniV3Vaults.length; ++i) {
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

    /// @param data structure with all immutable, mutable and internal params of the strategy
    /// @param restrictions rebalance restrictions
    function processRebalance(
        StrategyData memory data,
        Restrictions memory restrictions
    ) external returns (Restrictions memory actualAmounts) {
        _requireAdmin();

        // Getting sqrtPriceX96 and spotTick from the swapPool. These parameters will be used for future ratio calculations.
        // It also needs to keep it in mind, that these parameters for different UniV3Vault could be slightly different.
        (uint160 sqrtPriceX96, int24 spotTick, , , , , ) = data.swapPool.slot0();
        bool newPositionMinted = false;
        {
            (int24 averageTick, , bool withFail) = OracleLibrary.consult(
                address(data.swapPool),
                data.averageTickTimespan
            );
            require(!withFail, ExceptionsLibrary.INVALID_STATE);
            for (uint256 i = 0; i < data.uniV3Vaults.length; i++) {
                (, int24 vaultSpotTick, , , , , ) = data.uniV3Vaults[i].pool().slot0();
                int24 tickDelta = vaultSpotTick - averageTick;
                if (tickDelta < 0) {
                    tickDelta = -tickDelta;
                }
                require(tickDelta < data.maxTickDeviation, ExceptionsLibrary.LIMIT_OVERFLOW);
            }
        }
        {
            (
                newPositionMinted,
                actualAmounts.newShortLowerTick,
                actualAmounts.newShortUpperTick,
                actualAmounts.drainedAmounts
            ) = _positionsRebalance(data, spotTick, restrictions);
            if (newPositionMinted) {
                data.shortLowerTick = actualAmounts.newShortLowerTick;
                data.shortUpperTick = actualAmounts.newShortUpperTick;
            }
        }

        Tvls memory tvls = getTvls(data);
        (
            uint256[] memory moneyExpected,
            uint256[][] memory uniV3Expected,
            uint256 expectedAmountOfToken0
        ) = calculateExpectedAmounts(data, sqrtPriceX96, tvls.total[0], tvls.total[1]);

        // pull extra tokens from subvaults to erc20Vault
        actualAmounts.pulledFromUniV3 = new uint256[][](data.uniV3Vaults.length);
        for (uint256 i = 0; i < data.uniV3Vaults.length; ++i) {
            actualAmounts.pulledFromUniV3[i] = _pullTokens(
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

        // swap tokens with swapRouter on UniswapV3
        actualAmounts.swappedAmounts = _swapRebalance(
            data,
            sqrtPriceX96,
            restrictions,
            tvls.total[0],
            expectedAmountOfToken0
        );

        // pull missing tokens from erc20Vault to subvaults
        actualAmounts.pulledToUniV3 = new uint256[][](data.uniV3Vaults.length);
        for (uint256 i = 0; i < data.uniV3Vaults.length; ++i) {
            actualAmounts.pulledToUniV3[i] = _pullTokens(
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

    // --------------------  EXTERNAL, VIEW  ----------------------

    /// @param sqrtPriceX96 sqrt prices X96 at lower and upper ticks of domain and short intervals
    /// @param sqrtPriceX96 sqrt price X96 at current spot tick in swapPool
    /// @param totalToken0 current actual amount of token 0 in the root vault system
    /// @param totalToken1 current actual amount of token 1 in the root vault system
    function calculateExpectedAmounts(
        StrategyData memory data,
        uint160 sqrtPriceX96,
        uint256 totalToken0,
        uint256 totalToken1
    )
        public
        view
        returns (uint256[] memory moneyExpected, uint256[][] memory uniV3Expected, uint256 expectedAmountOfToken0)
    {
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        uint256 totalCapitalInToken0 = totalToken0 + FullMath.mulDiv(totalToken1, Q96, priceX96);
        uint256[] memory totalUniV3Expected = new uint256[](2);
        SqrtRatios memory sqrtRatios = _calculateSqrtRatios(data);
        {
            uint256 uniCapitalInToken0;
            {
                uint256 uniV3RatioD = _calculateUniV3RatioD(sqrtRatios, sqrtPriceX96);
                uniCapitalInToken0 = FullMath.mulDiv(totalCapitalInToken0, uniV3RatioD, DENOMINATOR);
            }
            {
                uint256 ratioOfToken0D = _calculateRatioOfToken0D(
                    sqrtPriceX96,
                    sqrtRatios.sqrtShortLowerX96,
                    sqrtRatios.sqrtShortUpperX96
                );
                totalUniV3Expected[0] = FullMath.mulDiv(uniCapitalInToken0, ratioOfToken0D, DENOMINATOR);
                totalUniV3Expected[1] = FullMath.mulDiv(uniCapitalInToken0 - totalUniV3Expected[0], priceX96, Q96);
            }
            uint128 totalExpectedLiqudity = data.uniV3Vaults[0].tokenAmountsToLiquidity(totalUniV3Expected);
            // totalUniV3Expected calculated by liquidity may differ slightly from totalUniV3Expected calculated
            // by price from the `pool`. But according to our logic, the domain interval is much larger
            // than the short interval, so we store much fewer tokens (10-20% of the total capital) in UniV3 positions.
            // So we can compute this part a bit less accurately.

            (uniV3Expected, totalUniV3Expected) = _calculateUniV3VaultsExpectedAmounts(totalExpectedLiqudity, data);
        }

        expectedAmountOfToken0 = FullMath.mulDiv(
            totalCapitalInToken0,
            _calculateRatioOfToken0D(sqrtPriceX96, sqrtRatios.sqrtDomainLowerX96, sqrtRatios.sqrtDomainUpperX96),
            DENOMINATOR
        );

        moneyExpected = new uint256[](2);
        moneyExpected[0] = FullMath.mulDiv(
            expectedAmountOfToken0 - totalUniV3Expected[0],
            DENOMINATOR - data.erc20CapitalRatioD,
            DENOMINATOR
        );

        uint256 expectedAmountOfToken1 = FullMath.mulDiv(totalCapitalInToken0 - expectedAmountOfToken0, priceX96, Q96);
        moneyExpected[1] = FullMath.mulDiv(
            expectedAmountOfToken1 - totalUniV3Expected[1],
            DENOMINATOR - data.erc20CapitalRatioD,
            DENOMINATOR
        );
    }

    /// @param data structure with all immutable, mutable and internal params of the strategy
    /// @param tick current spot tick of swapPool
    function calculateNewPosition(
        StrategyData memory data,
        int24 tick
    ) public pure returns (int24 newShortLowerTick, int24 newShortUpperTick) {
        int24 lowerCentralTick = tick - (tick % data.halfOfShortInterval);
        int24 upperCentralTick = lowerCentralTick + data.halfOfShortInterval;

        if (tick - lowerCentralTick <= upperCentralTick - tick) {
            newShortLowerTick = lowerCentralTick - data.halfOfShortInterval;
            newShortUpperTick = lowerCentralTick + data.halfOfShortInterval;
        } else {
            newShortLowerTick = upperCentralTick - data.halfOfShortInterval;
            newShortUpperTick = upperCentralTick + data.halfOfShortInterval;
        }

        if (newShortLowerTick < data.domainLowerTick) {
            newShortLowerTick = data.domainLowerTick;
            newShortUpperTick = newShortLowerTick + data.halfOfShortInterval * 2;
        } else if (newShortUpperTick > data.domainUpperTick) {
            newShortUpperTick = data.domainUpperTick;
            newShortLowerTick = newShortUpperTick - data.halfOfShortInterval * 2;
        }
    }

    // ------------------- INTERNAL, MUTATING  --------------------

    /// @param data structure with all immutable, mutable and internal params of the strategy
    /// @param tick current spot tick of swapPool
    /// @param restrictions rebalance restrictions
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

    /// @param data structure with all immutable, mutable and internal params of the strategy
    /// @param restrictions rebalance restrictions
    function _updatePositions(
        StrategyData memory data,
        Restrictions memory restrictions
    ) private returns (uint256[][] memory drainedAmounts) {
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
            IUniV3Vault vault = data.uniV3Vaults[i];
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
                    fee: vault.pool().fee(), // TODO: may be we should add logic here
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

            positionManager.safeTransferFrom(address(this), address(vault), newNft);
            mintedPositions[i] = newNft;
            if (uniV3Nft != 0) {
                positionManager.burn(uniV3Nft);
                burntPositions[i] = uniV3Nft;
            }
        }
        IERC20(data.tokens[0]).safeApprove(address(positionManager), 0);
        IERC20(data.tokens[1]).safeApprove(address(positionManager), 0);

        emit PositionsMinted(mintedPositions);
        if (burntPositions[0] > 0) {
            emit PositionsBurned(burntPositions);
        }
    }

    /// @param data structure with all immutable, mutable and internal params of the strategy
    /// @param sqrtPriceX96 sqrt price X96 at current spot tick in swapPool
    /// @param restrictions rebalance restrictions
    /// @param currentAmountOfToken0 current actual amount of token0 in the root vault sytem
    /// @param expectedAmountOfToken0 expected amount of token0 in the root vault system after rebalance
    function _swapRebalance(
        StrategyData memory data,
        uint160 sqrtPriceX96,
        Restrictions memory restrictions,
        uint256 currentAmountOfToken0,
        uint256 expectedAmountOfToken0
    ) private returns (int256[] memory swappedAmounts) {
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        uint256 tokenInIndex;
        uint256 amountIn;
        if (expectedAmountOfToken0 > currentAmountOfToken0) {
            tokenInIndex = 1;
            amountIn = FullMath.mulDiv(expectedAmountOfToken0 - currentAmountOfToken0, priceX96, Q96);
        } else {
            tokenInIndex = 0;
            amountIn = currentAmountOfToken0 - expectedAmountOfToken0;
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
            fee: data.swapPool.fee(),
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

        swappedAmounts = new int256[](2);
        swappedAmounts[tokenInIndex ^ 1] = int256(amountOut);
        swappedAmounts[tokenInIndex] = -int256(amountIn);

        emit TokensSwapped(swapParams, amountOut);
    }

    /// @param tokens tokens of the strategy
    /// @param vault if isExtra true, then vault is a source vault from which tokens will be transferred, otherwise opposite
    /// @param erc20Vault if isExtra true, then vault is a destination vault on which tokens will be transferred, otherwise opposite
    /// @param expected expected amounts of tokens on vault
    /// @param tvl actual current amounts for tokens on vault
    /// @param restrictions restrictions for token transferring
    /// @param isExtra bool flag, that shows the direction of the tokens transfer
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
            }
        }
        if (pulledAmounts.length == 0) {
            pulledAmounts = new uint256[](2);
        }
        _compareAmounts(pulledAmounts, restrictions);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    /// @param totalExpectedLiquidity expected total liquidity over all uniV3Vaults after rebalance
    /// @param data structure with all immutable, mutable and internal params of the strategy
    function _calculateUniV3VaultsExpectedAmounts(
        uint128 totalExpectedLiquidity,
        StrategyData memory data
    ) private view returns (uint256[][] memory expectedTokenAmounts, uint256[] memory totalAmount) {
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < data.uniV3Weights.length; ++i) {
            totalWeight += data.uniV3Weights[i];
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

    /// @param actual actual pulled or transferred amounts of tokens
    /// @param expected expected pulled or transferred amounts of tokens
    function _compareAmounts(uint256[] memory actual, uint256[] memory expected) private pure {
        require(actual.length == expected.length, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < actual.length; i++) {
            require(actual[i] >= expected[i], ExceptionsLibrary.LIMIT_UNDERFLOW);
        }
    }

    /// @param data structure with all immutable, mutable and internal params of the strategy
    function _calculateSqrtRatios(StrategyData memory data) private pure returns (SqrtRatios memory sqrtRatios) {
        sqrtRatios.sqrtShortLowerX96 = TickMath.getSqrtRatioAtTick(data.shortLowerTick);
        sqrtRatios.sqrtShortUpperX96 = TickMath.getSqrtRatioAtTick(data.shortUpperTick);
        sqrtRatios.sqrtDomainLowerX96 = TickMath.getSqrtRatioAtTick(data.domainLowerTick);
        sqrtRatios.sqrtDomainUpperX96 = TickMath.getSqrtRatioAtTick(data.domainUpperTick);
    }

    /// @param sqrtRatios sqrt prices X96 lower and upper ticks of domain and short intervals
    /// @param sqrtPriceX96 sqrt price X96 at current spot tick in swapPool
    function _calculateUniV3RatioD(
        SqrtRatios memory sqrtRatios,
        uint160 sqrtPriceX96
    ) private pure returns (uint256 uniV3RatioD) {
        uniV3RatioD = FullMath.mulDiv(
            DENOMINATOR,
            2 *
                Q96 -
                FullMath.mulDiv(sqrtRatios.sqrtShortLowerX96, Q96, sqrtPriceX96) -
                FullMath.mulDiv(sqrtPriceX96, Q96, sqrtRatios.sqrtShortUpperX96),
            2 *
                Q96 -
                FullMath.mulDiv(sqrtRatios.sqrtDomainLowerX96, Q96, sqrtPriceX96) -
                FullMath.mulDiv(sqrtPriceX96, Q96, sqrtRatios.sqrtDomainUpperX96)
        );
    }

    /// @param sqrtSpotPriceX96 sqrt price X96 at spot tick
    /// @param sqrtLowerPriceX96 sqrt price X96 at lower tick of some position
    /// @param sqrtUpperPriceX96 sqrt price X96 at upper tick of some position
    function _calculateRatioOfToken0D(
        uint160 sqrtSpotPriceX96,
        uint160 sqrtLowerPriceX96,
        uint160 sqrtUpperPriceX96
    ) private pure returns (uint256 ratioOfToken0D) {
        ratioOfToken0D = FullMath.mulDiv(
            DENOMINATOR,
            sqrtUpperPriceX96 - sqrtSpotPriceX96,
            2 *
                sqrtUpperPriceX96 -
                sqrtSpotPriceX96 -
                FullMath.mulDiv(sqrtLowerPriceX96, sqrtUpperPriceX96, sqrtSpotPriceX96)
        );
    }

    /// @notice Emitted when new short positions minted in uniV3Vaults
    /// @param uniV3Nfts nfts of minted positions
    event PositionsMinted(uint256[] uniV3Nfts);

    /// @notice Emitted when old short positions burned in uniV3Vaults
    /// @param uniV3Nfts nfts of burned positions
    event PositionsBurned(uint256[] uniV3Nfts);

    /// @notice Emitted when a swap is called on the router
    /// @param swapParams parameters to process swap with UniswapV3 router
    /// @param amountOut recived amount of token during the swap
    event TokensSwapped(ISwapRouter.ExactInputSingleParams swapParams, uint256 amountOut);
}
