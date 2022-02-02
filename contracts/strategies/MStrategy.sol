// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

    // MUTABLE PARAMS

    struct OracleParams {
        uint16 oracleObservationDelta;
        uint24 maxTickDeviation;
        uint256 maxSlippageD;
    }

    struct RatioParams {
        int24 tickMin;
        int24 tickMax;
        uint256 erc20MoneyRatioD;
    }

    OracleParams public oracleParams;
    RatioParams public ratioParams;

    /// @notice Deploys a new contract
    /// @param positionManager_ Uniswap V3 position manager
    /// @param router_ Uniswap V3 swap router
    constructor(INonfungiblePositionManager positionManager_, ISwapRouter router_) {
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

        address[] memory erc20Tokens = erc20Vault_.vaultTokens();
        address[] memory moneyTokens = moneyVault_.vaultTokens();
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
    function rebalance() external returns (uint256[] memory poolAmounts, uint256[] memory tokenAmounts) {
        _requireAdmin();
        IIntegrationVault erc20Vault_ = erc20Vault;
        IIntegrationVault moneyVault_ = moneyVault;
        address[] memory tokens_ = tokens;
        IUniswapV3Pool pool_ = pool;
        ISwapRouter router_ = router;
        int256[] memory poolAmountsI = _rebalancePools(erc20Vault_, moneyVault_, tokens_);
        (uint256 amountIn, uint8 index) = _rebalanceTokens(pool_, router_, erc20Vault_, moneyVault_, tokens_);
        poolAmounts = new uint256[](2);
        tokenAmounts = new uint256[](2);
        for (uint256 i = 0; i < 2; i++) {
            poolAmounts[i] = poolAmountsI[i] > 0 ? uint256(poolAmountsI[i]) : uint256(-poolAmountsI[i]);
        }
        tokenAmounts[index] = amountIn;
    }

    /// @notice Manually pull tokens from fromVault to toVault
    /// @param fromVault Pull tokens from this vault
    /// @param toVault Pull tokens to this vault
    /// @param tokenAmounts Token amounts to pull
    function manualPull(
        IIntegrationVault fromVault,
        IIntegrationVault toVault,
        uint256[] memory tokenAmounts
    ) external {
        _requireAdmin();
        fromVault.pull(address(toVault), tokens, tokenAmounts, "");
    }

    /// @notice Set new Oracle params
    /// @param params Params to set
    function setOracleParams(OracleParams memory params) external {
        _requireAdmin();
        oracleParams = params;
        emit SetOracleParams(tx.origin, msg.sender, params);
    }

    /// @notice Set new Ratio params
    /// @param params Params to set
    function setRatioParams(RatioParams memory params) external {
        _requireAdmin();
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
            return 0;
        }
        if (tick >= tickMax) {
            return DENOMINATOR;
        }
        return (uint256(uint24(tick - tickMin)) * DENOMINATOR) / uint256(uint24(tickMax - tickMin));
    }

    function _getAverageTickChecked(IUniswapV3Pool pool_) internal view returns (int24) {
        (int24 tick, int24 deviation) = _getAverageTick(pool_);
        int24 maxDeviation = int24(oracleParams.maxTickDeviation);
        require((deviation < maxDeviation) && (deviation > -maxDeviation), ExceptionsLibrary.INVARIANT);
        return tick;
    }

    function _getAverageTick(IUniswapV3Pool pool_) internal view returns (int24 averageTick, int24 tickDeviation) {
        uint16 oracleObservationDelta = oracleParams.oracleObservationDelta;

        (, int24 tick, uint16 observationIndex, uint16 observationCardinality, , , ) = pool_.slot0();
        require(observationCardinality > oracleObservationDelta, ExceptionsLibrary.LIMIT_UNDERFLOW);
        (uint32 blockTimestamp, int56 tickCumulative, , ) = pool_.observations(observationIndex);

        uint16 observationIndexLast = observationIndex >= oracleObservationDelta
            ? observationIndex - oracleObservationDelta
            : observationIndex + (type(uint16).max - oracleObservationDelta + 1);
        (uint32 blockTimestampLast, int56 tickCumulativeLast, , ) = pool_.observations(observationIndexLast);

        uint32 timespan = blockTimestamp - blockTimestampLast;
        averageTick = int24((int256(tickCumulative) - int256(tickCumulativeLast)) / int256(uint256(timespan)));
        tickDeviation = tick - averageTick;
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _rebalancePools(
        IIntegrationVault erc20Vault_,
        IIntegrationVault moneyVault_,
        address[] memory tokens_
    ) internal returns (int256[] memory tokenAmounts) {
        uint256 erc20MoneyRatioD = ratioParams.erc20MoneyRatioD;
        (uint256[] memory erc20Tvl, ) = erc20Vault_.tvl();
        (uint256[] memory moneyTvl, ) = moneyVault_.tvl();
        tokenAmounts = new int256[](2);
        uint256 max = type(uint256).max / 2;
        for (uint256 i = 0; i < 2; i++) {
            uint256 targetErc20Token = FullMath.mulDiv(erc20Tvl[i] + moneyTvl[i], erc20MoneyRatioD, DENOMINATOR);
            require(targetErc20Token < max && erc20Tvl[i] < max, ExceptionsLibrary.LIMIT_OVERFLOW);
            tokenAmounts[i] = int256(targetErc20Token) - int256(erc20Tvl[i]);
        }
        if ((tokenAmounts[0] == 0) && (tokenAmounts[1] == 0)) {
            return tokenAmounts;
        } else if ((tokenAmounts[0] <= 0) && (tokenAmounts[1] <= 0)) {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = uint256(-tokenAmounts[0]);
            amounts[1] = uint256(-tokenAmounts[1]);
            erc20Vault_.pull(address(moneyVault_), tokens_, amounts, "");
        } else if ((tokenAmounts[0] >= 0) && (tokenAmounts[1] >= 0)) {
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = uint256(tokenAmounts[0]);
            amounts[1] = uint256(tokenAmounts[1]);
            moneyVault_.pull(address(erc20Vault_), tokens_, amounts, "");
        } else {
            for (uint256 i = 0; i < 2; i++) {
                uint256[] memory amounts = new uint256[](2);
                if (tokenAmounts[i] > 0) {
                    amounts[i] = uint256(tokenAmounts[i]);
                    moneyVault_.pull(address(erc20Vault_), tokens_, amounts, "");
                } else {
                    // cannot == 0 here
                    amounts[i] = uint256(-tokenAmounts[i]);
                    erc20Vault_.pull(address(moneyVault_), tokens_, amounts, "");
                }
            }
        }
        emit RebalancedPools(tokenAmounts);
    }

    function _rebalanceTokens(
        IUniswapV3Pool pool_,
        ISwapRouter router_,
        IIntegrationVault erc20Vault_,
        IIntegrationVault moneyVault_,
        address[] memory tokens_
    ) internal returns (uint256 amountIn, uint8 index) {
        uint256 token0;
        uint256 priceX96;
        uint256 targetToken0;
        uint256[] memory erc20Tvl;
        {
            uint256 targetTokenRatioD;
            {
                int24 tickMin = ratioParams.tickMin;
                int24 tickMax = ratioParams.tickMax;
                int24 tick = _getAverageTickChecked(pool_);
                priceX96 = _priceX96FromTick(tick);
                targetTokenRatioD = _targetTokenRatioD(tick, tickMin, tickMax);
            }
            (erc20Tvl, ) = erc20Vault_.tvl();
            uint256 token1;
            {
                (uint256[] memory moneyTvl, ) = moneyVault_.tvl();
                token0 = erc20Tvl[0] + moneyTvl[0];
                token1 = erc20Tvl[1] + moneyTvl[1];
            }

            uint256 token1InToken0 = FullMath.mulDiv(token1, CommonLibrary.Q96, priceX96);
            targetToken0 = FullMath.mulDiv(token1InToken0 + token0, targetTokenRatioD, DENOMINATOR);
        }
        SwapToTargetParams memory params;
        if (targetToken0 < token0) {
            index = 0;
            params = SwapToTargetParams({
                amountIn: token0 - targetToken0,
                tokens: tokens_,
                tokenInIndex: index,
                priceX96: priceX96,
                erc20Tvl: erc20Tvl,
                pool: pool_,
                router: router_,
                erc20Vault: erc20Vault_,
                moneyVault: moneyVault_
            });
        } else {
            amountIn = FullMath.mulDiv(targetToken0 - token0, priceX96, CommonLibrary.Q96);
            index = 1;
            params = SwapToTargetParams({
                amountIn: amountIn,
                tokens: tokens_,
                tokenInIndex: index,
                priceX96: priceX96,
                erc20Tvl: erc20Tvl,
                pool: pool_,
                router: router_,
                erc20Vault: erc20Vault_,
                moneyVault: moneyVault_
            });
        }
        _swapToTarget(params);
        emit SwappedTokens(params);
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

    function _swapToTarget(SwapToTargetParams memory params) internal {
        ISwapRouter.ExactInputSingleParams memory swapParams;
        uint8 tokenInIndex = params.tokenInIndex;
        uint256 amountIn = params.amountIn;
        ISwapRouter router_ = params.router;
        {
            address[] memory tokens_ = params.tokens;
            uint256 priceX96 = params.priceX96;
            uint256[] memory erc20Tvl = params.erc20Tvl;
            IUniswapV3Pool pool_ = params.pool;
            IIntegrationVault erc20Vault_ = params.erc20Vault;
            IIntegrationVault moneyVault_ = params.moneyVault;

            if (amountIn > erc20Tvl[tokenInIndex]) {
                uint256[] memory tokenAmounts = new uint256[](2);
                tokenAmounts[tokenInIndex] = amountIn - erc20Tvl[tokenInIndex];
                moneyVault_.pull(address(erc20Vault_), tokens_, tokenAmounts, "");
                amountIn = IERC20(tokens[tokenInIndex]).balanceOf(address(erc20Vault));
            }
            uint256 amountOutMinimum;
            if (tokenInIndex == 1) {
                amountOutMinimum = FullMath.mulDiv(amountIn, CommonLibrary.Q96, priceX96);
            } else {
                amountOutMinimum = FullMath.mulDiv(amountIn, priceX96, CommonLibrary.Q96);
            }
            amountOutMinimum = FullMath.mulDiv(amountOutMinimum, DENOMINATOR - oracleParams.maxSlippageD, DENOMINATOR);
            swapParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: tokens_[tokenInIndex],
                tokenOut: tokens_[1 - tokenInIndex],
                fee: pool_.fee(),
                recipient: address(erc20Vault),
                deadline: block.timestamp + 1,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            });
        }
        bytes memory data = abi.encode(swapParams);
        erc20Vault.externalCall(tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(address(router_), amountIn)); // approve
        erc20Vault.externalCall(address(router_), EXACT_INPUT_SINGLE_SELECTOR, data); //swap
        erc20Vault.externalCall(tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(address(router_), 0)); // reset allowance
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
