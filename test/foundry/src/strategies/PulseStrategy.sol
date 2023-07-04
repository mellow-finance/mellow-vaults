// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

import "../interfaces/utils/ILpCallback.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";

import "../libraries/external/FullMath.sol";
import "../libraries/external/OracleLibrary.sol";
import "../libraries/external/TickMath.sol";

import "../utils/ContractMeta.sol";
import "../utils/DefaultAccessControlLateInit.sol";

contract PulseStrategy is ContractMeta, Multicall, DefaultAccessControlLateInit, ILpCallback {
    using SafeERC20 for IERC20;

    uint256 public constant D6 = 10 ** 6;
    uint256 public constant D9 = 10 ** 9;
    uint256 public constant Q96 = 2 ** 96;

    INonfungiblePositionManager public immutable positionManager;

    /// @param router 1inch router to process swaps with optimal routing && smallest possible slippage
    /// @param erc20Vault buffer vault of rootVault system
    /// @param uniV3Vault vault containing a uniswap position, allowing to add and withdraw liquidity from it
    /// @param tokens array of length 2 with strategy and vaults tokens
    struct ImmutableParams {
        address router;
        IERC20Vault erc20Vault;
        IUniV3Vault uniV3Vault;
        address[] tokens;
    }

    /// @param priceImpactD6 coefficient to take into account the impact of changing the price during tokens swaps
    /// @param intervalWidth uniswap position interval width
    /// @param tickNeighborhood if the spot tick is inside [lowerTick + tickNeighborhood, upperTick - tickNeighborhood], then the position will not be rebalanced
    /// @param maxDeviationForVaultPool maximum deviation of the spot tick from the average tick for the pool of token 0 and token 1
    /// @param timespanForAverageTick time interval on which average ticks in pools are determined
    /// @param amount0Desired amount of token 0 to mint position on UniswapV3Pool
    /// @param amount1Desired amount of token 1 to mint position on UniswapV3Pool
    /// @param swapSlippageD coefficient to protect against price slippage when swapping tokens
    /// @param swappingAmountsCoefficientD coefficient of deviation of expected tokens for the swap and the actual number of exchanged tokens
    /// @param minSwapAmounts thresholds that cut off swap of an insignificant amount of tokens
    struct MutableParams {
        int24 priceImpactD6;
        int24 intervalWidth;
        int24 tickNeighborhood;
        int24 maxDeviationForVaultPool;
        uint32 timespanForAverageTick;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 swapSlippageD;
        uint256 swappingAmountsCoefficientD;
        uint256[] minSwapAmounts;
    }

    /// @param lowerTick lower tick of an interval
    /// @param upperTick upper tick of an interval
    struct Interval {
        int24 lowerTick;
        int24 upperTick;
    }

    /// @dev structure with all immutable params of the strategy
    ImmutableParams public immutableParams;
    /// @dev structure with all mutable params of the strategy
    MutableParams public mutableParams;

    /// @param positionManager_ Uniswap v3 NonfungiblePositionManager
    constructor(INonfungiblePositionManager positionManager_) {
        require(address(positionManager_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        positionManager = positionManager_;
    }

    /// @param immutableParams_ structure with all immutable params of the strategy
    /// @param admin admin of the strategy
    function initialize(ImmutableParams memory immutableParams_, address admin) external {
        checkImmutableParams(immutableParams_);
        immutableParams = immutableParams_;
        for (uint256 i = 0; i < 2; i++) {
            IERC20(immutableParams_.tokens[i]).safeIncreaseAllowance(address(positionManager), type(uint256).max);
            try
                immutableParams_.erc20Vault.externalCall(
                    immutableParams_.tokens[i],
                    IERC20.approve.selector,
                    abi.encode(immutableParams_.router, type(uint256).max)
                )
            returns (bytes memory) {} catch {}
        }
        DefaultAccessControlLateInit.init(admin);
    }

    /// @dev updates mutable params of the strategy. Only the admin can call the function
    /// @param mutableParams_ new params to set
    function updateMutableParams(MutableParams memory mutableParams_) external {
        _requireAdmin();
        checkMutableParams(mutableParams_, immutableParams);
        mutableParams = mutableParams_;
        emit UpdateMutableParams(tx.origin, msg.sender, mutableParams_);
    }

    /// @dev Rebalancing goes like this:
    /// 1. Function checks the current states of the pools, and if the volatility is significant, the transaction reverts.
    /// 2. If necessary, a new position is minted on uniV3Vault, and the previous one is burned.
    /// 3. Tokens on erc20Vault are swapped via AggregationRouterV5 so that the proportion matches the tokens on uniV3Vault.
    /// 4. The strategy transfers all possible tokens from erc20Vault to uniV3Vault.
    /// Only users with administrator or operator roles can call the function.
    /// @param deadline Timestamp by which the transaction must be completed
    /// @param swapData Data for swap on 1inch AggregationRouterV5
    function rebalance(uint256 deadline, bytes calldata swapData) external {
        require(block.timestamp <= deadline, ExceptionsLibrary.TIMESTAMP);
        _requireAtLeastOperator();
        ImmutableParams memory immutableParams_ = immutableParams;
        MutableParams memory mutableParams_ = mutableParams;
        IUniswapV3Pool pool = immutableParams_.uniV3Vault.pool();
        checkTickDeviation(mutableParams_, pool);

        (uint160 sqrtPriceX96, int24 spotTick, , , , , ) = pool.slot0();
        Interval memory interval = _positionsRebalance(immutableParams_, mutableParams_, spotTick, pool);
        _swapToTarget(immutableParams_, mutableParams_, interval, sqrtPriceX96, swapData);
        _pushIntoUniswap(immutableParams_);

        emit Rebalance(tx.origin, msg.sender);
    }

    /// @dev checks mutable params according to strategy restrictions
    /// @param params mutable parameters to be checked
    /// @param immutableParams_ structure with all immutable params of the strategy
    function checkMutableParams(MutableParams memory params, ImmutableParams memory immutableParams_) public view {
        int24 tickSpacing = immutableParams_.uniV3Vault.pool().tickSpacing();
        require(
            params.intervalWidth > 0 && params.intervalWidth % (2 * tickSpacing) == 0,
            ExceptionsLibrary.INVALID_VALUE
        );

        require(
            params.tickNeighborhood >= -params.intervalWidth && params.tickNeighborhood <= params.intervalWidth / 2,
            ExceptionsLibrary.LIMIT_OVERFLOW
        );

        require(params.maxDeviationForVaultPool > 0, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(params.timespanForAverageTick > 0, ExceptionsLibrary.VALUE_ZERO);
        require(params.timespanForAverageTick < 7 * 24 * 60 * 60, ExceptionsLibrary.VALUE_ZERO);

        require(params.amount0Desired > 0, ExceptionsLibrary.VALUE_ZERO);
        require(params.amount0Desired <= D9, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(params.amount1Desired > 0, ExceptionsLibrary.VALUE_ZERO);
        require(params.amount1Desired <= D9, ExceptionsLibrary.LIMIT_OVERFLOW);

        require(params.minSwapAmounts.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(params.swapSlippageD <= D9, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(params.swappingAmountsCoefficientD <= D9, ExceptionsLibrary.LIMIT_OVERFLOW);
    }

    /// @dev checks immutable params according to strategy restrictions
    /// @param params immutable parameters to be checked
    function checkImmutableParams(ImmutableParams memory params) public view {
        require(params.tokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(params.tokens[0] != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(params.tokens[1] != address(0), ExceptionsLibrary.ADDRESS_ZERO);

        require(params.router != address(0), ExceptionsLibrary.ADDRESS_ZERO);

        {
            require(address(params.erc20Vault) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
            address[] memory erc20VaultTokens = params.erc20Vault.vaultTokens();
            require(erc20VaultTokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
            require(erc20VaultTokens[0] == params.tokens[0], ExceptionsLibrary.INVARIANT);
            require(erc20VaultTokens[1] == params.tokens[1], ExceptionsLibrary.INVARIANT);
        }

        {
            require(address(params.uniV3Vault) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
            address[] memory uniV3VaultTokens = params.uniV3Vault.vaultTokens();
            require(uniV3VaultTokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
            require(uniV3VaultTokens[0] == params.tokens[0], ExceptionsLibrary.INVARIANT);
            require(uniV3VaultTokens[1] == params.tokens[1], ExceptionsLibrary.INVARIANT);
        }
    }

    /// @dev checks deviation of spot ticks of all pools in strategy from corresponding average ticks.
    /// If any deviation is large than maxDevation parameter for the pool, then the transaction will be reverted with a LIMIT_OVERFLOW error.
    /// If there are no observations 10 seconds ago in any of the considered pools, then the transaction will be reverted with an INVALID_STATE error.
    /// @param mutableParams_ structure with all mutable params of the strategy
    /// @param vaultPool UniswapV3Pool of uniV3Vault
    function checkTickDeviation(MutableParams memory mutableParams_, IUniswapV3Pool vaultPool) public view {
        (, int24 spotTick, , , , , ) = vaultPool.slot0();
        (int24 averageTick, , bool withFail) = OracleLibrary.consult(
            address(vaultPool),
            mutableParams_.timespanForAverageTick
        );
        require(!withFail, ExceptionsLibrary.INVALID_STATE);
        int24 tickDeviation = spotTick - averageTick;
        if (tickDeviation < 0) {
            tickDeviation = -tickDeviation;
        }
        require(tickDeviation < mutableParams_.maxDeviationForVaultPool, ExceptionsLibrary.LIMIT_OVERFLOW);
    }

    /// @param mutableParams_ structure with all mutable params of the strategy
    /// @param spotTick current spot tick of UniswapV3Pool of uniV3Vault
    /// @param pool UniswapV3Pool of uniV3Vault
    /// @param uniV3Nft Nft of uniswap position
    /// @return newInterval expected interval after reblance
    /// @return neededNewInterval flag that is true if it is needed to mint new interval
    function calculateNewPosition(
        MutableParams memory mutableParams_,
        int24 spotTick,
        IUniswapV3Pool pool,
        uint256 uniV3Nft
    ) public view returns (Interval memory newInterval, bool neededNewInterval) {
        if (uniV3Nft != 0) {
            Interval memory currentInterval;
            (, , , , , currentInterval.lowerTick, currentInterval.upperTick, , , , , ) = positionManager.positions(
                uniV3Nft
            );
            if (
                mutableParams_.tickNeighborhood + currentInterval.lowerTick <= spotTick &&
                spotTick <= currentInterval.upperTick - mutableParams_.tickNeighborhood &&
                mutableParams_.intervalWidth == currentInterval.upperTick - currentInterval.lowerTick
            ) {
                return (currentInterval, false);
            }
        }

        int24 tickSpacing = pool.tickSpacing();
        int24 centralTick = spotTick - (spotTick % tickSpacing);
        if ((spotTick % tickSpacing) * 2 > tickSpacing) {
            centralTick += tickSpacing;
        }

        newInterval.lowerTick = centralTick - mutableParams_.intervalWidth / 2;
        newInterval.upperTick = centralTick + mutableParams_.intervalWidth / 2;
        neededNewInterval = true;
    }

    /// @dev The function rebalances the position on the uniswap pool. If there was a position in the uniV3Vault,
    /// and the current tick is inside this position, taking into account the tickNeighborhood, then the position will not be rebalanced.
    /// Otherwise, if there is a position in the uniV3Vault, then all tokens will be sent to erc20Vault, the new position will be mined,
    /// and the old one will be burned.
    /// @param immutableParams_ structure with all immutable params of the strategy
    /// @param mutableParams_ structure with all mutable params of the strategy
    /// @param spotTick current spot tick of UniswapV3Pool of uniV3Vault
    /// @param pool UniswapV3Pool of uniV3Vault
    /// @return Interval The position on the uniV3Vault after the function is executed.
    function _positionsRebalance(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        int24 spotTick,
        IUniswapV3Pool pool
    ) private returns (Interval memory) {
        IUniV3Vault vault = immutableParams_.uniV3Vault;
        uint256 uniV3Nft = vault.uniV3Nft();
        (Interval memory interval, bool neededNewInterval) = calculateNewPosition(
            mutableParams_,
            spotTick,
            pool,
            uniV3Nft
        );

        if (!neededNewInterval) {
            vault.collectEarnings();
            return interval;
        } else if (uniV3Nft != 0) {
            vault.pull(
                address(immutableParams_.erc20Vault),
                immutableParams_.tokens,
                vault.liquidityToTokenAmounts(type(uint128).max),
                ""
            );
        }

        (uint256 newNft, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: immutableParams_.tokens[0],
                token1: immutableParams_.tokens[1],
                fee: pool.fee(),
                tickLower: interval.lowerTick,
                tickUpper: interval.upperTick,
                amount0Desired: mutableParams_.amount0Desired,
                amount1Desired: mutableParams_.amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: type(uint256).max
            })
        );
        positionManager.safeTransferFrom(address(this), address(vault), newNft);

        emit PositionMinted(newNft);
        if (uniV3Nft != 0) {
            positionManager.burn(uniV3Nft);
            emit PositionBurned(uniV3Nft);
        }
        return interval;
    }

    /// @dev calculate target ratio of token 1 to total capital after rebalance
    /// @param interval current interval on uniV3Vault
    /// @param sqrtSpotPriceX96 sqrt price X96 of spot tick
    /// @param spotPriceX96 price X96 of spot tick
    /// @return targetRatioOfToken1X96 ratio of token 1 multiplied by 2^96
    function calculateTargetRatioOfToken1(
        Interval memory interval,
        uint160 sqrtSpotPriceX96,
        uint256 spotPriceX96
    ) public pure returns (uint256 targetRatioOfToken1X96) {
        // y = L * (sqrt_p - sqrt_a)
        // x = L * (sqrt_b - sqrt_p) / (sqrt_b * sqrt_p)
        // targetRatioOfToken1X96 = y / (y + x * p)
        uint256 sqrtLowerPriceX96 = TickMath.getSqrtRatioAtTick(interval.lowerTick);
        uint256 sqrtUpperPriceX96 = TickMath.getSqrtRatioAtTick(interval.upperTick);
        if (sqrtLowerPriceX96 >= sqrtSpotPriceX96) {
            return 0;
        } else if (sqrtUpperPriceX96 <= sqrtSpotPriceX96) {
            return Q96;
        }

        uint256 x = FullMath.mulDiv(
            sqrtUpperPriceX96 - sqrtSpotPriceX96,
            Q96,
            FullMath.mulDiv(sqrtSpotPriceX96, sqrtUpperPriceX96, Q96)
        );
        uint256 y = sqrtSpotPriceX96 - sqrtLowerPriceX96;
        targetRatioOfToken1X96 = FullMath.mulDiv(y, Q96, FullMath.mulDiv(x, spotPriceX96, Q96) + y);
    }

    /// @dev notion link: https://www.notion.so/mellowprotocol/Swap-formula-53807cbf5c5641eda937dd1847d70f43
    /// calculates the token that needs to be swapped and its amount to get the target ratio of tokens in the erc20Vault.
    /// @param immutableParams_ structure with all immutable params of the strategy
    /// @param mutableParams_ structure with all mutable params of the strategy
    /// @param priceX96 price X96 of spot tick
    /// @param targetRatioOfToken1X96 target ratio of token 1 to total capital after rebalance
    /// @return tokenInIndex swap token index
    /// @return amountIn number of tokens to swap
    function calculateAmountsForSwap(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        uint256 priceX96,
        uint256 targetRatioOfToken1X96
    ) public view returns (uint256 tokenInIndex, uint256 amountIn) {
        uint256 targetRatioOfToken0X96 = Q96 - targetRatioOfToken1X96;
        (uint256[] memory currentAmounts, ) = immutableParams_.erc20Vault.tvl();
        uint256 currentRatioOfToken1X96 = FullMath.mulDiv(
            currentAmounts[1],
            Q96,
            currentAmounts[1] + FullMath.mulDiv(currentAmounts[0], priceX96, Q96)
        );

        uint256 feesX96 = FullMath.mulDiv(Q96, uint256(int256(mutableParams_.priceImpactD6)), D6);

        if (currentRatioOfToken1X96 > targetRatioOfToken1X96) {
            tokenInIndex = 1;
            // (dx * y0 - dy * x0 * p) / (1 - dy * fee)
            uint256 invertedPriceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
            amountIn = FullMath.mulDiv(
                FullMath.mulDiv(currentAmounts[1], targetRatioOfToken0X96, Q96) -
                    FullMath.mulDiv(targetRatioOfToken1X96, currentAmounts[0], invertedPriceX96),
                Q96,
                Q96 - FullMath.mulDiv(targetRatioOfToken1X96, feesX96, Q96)
            );
        } else {
            // (dy * x0 - dx * y0 / p) / (1 - dx * fee)
            tokenInIndex = 0;
            amountIn = FullMath.mulDiv(
                FullMath.mulDiv(currentAmounts[0], targetRatioOfToken1X96, Q96) -
                    FullMath.mulDiv(targetRatioOfToken0X96, currentAmounts[1], priceX96),
                Q96,
                Q96 - FullMath.mulDiv(targetRatioOfToken0X96, feesX96, Q96)
            );
        }
        if (amountIn > currentAmounts[tokenInIndex]) {
            amountIn = currentAmounts[tokenInIndex];
        }
    }

    /// @dev calculates the target ratio of tokens and swaps them
    /// @param immutableParams_ structure with all immutable params of the strategy
    /// @param mutableParams_ structure with all mutable params of the strategy
    /// @param interval current interval on uniV3Vault
    /// @param sqrtSpotPriceX96 sqrt price X96 of spot tick
    function _swapToTarget(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        Interval memory interval,
        uint160 sqrtSpotPriceX96,
        bytes calldata swapData
    ) private {
        uint256 priceX96 = FullMath.mulDiv(sqrtSpotPriceX96, sqrtSpotPriceX96, Q96);
        (uint256 tokenInIndex, uint256 amountIn) = calculateAmountsForSwap(
            immutableParams_,
            mutableParams_,
            priceX96,
            calculateTargetRatioOfToken1(interval, sqrtSpotPriceX96, priceX96)
        );

        if (amountIn < mutableParams_.minSwapAmounts[tokenInIndex]) {
            return;
        }

        if (tokenInIndex == 1) {
            priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
        }

        (uint256[] memory tvlBefore, ) = immutableParams_.erc20Vault.tvl();
        immutableParams_.erc20Vault.externalCall(immutableParams_.router, bytes4(swapData[:4]), swapData[4:]);
        (uint256[] memory tvlAfter, ) = immutableParams_.erc20Vault.tvl();

        require(tvlAfter[tokenInIndex] <= tvlBefore[tokenInIndex], ExceptionsLibrary.INVARIANT);
        require(tvlAfter[tokenInIndex ^ 1] >= tvlBefore[tokenInIndex ^ 1], ExceptionsLibrary.INVARIANT);

        uint256 actualAmountIn = tvlBefore[tokenInIndex] - tvlAfter[tokenInIndex];
        uint256 actualAmountOut = tvlAfter[tokenInIndex ^ 1] - tvlBefore[tokenInIndex ^ 1];
        uint256 actualSwapPriceX96 = FullMath.mulDiv(actualAmountOut, Q96, actualAmountIn);

        require(
            FullMath.mulDiv(priceX96, D9 - mutableParams_.swapSlippageD, D9) <= actualSwapPriceX96,
            ExceptionsLibrary.LIMIT_UNDERFLOW
        );

        require(
            FullMath.mulDiv(amountIn, D9 - mutableParams_.swappingAmountsCoefficientD, D9) <= actualAmountIn,
            ExceptionsLibrary.LIMIT_UNDERFLOW
        );

        require(
            FullMath.mulDiv(actualAmountIn, D9 - mutableParams_.swappingAmountsCoefficientD, D9) <= amountIn,
            ExceptionsLibrary.LIMIT_UNDERFLOW
        );

        emit TokensSwapped(actualAmountIn, actualAmountOut, tokenInIndex);
    }

    /// @dev pushed maximal possible amounts of tokens from erc20Vault to uniV3Vault
    /// @param immutableParams_ structure with all immutable params of the strategy
    function _pushIntoUniswap(ImmutableParams memory immutableParams_) private {
        (uint256[] memory tokenAmounts, ) = immutableParams_.erc20Vault.tvl();
        if (tokenAmounts[0] > 0 || tokenAmounts[1] > 0) {
            immutableParams_.erc20Vault.pull(
                address(immutableParams_.uniV3Vault),
                immutableParams_.tokens,
                tokenAmounts,
                ""
            );
        }
    }

    /// @inheritdoc ILpCallback
    function depositCallback() external {
        // pushes all tokens from erc20Vault to uniswap to prevent possible attacks
        _pushIntoUniswap(immutableParams);
    }

    /// @inheritdoc ILpCallback
    function withdrawCallback() external {}

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("PulseStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    /// @notice Emitted after a successful token swap
    /// @param amountIn amount of token, that pushed into SwapRouter
    /// @param amountOut amount of token, that recieved from SwapRouter
    /// @param tokenInIndex index of token, that pushed into SwapRouter
    event TokensSwapped(uint256 amountIn, uint256 amountOut, uint256 tokenInIndex);

    /// @notice Emited when mutable parameters are successfully updated
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param mutableParams Updated parameters
    event UpdateMutableParams(address indexed origin, address indexed sender, MutableParams mutableParams);

    /// @notice Emited when the rebalance is successfully completed
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    event Rebalance(address indexed origin, address indexed sender);

    /// @notice Emited when a new uniswap position is created
    /// @param tokenId nft of new uniswap position
    event PositionMinted(uint256 tokenId);

    /// @notice Emited when a uniswap position is burned
    /// @param tokenId nft of uniswap position
    event PositionBurned(uint256 tokenId);
}
