// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/external/OracleLibrary.sol";
import "../utils/DefaultAccessControlLateInit.sol";
import "../utils/ContractMeta.sol";

contract MStrategy is ContractMeta, Multicall, DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    // IMMUTABLES
    uint256 public constant DENOMINATOR = 10**9;
    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;

    address[] public tokens;
    IERC20Vault public erc20Vault;
    IIntegrationVault public moneyVault;
    IUniswapV3Pool public pool;
    INonfungiblePositionManager public positionManager;
    ISwapRouter public router;

    // INTERNAL STATE
    int24 public lastRebalanceTick;

    // MUTABLE PARAMS

    struct OracleParams {
        uint32 oracleObservationDelta;
        uint24 maxTickDeviation;
        uint256 maxSlippageD;
    }

    struct RatioParams {
        int24 tickMin;
        int24 tickMax;
        int24 minTickRebalanceThreshold;
        int24 tickNeighborhood;
        int24 tickIncrease;
        uint256 erc20MoneyRatioD;
        uint256 minErc20MoneyRatioDeviation0D;
        uint256 minErc20MoneyRatioDeviation1D;
    }

    OracleParams public oracleParams;
    RatioParams public ratioParams;

    /// @notice Deploys a new contract
    /// @param positionManager_ Uniswap V3 position manager
    /// @param router_ Uniswap V3 swap router
    constructor(INonfungiblePositionManager positionManager_, ISwapRouter router_) {
        require(address(positionManager_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(router_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        positionManager = positionManager_;
        router = router_;
        DefaultAccessControlLateInit.init(address(this));
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @notice UniV3 pool price stats
    /// @return averageTick Average tick according to oracle and oracleParams.maxTickDeviation
    /// @return deviation Current pool tick - average tick
    function getAverageTick() external view returns (int24 averageTick, int24 deviation) {
        return _getAverageTick(pool);
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @notice Set initial values.
    /// @dev Can be only called once.
    /// @param positionManager_ Uniswap V3 position manager
    /// @param router_ Uniswap V3 swap router
    /// @param tokens_ Tokens under management
    /// @param erc20Vault_ erc20Vault of the Strategy
    /// @param moneyVault_ moneyVault of the Strategy
    /// @param fee_ Uniswap V3 fee for the pool (needed for oracle and swaps)
    /// @param admin_ Admin of the strategy
    function initialize(
        INonfungiblePositionManager positionManager_,
        ISwapRouter router_,
        address[] memory tokens_,
        IERC20Vault erc20Vault_,
        IIntegrationVault moneyVault_,
        uint24 fee_,
        address admin_
    ) external {
        DefaultAccessControlLateInit.init(admin_); // call once is checked here
        require(tokens_.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        address[] memory erc20Tokens = erc20Vault_.vaultTokens();
        address[] memory moneyTokens = moneyVault_.vaultTokens();
        require(erc20Tokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(moneyTokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < 2; i++) {
            require(erc20Tokens[i] == tokens_[i], ExceptionsLibrary.INVARIANT);
            require(moneyTokens[i] == tokens_[i], ExceptionsLibrary.INVARIANT);
        }
        positionManager = positionManager_;
        router = router_;
        erc20Vault = erc20Vault_;
        moneyVault = moneyVault_;
        tokens = tokens_;
        IUniswapV3Factory factory = IUniswapV3Factory(positionManager_.factory());
        pool = IUniswapV3Pool(factory.getPool(tokens[0], tokens[1], fee_));
        require(address(pool) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
    }

    /// @notice Deploy a new strategy.
    /// @param tokens_ Tokens under management
    /// @param erc20Vault_ erc20Vault of the Strategy
    /// @param moneyVault_ moneyVault of the Strategy
    /// @param fee_ Uniswap V3 fee for the pool (needed for oracle and swaps)
    /// @param admin_ Admin of the new strategy
    function createStrategy(
        address[] memory tokens_,
        IERC20Vault erc20Vault_,
        IIntegrationVault moneyVault_,
        uint24 fee_,
        address admin_
    ) external returns (MStrategy strategy) {
        strategy = MStrategy(Clones.clone(address(this)));
        strategy.initialize(positionManager, router, tokens_, erc20Vault_, moneyVault_, fee_, admin_);
    }

    /// @notice Perform a rebalance according to target ratios
    /// @param minTokensAmount Lower bounds for amountOut of tokens, that we want to get after swap via SwapRouter
    /// @param vaultOptions Parameters of money vault for operations with it
    /// @return poolAmounts The amount of each token that was pulled from erc20Vault to the money vault if positive, otherwise vice versa
    /// @return tokenAmounts The amount of each token passed to and from SwapRouter dependings on zeroToOne
    /// @return zeroToOne Flag, that true if we swapped amount of zero token to first token, otherwise false
    function rebalance(uint256[] memory minTokensAmount, bytes memory vaultOptions)
        external
        returns (
            int256[] memory poolAmounts,
            uint256[] memory tokenAmounts,
            bool zeroToOne
        )
    {
        _requireAtLeastOperator();
        SwapToTargetParams memory params;
        params.tokens = tokens;
        params.pool = pool;
        params.router = router;
        params.erc20Vault = erc20Vault;
        params.moneyVault = moneyVault;
        tokenAmounts = new uint256[](2);
        {
            uint256 amountIn;
            uint8 index;
            uint256 amountOut;
            (amountIn, index, amountOut) = _rebalanceTokens(
                params,
                minTokensAmount,
                ratioParams.minTickRebalanceThreshold,
                vaultOptions
            );
            if (index == 0) {
                zeroToOne = true;
                tokenAmounts[0] = amountIn;
                tokenAmounts[1] = amountOut;
            } else {
                zeroToOne = false;
                tokenAmounts[0] = amountOut;
                tokenAmounts[1] = amountIn;
            }
        }
        uint256[] memory minDeviations = new uint256[](2);
        minDeviations[0] = ratioParams.minErc20MoneyRatioDeviation0D;
        minDeviations[1] = ratioParams.minErc20MoneyRatioDeviation1D;
        poolAmounts = _rebalancePools(params.erc20Vault, params.moneyVault, params.tokens, minDeviations, vaultOptions);
    }

    /// @notice Manually pull tokens from fromVault to toVault
    /// @param fromVault Pull tokens from this vault
    /// @param toVault Pull tokens to this vault
    /// @param tokenAmounts Token amounts to pull
    function manualPull(
        IIntegrationVault fromVault,
        IIntegrationVault toVault,
        uint256[] memory tokenAmounts,
        bytes memory vaultOptions
    ) external {
        _requireAdmin();
        fromVault.pull(address(toVault), tokens, tokenAmounts, vaultOptions);
    }

    /// @notice Set new Oracle params
    /// @param params Params to set
    function setOracleParams(OracleParams memory params) external {
        _requireAdmin();
        require((params.maxSlippageD > 0) && (params.maxSlippageD <= DENOMINATOR), ExceptionsLibrary.INVARIANT);

        oracleParams = params;
        emit SetOracleParams(tx.origin, msg.sender, params);
    }

    /// @notice Set new Ratio params
    /// @param params Params to set
    function setRatioParams(RatioParams memory params) external {
        _requireAdmin();
        require(
            (params.tickMin <= params.tickMax) &&
                (params.erc20MoneyRatioD <= DENOMINATOR) &&
                (params.minErc20MoneyRatioDeviation0D <= DENOMINATOR) &&
                (params.minErc20MoneyRatioDeviation1D <= DENOMINATOR) &&
                (params.tickMin >= TickMath.MIN_TICK) &&
                (params.tickMax <= TickMath.MAX_TICK) &&
                (params.tickNeighborhood >= 0) &&
                (params.tickNeighborhood <= TickMath.MAX_TICK) &&
                (params.tickIncrease >= 0) &&
                (params.tickIncrease <= TickMath.MAX_TICK),
            ExceptionsLibrary.INVARIANT
        );

        ratioParams = params;
        emit SetRatioParams(tx.origin, msg.sender, params);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("MStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    function _priceX96FromTick(int24 _tick) internal pure returns (uint256) {
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(_tick);
        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, CommonLibrary.Q96);
    }

    function _targetTokenRatioD(
        int24 tick,
        int24 tickMin,
        int24 tickMax
    ) internal pure returns (uint256) {
        if (tick <= tickMin) {
            return DENOMINATOR;
        }
        if (tick >= tickMax) {
            return 0;
        }
        return (uint256(uint24(tickMax - tick)) * DENOMINATOR) / uint256(uint24(tickMax - tickMin));
    }

    function _getAverageTickChecked(IUniswapV3Pool pool_) internal view returns (int24) {
        (int24 tick, int24 deviation) = _getAverageTick(pool_);
        uint24 absoluteDeviation = deviation < 0 ? uint24(-deviation) : uint24(deviation);
        require(absoluteDeviation < oracleParams.maxTickDeviation, ExceptionsLibrary.INVARIANT);
        return tick;
    }

    function _getAverageTick(IUniswapV3Pool pool_) internal view returns (int24 averageTick, int24 tickDeviation) {
        uint32 oracleObservationDelta = oracleParams.oracleObservationDelta;
        (, int24 tick, , , , , ) = pool_.slot0();
        bool withFail = false;
        (averageTick, , withFail) = OracleLibrary.consult(address(pool_), oracleObservationDelta);
        // Fails when we dont have observations, so return spot tick as this was the last trade price
        if (withFail) {
            averageTick = tick;
        }
        tickDeviation = tick - averageTick;
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _rebalancePools(
        IIntegrationVault erc20Vault_,
        IIntegrationVault moneyVault_,
        address[] memory tokens_,
        uint256[] memory minDeviations,
        bytes memory vaultOptions
    ) internal returns (int256[] memory tokenAmounts) {
        uint256 erc20MoneyRatioD = ratioParams.erc20MoneyRatioD;
        (uint256[] memory erc20Tvl, ) = erc20Vault_.tvl();
        (uint256[] memory moneyTvl, ) = moneyVault_.tvl();
        tokenAmounts = new int256[](2);
        uint256 max = type(uint256).max / 2;
        bool hasSignificantDeltas = false;
        for (uint256 i = 0; i < 2; i++) {
            uint256 targetErc20Token = FullMath.mulDiv(erc20Tvl[i] + moneyTvl[i], erc20MoneyRatioD, DENOMINATOR);
            uint256 absoluteTokenAmount = 0;
            if (targetErc20Token > erc20Tvl[i]) {
                absoluteTokenAmount = targetErc20Token - erc20Tvl[i];
            } else {
                absoluteTokenAmount = erc20Tvl[i] - targetErc20Token;
            }
            require(absoluteTokenAmount < max, ExceptionsLibrary.LIMIT_OVERFLOW);
            if (targetErc20Token > erc20Tvl[i]) {
                tokenAmounts[i] = int256(absoluteTokenAmount);
            } else {
                tokenAmounts[i] = -int256(absoluteTokenAmount);
            }
            if (absoluteTokenAmount >= minDeviations[i]) {
                hasSignificantDeltas = true;
            }
        }

        if (!hasSignificantDeltas) {
            return new int256[](2);
        } else if ((tokenAmounts[0] <= 0) && (tokenAmounts[1] <= 0)) {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = uint256(-tokenAmounts[0]);
            amounts[1] = uint256(-tokenAmounts[1]);
            erc20Vault_.pull(address(moneyVault_), tokens_, amounts, vaultOptions);
        } else if ((tokenAmounts[0] >= 0) && (tokenAmounts[1] >= 0)) {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = uint256(tokenAmounts[0]);
            amounts[1] = uint256(tokenAmounts[1]);
            moneyVault_.pull(address(erc20Vault_), tokens_, amounts, vaultOptions);
        } else {
            for (uint256 i = 0; i < 2; i++) {
                uint256[] memory amounts = new uint256[](2);
                if (tokenAmounts[i] > 0) {
                    amounts[i] = uint256(tokenAmounts[i]);
                    moneyVault_.pull(address(erc20Vault_), tokens_, amounts, vaultOptions);
                } else if (tokenAmounts[i] < 0) {
                    amounts[i] = uint256(-tokenAmounts[i]);
                    erc20Vault_.pull(address(moneyVault_), tokens_, amounts, vaultOptions);
                }
            }
        }
        emit RebalancedPools(tokenAmounts);
    }

    function _rebalanceTokens(
        SwapToTargetParams memory params,
        uint256[] memory minTokensAmount,
        int24 minTickRebalanceThreshold_,
        bytes memory vaultOptions
    )
        internal
        returns (
            uint256, // amountIn     - amount of token, that we pushed into SwapRouter
            uint8, // index        - index of token, that we pushed into SwapRouter
            uint256 // amountOut    - amount of token, that we recieved from SwapRouter
        )
    {
        uint256 token0;
        uint256 targetToken0;
        {
            uint256 targetTokenRatioD;
            {
                int24 tick = _getAverageTickChecked(params.pool);
                if (ratioParams.tickMin + ratioParams.tickNeighborhood > tick) {
                    ratioParams.tickMin =
                        (tick < ratioParams.tickMin ? tick : ratioParams.tickMin) -
                        ratioParams.tickIncrease;
                    if (ratioParams.tickMin < TickMath.MIN_TICK) {
                        ratioParams.tickMin = TickMath.MIN_TICK;
                    }
                }
                if (ratioParams.tickMax - ratioParams.tickNeighborhood < tick) {
                    ratioParams.tickMax =
                        (tick > ratioParams.tickMax ? tick : ratioParams.tickMax) +
                        ratioParams.tickIncrease;
                    if (ratioParams.tickMax > TickMath.MAX_TICK) {
                        ratioParams.tickMax = TickMath.MAX_TICK;
                    }
                }

                require(
                    (tick > lastRebalanceTick + minTickRebalanceThreshold_) ||
                        (tick < lastRebalanceTick - minTickRebalanceThreshold_),
                    ExceptionsLibrary.LIMIT_UNDERFLOW
                );
                lastRebalanceTick = tick;
                params.priceX96 = _priceX96FromTick(tick);
                targetTokenRatioD = _targetTokenRatioD(tick, ratioParams.tickMin, ratioParams.tickMax);
            }
            (params.erc20Tvl, ) = params.erc20Vault.tvl();
            uint256 token1;
            {
                (uint256[] memory moneyTvl, ) = params.moneyVault.tvl();
                token0 = params.erc20Tvl[0] + moneyTvl[0];
                token1 = params.erc20Tvl[1] + moneyTvl[1];
            }

            uint256 token1InToken0 = FullMath.mulDiv(token1, CommonLibrary.Q96, params.priceX96);
            targetToken0 = FullMath.mulDiv(token1InToken0 + token0, targetTokenRatioD, DENOMINATOR);
        }

        if (targetToken0 < token0) {
            params.amountIn = token0 - targetToken0;
            params.tokenInIndex = 0;
        } else {
            params.amountIn = FullMath.mulDiv(targetToken0 - token0, params.priceX96, CommonLibrary.Q96);
            params.tokenInIndex = 1;
        }
        if (params.amountIn != 0) {
            uint256 amountOut = _swapToTarget(params, vaultOptions);
            require(amountOut >= minTokensAmount[params.tokenInIndex ^ 1], ExceptionsLibrary.LIMIT_UNDERFLOW);
            emit SwappedTokens(params);
            return (params.amountIn, params.tokenInIndex, amountOut);
        } else {
            return (params.amountIn, params.tokenInIndex, 0);
        }
    }

    struct SwapToTargetParams {
        uint256 amountIn;
        address[] tokens;
        uint8 tokenInIndex;
        uint256 priceX96;
        uint256[] erc20Tvl;
        IUniswapV3Pool pool;
        ISwapRouter router;
        IIntegrationVault erc20Vault;
        IIntegrationVault moneyVault;
    }

    function _swapToTarget(SwapToTargetParams memory params, bytes memory vaultOptions)
        internal
        returns (uint256 amountOut)
    {
        ISwapRouter.ExactInputSingleParams memory swapParams;
        uint8 tokenInIndex = params.tokenInIndex;
        uint256 amountIn = params.amountIn;
        ISwapRouter router_ = params.router;
        {
            uint256 priceX96 = params.priceX96;
            uint256[] memory erc20Tvl = params.erc20Tvl;

            if (amountIn > erc20Tvl[tokenInIndex]) {
                uint256[] memory tokenAmounts = new uint256[](2);
                tokenAmounts[tokenInIndex] = amountIn - erc20Tvl[tokenInIndex];
                params.moneyVault.pull(address(params.erc20Vault), params.tokens, tokenAmounts, vaultOptions);
                uint256 balance = IERC20(tokens[tokenInIndex]).balanceOf(address(erc20Vault));
                if (balance < amountIn) {
                    amountIn = balance;
                }
            }
            uint256 amountOutMinimum;
            if (tokenInIndex == 1) {
                amountOutMinimum = FullMath.mulDiv(amountIn, CommonLibrary.Q96, priceX96);
            } else {
                amountOutMinimum = FullMath.mulDiv(amountIn, priceX96, CommonLibrary.Q96);
            }
            amountOutMinimum = FullMath.mulDiv(amountOutMinimum, DENOMINATOR - oracleParams.maxSlippageD, DENOMINATOR);
            swapParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: params.tokens[tokenInIndex],
                tokenOut: params.tokens[1 - tokenInIndex],
                fee: params.pool.fee(),
                recipient: address(erc20Vault),
                deadline: block.timestamp + 1,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            });
        }
        bytes memory data = abi.encode(swapParams);
        erc20Vault.externalCall(tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(address(router_), amountIn)); // approve
        bytes memory routerResult = erc20Vault.externalCall(address(router_), EXACT_INPUT_SINGLE_SELECTOR, data); //swap
        erc20Vault.externalCall(tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(address(router_), 0)); // reset allowance
        amountOut = abi.decode(routerResult, (uint256));
    }

    /// @notice Emitted when pool rebalance is initiated.
    /// @param tokenAmounts Token amounts for rebalance, negative means erc20Vault => moneyVault and vice versa.
    event RebalancedPools(int256[] tokenAmounts);

    /// @notice Emitted when swap is initiated.
    /// @param params Swap params
    event SwappedTokens(SwapToTargetParams params);

    /// @notice Emitted when Oracle params are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param params Updated params
    event SetOracleParams(address indexed origin, address indexed sender, OracleParams params);

    /// @notice Emitted when Ratio params are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param params Updated params
    event SetRatioParams(address indexed origin, address indexed sender, RatioParams params);
}
