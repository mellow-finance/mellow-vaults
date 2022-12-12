// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";

import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/external/OracleLibrary.sol";

import "../utils/ContractMeta.sol";
import "../utils/DefaultAccessControlLateInit.sol";

contract SinglePositionStrategy is ContractMeta, Multicall, DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 10**9;
    uint256 public constant MAX_MINTING_PARAMS = 10**9;
    uint256 public constant Q96 = 2**96;

    bytes4 public constant APPROVE_SELECTOR = IERC20.approve.selector;
    bytes4 public constant EXACT_INPUT_SELECTOR = ISwapRouter.exactInput.selector;

    INonfungiblePositionManager public immutable positionManager;

    struct ImmutableParams {
        address router;
        address[] tokens;
        IERC20Vault erc20Vault;
        IUniV3Vault uniV3Vault;
    }

    struct MutableParams {
        uint24 token0ToIntermediateSwapFeeTier;
        uint24 token1ToIntermediateSwapFeeTier;
        address intermediateToken;
        int24 intervalWidth;
        int24 tickNeighborhood;
        int24 maxDeviationFromAverageTick;
        uint32 timespanForAverageTick;
        uint256 amount0ForMint;
        uint256 amount1ForMint;
        uint256 erc20CapitalRatioD;
        uint256 swapSlippageD;
    }

    struct Tvls {
        uint256[] uniV3;
        uint256[] erc20;
        uint256[] total;
    }

    struct Interval {
        int24 lowerTick;
        int24 upperTick;
    }

    ImmutableParams public immutableParams;
    MutableParams public mutableParams;

    constructor(INonfungiblePositionManager positionManager_) {
        require(address(positionManager_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        positionManager = positionManager_;
        DefaultAccessControlLateInit.init(address(this));
    }

    function initialize(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        address admin
    ) external {
        checkImmutableParams(immutableParams_);
        immutableParams = immutableParams_;
        IERC20(immutableParams_.tokens[0]).safeIncreaseAllowance(address(positionManager), type(uint256).max);
        IERC20(immutableParams_.tokens[1]).safeIncreaseAllowance(address(positionManager), type(uint256).max);
        checkMutableParams(mutableParams_, immutableParams_);
        mutableParams = mutableParams_;
        DefaultAccessControlLateInit.init(admin);
    }

    function createStrategy(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        address admin
    ) external returns (SinglePositionStrategy strategy) {
        strategy = SinglePositionStrategy(Clones.clone(address(this)));
        strategy.initialize(immutableParams_, mutableParams_, admin);
    }

    function updateMutableParams(MutableParams memory mutableParams_) external {
        _requireAdmin();
        checkMutableParams(mutableParams_, immutableParams);
        mutableParams = mutableParams_;
        emit UpdateMutableParams(tx.origin, msg.sender, mutableParams_);
    }

    function rebalance(uint256 deadline) external {
        require(block.timestamp <= deadline, ExceptionsLibrary.TIMESTAMP);
        _requireAtLeastOperator();
        ImmutableParams memory immutableParams_ = immutableParams;
        MutableParams memory mutableParams_ = mutableParams;
        IUniswapV3Pool pool = immutableParams_.uniV3Vault.pool();

        (uint160 sqrtPriceX96, int24 spotTick, , , , , ) = pool.slot0();
        checkAverageTickDeviation(mutableParams_, pool, spotTick);

        Interval memory interval = _positionsRebalance(immutableParams_, mutableParams_, spotTick);
        _capitalRebalance(immutableParams_, mutableParams_, interval, sqrtPriceX96);

        emit Rebalance(tx.origin, msg.sender);
    }

    function calculateTvls(ImmutableParams memory params) public view returns (Tvls memory tvls) {
        (tvls.erc20, ) = params.erc20Vault.tvl();
        (tvls.uniV3, ) = params.uniV3Vault.tvl();
        tvls.total = new uint256[](2);
        tvls.total[0] = tvls.erc20[0] + tvls.uniV3[0];
        tvls.total[1] = tvls.erc20[1] + tvls.uniV3[1];
    }

    function calculateTargetAmounts(
        Interval memory interval,
        MutableParams memory mutableParams_,
        uint256 priceX96,
        uint160 sqrtSpotPriceX96,
        uint256 totalToken0,
        uint256 totalToken1
    ) public pure returns (uint256[] memory targetUniV3TokenAmounts, uint256 targetAmountOfToken0) {
        uint256 totalCapitalInToken0 = totalToken0 + FullMath.mulDiv(totalToken1, Q96, priceX96);
        uint160 sqrtLowerPriceX96 = TickMath.getSqrtRatioAtTick(interval.lowerTick);
        uint160 sqrtUpperPriceX96 = TickMath.getSqrtRatioAtTick(interval.upperTick);
        // the derivation of the formula is available at the link: https://www.desmos.com/calculator/xdh2vj3cli
        uint256 targetRatioOfToken0D = FullMath.mulDiv(
            DENOMINATOR,
            sqrtUpperPriceX96 - sqrtSpotPriceX96,
            2 *
                sqrtUpperPriceX96 -
                sqrtSpotPriceX96 -
                FullMath.mulDiv(sqrtLowerPriceX96, sqrtUpperPriceX96, sqrtSpotPriceX96)
        );

        targetAmountOfToken0 = FullMath.mulDiv(totalCapitalInToken0, targetRatioOfToken0D, DENOMINATOR);

        targetUniV3TokenAmounts = new uint256[](2);
        targetUniV3TokenAmounts[0] = FullMath.mulDiv(
            targetAmountOfToken0,
            DENOMINATOR - mutableParams_.erc20CapitalRatioD,
            DENOMINATOR
        );
        targetUniV3TokenAmounts[1] = FullMath.mulDiv(
            FullMath.mulDiv(
                totalCapitalInToken0 - targetAmountOfToken0,
                DENOMINATOR - mutableParams_.erc20CapitalRatioD,
                DENOMINATOR
            ),
            priceX96,
            Q96
        );
    }

    function calculateNewInterval(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        int24 tick
    ) public view returns (int24 lowerTick, int24 upperTick) {
        IUniswapV3Pool pool = immutableParams_.uniV3Vault.pool();
        int24 tickSpacing = pool.tickSpacing();

        int24 centralTick = tick - (tick % tickSpacing);
        if (tick - centralTick > centralTick + tickSpacing - tick) {
            centralTick += tickSpacing;
        }

        lowerTick = centralTick - mutableParams_.intervalWidth / 2;
        upperTick = lowerTick + mutableParams_.intervalWidth;
    }

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

        require(params.intermediateToken != address(0), ExceptionsLibrary.ADDRESS_ZERO);

        require(
            params.token0ToIntermediateSwapFeeTier == 100 ||
                params.token0ToIntermediateSwapFeeTier == 500 ||
                params.token0ToIntermediateSwapFeeTier == 3000 ||
                params.token0ToIntermediateSwapFeeTier == 10000,
            ExceptionsLibrary.INVALID_VALUE
        );

        require(
            params.token1ToIntermediateSwapFeeTier == 100 ||
                params.token1ToIntermediateSwapFeeTier == 500 ||
                params.token1ToIntermediateSwapFeeTier == 3000 ||
                params.token1ToIntermediateSwapFeeTier == 10000,
            ExceptionsLibrary.INVALID_VALUE
        );

        require(params.maxDeviationFromAverageTick > 0, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(params.timespanForAverageTick > 0, ExceptionsLibrary.VALUE_ZERO);
        require(params.timespanForAverageTick < 7 * 24 * 60 * 60, ExceptionsLibrary.VALUE_ZERO);

        require(params.amount0ForMint > 0, ExceptionsLibrary.VALUE_ZERO);
        require(params.amount0ForMint <= MAX_MINTING_PARAMS, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(params.amount1ForMint > 0, ExceptionsLibrary.VALUE_ZERO);
        require(params.amount1ForMint <= MAX_MINTING_PARAMS, ExceptionsLibrary.LIMIT_OVERFLOW);

        require(params.erc20CapitalRatioD <= DENOMINATOR, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(params.swapSlippageD <= DENOMINATOR, ExceptionsLibrary.LIMIT_OVERFLOW);
    }

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

    function checkAverageTickDeviation(
        MutableParams memory mutableParams_,
        IUniswapV3Pool pool,
        int24 spotTick
    ) public view {
        (int24 averageTick, , bool withFail) = OracleLibrary.consult(
            address(pool),
            mutableParams_.timespanForAverageTick
        );
        require(!withFail, ExceptionsLibrary.INVALID_STATE);
        int24 tickDelta = spotTick - averageTick;
        if (tickDelta < 0) {
            tickDelta = -tickDelta;
        }
        require(tickDelta < mutableParams_.maxDeviationFromAverageTick, ExceptionsLibrary.LIMIT_OVERFLOW);
    }

    function _positionsRebalance(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        int24 spotTick
    ) private returns (Interval memory newInterval) {
        IUniV3Vault vault = immutableParams_.uniV3Vault;

        uint256 uniV3Nft = vault.uniV3Nft();
        if (uniV3Nft != 0) {
            Interval memory currentPosition;
            (, , , , , currentPosition.lowerTick, currentPosition.upperTick, , , , , ) = positionManager.positions(
                uniV3Nft
            );
            if (
                mutableParams_.tickNeighborhood + currentPosition.lowerTick <= spotTick &&
                spotTick <= currentPosition.upperTick - mutableParams_.tickNeighborhood
            ) {
                return currentPosition;
            }
        }

        (newInterval.lowerTick, newInterval.upperTick) = calculateNewInterval(
            immutableParams_,
            mutableParams_,
            spotTick
        );

        if (uniV3Nft != 0) {
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
                fee: vault.pool().fee(),
                tickLower: newInterval.lowerTick,
                tickUpper: newInterval.upperTick,
                amount0Desired: mutableParams_.amount0ForMint,
                amount1Desired: mutableParams_.amount1ForMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: type(uint256).max
            })
        );
        positionManager.safeTransferFrom(address(this), address(vault), newNft);

        if (uniV3Nft != 0) {
            positionManager.burn(uniV3Nft);
        }
    }

    function _capitalRebalance(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        Interval memory interval,
        uint160 sqrtPriceX96
    ) private {
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        Tvls memory tvls = calculateTvls(immutableParams_);
        (uint256[] memory targetUniV3TokenAmounts, uint256 targetAmountOfToken0) = calculateTargetAmounts(
            interval,
            mutableParams_,
            priceX96,
            sqrtPriceX96,
            tvls.total[0],
            tvls.total[1]
        );

        _pullExtraTokens(immutableParams_, targetUniV3TokenAmounts, tvls.uniV3);
        _swapRebalance(immutableParams_, mutableParams_, priceX96, tvls.total[0], targetAmountOfToken0);
        _pullMissingTokens(immutableParams_, targetUniV3TokenAmounts, tvls.uniV3);
    }

    function _swapRebalance(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        uint256 priceX96,
        uint256 currentAmountOfToken0,
        uint256 targetAmountOfToken0
    ) private {
        uint256 tokenInIndex;
        uint256 amountIn;
        uint256 expectedAmountOut;
        if (targetAmountOfToken0 > currentAmountOfToken0) {
            tokenInIndex = 1;
            amountIn = FullMath.mulDiv(targetAmountOfToken0 - currentAmountOfToken0, priceX96, Q96);
            expectedAmountOut = targetAmountOfToken0 - currentAmountOfToken0;
        } else {
            tokenInIndex = 0;
            amountIn = currentAmountOfToken0 - targetAmountOfToken0;
            expectedAmountOut = FullMath.mulDiv(amountIn, priceX96, Q96);
        }

        if (amountIn == 0) {
            return;
        }

        bytes memory path;
        if (tokenInIndex == 0) {
            path = abi.encodePacked(
                immutableParams_.tokens[0],
                mutableParams_.token0ToIntermediateSwapFeeTier,
                mutableParams_.intermediateToken,
                mutableParams_.token1ToIntermediateSwapFeeTier,
                immutableParams_.tokens[1]
            );
        } else {
            path = abi.encodePacked(
                immutableParams_.tokens[1],
                mutableParams_.token1ToIntermediateSwapFeeTier,
                mutableParams_.intermediateToken,
                mutableParams_.token0ToIntermediateSwapFeeTier,
                immutableParams_.tokens[0]
            );
        }

        bytes memory routerResult;
        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
            path: path,
            recipient: address(immutableParams_.erc20Vault),
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        immutableParams_.erc20Vault.externalCall(
            immutableParams_.tokens[tokenInIndex],
            APPROVE_SELECTOR,
            abi.encode(immutableParams_.router, amountIn)
        );
        routerResult = immutableParams_.erc20Vault.externalCall(
            immutableParams_.router,
            EXACT_INPUT_SELECTOR,
            abi.encode(swapParams)
        );
        immutableParams_.erc20Vault.externalCall(
            immutableParams_.tokens[tokenInIndex],
            APPROVE_SELECTOR,
            abi.encode(immutableParams_.router, 0)
        );
        uint256 amountOut = abi.decode(routerResult, (uint256));

        require(
            amountOut >= FullMath.mulDiv(expectedAmountOut, DENOMINATOR - mutableParams_.swapSlippageD, DENOMINATOR),
            ExceptionsLibrary.LIMIT_UNDERFLOW
        );

        emit TokensSwapped(swapParams, amountOut);
    }

    function _pullExtraTokens(
        ImmutableParams memory immutableParams_,
        uint256[] memory targetUniV3TokenAmounts,
        uint256[] memory currentUniV3TokenAmounts
    ) private {
        uint256[] memory amountsToPull = new uint256[](2);
        if (currentUniV3TokenAmounts[0] > targetUniV3TokenAmounts[0])
            amountsToPull[0] = currentUniV3TokenAmounts[0] - targetUniV3TokenAmounts[0];
        if (currentUniV3TokenAmounts[1] > targetUniV3TokenAmounts[1])
            amountsToPull[1] = currentUniV3TokenAmounts[1] - targetUniV3TokenAmounts[1];
        if (amountsToPull[0] > 0 || amountsToPull[1] > 0) {
            immutableParams_.uniV3Vault.pull(
                address(immutableParams_.erc20Vault),
                immutableParams_.tokens,
                amountsToPull,
                ""
            );
        }
    }

    function _pullMissingTokens(
        ImmutableParams memory immutableParams_,
        uint256[] memory targetUniV3TokenAmounts,
        uint256[] memory currentUniV3TokenAmounts
    ) private {
        uint256[] memory amountsToPull = new uint256[](2);
        if (currentUniV3TokenAmounts[0] < targetUniV3TokenAmounts[0])
            amountsToPull[0] = targetUniV3TokenAmounts[0] - currentUniV3TokenAmounts[0];
        if (currentUniV3TokenAmounts[1] < targetUniV3TokenAmounts[1])
            amountsToPull[1] = targetUniV3TokenAmounts[1] - currentUniV3TokenAmounts[1];
        if (amountsToPull[0] > 0 || amountsToPull[1] > 0) {
            immutableParams_.erc20Vault.pull(
                address(immutableParams_.uniV3Vault),
                immutableParams_.tokens,
                amountsToPull,
                ""
            );
        }
    }

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("SinglePositionStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    event TokensSwapped(ISwapRouter.ExactInputParams swapParams, uint256 amountOut);
    event UpdateMutableParams(address indexed origin, address indexed sender, MutableParams mutableParams);
    event Rebalance(address indexed origin, address indexed sender);
}
