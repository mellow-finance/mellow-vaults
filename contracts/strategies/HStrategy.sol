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
import "../utils/HStrategyHelper.sol";
import "../utils/ContractMeta.sol";
import "../utils/UniV3Helper.sol";

contract HStrategy is ContractMeta, Multicall, DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    // IMMUTABLES
    uint32 public constant DENOMINATOR = 10**9;
    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;
    ISwapRouter public immutable router;

    IERC20Vault public erc20Vault;
    IIntegrationVault public moneyVault;
    IUniV3Vault public uniV3Vault;
    address[] public tokens;
    uint256 public lastRebalanceTimestamp;

    INonfungiblePositionManager public positionManager;
    IUniswapV3Pool public pool;
    UniV3Helper private _uniV3Helper;
    HStrategyHelper private _hStrategyHelper;
    LastShortInterval private lastShortInterval;

    // MUTABLE PARAMS
    struct StrategyParams {
        int24 widthCoefficient;
        int24 widthTicks;
        int24 tickNeighborhood;
        int24 globalLowerTick;
        int24 globalUpperTick;
    }

    struct MintingParams {
        uint256 minToken0ForOpening;
        uint256 minToken1ForOpening;
    }

    struct OracleParams {
        uint32 oracleObservationDelta;
        uint24 maxTickDeviation;
    }

    struct RatioParams {
        uint256 erc20MoneyRatioD;
        uint256 minUniV3RatioDeviation0D;
        uint256 minUniV3RatioDeviation1D;
        uint256 minMoneyRatioDeviation0D;
        uint256 minMoneyRatioDeviation1D;
    }

    StrategyParams public strategyParams;
    MintingParams public mintingParams;
    OracleParams public oracleParams;
    RatioParams public ratioParams;

    // INTERNAL STRUCTURES

    struct LastShortInterval {
        int24 lowerTick;
        int24 upperTick;
    }

    struct RebalanceRestrictions {
        uint256[] pulledOnUniV3Vault;
        uint256[] pulledOnMoneyVault;
        uint256[] pulledFromMoneyVault;
        uint256[] pulledFromUniV3Vault;
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
        address uniV3Hepler_,
        address hStrategyHelper_
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
        require(uniV3Hepler_ != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(hStrategyHelper_ != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        _uniV3Helper = UniV3Helper(uniV3Hepler_);
        _hStrategyHelper = HStrategyHelper(hStrategyHelper_);
    }

    function createStrategy(
        address[] memory tokens_,
        IERC20Vault erc20Vault_,
        IIntegrationVault moneyVault_,
        IUniV3Vault uniV3Vault_,
        uint24 fee_,
        address admin_,
        address uniV3Helper_,
        address hStrategyHelper_
    ) external returns (HStrategy strategy) {
        strategy = HStrategy(Clones.clone(address(this)));
        strategy.initialize(
            positionManager,
            tokens_,
            erc20Vault_,
            moneyVault_,
            uniV3Vault_,
            fee_,
            admin_,
            uniV3Helper_,
            hStrategyHelper_
        );
    }

    function updateStrategyParams(StrategyParams calldata newStrategyParams) external {
        _requireAdmin();
        require(
            (newStrategyParams.widthCoefficient > 0 &&
                newStrategyParams.widthTicks > 0 &&
                type(int24).max / newStrategyParams.widthTicks / 2 >= newStrategyParams.widthCoefficient) &&
                newStrategyParams.tickNeighborhood <= TickMath.MAX_TICK &&
                newStrategyParams.tickNeighborhood >= TickMath.MIN_TICK,
            ExceptionsLibrary.INVARIANT
        );

        int24 globalIntervalWidth = newStrategyParams.globalUpperTick - newStrategyParams.globalLowerTick;
        int24 shortIntervalWidth = newStrategyParams.widthCoefficient * newStrategyParams.widthTicks;
        require(
            globalIntervalWidth > 0 && shortIntervalWidth > 0 && (globalIntervalWidth % shortIntervalWidth == 0),
            ExceptionsLibrary.INVARIANT
        );

        strategyParams = newStrategyParams;
        emit UpdateStrategyParams(tx.origin, msg.sender, newStrategyParams);
    }

    function updateMintingParams(MintingParams calldata newMintingParams) external {
        _requireAdmin();
        require(
            newMintingParams.minToken0ForOpening > 0 && newMintingParams.minToken1ForOpening > 0,
            ExceptionsLibrary.INVARIANT
        );
        mintingParams = newMintingParams;
        emit UpdateMintingParams(tx.origin, msg.sender, newMintingParams);
    }

    function updateOracleParams(OracleParams calldata newOracleParams) external {
        _requireAdmin();
        require(
            newOracleParams.oracleObservationDelta > 0 &&
                newOracleParams.maxTickDeviation > 0 &&
                newOracleParams.maxTickDeviation <= uint24(TickMath.MAX_TICK),
            ExceptionsLibrary.INVARIANT
        );
        oracleParams = newOracleParams;
        emit UpdateOracleParams(tx.origin, msg.sender, newOracleParams);
    }

    function updateRatioParams(RatioParams calldata newRatioParams) external {
        _requireAdmin();
        require(
            newRatioParams.erc20MoneyRatioD <= DENOMINATOR &&
                newRatioParams.minUniV3RatioDeviation0D <= DENOMINATOR &&
                newRatioParams.minUniV3RatioDeviation1D <= DENOMINATOR &&
                newRatioParams.minMoneyRatioDeviation0D <= DENOMINATOR &&
                newRatioParams.minMoneyRatioDeviation1D <= DENOMINATOR &&
                newRatioParams.erc20MoneyRatioD > 0,
            ExceptionsLibrary.INVARIANT
        );
        ratioParams = newRatioParams;
        emit UpdateRatioParams(tx.origin, msg.sender, newRatioParams);
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

    function _checkRebalancePossibility(
        StrategyParams memory strategyParams_,
        uint256 positionNft,
        IUniswapV3Pool pool_
    ) internal {
        if (positionNft == 0) return;
        uint256 currentTimestamp = block.timestamp;
        require(currentTimestamp - lastRebalanceTimestamp >= 30 minutes, ExceptionsLibrary.LIMIT_UNDERFLOW);
        (int24 averageTick, , ) = _uniV3Helper.getAverageTickAndSqrtSpotPrice(
            pool_,
            30 * 60 /* last 30 minutes */
        );
        require(
            strategyParams_.globalLowerTick <= averageTick && averageTick <= strategyParams_.globalUpperTick,
            ExceptionsLibrary.INVARIANT
        );
        require(
            averageTick < lastShortInterval.lowerTick + strategyParams_.tickNeighborhood ||
                lastShortInterval.upperTick - strategyParams_.tickNeighborhood < averageTick,
            ExceptionsLibrary.INVARIANT
        );
        lastRebalanceTimestamp = currentTimestamp;
    }

    function rebalance(RebalanceRestrictions memory restrictions, bytes memory moneyVaultOptions)
        external
        returns (RebalanceRestrictions memory actualPulledAmounts)
    {
        _requireAtLeastOperator();
        uint256 uniV3Nft = uniV3Vault.uniV3Nft();
        INonfungiblePositionManager positionManager_ = positionManager;
        StrategyParams memory strategyParams_ = strategyParams;
        OracleParams memory oracleParams_ = oracleParams;
        IUniswapV3Pool pool_ = pool;
        _checkRebalancePossibility(strategyParams_, uniV3Nft, pool_);

        if (uniV3Nft != 0) {
            // cannot burn only if it is first call of the rebalance function
            // and we dont have any position
            actualPulledAmounts.burnedAmounts = _burnPosition(restrictions.burnedAmounts, uniV3Nft);
        }

        (int24 averageTick, , ) = _uniV3Helper.getAverageTickAndSqrtSpotPrice(
            pool_,
            oracleParams_.oracleObservationDelta
        );
        uniV3Nft = _mintPosition(
            strategyParams_,
            pool_,
            restrictions.deadline,
            positionManager_,
            averageTick,
            uniV3Nft
        );
        actualPulledAmounts = tokenRebalance(restrictions, moneyVaultOptions);
    }

    function tokenRebalance(RebalanceRestrictions memory restrictions, bytes memory moneyVaultOptions)
        public
        returns (RebalanceRestrictions memory actualPulledAmounts)
    {
        _requireAtLeastOperator();
        INonfungiblePositionManager positionManager_ = positionManager;
        StrategyParams memory strategyParams_ = strategyParams;
        OracleParams memory oracleParams_ = oracleParams;
        IUniswapV3Pool pool_ = pool;
        HStrategyHelper hStrategyHelper_ = _hStrategyHelper;
        uint256 uniV3Nft = uniV3Vault.uniV3Nft();
        require(uniV3Nft != 0, ExceptionsLibrary.INVARIANT);
        DomainPositionParams memory domainPositionParams;
        {
            (int24 averageTick, uint160 sqrtSpotPriceX96, int24 deviation) = _uniV3Helper
                .getAverageTickAndSqrtSpotPrice(pool_, oracleParams_.oracleObservationDelta);
            if (deviation < 0) {
                deviation = -deviation;
            }
            require(uint24(deviation) <= oracleParams_.maxTickDeviation, ExceptionsLibrary.LIMIT_OVERFLOW);
            domainPositionParams = hStrategyHelper_.calculateDomainPositionParams(
                averageTick,
                sqrtSpotPriceX96,
                strategyParams_,
                uniV3Nft,
                positionManager_
            );
        }
        TokenAmounts memory currentTokenAmounts = hStrategyHelper_.calculateCurrentTokenAmounts(
            erc20Vault,
            moneyVault,
            domainPositionParams
        );
        TokenAmounts memory expectedTokenAmounts;

        {
            {
                RatioParams memory ratioParams_ = ratioParams;
                ExpectedRatios memory expectedRatios = hStrategyHelper_.calculateExpectedRatios(domainPositionParams);
                TokenAmountsInToken0 memory expectedTokenAmountsInToken0;
                {
                    TokenAmountsInToken0 memory currentTokenAmountsInToken0 = hStrategyHelper_
                        .calculateCurrentTokenAmountsInToken0(domainPositionParams, currentTokenAmounts);
                    expectedTokenAmountsInToken0 = hStrategyHelper_.calculateExpectedTokenAmountsInToken0(
                        currentTokenAmountsInToken0,
                        expectedRatios,
                        ratioParams_
                    );
                }

                expectedTokenAmounts = hStrategyHelper_.calculateExpectedTokenAmounts(
                    expectedRatios,
                    expectedTokenAmountsInToken0,
                    domainPositionParams
                );
                require(
                    _hStrategyHelper.tokenRebalanceNeeded(currentTokenAmounts, expectedTokenAmounts, ratioParams),
                    ExceptionsLibrary.INVARIANT
                );
            }

            (actualPulledAmounts.pulledFromUniV3Vault, actualPulledAmounts.pulledFromMoneyVault) = _pullExtraTokens(
                hStrategyHelper_,
                expectedTokenAmounts,
                restrictions,
                moneyVaultOptions,
                domainPositionParams
            );
        }
        TokenAmounts memory missingTokenAmounts = hStrategyHelper_.calculateMissingTokenAmounts(
            moneyVault,
            expectedTokenAmounts,
            domainPositionParams
        );

        if (_hStrategyHelper.swapNeeded(missingTokenAmounts, expectedTokenAmounts, erc20Vault, ratioParams)) {
            actualPulledAmounts.swappedAmounts = _swapTokens(expectedTokenAmounts, currentTokenAmounts, restrictions);
        }

        (actualPulledAmounts.pulledOnUniV3Vault, actualPulledAmounts.pulledOnMoneyVault) = _pullMissingTokens(
            missingTokenAmounts,
            restrictions,
            moneyVaultOptions
        );
    }

    // -------------------  INTERNAL  -------------------

    function _swapTokens(
        TokenAmounts memory expectedTokenAmounts,
        TokenAmounts memory currentTokenAmounts,
        RebalanceRestrictions memory restrictions
    ) internal returns (uint256[] memory swappedAmounts) {
        uint256 expectedToken0Amount = expectedTokenAmounts.erc20Token0 +
            expectedTokenAmounts.moneyToken0 +
            expectedTokenAmounts.uniV3Token0;
        uint256 expectedToken1Amount = expectedTokenAmounts.erc20Token1 +
            expectedTokenAmounts.moneyToken1 +
            expectedTokenAmounts.uniV3Token1;

        uint256 currentToken0Amount = currentTokenAmounts.erc20Token0 +
            currentTokenAmounts.moneyToken0 +
            currentTokenAmounts.uniV3Token0;
        uint256 currentToken1Amount = currentTokenAmounts.erc20Token1 +
            currentTokenAmounts.moneyToken1 +
            currentTokenAmounts.uniV3Token1;

        if (currentToken0Amount > expectedToken0Amount) {
            swappedAmounts = _swapTokensOnERC20Vault(currentToken0Amount - expectedToken0Amount, 0, restrictions);
        } else if (currentToken1Amount > expectedToken1Amount) {
            swappedAmounts = _swapTokensOnERC20Vault(currentToken1Amount - expectedToken1Amount, 1, restrictions);
        }
    }

    function _pullExtraTokens(
        HStrategyHelper hStrategyHelper_,
        TokenAmounts memory expectedTokenAmounts,
        RebalanceRestrictions memory restrictions,
        bytes memory moneyVaultOptions,
        DomainPositionParams memory domainPositionParams
    ) internal returns (uint256[] memory pulledFromUniV3VaultAmounts, uint256[] memory pulledFromMoneyVaultAmounts) {
        {
            IUniV3Vault vault_ = uniV3Vault;
            (uint256 token0Amount, uint256 token1Amount) = hStrategyHelper_.calculateExtraTokenAmountsForUniV3Vault(
                expectedTokenAmounts,
                domainPositionParams
            );

            uint256[] memory extraTokenAmountsForPull = new uint256[](2);
            if (token0Amount > 0 || token1Amount > 0) {
                extraTokenAmountsForPull[0] = token0Amount;
                extraTokenAmountsForPull[1] = token1Amount;
                pulledFromUniV3VaultAmounts = vault_.pull(address(erc20Vault), tokens, extraTokenAmountsForPull, "");
                _compareAmounts(restrictions.pulledFromUniV3Vault, pulledFromUniV3VaultAmounts);
            }
        }

        {
            IIntegrationVault vault_ = moneyVault;
            (uint256 token0Amount, uint256 token1Amount) = hStrategyHelper_.calculateExtraTokenAmountsForMoneyVault(
                vault_,
                expectedTokenAmounts
            );

            uint256[] memory extraTokenAmountsForPull = new uint256[](2);
            if (token0Amount > 0 || token1Amount > 0) {
                extraTokenAmountsForPull[0] = token0Amount;
                extraTokenAmountsForPull[1] = token1Amount;
                pulledFromMoneyVaultAmounts = vault_.pull(
                    address(erc20Vault),
                    tokens,
                    extraTokenAmountsForPull,
                    moneyVaultOptions
                );
                _compareAmounts(restrictions.pulledFromMoneyVault, pulledFromMoneyVaultAmounts);
            }
        }
    }

    function _pullMissingTokens(
        TokenAmounts memory missingTokenAmounts,
        RebalanceRestrictions memory restrictions,
        bytes memory moneyVaultOptions
    ) internal returns (uint256[] memory pulledOnUniV3Vault, uint256[] memory pulledOnMoneyVault) {
        uint256[] memory extraTokenAmountsForPull = new uint256[](2);
        {
            if (missingTokenAmounts.uniV3Token0 > 0 || missingTokenAmounts.uniV3Token1 > 0) {
                extraTokenAmountsForPull[0] = missingTokenAmounts.uniV3Token0;
                extraTokenAmountsForPull[1] = missingTokenAmounts.uniV3Token1;
                pulledOnUniV3Vault = erc20Vault.pull(address(uniV3Vault), tokens, extraTokenAmountsForPull, "");
                _compareAmounts(restrictions.pulledOnUniV3Vault, pulledOnUniV3Vault);
            }
        }
        {
            if (missingTokenAmounts.moneyToken0 > 0 || missingTokenAmounts.moneyToken1 > 0) {
                extraTokenAmountsForPull[0] = missingTokenAmounts.moneyToken0;
                extraTokenAmountsForPull[1] = missingTokenAmounts.moneyToken1;
                pulledOnMoneyVault = erc20Vault.pull(
                    address(moneyVault),
                    tokens,
                    extraTokenAmountsForPull,
                    moneyVaultOptions
                );
                _compareAmounts(restrictions.pulledOnMoneyVault, pulledOnMoneyVault);
            }
        }
    }

    function _mintPosition(
        StrategyParams memory strategyParams_,
        IUniswapV3Pool pool_,
        uint256 deadline,
        INonfungiblePositionManager positionManager_,
        int24 averageTick,
        uint256 oldNft
    ) internal returns (uint256 newNft) {
        int24 lowerTick = 0;
        int24 upperTick = 0;

        int24 intervalWidth = strategyParams_.widthTicks * strategyParams_.widthCoefficient;
        {
            // in this case it is first mint
            int24 deltaToLowerTick = averageTick - strategyParams_.globalLowerTick;
            deltaToLowerTick -= (deltaToLowerTick % intervalWidth);
            int24 mintLeftTick = strategyParams_.globalLowerTick + deltaToLowerTick;
            int24 mintRightTick = mintLeftTick + intervalWidth;
            int24 mintTick = 0;
            if (averageTick - mintLeftTick <= mintRightTick - averageTick) {
                mintTick = mintLeftTick;
            } else {
                mintTick = mintRightTick;
            }

            lowerTick = mintTick - intervalWidth;
            upperTick = mintTick + intervalWidth;

            if (lowerTick < strategyParams_.globalLowerTick) {
                lowerTick = strategyParams_.globalLowerTick;
                upperTick = lowerTick + 2 * intervalWidth;
            } else if (upperTick > strategyParams_.globalUpperTick) {
                upperTick = strategyParams_.globalUpperTick;
                lowerTick = upperTick - 2 * intervalWidth;
            }
        }

        lastShortInterval = LastShortInterval({lowerTick: lowerTick, upperTick: upperTick});

        uint256 minToken0ForOpening;
        uint256 minToken1ForOpening;
        {
            MintingParams memory mintingParams_ = mintingParams;
            minToken0ForOpening = mintingParams_.minToken0ForOpening;
            minToken1ForOpening = mintingParams_.minToken1ForOpening;
        }
        IERC20(tokens[0]).safeApprove(address(positionManager_), minToken0ForOpening);
        IERC20(tokens[1]).safeApprove(address(positionManager_), minToken1ForOpening);
        (newNft, , , ) = positionManager_.mint(
            INonfungiblePositionManager.MintParams({
                token0: tokens[0],
                token1: tokens[1],
                fee: pool_.fee(),
                tickLower: lowerTick,
                tickUpper: upperTick,
                amount0Desired: minToken0ForOpening,
                amount1Desired: minToken1ForOpening,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: deadline
            })
        );
        IERC20(tokens[0]).safeApprove(address(positionManager_), 0);
        IERC20(tokens[1]).safeApprove(address(positionManager_), 0);

        positionManager_.safeTransferFrom(address(this), address(uniV3Vault), newNft);
        if (oldNft != 0) {
            positionManager_.burn(oldNft);
        }
        emit MintUniV3Position(tx.origin, newNft, lowerTick, upperTick);
    }

    function _burnPosition(uint256[] memory burnAmounts, uint256 uniV3Nft)
        internal
        returns (uint256[] memory tokenAmounts)
    {
        IUniV3Vault vault = uniV3Vault;
        uint256[] memory collectedFees = vault.collectEarnings();
        tokenAmounts = vault.liquidityToTokenAmounts(type(uint128).max);
        uint256[] memory pulledAmounts = vault.pull(address(erc20Vault), tokens, tokenAmounts, "");
        for (uint256 i = 0; i < 2; i++) {
            tokenAmounts[i] = collectedFees[i] + pulledAmounts[i];
        }
        _compareAmounts(burnAmounts, tokenAmounts);
        emit BurnUniV3Position(tx.origin, uniV3Nft);
    }

    function _swapTokensOnERC20Vault(
        uint256 amountIn,
        uint256 tokenInIndex,
        RebalanceRestrictions memory restrictions
    ) internal returns (uint256[] memory amountsOut) {
        IIntegrationVault vault = erc20Vault;
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokens[tokenInIndex],
            tokenOut: tokens[tokenInIndex ^ 1],
            fee: pool.fee(),
            recipient: address(vault),
            deadline: restrictions.deadline,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        bytes memory routerResult;
        {
            bytes memory data = abi.encode(swapParams);
            vault.externalCall(tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(address(router), amountIn)); // approve
            routerResult = vault.externalCall(address(router), EXACT_INPUT_SINGLE_SELECTOR, data); // swap
            vault.externalCall(tokens[tokenInIndex], APPROVE_SELECTOR, abi.encode(address(router), 0)); // reset allowance
        }

        uint256 amountOut = abi.decode(routerResult, (uint256));
        require(restrictions.swappedAmounts[tokenInIndex ^ 1] <= amountOut, ExceptionsLibrary.LIMIT_UNDERFLOW);

        amountsOut = new uint256[](2);
        amountsOut[tokenInIndex ^ 1] = amountOut;

        emit SwapTokensOnERC20Vault(tx.origin, swapParams);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    /// @notice reverts in for any elent holds needed[i] > actual[i]
    function _compareAmounts(uint256[] memory needed, uint256[] memory actual) internal pure {
        for (uint256 i = 0; i < 2; i++) {
            require(needed[i] <= actual[i], ExceptionsLibrary.LIMIT_UNDERFLOW);
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

    /// @notice Emitted when Strategy strategyParams are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param strategyParams Updated strategyParams
    event UpdateStrategyParams(address indexed origin, address indexed sender, StrategyParams strategyParams);

    /// @notice Emitted when Strategy mintingParams are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param mintingParams Updated mintingParams
    event UpdateMintingParams(address indexed origin, address indexed sender, MintingParams mintingParams);

    /// @notice Emitted when Strategy oracleParams are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param oracleParams Updated oracleParams
    event UpdateOracleParams(address indexed origin, address indexed sender, OracleParams oracleParams);

    /// @notice Emitted when Strategy ratioParams are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param ratioParams Updated ratioParams
    event UpdateRatioParams(address indexed origin, address indexed sender, RatioParams ratioParams);
}
