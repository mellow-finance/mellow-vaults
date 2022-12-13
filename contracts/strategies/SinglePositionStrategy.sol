// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";
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
        IERC20Vault erc20Vault;
        IUniV3Vault uniV3Vault;
        address[] tokens;
    }

    struct MutableParams {
        uint24 feeTierOfPoolOfAuxiliaryAnd0Tokens;
        uint24 feeTierOfPoolOfAuxiliaryAnd1Tokens;
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
        try
            immutableParams_.erc20Vault.externalCall(
                immutableParams_.tokens[0],
                APPROVE_SELECTOR,
                abi.encode(immutableParams_.router, type(uint256).max)
            )
        returns (bytes memory) {} catch {}
        try
            immutableParams_.erc20Vault.externalCall(
                immutableParams_.tokens[1],
                APPROVE_SELECTOR,
                abi.encode(immutableParams_.router, type(uint256).max)
            )
        returns (bytes memory) {} catch {}
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
        checkTickDeviations(immutableParams_, mutableParams_, pool);

        (uint160 sqrtPriceX96, int24 spotTick, , , , , ) = pool.slot0();
        Interval memory interval = _positionsRebalance(immutableParams_, mutableParams_, spotTick, pool);
        _swapToTarget(immutableParams_, mutableParams_, interval, sqrtPriceX96);
        _pushIntoUniswap(immutableParams_);

        emit Rebalance(tx.origin, msg.sender);
    }

    function calculateTvls(ImmutableParams memory params) public view returns (Tvls memory tvls) {
        (tvls.erc20, ) = params.erc20Vault.tvl();
        (tvls.uniV3, ) = params.uniV3Vault.tvl();
        tvls.total = new uint256[](2);
        tvls.total[0] = tvls.erc20[0] + tvls.uniV3[0];
        tvls.total[1] = tvls.erc20[1] + tvls.uniV3[1];
    }

    function calculateNewInterval(
        MutableParams memory mutableParams_,
        int24 tick,
        IUniswapV3Pool pool
    ) public view returns (int24 lowerTick, int24 upperTick) {
        int24 tickSpacing = pool.tickSpacing();

        int24 centralTick = tick - (tick % tickSpacing);
        if ((tick % tickSpacing) * 2 > tickSpacing) {
            centralTick += tickSpacing;
        }

        lowerTick = centralTick - mutableParams_.intervalWidth / 2;
        upperTick = centralTick + mutableParams_.intervalWidth / 2;
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

        require(params.maxDeviationForVaultPool > 0, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(params.maxDeviationForPoolOfAuxiliaryAnd0Tokens > 0, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(params.maxDeviationForPoolOfAuxiliaryAnd1Tokens > 0, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(params.timespanForAverageTick > 0, ExceptionsLibrary.VALUE_ZERO);
        require(params.timespanForAverageTick < 7 * 24 * 60 * 60, ExceptionsLibrary.VALUE_ZERO);

        require(params.amount0Desired > 0, ExceptionsLibrary.VALUE_ZERO);
        require(params.amount0Desired <= MAX_MINTING_PARAMS, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(params.amount1Desired > 0, ExceptionsLibrary.VALUE_ZERO);
        require(params.amount1Desired <= MAX_MINTING_PARAMS, ExceptionsLibrary.LIMIT_OVERFLOW);

        require(params.swapSlippageD <= DENOMINATOR, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(
            params.swapSlippageD >=
                (params.feeTierOfPoolOfAuxiliaryAnd0Tokens + params.feeTierOfPoolOfAuxiliaryAnd1Tokens) * 1000,
            ExceptionsLibrary.LIMIT_UNDERFLOW
        );
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

    function checkTickDeviations(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        IUniswapV3Pool vaultPool
    ) public view {
        IUniswapV3Factory factory = IUniswapV3Factory(positionManager.factory());
        address poolOfAuxiliaryAnd0Tokens = factory.getPool(
            immutableParams_.tokens[0],
            mutableParams_.auxiliaryToken,
            mutableParams_.feeTierOfPoolOfAuxiliaryAnd0Tokens
        );
        address poolOfAuxiliaryAnd1Tokens = factory.getPool(
            immutableParams_.tokens[1],
            mutableParams_.auxiliaryToken,
            mutableParams_.feeTierOfPoolOfAuxiliaryAnd1Tokens
        );
        address[3] memory pools = [poolOfAuxiliaryAnd0Tokens, poolOfAuxiliaryAnd1Tokens, address(vaultPool)];
        int24[3] memory maxTickDeviations = [
            mutableParams_.maxDeviationForPoolOfAuxiliaryAnd0Tokens,
            mutableParams_.maxDeviationForPoolOfAuxiliaryAnd1Tokens,
            mutableParams_.maxDeviationForVaultPool
        ];
        for (uint256 i = 0; i < 3; i++) {
            (, int24 spotTick, , , , , ) = IUniswapV3Pool(pools[i]).slot0();
            (int24 averageTick, , bool withFail) = OracleLibrary.consult(
                pools[i],
                mutableParams_.timespanForAverageTick
            );
            require(!withFail, ExceptionsLibrary.INVALID_STATE);
            int24 tickDeviation = spotTick - averageTick;
            if (tickDeviation < 0) {
                tickDeviation = -tickDeviation;
            }
            require(tickDeviation < maxTickDeviations[i], ExceptionsLibrary.LIMIT_OVERFLOW);
        }
    }

    function _positionsRebalance(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        int24 spotTick,
        IUniswapV3Pool pool
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
                vault.collectEarnings();
                return currentPosition;
            }
        }

        (newInterval.lowerTick, newInterval.upperTick) = calculateNewInterval(mutableParams_, spotTick, pool);

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
                fee: pool.fee(),
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
        positionManager.safeTransferFrom(address(this), address(vault), newNft);

        if (uniV3Nft != 0) {
            positionManager.burn(uniV3Nft);
        }
    }

    function calculateAmountsForSwap(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        Interval memory interval,
        uint160 sqrtSpotPriceX96,
        uint256 priceX96
    ) public view returns (uint256 tokenInIndex, uint256 amountIn) {
        uint256 totalToken0Amount;
        uint256 totalToken1Amount;
        {
            Tvls memory tvls = calculateTvls(immutableParams_);
            totalToken0Amount = tvls.total[0];
            totalToken1Amount = tvls.total[1];
        }
        uint160 sqrtLowerPriceX96 = TickMath.getSqrtRatioAtTick(interval.lowerTick);
        uint160 sqrtUpperPriceX96 = TickMath.getSqrtRatioAtTick(interval.upperTick);
        if (sqrtSpotPriceX96 < sqrtLowerPriceX96) {
            tokenInIndex = 1;
            amountIn = totalToken1Amount;
        } else if (sqrtSpotPriceX96 > sqrtUpperPriceX96) {
            tokenInIndex = 0;
            amountIn = totalToken0Amount;
        } else {
            uint256 swapFeesTierD = (mutableParams_.feeTierOfPoolOfAuxiliaryAnd0Tokens +
                mutableParams_.feeTierOfPoolOfAuxiliaryAnd1Tokens) * 1000;
            uint256 targetRatioX96 = FullMath.mulDiv(
                FullMath.mulDiv(sqrtSpotPriceX96 - sqrtLowerPriceX96, sqrtUpperPriceX96, Q96),
                FullMath.mulDiv(sqrtSpotPriceX96, Q96, sqrtUpperPriceX96 - sqrtSpotPriceX96),
                Q96
            );

            uint256 expectedToken1AmountForTargetRatio = FullMath.mulDiv(totalToken0Amount, targetRatioX96, Q96);
            if (expectedToken1AmountForTargetRatio > totalToken1Amount) {
                tokenInIndex = 0;
                amountIn = FullMath.mulDiv(
                    expectedToken1AmountForTargetRatio - totalToken1Amount,
                    Q96,
                    targetRatioX96 + FullMath.mulDiv(DENOMINATOR - swapFeesTierD, priceX96, DENOMINATOR)
                );
            } else if (expectedToken1AmountForTargetRatio < totalToken1Amount) {
                tokenInIndex = 1;
                amountIn = FullMath.mulDiv(
                    totalToken1Amount - expectedToken1AmountForTargetRatio,
                    Q96,
                    Q96 +
                        FullMath.mulDiv(
                            FullMath.mulDiv(DENOMINATOR - swapFeesTierD, targetRatioX96, DENOMINATOR),
                            Q96,
                            priceX96
                        )
                );
            }
        }
    }

    function _swapToTarget(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        Interval memory interval,
        uint160 sqrtSpotPriceX96
    ) private {
        uint256 priceX96 = FullMath.mulDiv(sqrtSpotPriceX96, sqrtSpotPriceX96, Q96);
        (uint256 tokenInIndex, uint256 amountIn) = calculateAmountsForSwap(
            immutableParams_,
            mutableParams_,
            interval,
            sqrtSpotPriceX96,
            priceX96
        );
        if (amountIn == 0) {
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

        bytes memory routerResult;
        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
            path: path,
            recipient: address(immutableParams_.erc20Vault),
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: 0
        });

        routerResult = immutableParams_.erc20Vault.externalCall(
            immutableParams_.router,
            EXACT_INPUT_SELECTOR,
            abi.encode(swapParams)
        );

        uint256 amountOut = abi.decode(routerResult, (uint256));

        require(
            amountOut >= FullMath.mulDiv(expectedAmountOut, DENOMINATOR - mutableParams_.swapSlippageD, DENOMINATOR),
            ExceptionsLibrary.LIMIT_UNDERFLOW
        );

        emit TokensSwapped(swapParams, amountOut);
    }

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
