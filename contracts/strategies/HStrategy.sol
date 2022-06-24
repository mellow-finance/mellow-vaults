// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

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

contract HStrategy is ContractMeta, DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    struct StrategyParams {
        int24 burnDeltaTicks;
        int24 mintDeltaTicks;
        int24 biDeltaTicks;
        int24 widthCoefficient;
        int24 widthTicks;
        uint32 oracleObservationDelta;
        uint32 erc20MoneyRatioD;
        uint256 minToken0AmountForMint;
        uint256 minToken1AmountForMint;
    }

    IERC20Vault public erc20Vault;
    IIntegrationVault public moneyVault;
    IUniV3Vault public uniV3Vault;
    address[] public tokens;

    INonfungiblePositionManager public positionManager;
    IUniswapV3Pool public pool;
    UniV3Helper private _uniV3Helper;

    bytes4 public constant APPROVE_SELECTOR = IERC20.approve.selector; // 0x095ea7b3; more consistent?
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;
    ISwapRouter public router;

    int24 public lastSwapRebalanceTick;
    int24 public lastMintRebalanceTick;
    uint32 public constant DENOMINATOR = 10**9;

    StrategyParams public strategyParams;

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
            (newStrategyParams.burnDeltaTicks > 0 &&
                newStrategyParams.mintDeltaTicks > 0 &&
                newStrategyParams.biDeltaTicks > 0 &&
                newStrategyParams.widthCoefficient > 0 &&
                newStrategyParams.widthTicks > 0 &&
                newStrategyParams.oracleObservationDelta > 0 &&
                newStrategyParams.erc20MoneyRatioD > 0 &&
                newStrategyParams.erc20MoneyRatioD <= DENOMINATOR &&
                newStrategyParams.minToken0AmountForMint > 0 &&
                newStrategyParams.minToken1AmountForMint > 0 &&
                type(int24).max / newStrategyParams.widthTicks / 2 >= newStrategyParams.widthCoefficient &&
                newStrategyParams.burnDeltaTicks + newStrategyParams.mintDeltaTicks < newStrategyParams.widthTicks),
            ExceptionsLibrary.INVARIANT
        );
        strategyParams = newStrategyParams;
        emit UpdateStrategyParams(tx.origin, msg.sender, newStrategyParams);
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

    struct RebalanceRestrictions {
        uint256[] pulledOnUniV3Vault;
        uint256[] pulledFromUniV3Vault;
        uint256[] pulledOnMoneyVault;
        uint256[] pulledFromMoneyVault;
        uint256[] swappedAmounts;
        uint256[] burnedAmounts;
        uint256 deadline;
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
        RebalanceRestrictions memory restrictions = RebalanceRestrictions({
            pulledOnUniV3Vault: pulledOnUniV3Vault,
            pulledFromUniV3Vault: pulledFromUniV3Vault,
            pulledOnMoneyVault: pulledOnMoneyVault,
            pulledFromMoneyVault: pulledFromMoneyVault,
            swappedAmounts: swappedAmounts,
            burnedAmounts: burnedAmounts,
            deadline: deadline
        });

        _requireAdmin();
        _burnRebalance(restrictions);
        _mintRebalance(restrictions);
        _smartRebalance(restrictions, moneyVaultOptions);
    }

    /// @dev if the current averageTick differs from lastMintRebalanceTick by more than burnDeltaTicks,
    /// then function transfers all tokens from UniV3Vault to ERC20Vault and burns the position by uniV3Nft
    function _burnRebalance(RebalanceRestrictions memory restrictions) internal {
        uint256 uniV3Nft = uniV3Vault.nft();
        if (uniV3Nft == 0) {
            // nothing to burn
            return;
        }

        StrategyParams memory strategyParams_ = strategyParams;
        (int24 averageTick, ) = _uniV3Helper.getAverageTickAndSpotPrice(pool, strategyParams_.oracleObservationDelta);

        int24 delta = averageTick - lastMintRebalanceTick;
        if (delta < 0) {
            delta = -delta;
        }

        // if average tick deviated from last rebalance tick more than burnDeltaTicks, then burn position
        if (delta > strategyParams_.burnDeltaTicks) {
            uint256[] memory collectedTokens = uniV3Vault.collectEarnings();
            _compareAmounts(restrictions.burnedAmounts, collectedTokens);
            (, , , , , , , uint256 liquidity, , , , ) = positionManager.positions(uniV3Nft);
            require(liquidity == 0, ExceptionsLibrary.INVARIANT);
            positionManager.burn(uniV3Nft);

            emit BurnUniV3Position(tx.origin, uniV3Nft);
        }
    }

    function _mintRebalance(RebalanceRestrictions memory restrictions) internal {
        if (uniV3Vault.nft() != 0) {
            return;
        }
        StrategyParams memory strategyParams_ = strategyParams;
        (int24 averageTick, ) = _uniV3Helper.getAverageTickAndSpotPrice(pool, strategyParams_.oracleObservationDelta);
        int24 widthTicks = strategyParams_.widthTicks;

        int24 nearestLeftTick = (averageTick / widthTicks) * widthTicks;
        int24 nearestRightTick = nearestLeftTick;

        if (nearestLeftTick < averageTick) {
            nearestRightTick += widthTicks;
        } else if (nearestLeftTick > averageTick) {
            nearestLeftTick -= widthTicks;
        }

        int24 distToLeft = averageTick - nearestLeftTick;
        int24 distToRight = nearestRightTick - averageTick;
        int24 newMintTick = nearestLeftTick;

        if (distToLeft > strategyParams_.mintDeltaTicks && distToRight > strategyParams_.mintDeltaTicks) {
            return;
        }

        if (distToLeft <= distToRight) {
            newMintTick = nearestLeftTick;
        } else {
            newMintTick = nearestRightTick;
        }

        _mintUniV3Position(
            newMintTick - strategyParams_.widthCoefficient * widthTicks,
            newMintTick + strategyParams_.widthCoefficient * widthTicks,
            restrictions.deadline,
            strategyParams_
        );
        lastMintRebalanceTick = newMintTick;
    }

    struct ExpectedRatios {
        uint32 token0RatioD;
        uint32 token1RatioD;
        uint32 uniV3RatioD;
    }

    function _getExpectedRatios(UniV3Helper.UniswapPositionParameters memory uniswapParams)
        internal
        pure
        returns (ExpectedRatios memory ratios)
    {
        ratios.token0RatioD = DENOMINATOR >> 1;
        ratios.token1RatioD = DENOMINATOR >> 1;
        ratios.uniV3RatioD = 0;
        uint256 uniV3Nft = uniswapParams.nft;
        if (uniV3Nft != 0) {
            ratios.token0RatioD = uint32(
                FullMath.mulDiv(uniswapParams.averagePriceSqrtX96, ratios.token0RatioD, uniswapParams.upperPriceSqrtX96)
            );
            ratios.token1RatioD = uint32(
                FullMath.mulDiv(uniswapParams.lowerPriceSqrtX96, ratios.token1RatioD, uniswapParams.averagePriceSqrtX96)
            );
            ratios.uniV3RatioD = DENOMINATOR - ratios.token0RatioD - ratios.token1RatioD;
        }
    }

    function _getTvlInToken0(address vault, uint256 averagePriceX96) internal view returns (uint256 amount) {
        (uint256[] memory minTvl, uint256[] memory maxTvl) = IIntegrationVault(vault).tvl();
        uint256 averageToken0Tvl = (minTvl[0] + minTvl[0]) >> 1;
        uint256 averageToken1Tvl = (minTvl[1] + maxTvl[1]) >> 1;
        amount = FullMath.mulDiv(averageToken1Tvl, CommonLibrary.Q96, averagePriceX96) + averageToken0Tvl;
    }

    struct VaultsStatistics {
        uint256[] uniV3Vault;
        uint256[] erc20Vault;
        uint256[] moneyVault;
    }

    function _initVaultStats() internal pure returns (VaultsStatistics memory stat) {
        stat = VaultsStatistics({
            uniV3Vault: new uint256[](2),
            erc20Vault: new uint256[](2),
            moneyVault: new uint256[](2)
        });
    }

    struct VaultTvlStats {
        uint256 erc20TokensAmountInToken0;
        uint256 moneyTokensAmountInToken0;
        uint256 uniV3TokensAmountInToken0;
        uint256 totalTokensInToken0;
    }

    function _getVaultTvlStats(uint256 averagePriceX96) internal view returns (VaultTvlStats memory stat) {
        stat = VaultTvlStats({
            erc20TokensAmountInToken0: _getTvlInToken0(address(erc20Vault), averagePriceX96),
            moneyTokensAmountInToken0: _getTvlInToken0(address(moneyVault), averagePriceX96),
            uniV3TokensAmountInToken0: _getTvlInToken0(address(uniV3Vault), averagePriceX96),
            totalTokensInToken0: 0
        });
        stat.totalTokensInToken0 =
            stat.erc20TokensAmountInToken0 +
            stat.moneyTokensAmountInToken0 +
            stat.uniV3TokensAmountInToken0;
    }

    struct ExpectedTokenAmounts {
        uint256 uniV3TokenAmountsInToken0;
        uint256 erc20TokenAmountsInToken0;
        uint256 moneyTokenAmountsInToken0;
    }

    function _pullFromUniV3Vault(uint256[] memory tokenAmounts, uint256 deadline)
        internal
        returns (uint256[] memory pulledTokenAmounts)
    {
        pulledTokenAmounts = uniV3Vault.pull(
            address(erc20Vault),
            tokens,
            tokenAmounts,
            _makeUniswapVaultOptions(tokenAmounts, deadline)
        );
    }

    function _pullFromMoneyVault(uint256[] memory tokenAmounts, bytes memory options)
        internal
        returns (uint256[] memory pulledTokenAmounts)
    {
        pulledTokenAmounts = moneyVault.pull(address(erc20Vault), tokens, tokenAmounts, options);
    }

    function _pullOnUniV3Vault(uint256[] memory tokenAmounts, uint256 deadline)
        internal
        returns (uint256[] memory pulledTokenAmounts)
    {
        pulledTokenAmounts = erc20Vault.pull(
            address(uniV3Vault),
            tokens,
            tokenAmounts,
            _makeUniswapVaultOptions(tokenAmounts, deadline)
        );
    }

    function _pullOnMoneyVault(uint256[] memory tokenAmounts, bytes memory options)
        internal
        returns (uint256[] memory pulledTokenAmounts)
    {
        pulledTokenAmounts = erc20Vault.pull(address(moneyVault), tokens, tokenAmounts, options);
    }

    function _pullExtraTokensOnERC20Vault(
        UniV3Helper.UniswapPositionParameters memory uniswapParams,
        VaultsStatistics memory missingTokenAmountsStat,
        RebalanceRestrictions memory restrictions,
        bytes memory moneyVaultOptions
    ) internal {
        ExpectedRatios memory expectedRatios = _getExpectedRatios(uniswapParams);
        VaultTvlStats memory tvlStats = _getVaultTvlStats(uniswapParams.averagePriceX96);
        ExpectedTokenAmounts memory expectedTokenAmounts;
        expectedTokenAmounts.uniV3TokenAmountsInToken0 = FullMath.mulDiv(
            tvlStats.totalTokensInToken0,
            expectedRatios.uniV3RatioD,
            DENOMINATOR
        );
        expectedTokenAmounts.erc20TokenAmountsInToken0 = FullMath.mulDiv(
            tvlStats.totalTokensInToken0 - expectedTokenAmounts.uniV3TokenAmountsInToken0,
            strategyParams.erc20MoneyRatioD,
            DENOMINATOR
        );
        expectedTokenAmounts.moneyTokenAmountsInToken0 =
            tvlStats.totalTokensInToken0 -
            expectedTokenAmounts.uniV3TokenAmountsInToken0 -
            expectedTokenAmounts.erc20TokenAmountsInToken0;

        VaultsStatistics memory expectedTokenAmountsStat = _initVaultStats();

        // possible it will be better to choose 1 to 1 ratio here
        {
            expectedTokenAmountsStat.erc20Vault[0] = FullMath.mulDiv(
                expectedRatios.token0RatioD,
                expectedTokenAmounts.erc20TokenAmountsInToken0,
                expectedRatios.token0RatioD + expectedRatios.token1RatioD
            );
            expectedTokenAmountsStat.erc20Vault[1] = FullMath.mulDiv(
                expectedTokenAmounts.erc20TokenAmountsInToken0 - expectedTokenAmountsStat.erc20Vault[0],
                uniswapParams.averagePriceX96,
                CommonLibrary.Q96
            );
        }

        // pull tokens from UniV3Vault
        // possible only in uniV3Nft is not 0
        if (tvlStats.uniV3TokensAmountInToken0 > expectedTokenAmounts.uniV3TokenAmountsInToken0) {
            uint128 liquidityDelta = uint128(
                FullMath.mulDiv(
                    tvlStats.uniV3TokensAmountInToken0 - expectedTokenAmounts.uniV3TokenAmountsInToken0,
                    uniswapParams.liquidity,
                    tvlStats.uniV3TokensAmountInToken0
                )
            );
            uint256[] memory tokenAmountsFromUniV3Vault = new uint256[](2);
            (tokenAmountsFromUniV3Vault[0], tokenAmountsFromUniV3Vault[1]) = LiquidityAmounts.getAmountsForLiquidity(
                uniswapParams.spotPriceSqrtX96,
                uniswapParams.lowerPriceSqrtX96,
                uniswapParams.upperPriceSqrtX96,
                liquidityDelta
            );

            uint256[] memory pulledAmounts = _pullFromUniV3Vault(tokenAmountsFromUniV3Vault, restrictions.deadline);
            _compareAmounts(restrictions.pulledFromUniV3Vault, pulledAmounts);
        }

        // pull tokens from moneyVault
        {
            (uint256[] memory moneyTvl, ) = moneyVault.tvl();
            expectedTokenAmountsStat.moneyVault[0] = FullMath.mulDiv(
                expectedRatios.token0RatioD,
                expectedTokenAmounts.moneyTokenAmountsInToken0,
                expectedRatios.token0RatioD + expectedRatios.token1RatioD
            );
            expectedTokenAmountsStat.moneyVault[1] = FullMath.mulDiv(
                expectedTokenAmounts.moneyTokenAmountsInToken0 - expectedTokenAmountsStat.moneyVault[0],
                uniswapParams.averagePriceX96,
                CommonLibrary.Q96
            );
            uint256[] memory tokenAmountsFromMoneyVault = new uint256[](2);
            bool needPull = false;
            for (uint256 i = 0; i < 2; i++) {
                if (moneyTvl[i] > expectedTokenAmountsStat.moneyVault[i]) {
                    tokenAmountsFromMoneyVault[i] = moneyTvl[i] - expectedTokenAmountsStat.moneyVault[i];
                    needPull = true;
                } else {
                    missingTokenAmountsStat.moneyVault[i] = missingTokenAmountsStat.moneyVault[i] - moneyTvl[i];
                }
            }
            if (needPull) {
                uint256[] memory pulledAmounts = _pullFromMoneyVault(tokenAmountsFromMoneyVault, moneyVaultOptions);
                _compareAmounts(restrictions.pulledFromMoneyVault, pulledAmounts);
            }
        }

        if (tvlStats.uniV3TokensAmountInToken0 < expectedTokenAmounts.uniV3TokenAmountsInToken0) {
            uint128 liquidityDelta = uint128(
                FullMath.mulDiv(
                    expectedTokenAmounts.uniV3TokenAmountsInToken0 - tvlStats.uniV3TokensAmountInToken0,
                    uniswapParams.liquidity,
                    tvlStats.uniV3TokensAmountInToken0
                )
            );

            (missingTokenAmountsStat.uniV3Vault[0], missingTokenAmountsStat.uniV3Vault[1]) = LiquidityAmounts
                .getAmountsForLiquidity(
                    uniswapParams.spotPriceSqrtX96,
                    uniswapParams.lowerPriceSqrtX96,
                    uniswapParams.upperPriceSqrtX96,
                    liquidityDelta
                );
        }
        {
            (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();

            for (uint256 i = 0; i < 2; i++) {
                uint256 term = expectedTokenAmountsStat.erc20Vault[i] +
                    missingTokenAmountsStat.uniV3Vault[i] +
                    missingTokenAmountsStat.moneyVault[i];

                if (erc20Tvl[i] < term) {
                    missingTokenAmountsStat.erc20Vault[i] = term - erc20Tvl[i];
                }
            }
        }
    }

    function _swapToTarget(
        VaultsStatistics memory missingTokenAmountsStat,
        UniV3Helper.UniswapPositionParameters memory uniswapParams,
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
        }
    }

    function _pullMissingTokensFromERC20Vault(
        VaultsStatistics memory missingTokenAmountsStat,
        RebalanceRestrictions memory restrictions,
        bytes memory moneyVaultOptions
    ) internal {
        {
            bool needPull = false;
            for (uint256 i = 0; i < 2; i++) {
                if (missingTokenAmountsStat.moneyVault[i] > 0) {
                    needPull = true;
                }
            }
            if (needPull) {
                uint256[] memory pulledAmounts = _pullOnMoneyVault(
                    missingTokenAmountsStat.moneyVault,
                    moneyVaultOptions
                );
                _compareAmounts(restrictions.pulledOnMoneyVault, pulledAmounts);
            }
        }

        // same code part 2 (replace with function call)
        {
            bool needPull = false;
            for (uint256 i = 0; i < 2; i++) {
                if (missingTokenAmountsStat.uniV3Vault[i] > 0) {
                    needPull = true;
                }
            }
            if (needPull) {
                uint256[] memory pulledAmounts = _pullOnUniV3Vault(
                    missingTokenAmountsStat.uniV3Vault,
                    restrictions.deadline
                );
                _compareAmounts(restrictions.pulledOnUniV3Vault, pulledAmounts);
            }
        }
    }

    function _smartRebalance(RebalanceRestrictions memory restrictions, bytes memory moneyVaultOptions) internal {
        VaultsStatistics memory missingTokenAmountsStat = _initVaultStats();
        UniV3Helper.UniswapPositionParameters memory uniswapParams;
        StrategyParams memory strategyParams_ = strategyParams;
        {
            (int24 averageTick, uint160 sqrtSpotPriceX96) = _uniV3Helper.getAverageTickAndSpotPrice(
                pool,
                strategyParams_.oracleObservationDelta
            );
            uniswapParams = _uniV3Helper.getUniswapPositionParameters(
                averageTick,
                sqrtSpotPriceX96,
                uniV3Vault.nft(),
                positionManager
            );
        }
        _pullExtraTokensOnERC20Vault(uniswapParams, missingTokenAmountsStat, restrictions, moneyVaultOptions);
        {
            // Mb we just don't need to check this biDeltaTicks?
            int24 swapDeltaTicks = uniswapParams.averageTick - lastSwapRebalanceTick;
            if (swapDeltaTicks < 0) {
                swapDeltaTicks = -swapDeltaTicks;
            }
            if (swapDeltaTicks > strategyParams_.biDeltaTicks) {
                _swapToTarget(missingTokenAmountsStat, uniswapParams, restrictions);
            }
        }
        _pullMissingTokensFromERC20Vault(missingTokenAmountsStat, restrictions, moneyVaultOptions);
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

    function _mintUniV3Position(
        int24 lowerTick,
        int24 upperTick,
        uint256 deadline,
        StrategyParams memory params
    ) internal {
        IERC20(tokens[0]).safeApprove(address(positionManager), params.minToken0AmountForMint);
        IERC20(tokens[1]).safeApprove(address(positionManager), params.minToken1AmountForMint);
        address[] memory tokens_ = tokens;
        {
            (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();
            uint256[] memory amountsForMint = new uint256[](2);
            amountsForMint[0] = params.minToken0AmountForMint;
            amountsForMint[1] = params.minToken1AmountForMint;
            for (uint256 i = 0; i < 2; i++) {
                require(erc20Tvl[i] >= amountsForMint[i], ExceptionsLibrary.LIMIT_UNDERFLOW);
                erc20Vault.externalCall(tokens_[i], APPROVE_SELECTOR, abi.encode(address(this), amountsForMint[i]));
                IERC20(tokens_[i]).safeTransferFrom(address(erc20Vault), address(this), amountsForMint[i]);
                erc20Vault.externalCall(tokens_[i], APPROVE_SELECTOR, abi.encode(address(this), 0));
            }
        }

        (uint256 newNft, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: tokens[0],
                token1: tokens[1],
                fee: pool.fee(),
                tickLower: lowerTick,
                tickUpper: upperTick,
                amount0Desired: params.minToken0AmountForMint,
                amount1Desired: params.minToken1AmountForMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: deadline
            })
        );

        positionManager.safeTransferFrom(address(this), address(uniV3Vault), newNft);
        IERC20(tokens[0]).safeApprove(address(positionManager), 0);
        IERC20(tokens[1]).safeApprove(address(positionManager), 0);

        for (uint256 i = 0; i < 2; i++) {
            uint256 amount = IERC20(tokens_[i]).balanceOf(address(this));
            if (amount > 0) {
                IERC20(tokens_[i]).safeTransfer(address(erc20Vault), amount);
            }
        }
        emit MintUniV3Position(tx.origin, newNft, lowerTick, upperTick);
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
    /// @param swapParams Swap params
    event SwapTokensOnERC20Vault(address indexed origin, ISwapRouter.ExactInputSingleParams swapParams);

    /// @notice Emitted when Strategy params are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param params Updated params
    event UpdateStrategyParams(address indexed origin, address indexed sender, StrategyParams params);
}
