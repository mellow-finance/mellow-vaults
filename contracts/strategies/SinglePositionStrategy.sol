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

    bytes4 public constant APPROVE_SELECTOR = IERC20.approve.selector; // better than this 0x095ea7b3;
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;

    INonfungiblePositionManager public immutable positionManager;

    struct ImmutableParams {
        address router;
        address[] tokens;
        IERC20Vault erc20Vault;
        IUniV3Vault uniV3Vault;
    }

    struct MutableParams {
        int24 maxTickDeviation;
        int24 intervalWidthInTickSpacings;
        int24 tickSpacing;
        uint24 swapFee;
        uint32 averageTickTimespan;
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
        require(admin != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        checkImmutableParams(immutableParams_);
        immutableParams = immutableParams_;
        IERC20(immutableParams_.tokens[0]).safeIncreaseAllowance(address(positionManager), type(uint256).max);
        IERC20(immutableParams_.tokens[1]).safeIncreaseAllowance(address(positionManager), type(uint256).max);
        checkMutableParams(mutableParams_);
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
        checkMutableParams(mutableParams_);
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
        Interval memory newInterval;
        {
            (int24 averageTick, , bool withFail) = OracleLibrary.consult(
                address(pool),
                mutableParams_.averageTickTimespan
            );
            require(!withFail, ExceptionsLibrary.INVALID_STATE);
            int24 tickDelta = spotTick - averageTick;
            if (tickDelta < 0) {
                tickDelta = -tickDelta;
            }
            require(tickDelta < mutableParams_.maxTickDeviation, ExceptionsLibrary.LIMIT_OVERFLOW);

            (newInterval.lowerTick, newInterval.upperTick) = calculateNewInterval(
                mutableParams_.intervalWidthInTickSpacings,
                mutableParams_.tickSpacing,
                spotTick
            );
            _positionsRebalance(immutableParams_, mutableParams_, newInterval);
        }
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

        Tvls memory tvls = calculateTvls(immutableParams_);
        (uint256[] memory uniV3Expected, uint256 expectedAmountOfToken0) = calculateExpectedAmounts(
            newInterval,
            mutableParams_,
            priceX96,
            sqrtPriceX96,
            tvls.total[0],
            tvls.total[1]
        );

        _pullExtraTokens(immutableParams_, uniV3Expected, tvls.uniV3);
        _swapRebalance(immutableParams_, mutableParams_, priceX96, tvls.total[0], expectedAmountOfToken0);
        _pullMissingTokens(immutableParams_, uniV3Expected, tvls.uniV3);

        emit Rebalance(msg.sender, tx.origin);
    }

    function calculateTvls(ImmutableParams memory params) public view returns (Tvls memory tvls) {
        (tvls.erc20, ) = IVault(params.erc20Vault).tvl();
        (tvls.uniV3, ) = IVault(params.uniV3Vault).tvl();
        tvls.total = new uint256[](2);
        tvls.total[0] = tvls.erc20[0] + tvls.uniV3[0];
        tvls.total[1] = tvls.erc20[1] + tvls.uniV3[1];
    }

    function calculateExpectedAmounts(
        Interval memory newInterval,
        MutableParams memory mutableParams_,
        uint256 priceX96,
        uint160 sqrtSpotPriceX96,
        uint256 totalToken0,
        uint256 totalToken1
    ) public pure returns (uint256[] memory uniV3Expected, uint256 expectedAmountOfToken0) {
        uint256 totalCapitalInToken0 = totalToken0 + FullMath.mulDiv(totalToken1, Q96, priceX96);
        uint160 sqrtLowerPriceX96 = TickMath.getSqrtRatioAtTick(newInterval.lowerTick);
        uint160 sqrtUpperPriceX96 = TickMath.getSqrtRatioAtTick(newInterval.upperTick);
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
        uniV3Expected[0] = FullMath.mulDiv(
            expectedAmountOfToken0,
            DENOMINATOR - mutableParams_.erc20CapitalRatioD,
            DENOMINATOR
        );
        uniV3Expected[1] = FullMath.mulDiv(
            FullMath.mulDiv(
                totalCapitalInToken0 - expectedAmountOfToken0,
                DENOMINATOR - mutableParams_.erc20CapitalRatioD,
                DENOMINATOR
            ),
            priceX96,
            Q96
        );
    }

    function calculateNewInterval(
        int24 intervalWidthInTickSpacings,
        int24 tickSpacing,
        int24 tick
    ) public pure returns (int24 lowerTick, int24 upperTick) {
        tick -= tick % tickSpacing;
        lowerTick = tick - tickSpacing * intervalWidthInTickSpacings;
        upperTick = tick + tickSpacing * intervalWidthInTickSpacings;
    }

    function checkMutableParams(MutableParams memory params) public view {
        ImmutableParams memory immutableParams_ = immutableParams;
        IUniswapV3Pool pool = immutableParams_.uniV3Vault.pool();

        require(params.maxTickDeviation > 0, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(
            params.tickSpacing > 0 &&
                params.tickSpacing % pool.tickSpacing() == 0 &&
                params.tickSpacing < TickMath.MAX_TICK / 4,
            ExceptionsLibrary.INVALID_VALUE
        );
        require(
            params.swapFee == 100 || params.swapFee == 500 || params.swapFee == 3000 || params.swapFee == 10000,
            ExceptionsLibrary.INVALID_VALUE
        );

        require(params.averageTickTimespan > 0, ExceptionsLibrary.VALUE_ZERO);
        require(params.averageTickTimespan < 24 * 60 * 60, ExceptionsLibrary.VALUE_ZERO);

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

    function _positionsRebalance(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        Interval memory newInterval
    ) private {
        IUniV3Vault vault = immutableParams_.uniV3Vault;
        uint256 uniV3Nft = vault.uniV3Nft();
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

    function _swapRebalance(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        uint256 priceX96,
        uint256 currentAmountOfToken0,
        uint256 expectedAmountOfToken0
    ) private {
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
            return;
        }

        bytes memory routerResult;
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: immutableParams_.tokens[tokenInIndex],
            tokenOut: immutableParams_.tokens[tokenInIndex ^ 1],
            fee: mutableParams_.swapFee,
            recipient: address(immutableParams_.erc20Vault),
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        immutableParams_.erc20Vault.externalCall(
            immutableParams_.tokens[tokenInIndex],
            APPROVE_SELECTOR,
            abi.encode(immutableParams_.router, amountIn)
        );
        routerResult = immutableParams_.erc20Vault.externalCall(
            immutableParams_.router,
            EXACT_INPUT_SINGLE_SELECTOR,
            abi.encode(swapParams)
        );
        immutableParams_.erc20Vault.externalCall(
            immutableParams_.tokens[tokenInIndex],
            APPROVE_SELECTOR,
            abi.encode(immutableParams_.router, 0)
        );
        uint256 amountOut = abi.decode(routerResult, (uint256));

        require(
            amountOut >= FullMath.mulDiv(expectedAmountOut, mutableParams_.swapSlippageD, DENOMINATOR),
            ExceptionsLibrary.LIMIT_UNDERFLOW
        );

        emit TokensSwapped(swapParams, amountOut);
    }

    function _pullExtraTokens(
        ImmutableParams memory immutableParams_,
        uint256[] memory expected,
        uint256[] memory tvl
    ) private {
        uint256[] memory amountsToPull = new uint256[](2);
        if (tvl[0] > expected[0]) amountsToPull[0] = tvl[0] - expected[0];
        if (tvl[1] > expected[1]) amountsToPull[1] = tvl[1] - expected[1];
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
        uint256[] memory expected,
        uint256[] memory tvl
    ) private {
        uint256[] memory amountsToPull = new uint256[](2);
        if (tvl[0] < expected[0]) amountsToPull[0] = expected[0] - tvl[0];
        if (tvl[1] < expected[1]) amountsToPull[1] = expected[1] - tvl[1];
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

    event TokensSwapped(ISwapRouter.ExactInputSingleParams swapParams, uint256 amountOut);
    event UpdateMutableParams(address indexed origin, address indexed sender, MutableParams mutableParams);
    event Rebalance(address indexed sender, address indexed origin);
}
