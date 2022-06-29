// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/external/OracleLibrary.sol";
import "../libraries/external/LiquidityAmounts.sol";
import "../utils/DefaultAccessControlLateInit.sol";
import "../utils/ContractMeta.sol";
import "../utils/UniV3Helper.sol";

contract HStrategy is ContractMeta, Multicall, DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    // IMMUTABLES
    uint32 public constant DENOMINATOR = 10**9;
    bytes4 public constant APPROVE_SELECTOR = IERC20.approve.selector; // 0x095ea7b3; more consistent?
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;
    ISwapRouter public router;

    IERC20Vault public erc20Vault;
    IIntegrationVault public moneyVault;
    IUniV3Vault public uniV3Vault;
    address[] public tokens;

    INonfungiblePositionManager public positionManager;
    IUniswapV3Pool public pool;
    UniV3Helper private _uniV3Helper;

    // MUTABLE PARAMS
    struct IntervalParams {
        int24 lowerTick;
        int24 upperTick;
    }

    struct StrategyParams {
        int24 widthCoefficient;
        int24 widthTicks;
        uint32 oracleObservationDelta;
        uint32 erc20MoneyRatioD;
        uint256 minToken0ForOpening;
        uint256 minToken1ForOpening;
        bool simulateUniV3Interval;
    }

    StrategyParams public strategyParams;
    IntervalParams public globalIntervalParams;

    // INTERNAL STRUCTURES
    struct RebalanceRestrictions {
        uint256[] pulledOnUniV3Vault;
        uint256[] pulledFromUniV3Vault;
        uint256[] pulledOnMoneyVault;
        uint256[] pulledFromMoneyVault;
        uint256[] swappedAmounts;
        uint256[] burnedAmounts;
        uint256 deadline;
    }

    struct TokenAmountsInToken0 {
        uint256 erc20TokensAmountInToken0;
        uint256 moneyTokensAmountInToken0;
        uint256 uniV3TokensAmountInToken0;
        uint256 totalTokensInToken0;
    }

    struct TokenAmounts {
        uint256 erc20Token0;
        uint256 erc20Token1;
        uint256 moneyToken0;
        uint256 moneyToken1;
        uint256 uniV3Token0;
        uint256 uniV3Token1;
    }

    struct ExpectedRatios {
        uint32 token0RatioD;
        uint32 token1RatioD;
        uint32 uniV3RatioD;
    }

    struct VaultsStatistics {
        uint256[] uniV3Vault;
        uint256[] erc20Vault;
        uint256[] moneyVault;
    }

    // INTERNAL STATE
    int24 public lastSwapRebalanceTick;
    int24 public lastMintRebalanceTick;

    // -------------------  EXTERNAL, MUTATING  -------------------

    constructor(INonfungiblePositionManager positionManager_, ISwapRouter router_) {
        require(address(positionManager_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(router_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        positionManager = positionManager_;
        DefaultAccessControlLateInit.init(address(this));
        router = router_;
    }

    function initialize(
        INonfungiblePositionManager positionManager_,
        address[] memory tokens_,
        IERC20Vault erc20Vault_,
        IIntegrationVault moneyVault_,
        IUniV3Vault uniV3Vault_,
        uint24 fee_,
        address admin_,
        address uniV3Hepler_
    ) external {
        DefaultAccessControlLateInit.init(admin_); // call once is checked here
        address[] memory erc20Tokens = erc20Vault_.vaultTokens();
        address[] memory moneyTokens = moneyVault_.vaultTokens();
        address[] memory uniV3Tokens = uniV3Vault_.vaultTokens();
        require(tokens_.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(erc20Tokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(moneyTokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(uniV3Tokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < 2; i++) {
            require(erc20Tokens[i] == tokens_[i], ExceptionsLibrary.INVARIANT);
            require(moneyTokens[i] == tokens_[i], ExceptionsLibrary.INVARIANT);
            require(uniV3Tokens[i] == tokens_[i], ExceptionsLibrary.INVARIANT);
        }
        positionManager = positionManager_;
        erc20Vault = erc20Vault_;
        moneyVault = moneyVault_;
        uniV3Vault = uniV3Vault_;
        tokens = tokens_;
        IUniswapV3Factory factory = IUniswapV3Factory(positionManager_.factory());
        pool = IUniswapV3Pool(factory.getPool(tokens[0], tokens[1], fee_));
        require(address(pool) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        _uniV3Helper = UniV3Helper(uniV3Hepler_);
    }

    function createStrategy(
        address[] memory tokens_,
        IERC20Vault erc20Vault_,
        IIntegrationVault moneyVault_,
        IUniV3Vault uniV3Vault_,
        uint24 fee_,
        address admin_,
        address uniV3Helper
    ) external returns (HStrategy strategy) {
        strategy = HStrategy(Clones.clone(address(this)));
        strategy.initialize(positionManager, tokens_, erc20Vault_, moneyVault_, uniV3Vault_, fee_, admin_, uniV3Helper);
    }

    function updateStrategyParams(StrategyParams calldata newStrategyParams) external {
        _requireAdmin();
        require(
            (newStrategyParams.widthCoefficient > 0 &&
                newStrategyParams.widthTicks > 0 &&
                newStrategyParams.oracleObservationDelta > 0 &&
                newStrategyParams.erc20MoneyRatioD > 0 &&
                newStrategyParams.erc20MoneyRatioD <= DENOMINATOR &&
                newStrategyParams.minToken0ForOpening > 0 &&
                newStrategyParams.minToken1ForOpening > 0 &&
                type(int24).max / newStrategyParams.widthTicks / 2 >= newStrategyParams.widthCoefficient),
            ExceptionsLibrary.INVARIANT
        );
        strategyParams = newStrategyParams;
        emit UpdateStrategyParams(tx.origin, msg.sender, newStrategyParams);
    }

    function updateIntervalParams(IntervalParams calldata newIntervalParams) external {
        _requireAdmin();
        require((newIntervalParams.lowerTick < newIntervalParams.upperTick), ExceptionsLibrary.INVARIANT);
        globalIntervalParams = newIntervalParams;
        emit UpdateIntervalParams(tx.origin, msg.sender, newIntervalParams);
    }

    function manualPull(
        IIntegrationVault fromVault,
        IIntegrationVault toVault,
        uint256[] memory tokenAmounts,
        bytes memory vaultOptions
    ) external {
        _requireAdmin();
        fromVault.pull(address(toVault), tokens, tokenAmounts, vaultOptions);
    }

    function rebalance(
        uint256[] memory pulledOnMoneyVault,
        uint256[] memory pulledFromMoneyVault,
        uint256[] memory pulledOnUniV3Vault,
        uint256[] memory pulledFromUniV3Vault,
        uint256[] memory swappedAmounts,
        uint256[] memory burnedAmounts,
        uint256 deadline,
        bytes memory moneyVaultOptions
    ) external {
        uint256 uniV3Nft = uniV3Vault.nft();
        INonfungiblePositionManager positionManager_ = positionManager;
        StrategyParams memory strategyParams_ = strategyParams;
        IUniswapV3Pool pool_ = pool;

        if (uniV3Nft != 0) {
            // cannot burn only if it is first call of the rebalance function
            // and we dont have any position
            _burnPosition(burnedAmounts, uniV3Nft, positionManager_);
        }

        (int24 averageTick, uint160 sqrtSpotPriceX96) = _uniV3Helper.getAverageTickAndSqrtSpotPrice(
            pool_,
            strategyParams_.oracleObservationDelta
        );
        uniV3Nft = _mintPosition(globalIntervalParams, strategyParams_, pool_, deadline, positionManager_, averageTick);

        DomainPositionParams memory domainPositionParams = _calculateDomainPositionParams(
            averageTick,
            sqrtSpotPriceX96,
            globalIntervalParams,
            pool_,
            strategyParams_,
            uniV3Nft,
            positionManager_
        );
        ExpectedRatios memory expectedRatios = _calculateExpectedRatios(domainPositionParams);

        TokenAmountsInToken0 memory currentTokenAmountsInToken0 = _calculateCurrentTokenAmountsInToken0(
            domainPositionParams
        );
        TokenAmountsInToken0 memory expectedTokenAmountsInToken0 = _calculateExpectedTokenAmountsInToken0(
            currentTokenAmountsInToken0,
            expectedRatios,
            strategyParams_
        );

        TokenAmounts memory expectedTokenAmounts = _calculateExpectedTokenAmounts(
            expectedRatios,
            expectedTokenAmountsInToken0,
            domainPositionParams
        );

        {
            TokenAmounts memory extraTokenAmounts = _calculateExtraTokenAmounts(
                expectedTokenAmounts,
                domainPositionParams
            );
        }
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _mintPosition(
        IntervalParams memory globalIntervalParams_,
        StrategyParams memory strategyParams_,
        IUniswapV3Pool pool_,
        uint256 deadline,
        INonfungiblePositionManager positionManager_,
        int24 averageTick
    ) internal returns (uint256 newNft) {
        int24 lowerTick = 0;
        int24 upperTick = 0;
        {
            int24 intervalWidth = strategyParams_.widthTicks * strategyParams_.widthCoefficient;
            int24 deltaToLowerTick = averageTick - globalIntervalParams_.lowerTick;
            require(deltaToLowerTick >= 0, ExceptionsLibrary.LIMIT_UNDERFLOW);
            deltaToLowerTick -= (deltaToLowerTick % intervalWidth);
            int24 mintLeftTick = globalIntervalParams_.lowerTick + deltaToLowerTick;
            int24 mintRightTick = mintLeftTick + intervalWidth;
            int24 mintTick = 0;
            if (averageTick - mintLeftTick <= mintRightTick - averageTick) {
                mintTick = mintLeftTick;
            } else {
                mintTick = mintRightTick;
            }


            lowerTick = mintTick - intervalWidth;
            upperTick = mintTick + intervalWidth;

            if (lowerTick < globalIntervalParams_.lowerTick) {
                lowerTick = globalIntervalParams_.lowerTick;
                upperTick = lowerTick + 2 * intervalWidth;
            } else if (upperTick > globalIntervalParams_.upperTick) {
                upperTick = globalIntervalParams_.upperTick;
                lowerTick = upperTick - 2 * intervalWidth;
            }
        }

        IERC20(tokens[0]).safeApprove(address(positionManager_), strategyParams_.minToken0ForOpening);
        IERC20(tokens[1]).safeApprove(address(positionManager_), strategyParams_.minToken1ForOpening);
        (newNft, , , ) = positionManager_.mint(
            INonfungiblePositionManager.MintParams({
                token0: tokens[0],
                token1: tokens[1],
                fee: pool_.fee(),
                tickLower: lowerTick,
                tickUpper: upperTick,
                amount0Desired: strategyParams_.minToken0ForOpening,
                amount1Desired: strategyParams_.minToken1ForOpening,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: deadline
            })
        );
        IERC20(tokens[0]).safeApprove(address(positionManager_), 0);
        IERC20(tokens[1]).safeApprove(address(positionManager_), 0);

        positionManager_.safeTransferFrom(address(this), address(uniV3Vault), newNft);
    }

    function _burnPosition(
        uint256[] memory burnAmounts,
        uint256 uniV3Nft,
        INonfungiblePositionManager positionManager_
    ) internal {
        if (uniV3Nft == 0) {
            return;
        }

        uint256[] memory burnedTokens = uniV3Vault.collectEarnings();
        _compareAmounts(burnAmounts, burnedTokens);
        {
            (, , , , , , , uint128 liquidity, , , , ) = positionManager_.positions(uniV3Nft);
            require(liquidity == 0, ExceptionsLibrary.INVARIANT);
        }
        positionManager_.burn(uniV3Nft);
        emit BurnUniV3Position(tx.origin, uniV3Nft);
    }

    function _calculateExtraTokenAmounts(
        TokenAmounts memory expectedTokenAmounts,
        DomainPositionParams memory domainPositionParams
    ) internal returns (TokenAmounts memory extraTokenAmounts) {
        // TODO: that
    }

    function _calculateExpectedTokenAmounts(
        ExpectedRatios memory expectedRatios,
        TokenAmountsInToken0 memory expectedTokenAmountsInToken0,
        DomainPositionParams memory domainPositionParams
    ) internal pure returns (TokenAmounts memory amounts) {
        amounts.erc20Token0 = FullMath.mulDiv(
            expectedRatios.token0RatioD,
            expectedTokenAmountsInToken0.erc20TokensAmountInToken0,
            expectedRatios.token0RatioD + expectedRatios.token1RatioD
        );
        amounts.erc20Token1 = FullMath.mulDiv(
            expectedTokenAmountsInToken0.erc20TokensAmountInToken0 - amounts.erc20Token0,
            domainPositionParams.averagePriceX96,
            CommonLibrary.Q96
        );

        amounts.moneyToken0 = FullMath.mulDiv(
            expectedRatios.token0RatioD,
            expectedTokenAmountsInToken0.moneyTokensAmountInToken0,
            expectedRatios.token0RatioD + expectedRatios.token1RatioD
        );
        amounts.moneyToken1 = FullMath.mulDiv(
            expectedTokenAmountsInToken0.moneyTokensAmountInToken0 - amounts.moneyToken0,
            domainPositionParams.averagePriceX96,
            CommonLibrary.Q96
        );

        {
            uint128 expectedLiquidity = LiquidityAmounts.getLiquidityForAmount0(
                domainPositionParams.spotPriceSqrtX96,
                domainPositionParams.upperPriceSqrtX96,
                expectedTokenAmountsInToken0.uniV3TokensAmountInToken0
            );
            (amounts.uniV3Token0, amounts.uniV3Token1) = LiquidityAmounts.getAmountsForLiquidity(
                domainPositionParams.spotPriceSqrtX96,
                domainPositionParams.lowerPriceSqrtX96,
                domainPositionParams.upperPriceSqrtX96,
                expectedLiquidity
            );
        }
    }

    function _calculateCurrentTokenAmountsInToken0(DomainPositionParams memory params)
        internal
        view
        returns (TokenAmountsInToken0 memory amounts)
    {
        uint256[] memory uniV3TokenAmounts = new uint256[](2);
        (uniV3TokenAmounts[0], uniV3TokenAmounts[1]) = LiquidityAmounts.getAmountsForLiquidity(
            params.spotPriceSqrtX96,
            params.lowerPriceSqrtX96,
            params.upperPriceSqrtX96,
            params.liquidity
        );

        (uint256[] memory minMoneyTvl, uint256[] memory maxMoneyTvl) = moneyVault.tvl();
        (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();
        amounts.erc20TokensAmountInToken0 =
            erc20Tvl[0] +
            FullMath.mulDiv(erc20Tvl[1], CommonLibrary.Q96, params.averagePriceX96);
        amounts.uniV3TokensAmountInToken0 =
            uniV3TokenAmounts[0] +
            FullMath.mulDiv(uniV3TokenAmounts[1], CommonLibrary.Q96, params.averagePriceX96);
        amounts.moneyTokensAmountInToken0 =
            ((minMoneyTvl[0] + maxMoneyTvl[0]) >> 1) +
            FullMath.mulDiv((minMoneyTvl[1] + maxMoneyTvl[1]) >> 1, CommonLibrary.Q96, params.averagePriceX96);
        amounts.totalTokensInToken0 =
            amounts.erc20TokensAmountInToken0 +
            amounts.uniV3TokensAmountInToken0 +
            amounts.moneyTokensAmountInToken0;
    }

    function _calculateExpectedTokenAmountsInToken0(
        TokenAmountsInToken0 memory currentTokenAmounts,
        ExpectedRatios memory expectedRatios,
        StrategyParams memory strategyParams_
    ) internal pure returns (TokenAmountsInToken0 memory amounts) {
        amounts.uniV3TokensAmountInToken0 = FullMath.mulDiv(
            currentTokenAmounts.totalTokensInToken0,
            expectedRatios.uniV3RatioD,
            DENOMINATOR
        );
        amounts.totalTokensInToken0 = currentTokenAmounts.totalTokensInToken0;
        amounts.erc20TokensAmountInToken0 = FullMath.mulDiv(
            amounts.totalTokensInToken0 - amounts.uniV3TokensAmountInToken0,
            strategyParams_.erc20MoneyRatioD,
            DENOMINATOR
        );
        amounts.moneyTokensAmountInToken0 =
            amounts.totalTokensInToken0 -
            amounts.uniV3TokensAmountInToken0 -
            amounts.erc20TokensAmountInToken0;
    }

    function _swapToTarget(
        VaultsStatistics memory missingTokenAmountsStat,
        DomainPositionParams memory uniswapParams,
        RebalanceRestrictions memory restrictions
    ) internal {
        uint256 amountIn = 0;
        uint32 tokenInIndex = 0;

        {
            uint256 totalMissingToken0 = missingTokenAmountsStat.erc20Vault[0];
            uint256 totalMissingToken1 = missingTokenAmountsStat.erc20Vault[1];

            uint256 totalMissingToken1InToken0 = FullMath.mulDiv(
                totalMissingToken1,
                CommonLibrary.Q96,
                uniswapParams.averagePriceX96
            );

            if (totalMissingToken1InToken0 > totalMissingToken0) {
                require(totalMissingToken0 == 0, ExceptionsLibrary.INVARIANT);
                amountIn = totalMissingToken1InToken0;
                tokenInIndex = 0;
            }
            if (totalMissingToken1InToken0 < totalMissingToken0) {
                require(totalMissingToken1InToken0 == 0, ExceptionsLibrary.INVARIANT);
                amountIn = FullMath.mulDiv(totalMissingToken0, uniswapParams.averagePriceX96, CommonLibrary.Q96);
                tokenInIndex = 1;
            }
        }

        if (amountIn > 0) {
            _swapTokensOnERC20Vault(amountIn, tokenInIndex, restrictions.swappedAmounts, restrictions.deadline);
            lastSwapRebalanceTick = uniswapParams.averageTick;
        }
    }

    struct DomainPositionParams {
        uint256 nft;
        uint128 liquidity;
        int24 lowerTick;
        int24 upperTick;
        int24 lower0Tick;
        int24 upper0Tick;
        int24 averageTick;
        uint160 lowerPriceSqrtX96;
        uint160 upperPriceSqrtX96;
        uint160 lower0PriceSqrtX96;
        uint160 upper0PriceSqrtX96;
        uint160 averagePriceSqrtX96;
        uint256 averagePriceX96;
        uint160 spotPriceSqrtX96;
    }

    function _calculateDomainPositionParams(
        int24 averageTick,
        uint160 sqrtSpotPriceX96,
        IntervalParams memory intervalParams_,
        IUniswapV3Pool pool_,
        StrategyParams memory strategyParams_,
        uint256 uniV3Nft,
        INonfungiblePositionManager _positionManager
    ) internal view returns (DomainPositionParams memory domainPositionParams) {
        require(uniV3Nft != 0, ExceptionsLibrary.INVARIANT);
        (, , , , , int24 lowerTick, int24 upperTick, uint128 liquidity, , , , ) = _positionManager.positions(uniV3Nft);

        domainPositionParams = DomainPositionParams({
            nft: uniV3Nft,
            liquidity: liquidity,
            lowerTick: lowerTick,
            upperTick: upperTick,
            lower0Tick: intervalParams_.lowerTick,
            upper0Tick: intervalParams_.upperTick,
            averageTick: averageTick,
            lowerPriceSqrtX96: TickMath.getSqrtRatioAtTick(lowerTick),
            upperPriceSqrtX96: TickMath.getSqrtRatioAtTick(upperTick),
            lower0PriceSqrtX96: TickMath.getSqrtRatioAtTick(intervalParams_.lowerTick),
            upper0PriceSqrtX96: TickMath.getSqrtRatioAtTick(intervalParams_.upperTick),
            averagePriceSqrtX96: TickMath.getSqrtRatioAtTick(averageTick),
            averagePriceX96: 0,
            spotPriceSqrtX96: sqrtSpotPriceX96
        });
        domainPositionParams.averagePriceX96 = FullMath.mulDiv(
            domainPositionParams.averagePriceSqrtX96,
            domainPositionParams.averagePriceSqrtX96,
            CommonLibrary.Q96
        );
    }

    function _swapTokensOnERC20Vault(
        uint256 amountIn,
        uint256 tokenInIndex,
        uint256[] memory swappedAmounts,
        uint256 deadline
    ) internal returns (uint256[] memory amountsOut) {
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokens[tokenInIndex],
            tokenOut: tokens[tokenInIndex ^ 1],
            fee: pool.fee(),
            recipient: address(erc20Vault),
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        bytes memory routerResult;
        {
            bytes memory data = abi.encode(swapParams);
            erc20Vault.externalCall(tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(address(router), amountIn)); // approve
            routerResult = erc20Vault.externalCall(address(router), EXACT_INPUT_SINGLE_SELECTOR, data); // swap
            erc20Vault.externalCall(tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(address(router), 0)); // reset allowance
        }

        uint256 amountOut = abi.decode(routerResult, (uint256));
        require(swappedAmounts[tokenInIndex ^ 1] <= amountOut, ExceptionsLibrary.LIMIT_UNDERFLOW);

        amountsOut = new uint256[](2);
        amountsOut[tokenInIndex ^ 1] = amountOut;

        emit SwapTokensOnERC20Vault(tx.origin, swapParams);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _getTvlInToken0(address vault, uint256 averagePriceX96) internal view returns (uint256 amount) {
        (uint256[] memory minTvl, uint256[] memory maxTvl) = IIntegrationVault(vault).tvl();
        uint256 averageToken0Tvl = (minTvl[0] + minTvl[0]) >> 1;
        uint256 averageToken1Tvl = (minTvl[1] + maxTvl[1]) >> 1;
        amount = FullMath.mulDiv(averageToken1Tvl, CommonLibrary.Q96, averagePriceX96) + averageToken0Tvl;
    }

    function _calculateExpectedRatios(DomainPositionParams memory domainPositionParams)
        internal
        view
        returns (ExpectedRatios memory ratios)
    {
        uint256 uniV3Nft = domainPositionParams.nft;
        require(uniV3Nft != 0, ExceptionsLibrary.INVARIANT);
        if (strategyParams.simulateUniV3Interval) {
            uint256 denominatorX96 = CommonLibrary.Q96 *
                2 -
                FullMath.mulDiv(
                    domainPositionParams.lower0PriceSqrtX96,
                    CommonLibrary.Q96,
                    domainPositionParams.averagePriceSqrtX96
                ) -
                FullMath.mulDiv(
                    domainPositionParams.averagePriceSqrtX96,
                    CommonLibrary.Q96,
                    domainPositionParams.upper0PriceSqrtX96
                );

            uint256 nominator0X96 = FullMath.mulDiv(
                domainPositionParams.averagePriceSqrtX96,
                CommonLibrary.Q96,
                domainPositionParams.upperPriceSqrtX96
            ) -
                FullMath.mulDiv(
                    domainPositionParams.averagePriceSqrtX96,
                    CommonLibrary.Q96,
                    domainPositionParams.upper0PriceSqrtX96
                );

            uint256 nominator1X96 = FullMath.mulDiv(
                domainPositionParams.lowerPriceSqrtX96,
                CommonLibrary.Q96,
                domainPositionParams.averagePriceSqrtX96
            ) -
                FullMath.mulDiv(
                    domainPositionParams.lower0PriceSqrtX96,
                    CommonLibrary.Q96,
                    domainPositionParams.averagePriceSqrtX96
                );

            ratios.token0RatioD = uint32(FullMath.mulDiv(nominator0X96, DENOMINATOR, denominatorX96));
            ratios.token1RatioD = uint32(FullMath.mulDiv(nominator1X96, DENOMINATOR, denominatorX96));
        } else {
            ratios.token0RatioD = uint32(
                FullMath.mulDiv(
                    domainPositionParams.averagePriceSqrtX96,
                    DENOMINATOR >> 1,
                    domainPositionParams.upperPriceSqrtX96
                )
            );
            ratios.token1RatioD = uint32(
                FullMath.mulDiv(
                    domainPositionParams.lowerPriceSqrtX96,
                    DENOMINATOR >> 1,
                    domainPositionParams.averagePriceSqrtX96
                )
            );
        }
        // remaining part goes to UniV3Vault
        ratios.uniV3RatioD = DENOMINATOR - ratios.token0RatioD - ratios.token1RatioD;
    }

    /// @notice reverts in for any elent holds needed[i] > actual[i]
    function _compareAmounts(uint256[] memory needed, uint256[] memory actual) internal pure {
        for (uint256 i = 0; i < 2; i++) {
            require(needed[i] <= actual[i], ExceptionsLibrary.LIMIT_UNDERFLOW);
        }
    }

    /// @notice Covert token amounts and deadline to byte options
    /// @dev Empty tokenAmounts are equivalent to zero tokenAmounts
    function _makeUniswapVaultOptions(uint256[] memory tokenAmounts, uint256 deadline)
        internal
        pure
        returns (bytes memory options)
    {
        options = new bytes(0x60);
        assembly {
            mstore(add(options, 0x60), deadline)
        }
        if (tokenAmounts.length == 2) {
            uint256 tokenAmount0 = tokenAmounts[0];
            uint256 tokenAmount1 = tokenAmounts[1];
            assembly {
                mstore(add(options, 0x20), tokenAmount0)
                mstore(add(options, 0x40), tokenAmount1)
            }
        }
    }

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("HStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    /// @notice Emitted when new position in UniV3Pool has been minted.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param uniV3Nft nft of new minted position
    /// @param lowerTick lowerTick of that position
    /// @param upperTick upperTick of that position
    event MintUniV3Position(address indexed origin, uint256 uniV3Nft, int24 lowerTick, int24 upperTick);

    /// @notice Emitted when position in UniV3Pool has been burnt.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param uniV3Nft nft of new minted position
    event BurnUniV3Position(address indexed origin, uint256 uniV3Nft);

    /// @notice Emitted when swap is initiated.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param swapParams Swap domainPositionParams
    event SwapTokensOnERC20Vault(address indexed origin, ISwapRouter.ExactInputSingleParams swapParams);

    /// @notice Emitted when Strategy domainPositionParams are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param domainPositionParams Updated domainPositionParams
    event UpdateStrategyParams(address indexed origin, address indexed sender, StrategyParams domainPositionParams);

    /// @notice Emitted when Interval domainPositionParams are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param domainPositionParams Updated domainPositionParams
    event UpdateIntervalParams(address indexed origin, address indexed sender, IntervalParams domainPositionParams);
}
