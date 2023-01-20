// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/external/quickswap/IAlgebraFactory.sol";
import "../interfaces/utils/ILpCallback.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IQuickSwapVault.sol";

import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";

import "../utils/ContractMeta.sol";
import "../utils/DefaultAccessControlLateInit.sol";
import "../utils/SinglePositionStrategyHelper.sol";

contract SinglePositionQuickSwapStrategy is ContractMeta, Multicall, DefaultAccessControlLateInit, ILpCallback {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 10**9;
    uint256 public constant MAX_MINTING_PARAMS = 10**9;
    uint256 public constant Q96 = 2**96;
    uint256 public constant D6 = 1000000;

    IAlgebraPool public algebraPool;
    IUniswapV3Factory public immutable uniswapV3Factory;
    IAlgebraNonfungiblePositionManager public immutable algebraPositionManager;
    SinglePositionStrategyHelper public immutable helper;

    /// @param router uniswap router to process swaps on UniswapV3 pools
    /// @param erc20Vault buffer vault of rootVault system
    /// @param quickSwapVault vault containing an algebra position, allowing to add and withdraw liquidity from it
    /// @param tokens array of length 2 with strategy and vaults tokens
    struct ImmutableParams {
        address router;
        IERC20Vault erc20Vault;
        IQuickSwapVault quickSwapVault;
        address[] tokens;
    }

    /// @param feeTierOfPoolOfAuxiliaryAnd0Tokens fee tier of the pool of auxiliary token and token 0
    /// @param feeTierOfPoolOfAuxiliaryAnd1Tokens fee tier of the pool of auxiliary token and token 1
    /// @param priceImpactD6 coefficient to take into account the impact of changing the price during tokens swaps
    /// @param intervalWidth uniswap position interval width
    /// @param tickNeighborhood if the spot tick is inside [lowerTick + tickNeighborhood, upperTick - tickNeighborhood], then the position will not be rebalanced
    /// @param maxDeviationForVaultPool maximum deviation of the spot tick from the average tick for the pool of token 0 and token 1
    /// @param maxDeviationForPoolOfAuxiliaryAnd0Tokens maximum deviation of the spot tick from the average tick for the pool of auxiliary token and token 0
    /// @param maxDeviationForPoolOfAuxiliaryAnd1Tokens maximum deviation of the spot tick from the average tick for the pool of auxiliary token and token 1
    /// @param timespanForAverageTick time interval on which average ticks in pools are determined
    /// @param auxiliaryToken intermediate token for swaps through pools with more liquidity
    /// @param amount0Desired amount of token 0 to mint position on UniswapV3Pool
    /// @param amount1Desired amount of token 1 to mint position on UniswapV3Pool
    /// @param swapSlippageD coefficient to protect against price slippage when swapping tokens
    /// @param minSwapAmounts thresholds that cut off swap of an insignificant amount of tokens
    struct MutableParams {
        uint24 feeTierOfPoolOfAuxiliaryAnd0Tokens;
        uint24 feeTierOfPoolOfAuxiliaryAnd1Tokens;
        int24 priceImpactD6;
        int24 intervalWidth;
        int24 tickNeighborhood;
        int24 maxDeviationForVaultPool;
        int24 maxDeviationForPoolOfAuxiliaryAnd0Tokens;
        int24 maxDeviationForPoolOfAuxiliaryAnd1Tokens;
        uint32 timespanForAverageTick;
        address auxiliaryToken;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 swapSlippageD;
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

    /// @param uniswapV3Factory_ Uniswap V3 pool factory
    /// @param algebraPositionManager_ Algebra NonfungiblePositionManager
    /// @param helper_ strategy helper
    constructor(
        IUniswapV3Factory uniswapV3Factory_,
        IAlgebraNonfungiblePositionManager algebraPositionManager_,
        SinglePositionStrategyHelper helper_
    ) {
        require(address(uniswapV3Factory_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        uniswapV3Factory = uniswapV3Factory_;
        require(address(algebraPositionManager_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        algebraPositionManager = algebraPositionManager_;
        require(address(helper_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        helper = helper_;
    }

    /// @param immutableParams_ structure with all immutable params of the strategy
    /// @param admin admin of the strategy
    function initialize(ImmutableParams memory immutableParams_, address admin) external {
        checkImmutableParams(immutableParams_);
        immutableParams = immutableParams_;
        for (uint256 i = 0; i < 2; i++) {
            IERC20(immutableParams_.tokens[i]).safeIncreaseAllowance(
                address(algebraPositionManager),
                type(uint256).max
            );
            try
                immutableParams_.erc20Vault.externalCall(
                    immutableParams_.tokens[i],
                    IERC20.approve.selector,
                    abi.encode(immutableParams_.router, type(uint256).max)
                )
            returns (bytes memory) {} catch {}
        }
        algebraPool = IAlgebraPool(
            immutableParams_.quickSwapVault.factory().poolByPair(immutableParams_.tokens[0], immutableParams_.tokens[1])
        );
        DefaultAccessControlLateInit.init(admin);
    }

    /// @dev updates mutable params of the strategy. Only the admin can call the function
    /// @param mutableParams_ new params to set
    function updateMutableParams(MutableParams memory mutableParams_) external {
        _requireAdmin();
        checkMutableParams(mutableParams_);
        mutableParams = mutableParams_;
        emit UpdateMutableParams(tx.origin, msg.sender, mutableParams_);
    }

    /// @dev Rebalancing goes like this:
    /// 1. Function checks the current states of the pools, and if the volatility is significant, the transaction reverts.
    /// 2. If necessary, a new position is minted on quickSwapVault, and the previous one is burned.
    /// 3. Tokens on erc20Vault are swapped via swapRouter so that the proportion matches the tokens on quickSwapVault.
    /// 4. The strategy transfers all possible tokens from erc20Vault to quickSwapVault.
    /// Only users with administrator or operator roles can call the function.
    /// @param deadline Timestamp by which the transaction must be completed
    function rebalance(uint256 deadline) external {
        require(block.timestamp <= deadline, ExceptionsLibrary.TIMESTAMP);
        _requireAtLeastOperator();
        ImmutableParams memory immutableParams_ = immutableParams;
        MutableParams memory mutableParams_ = mutableParams;
        IAlgebraPool pool = algebraPool;
        checkTickDeviations(immutableParams_, mutableParams_, pool);

        (uint160 sqrtPriceX96, int24 spotTick, , , , , ) = pool.globalState();
        Interval memory interval = _positionsRebalance(immutableParams_, mutableParams_, spotTick, pool);
        _swapToTarget(immutableParams_, mutableParams_, interval, sqrtPriceX96);
        _pushIntoQuickSwap(immutableParams_);

        emit Rebalance(tx.origin, msg.sender);
    }

    /// @dev calculates a new interval according to the mutable params, the tickSpacing of the pool and the spot tick
    /// @param mutableParams_ structure with all mutable params of the strategy
    /// @param tick current spot tick of the pool
    /// @param pool the quickSwapVault pool where the new position will be minted
    /// @return lowerTick lower tick of the new interval
    /// @return upperTick upper tick of the new interval
    function calculateNewInterval(
        MutableParams memory mutableParams_,
        int24 tick,
        IAlgebraPool pool
    ) public view returns (int24 lowerTick, int24 upperTick) {
        int24 tickSpacing = pool.tickSpacing();

        int24 centralTick = tick - (tick % tickSpacing);
        if ((tick % tickSpacing) * 2 > tickSpacing) {
            centralTick += tickSpacing;
        }

        lowerTick = centralTick - mutableParams_.intervalWidth / 2;
        upperTick = centralTick + mutableParams_.intervalWidth / 2;
    }

    /// @dev checks mutable params according to strategy restrictions
    /// @param params mutable parameters to be checked
    function checkMutableParams(MutableParams memory params) public view {
        int24 tickSpacing = algebraPool.tickSpacing();
        require(
            params.intervalWidth > 0 && params.intervalWidth % (2 * tickSpacing) == 0,
            ExceptionsLibrary.INVALID_VALUE
        );

        require(
            params.tickNeighborhood >= -params.intervalWidth && params.tickNeighborhood <= params.intervalWidth / 2,
            ExceptionsLibrary.LIMIT_OVERFLOW
        );

        require(params.auxiliaryToken != address(0), ExceptionsLibrary.ADDRESS_ZERO);

        require(
            params.feeTierOfPoolOfAuxiliaryAnd0Tokens == 100 ||
                params.feeTierOfPoolOfAuxiliaryAnd0Tokens == 500 ||
                params.feeTierOfPoolOfAuxiliaryAnd0Tokens == 3000 ||
                params.feeTierOfPoolOfAuxiliaryAnd0Tokens == 10000,
            ExceptionsLibrary.INVALID_VALUE
        );

        require(
            params.feeTierOfPoolOfAuxiliaryAnd1Tokens == 100 ||
                params.feeTierOfPoolOfAuxiliaryAnd1Tokens == 500 ||
                params.feeTierOfPoolOfAuxiliaryAnd1Tokens == 3000 ||
                params.feeTierOfPoolOfAuxiliaryAnd1Tokens == 10000,
            ExceptionsLibrary.INVALID_VALUE
        );

        require(
            int24(params.feeTierOfPoolOfAuxiliaryAnd0Tokens) +
                int24(params.feeTierOfPoolOfAuxiliaryAnd1Tokens) +
                params.priceImpactD6 >=
                0,
            ExceptionsLibrary.LIMIT_UNDERFLOW
        );

        require(params.maxDeviationForVaultPool > 0, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(params.maxDeviationForPoolOfAuxiliaryAnd0Tokens > 0, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(params.maxDeviationForPoolOfAuxiliaryAnd1Tokens > 0, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(params.timespanForAverageTick > 0, ExceptionsLibrary.VALUE_ZERO);
        require(params.timespanForAverageTick < 7 * 24 * 60 * 60, ExceptionsLibrary.VALUE_ZERO);

        require(params.amount0Desired > 0, ExceptionsLibrary.VALUE_ZERO);
        require(params.amount0Desired <= MAX_MINTING_PARAMS, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(params.amount1Desired > 0, ExceptionsLibrary.VALUE_ZERO);
        require(params.amount1Desired <= MAX_MINTING_PARAMS, ExceptionsLibrary.LIMIT_OVERFLOW);

        require(params.minSwapAmounts.length == 2, ExceptionsLibrary.INVALID_LENGTH);

        require(params.swapSlippageD <= DENOMINATOR, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(
            params.swapSlippageD >=
                (params.feeTierOfPoolOfAuxiliaryAnd0Tokens + params.feeTierOfPoolOfAuxiliaryAnd1Tokens) * 1000,
            ExceptionsLibrary.LIMIT_UNDERFLOW
        );
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
            require(address(params.quickSwapVault) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
            address[] memory quickSwapVaultTokens = params.quickSwapVault.vaultTokens();
            require(quickSwapVaultTokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
            require(quickSwapVaultTokens[0] == params.tokens[0], ExceptionsLibrary.INVARIANT);
            require(quickSwapVaultTokens[1] == params.tokens[1], ExceptionsLibrary.INVARIANT);
        }
    }

    /// @dev checks deviation of spot ticks of all pools in strategy from corresponding average ticks.
    /// If any deviation is large than maxDevation parameter for the pool, then the transaction will be reverted with a LIMIT_OVERFLOW error.
    /// If there are no observations 10 seconds ago in any of the considered pools, then the transaction will be reverted with an INVALID_STATE error.
    /// @param immutableParams_ structure with all immutable params of the strategy
    /// @param mutableParams_ structure with all mutable params of the strategy
    /// @param vaultPool UniswapV3Pool of quickSwapVault
    function checkTickDeviations(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        IAlgebraPool vaultPool
    ) public view {
        helper.checkUniV3PoolState(
            uniswapV3Factory.getPool(
                immutableParams_.tokens[0],
                mutableParams_.auxiliaryToken,
                mutableParams_.feeTierOfPoolOfAuxiliaryAnd0Tokens
            ),
            mutableParams_.maxDeviationForPoolOfAuxiliaryAnd0Tokens,
            mutableParams_.timespanForAverageTick
        );
        helper.checkUniV3PoolState(
            uniswapV3Factory.getPool(
                immutableParams_.tokens[1],
                mutableParams_.auxiliaryToken,
                mutableParams_.feeTierOfPoolOfAuxiliaryAnd1Tokens
            ),
            mutableParams_.maxDeviationForPoolOfAuxiliaryAnd1Tokens,
            mutableParams_.timespanForAverageTick
        );
        helper.checkAlgebraPoolState(
            address(vaultPool),
            mutableParams_.maxDeviationForVaultPool,
            mutableParams_.timespanForAverageTick
        );
    }

    /// @dev The function rebalances the position on the uniswap pool. If there was a position in the quickSwapVault,
    /// and the current tick is inside this position, taking into account the tickNeighborhood, then the position will not be rebalanced.
    /// Otherwise, if there is a position in the quickSwapVault, then all tokens will be sent to erc20Vault, the new position will be mined,
    /// and the old one will be burned.
    /// @param immutableParams_ structure with all immutable params of the strategy
    /// @param mutableParams_ structure with all mutable params of the strategy
    /// @param spotTick current spot tick of UniswapV3Pool of quickSwapVault
    /// @param pool UniswapV3Pool of quickSwapVault
    /// @return newInterval The position on the quickSwapVault after the function is executed.
    function _positionsRebalance(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        int24 spotTick,
        IAlgebraPool pool
    ) private returns (Interval memory newInterval) {
        IQuickSwapVault vault = immutableParams_.quickSwapVault;
        uint256 positionNft = vault.positionNft();
        if (positionNft != 0) {
            Interval memory currentPosition;
            (, , , , currentPosition.lowerTick, currentPosition.upperTick, , , , , ) = algebraPositionManager.positions(
                positionNft
            );
            if (
                mutableParams_.tickNeighborhood + currentPosition.lowerTick <= spotTick &&
                spotTick <= currentPosition.upperTick - mutableParams_.tickNeighborhood &&
                mutableParams_.intervalWidth == currentPosition.upperTick - currentPosition.lowerTick
            ) {
                vault.collectRewards(vault.delayedStrategyParams());
                vault.collectEarnings();
                return currentPosition;
            } else {
                vault.burnFarmingPosition(positionNft, vault.farmingCenter());
                (uint160 sqrtRatioX96, , , , , , ) = pool.globalState();
                uint256[] memory tokenAmounts = new uint256[](2);
                (tokenAmounts[0], tokenAmounts[1]) = vault.helper().liquidityToTokenAmounts(
                    positionNft,
                    sqrtRatioX96,
                    type(uint128).max
                );
                vault.pull(address(immutableParams_.erc20Vault), immutableParams_.tokens, tokenAmounts, "");
            }
        }

        (newInterval.lowerTick, newInterval.upperTick) = calculateNewInterval(mutableParams_, spotTick, pool);
        (uint256 newNft, , , ) = algebraPositionManager.mint(
            IAlgebraNonfungiblePositionManager.MintParams({
                token0: immutableParams_.tokens[0],
                token1: immutableParams_.tokens[1],
                tickLower: newInterval.lowerTick,
                tickUpper: newInterval.upperTick,
                amount0Desired: mutableParams_.amount0Desired,
                amount1Desired: mutableParams_.amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: type(uint256).max
            })
        );
        algebraPositionManager.safeTransferFrom(address(this), address(vault), newNft);

        emit PositionMinted(newNft);
        if (positionNft != 0) {
            algebraPositionManager.burn(positionNft);
            emit PositionBurned(positionNft);
        }
    }

    /// @dev calculate target ratio of token 1 to total capital after rebalance
    /// @param interval current interval on quickSwapVault
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

        uint256 feesX96 = FullMath.mulDiv(
            Q96,
            uint256(
                int256(
                    int24(mutableParams_.feeTierOfPoolOfAuxiliaryAnd0Tokens) +
                        int24(mutableParams_.feeTierOfPoolOfAuxiliaryAnd1Tokens) +
                        mutableParams_.priceImpactD6
                )
            ),
            D6
        );

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
    /// @param interval current interval on quickSwapVault
    /// @param sqrtSpotPriceX96 sqrt price X96 of spot tick
    function _swapToTarget(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        Interval memory interval,
        uint160 sqrtSpotPriceX96
    ) private {
        uint256 priceX96 = FullMath.mulDiv(sqrtSpotPriceX96, sqrtSpotPriceX96, Q96);
        uint256 targetRatioOfToken1X96 = calculateTargetRatioOfToken1(interval, sqrtSpotPriceX96, priceX96);
        (uint256 tokenInIndex, uint256 amountIn) = calculateAmountsForSwap(
            immutableParams_,
            mutableParams_,
            priceX96,
            targetRatioOfToken1X96
        );

        if (amountIn < mutableParams_.minSwapAmounts[tokenInIndex]) {
            return;
        }

        uint256 expectedAmountOut;
        bytes memory path;
        if (tokenInIndex == 0) {
            expectedAmountOut = FullMath.mulDiv(amountIn, priceX96, Q96);
            path = abi.encodePacked(
                immutableParams_.tokens[0],
                mutableParams_.feeTierOfPoolOfAuxiliaryAnd0Tokens,
                mutableParams_.auxiliaryToken,
                mutableParams_.feeTierOfPoolOfAuxiliaryAnd1Tokens,
                immutableParams_.tokens[1]
            );
        } else {
            expectedAmountOut = FullMath.mulDiv(amountIn, Q96, priceX96);
            path = abi.encodePacked(
                immutableParams_.tokens[1],
                mutableParams_.feeTierOfPoolOfAuxiliaryAnd1Tokens,
                mutableParams_.auxiliaryToken,
                mutableParams_.feeTierOfPoolOfAuxiliaryAnd0Tokens,
                immutableParams_.tokens[0]
            );
        }

        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
            path: path,
            recipient: address(immutableParams_.erc20Vault),
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: FullMath.mulDiv(
                expectedAmountOut,
                DENOMINATOR - mutableParams_.swapSlippageD,
                DENOMINATOR
            )
        });

        bytes memory routerResult = immutableParams_.erc20Vault.externalCall(
            immutableParams_.router,
            ISwapRouter.exactInput.selector,
            abi.encode(swapParams)
        );

        emit TokensSwapped(swapParams, abi.decode(routerResult, (uint256)));
    }

    /// @dev pushed maximal possible amounts of tokens from erc20Vault to quickSwapVault
    /// @param immutableParams_ structure with all immutable params of the strategy
    function _pushIntoQuickSwap(ImmutableParams memory immutableParams_) private {
        (uint256[] memory tokenAmounts, ) = immutableParams_.erc20Vault.tvl();
        if (tokenAmounts[0] > 0 || tokenAmounts[1] > 0) {
            immutableParams_.erc20Vault.pull(
                address(immutableParams_.quickSwapVault),
                immutableParams_.tokens,
                tokenAmounts,
                ""
            );
        }
    }

    /// @inheritdoc ILpCallback
    function depositCallback() external {
        // pushes all tokens from erc20Vault to uniswap to prevent possible attacks
        _pushIntoQuickSwap(immutableParams);
    }

    /// @inheritdoc ILpCallback
    function withdrawCallback() external {}

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("SinglePositionQuickSwapStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    /// @notice Emitted after a successful token swap
    /// @param swapParams structure with different parameters for handling swap via swapRouter
    /// @param amountOut the actual amount received from the swapRouter during swaps
    event TokensSwapped(ISwapRouter.ExactInputParams swapParams, uint256 amountOut);

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
