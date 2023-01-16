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
import "../libraries/external/TickMath.sol";
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

    INonfungiblePositionManager private immutable _positionManager;
    IUniswapV3Pool public pool;
    uint24 public swapFees;
    UniV3Helper private immutable _uniV3Helper;
    HStrategyHelper private immutable _hStrategyHelper;
    Interval private shortInterval;
    bool private needPositionRebalance;
    bool private newPositionMinted;

    // MUTABLE PARAMS

    /// @notice general params of the strategy - responsible for emulating interval and rebalance conditions
    /// @param halfOfShortInterval half of width of the uniV3 position measured in the strategy in ticks
    /// @param tickNeighborhood width of the neighbourhood of the current position border, in which rebalance can be called.
    /// Example: if the upperTick=10, tickNeighbourhood=5, rebalance can be called for all ticks greater than 10 - 5 = 5
    /// @param domainLowerTick the lower tick of the domain uniV3 position
    /// @param domainUpperTick the upper tick of the domain uniV3 position
    struct StrategyParams {
        int24 halfOfShortInterval;
        int24 tickNeighborhood;
        int24 domainLowerTick;
        int24 domainUpperTick;
    }

    /// @notice params of the actual minted position
    /// @param minToken0ForOpening the amount of token0 are tried to be depositted on the new position
    /// @param minToken1ForOpening the amount of token1 are tried to be depositted on the new position
    struct MintingParams {
        uint256 minToken0ForOpening;
        uint256 minToken1ForOpening;
    }

    /// @notice params of the interaction with oracle
    /// @param averagePriceTimeSpan delta in seconds, passed to oracle to get the price averagePriceTimeSpan seconds ago
    /// @param maxTickDeviation the upper bound for an absolute deviation between the spot price and the price for given number seconds ago
    struct OracleParams {
        uint32 averagePriceTimeSpan;
        uint24 maxTickDeviation;
    }

    /// @param erc20CapitalRatioD the ratio of tokens kept in money vault instead of erc20. The ratio is maintained for each token
    /// @param minCapitalDeviationD the needed deviation from target amount of capital in some vault to call rebalance or swap tokens
    /// @param minRebalanceDeviationD the needed deviation from expected amounts to call swap of tokens
    struct RatioParams {
        uint256 erc20CapitalRatioD;
        uint256 minCapitalDeviationD;
        uint256 minRebalanceDeviationD;
    }

    StrategyParams public strategyParams;
    MintingParams public mintingParams;
    OracleParams public oracleParams;
    RatioParams public ratioParams;

    // INTERNAL STRUCTURES

    /// @notice parameters of the current position
    /// @param lowerTick lower tick of interval
    /// @param upperTick upper tick of interval
    struct Interval {
        int24 lowerTick;
        int24 upperTick;
    }

    /// @notice rebalance parameters restricting the tokens transfer
    struct RebalanceTokenAmounts {
        uint256[] pulledToUniV3Vault;
        uint256[] pulledFromUniV3Vault;
        int256[] swappedAmounts;
        uint256[] burnedAmounts;
        uint256 deadline;
    }

    /// @notice structure for keeping information about capital in different vaults
    /// @param erc20TokensAmountInToken0 the capital of erc20 vault calculated in token0
    /// @param moneyTokensAmountInToken0 the capital of money vault calculated in token0
    /// @param uniV3TokensAmountInToken0 the capital of uniV3 vault calculated in token0
    /// @param totalTokensInToken0 the total capital calculated in token0
    struct TokenAmountsInToken0 {
        uint256 erc20TokensAmountInToken0;
        uint256 moneyTokensAmountInToken0;
        uint256 uniV3TokensAmountInToken0;
        uint256 totalTokensInToken0;
    }

    /// @notice structure for calculation of the current and expected amounts of tokens on all vaults
    /// @param erc20Token0 the current amount of token0 on erc20 vault
    /// @param erc20Token1 the current amount of token1 on erc20 vault
    /// @param moneyToken0 the current amount of token0 on money vault
    /// @param moneyToken1 the current amount of token1 on money vault
    /// @param uniV3Token0 the current amount of token0 on uniV3 vault
    /// @param uniV3Token1 the current amount of token1 on uniV3 vault
    struct TokenAmounts {
        uint256 erc20Token0;
        uint256 erc20Token1;
        uint256 moneyToken0;
        uint256 moneyToken1;
        uint256 uniV3Token0;
        uint256 uniV3Token1;
    }

    /// @notice structure for the calculation of expected ratios between capitals in different assets
    /// @param token0RatioD the ratio of the capital in token0 / totalCapital
    /// @param token1RatioD the ratio of the capital in token1 / totalCapital
    /// @param uniV3RatioD the ratio of the capital in uniV3 / totalCapital
    struct ExpectedRatios {
        uint32 token0RatioD;
        uint32 token1RatioD;
        uint32 uniV3RatioD;
    }

    /// @notice structure for keeping information about the current position, pool state and oracle price
    /// @param nft the nft of the position in positionManager
    /// @param liquidity the total liquidity of the position
    /// @param lowerTick the lower tick of the position
    /// @param upperTick the upper tick of the position
    /// @param domainLowerTick the lower tick of the domain position
    /// @param domainUpperTick the upper tick of the domain position
    /// @param lowerPriceSqrtX96 the square root of the price at lower tick of the position
    /// @param upperPriceSqrtX96 the square root of the price at upper tick of the position
    /// @param domainLowerPriceSqrtX96 the square root of the price at lower tick of the domain position
    /// @param domainUpperPriceSqrtX96 the square root of the price at upper tick of the domain position
    /// @param intervalPriceSqrtX96 the square root of the spot price limited by the boundaries of the domain interval
    /// @param spotPriceX96 the spot price
    struct DomainPositionParams {
        uint256 nft;
        uint128 liquidity;
        int24 lowerTick;
        int24 upperTick;
        int24 domainLowerTick;
        int24 domainUpperTick;
        uint160 lowerPriceSqrtX96;
        uint160 upperPriceSqrtX96;
        uint160 domainLowerPriceSqrtX96;
        uint160 domainUpperPriceSqrtX96;
        uint160 intervalPriceSqrtX96;
        uint256 spotPriceX96;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @notice constructs a strategy
    /// @param positionManager_ the position manager for uniV3
    /// @param router_ the uniV3 router for swapping tokens
    /// @param uniV3Helper_ the address of the helper contract for uniV3
    /// @param hStrategyHelper_ the address of the strategy helper contract
    constructor(
        INonfungiblePositionManager positionManager_,
        ISwapRouter router_,
        address uniV3Helper_,
        address hStrategyHelper_
    ) {
        require(address(positionManager_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(router_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(uniV3Helper_ != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(hStrategyHelper_ != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        _positionManager = positionManager_;
        router = router_;
        _uniV3Helper = UniV3Helper(uniV3Helper_);
        _hStrategyHelper = HStrategyHelper(hStrategyHelper_);
        DefaultAccessControlLateInit.init(address(this));
    }

    /// @notice initializes the strategy
    /// @param tokens_ the addresses of the tokens managed by the strategy
    /// @param erc20Vault_ the address of the erc20 vault
    /// @param moneyVault_ the address of the moneyVault. It is expected to be yEarn or AAVE
    /// @param uniV3Vault_ the address of uniV3Vault. It is expected to not hold the position
    /// @param fee_ the fee of the uniV3 pool on which the vault operates
    /// @param admin_ the addres of the admin of the strategy
    function initialize(
        address[] memory tokens_,
        IERC20Vault erc20Vault_,
        IIntegrationVault moneyVault_,
        IUniV3Vault uniV3Vault_,
        uint24 fee_,
        address admin_
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
        erc20Vault = erc20Vault_;
        moneyVault = moneyVault_;
        uniV3Vault = uniV3Vault_;
        tokens = tokens_;
        IUniswapV3Factory factory = IUniswapV3Factory(_positionManager.factory());
        pool = IUniswapV3Pool(factory.getPool(tokens_[0], tokens_[1], fee_));
        require(address(pool) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
    }

    /// @notice creates the clone of the strategy
    /// @param tokens_ the addresses of the tokens managed by the strategy
    /// @param erc20Vault_ the address of the erc20 vault
    /// @param moneyVault_ the address of the moneyVault. It is expected to be yEarn or AAVE
    /// @param uniV3Vault_ the address of uniV3Vault. It is expected to not hold the position
    /// @param fee_ the fee of the uniV3 pool on which the vault operates
    /// @param admin_ the addres of the admin of the strategy
    /// @return strategy the address of new strategy
    function createStrategy(
        address[] memory tokens_,
        IERC20Vault erc20Vault_,
        IIntegrationVault moneyVault_,
        IUniV3Vault uniV3Vault_,
        uint24 fee_,
        address admin_
    ) external returns (HStrategy strategy) {
        strategy = HStrategy(Clones.clone(address(this)));
        strategy.initialize(tokens_, erc20Vault_, moneyVault_, uniV3Vault_, fee_, admin_);
    }

    /// @notice updates parameters of the strategy. Can be called only by admin
    /// @param newStrategyParams the new parameters
    function updateStrategyParams(StrategyParams calldata newStrategyParams) external {
        _requireAdmin();
        int24 tickSpacing = pool.tickSpacing();
        require(
            newStrategyParams.halfOfShortInterval > 0 &&
                (newStrategyParams.halfOfShortInterval % tickSpacing == 0) &&
                newStrategyParams.tickNeighborhood <= newStrategyParams.halfOfShortInterval &&
                newStrategyParams.tickNeighborhood >= TickMath.MIN_TICK,
            ExceptionsLibrary.INVARIANT
        );

        int24 globalIntervalWidth = newStrategyParams.domainUpperTick - newStrategyParams.domainLowerTick;
        require(
            (newStrategyParams.domainLowerTick % tickSpacing == 0) &&
                (newStrategyParams.domainUpperTick % tickSpacing == 0) &&
                globalIntervalWidth > newStrategyParams.halfOfShortInterval &&
                (globalIntervalWidth % newStrategyParams.halfOfShortInterval == 0),
            ExceptionsLibrary.INVARIANT
        );
        StrategyParams memory strategyParams_ = strategyParams;
        if (
            newStrategyParams.halfOfShortInterval != strategyParams_.halfOfShortInterval ||
            newStrategyParams.domainLowerTick != strategyParams_.domainLowerTick ||
            newStrategyParams.domainUpperTick != strategyParams_.domainUpperTick
        ) {
            needPositionRebalance = true;
        }
        strategyParams = newStrategyParams;
        emit UpdateStrategyParams(tx.origin, msg.sender, newStrategyParams);
    }

    /// @notice updates parameters for minting position. Can be called only by admin
    /// @param newMintingParams the new parameters
    function updateMintingParams(MintingParams calldata newMintingParams) external {
        _requireAdmin();
        require(
            newMintingParams.minToken0ForOpening > 0 &&
                newMintingParams.minToken1ForOpening > 0 &&
                (newMintingParams.minToken0ForOpening <= 1000000000) &&
                (newMintingParams.minToken1ForOpening <= 1000000000),
            ExceptionsLibrary.INVARIANT
        );
        mintingParams = newMintingParams;
        emit UpdateMintingParams(tx.origin, msg.sender, newMintingParams);
    }

    /// @notice updates oracle parameters. Can be called only by admin
    /// @param newOracleParams the new parameters
    function updateOracleParams(OracleParams calldata newOracleParams) external {
        _requireAdmin();
        require(
            newOracleParams.averagePriceTimeSpan > 0 && newOracleParams.maxTickDeviation <= uint24(TickMath.MAX_TICK),
            ExceptionsLibrary.INVARIANT
        );
        oracleParams = newOracleParams;
        emit UpdateOracleParams(tx.origin, msg.sender, newOracleParams);
    }

    /// @notice updates parameters of the capital ratios and deviation. Can be called only by admin
    /// @param newRatioParams the new parameters
    function updateRatioParams(RatioParams calldata newRatioParams) external {
        _requireAdmin();
        require(
            newRatioParams.erc20CapitalRatioD <= DENOMINATOR &&
                newRatioParams.minCapitalDeviationD <= newRatioParams.erc20CapitalRatioD &&
                newRatioParams.minRebalanceDeviationD > 0 &&
                newRatioParams.minRebalanceDeviationD <= DENOMINATOR,
            ExceptionsLibrary.INVARIANT
        );
        ratioParams = newRatioParams;
        emit UpdateRatioParams(tx.origin, msg.sender, newRatioParams);
    }

    /// @notice updates swap fees for uniswapV3Pool swaps
    /// @param newSwapFees the new parameters
    function updateSwapFees(uint24 newSwapFees) external {
        _requireAdmin();
        address poolForSwaps = IUniswapV3Factory(_positionManager.factory()).getPool(tokens[0], tokens[1], newSwapFees);
        require(poolForSwaps != address(0), ExceptionsLibrary.INVARIANT);
        swapFees = newSwapFees;
        emit UpdateSwapFees(tx.origin, msg.sender, newSwapFees);
    }

    /// @notice manual pulling tokens from vault. Can be called only by admin
    /// @param fromVault the address of the vault to pull tokens from
    /// @param toVault the address of the vault to pull tokens to
    /// @param tokenAmounts the amount of tokens to be pulled
    /// @param vaultOptions additional options for `pull` method
    function manualPull(
        IIntegrationVault fromVault,
        IIntegrationVault toVault,
        uint256[] memory tokenAmounts,
        bytes memory vaultOptions
    ) external {
        _requireAdmin();
        fromVault.pull(address(toVault), tokens, tokenAmounts, vaultOptions);
    }

    /// @notice rebalance method. Need to be called if the new position is needed
    /// @param restrictions the restrictions of the amount of tokens to be transferred
    /// @param moneyVaultOptions additional parameters for pulling for `pull` method for money vault
    /// @return actualPulledAmounts actual transferred amounts
    /// @return burnedAmounts actual burned amounts from uniV3 position
    function rebalance(RebalanceTokenAmounts memory restrictions, bytes memory moneyVaultOptions)
        external
        returns (RebalanceTokenAmounts memory actualPulledAmounts, uint256[] memory burnedAmounts)
    {
        _requireAtLeastOperator();
        IUniswapV3Pool pool_ = pool;
        (, int24 tick, , , , , ) = pool_.slot0();
        _hStrategyHelper.checkSpotTickDeviationFromAverage(tick, address(pool_), oracleParams, _uniV3Helper);
        burnedAmounts = _partialRebalanceOfUniV3Position(restrictions, tick);
        actualPulledAmounts = _capitalRebalance(restrictions, moneyVaultOptions, tick);
    }

    /// @notice rebalance, that if needed burns old univ3 position and mints new
    /// @param restrictions the restrictions of the amount of tokens to be transferred
    /// @param tick current price tick
    /// @return burnedAmounts actual transferred amounts of tokens from position while burn
    function _partialRebalanceOfUniV3Position(RebalanceTokenAmounts memory restrictions, int24 tick)
        internal
        returns (uint256[] memory burnedAmounts)
    {
        IIntegrationVault erc20Vault_ = erc20Vault;
        IUniV3Vault uniV3Vault_ = uniV3Vault;
        uint256 uniV3Nft = uniV3Vault_.uniV3Nft();
        StrategyParams memory strategyParams_ = strategyParams;
        IUniswapV3Pool pool_ = pool;
        address[] memory tokens_ = tokens;
        burnedAmounts = new uint256[](2);
        burnedAmounts[0] = type(uint256).max;
        burnedAmounts[1] = type(uint256).max;
        newPositionMinted = false;
        {
            Interval memory shortInterval_ = shortInterval;
            int24 tickNeighborhood = strategyParams_.tickNeighborhood;

            if (
                shortInterval_.lowerTick + tickNeighborhood <= tick &&
                shortInterval_.upperTick - tickNeighborhood >= tick &&
                !needPositionRebalance
            ) {
                return burnedAmounts;
            }
            needPositionRebalance = false;

            (int24 newLowerTick, int24 newUpperTick) = _hStrategyHelper.calculateNewPositionTicks(
                tick,
                strategyParams_
            );

            if (newLowerTick == shortInterval_.lowerTick && shortInterval_.upperTick == newUpperTick) {
                return burnedAmounts;
            }

            shortInterval = Interval({lowerTick: newLowerTick, upperTick: newUpperTick});
        }

        if (uniV3Nft != 0) {
            // cannot burn only if it is first call of the rebalance function
            // and we dont have any position
            burnedAmounts = _drainPosition(restrictions, erc20Vault_, uniV3Vault_, uniV3Nft, tokens_);
        }

        _mintPosition(pool_, restrictions.deadline, _positionManager, uniV3Vault_, uniV3Nft, tokens_);
    }

    /// @notice rebalance amount of tokens between vaults. Need to be called when no new position is needed
    /// @param restrictions the restrictions of the amount of tokens to be transferred
    /// @param moneyVaultOptions additional parameters for pulling for `pull` method for money vault
    /// @param tick spot tick for calculations
    /// @return actualPulledAmounts actual transferred amounts
    function _capitalRebalance(
        RebalanceTokenAmounts memory restrictions,
        bytes memory moneyVaultOptions,
        int24 tick
    ) internal returns (RebalanceTokenAmounts memory actualPulledAmounts) {
        HStrategyHelper hStrategyHelper_ = _hStrategyHelper;
        IUniV3Vault uniV3Vault_ = uniV3Vault;
        DomainPositionParams memory domainPositionParams;
        {
            uint256 uniV3Nft = uniV3Vault_.uniV3Nft();
            require(uniV3Nft != 0, ExceptionsLibrary.INVARIANT);
            domainPositionParams = hStrategyHelper_.calculateAndCheckDomainPositionParams(
                tick,
                strategyParams,
                uniV3Nft,
                _positionManager
            );
        }
        IIntegrationVault moneyVault_ = moneyVault;
        IIntegrationVault erc20Vault_ = erc20Vault;
        TokenAmounts memory currentTokenAmounts = hStrategyHelper_.calculateCurrentTokenAmounts(
            erc20Vault_,
            moneyVault_,
            domainPositionParams
        );
        TokenAmounts memory expectedTokenAmounts = hStrategyHelper_.calculateExpectedTokenAmounts(
            currentTokenAmounts,
            domainPositionParams,
            hStrategyHelper_,
            _uniV3Helper,
            ratioParams
        );

        if (!hStrategyHelper_.tokenRebalanceNeeded(currentTokenAmounts, expectedTokenAmounts, ratioParams)) {
            return actualPulledAmounts;
        }

        address[] memory tokens_ = tokens;
        actualPulledAmounts.pulledFromUniV3Vault = _pullExtraTokens(
            hStrategyHelper_,
            expectedTokenAmounts,
            restrictions,
            moneyVaultOptions,
            domainPositionParams,
            erc20Vault_,
            moneyVault_,
            uniV3Vault_,
            tokens_
        );

        if (hStrategyHelper_.swapNeeded(currentTokenAmounts, expectedTokenAmounts, ratioParams, domainPositionParams)) {
            actualPulledAmounts.swappedAmounts = _swapTokens(
                currentTokenAmounts,
                expectedTokenAmounts,
                restrictions,
                erc20Vault_,
                tokens_
            );
        }

        TokenAmounts memory missingTokenAmounts;
        {
            (, , , , , , , uint128 liquidity, , , , ) = _positionManager.positions(uniV3Vault_.uniV3Nft());
            missingTokenAmounts = hStrategyHelper_.calculateMissingTokenAmounts(
                moneyVault_,
                expectedTokenAmounts,
                domainPositionParams,
                liquidity
            );
        }
        actualPulledAmounts.pulledToUniV3Vault = _pullMissingTokens(
            missingTokenAmounts,
            restrictions,
            moneyVaultOptions,
            erc20Vault_,
            moneyVault_,
            uniV3Vault_,
            tokens_
        );
    }

    // -------------------  INTERNAL, MUTABLE  -------------------

    /// @notice determining the amount of tokens to be swapped and swapping it
    /// @param currentTokenAmounts the current amount of tokens
    /// @param expectedTokenAmounts the amount of tokens we expect to have after rebalance
    /// @param restrictions the restrictions of the amount of tokens to be transferred
    /// @param erc20Vault_ ERC20 vault of the strategy
    /// @param tokens_ the addresses of the tokens managed by the strategy
    /// @return swappedAmounts acutal amount of swapped tokens
    function _swapTokens(
        TokenAmounts memory currentTokenAmounts,
        TokenAmounts memory expectedTokenAmounts,
        RebalanceTokenAmounts memory restrictions,
        IIntegrationVault erc20Vault_,
        address[] memory tokens_
    ) internal returns (int256[] memory swappedAmounts) {
        (uint256 expectedToken0Amount, uint256 expectedToken1Amount) = _accumulateTokens(expectedTokenAmounts);
        (uint256 currentToken0Amount, uint256 currentToken1Amount) = _accumulateTokens(currentTokenAmounts);

        if (currentToken0Amount >= expectedToken0Amount && currentToken1Amount <= expectedToken1Amount) {
            swappedAmounts = _swapTokensOnERC20Vault(
                currentToken0Amount - expectedToken0Amount,
                0,
                restrictions,
                erc20Vault_,
                tokens_
            );
        } else if (currentToken0Amount <= expectedToken0Amount && currentToken1Amount >= expectedToken1Amount) {
            swappedAmounts = _swapTokensOnERC20Vault(
                currentToken1Amount - expectedToken1Amount,
                1,
                restrictions,
                erc20Vault_,
                tokens_
            );
        } else {
            revert(ExceptionsLibrary.INVALID_STATE);
        }
    }

    /// @notice pulling extra tokens from money and uniV3 vaults on erc20
    /// @param hStrategyHelper_ the helper of the strategy
    /// @param expectedTokenAmounts the amount of tokens we expect to have after rebalance
    /// @param restrictions the restrictions of the amount of tokens to be transferred
    /// @param moneyVaultOptions additional parameters for pulling for `pull` method for money vault
    /// @param domainPositionParams the current state of the pool and position
    /// @param erc20Vault_ ERC20 vault of the strategy
    /// @param moneyVault_ Money vault of the strategy
    /// @param uniV3Vault_ UniswapV3 vault of the strategy
    /// @param tokens_ the addresses of the tokens managed by the strategy
    /// @return pulledFromUniV3Vault the actual amount of tokens pulled from UniV3Vault
    function _pullExtraTokens(
        HStrategyHelper hStrategyHelper_,
        TokenAmounts memory expectedTokenAmounts,
        RebalanceTokenAmounts memory restrictions,
        bytes memory moneyVaultOptions,
        DomainPositionParams memory domainPositionParams,
        IIntegrationVault erc20Vault_,
        IIntegrationVault moneyVault_,
        IUniV3Vault uniV3Vault_,
        address[] memory tokens_
    ) internal returns (uint256[] memory pulledFromUniV3Vault) {
        pulledFromUniV3Vault = new uint256[](2);
        if (!newPositionMinted) {
            uint256[] memory extraTokenAmountsForPull = hStrategyHelper_.calculateExtraTokenAmountsForUniV3Vault(
                expectedTokenAmounts,
                domainPositionParams
            );

            if (extraTokenAmountsForPull[0] > 0 || extraTokenAmountsForPull[1] > 0) {
                pulledFromUniV3Vault = uniV3Vault_.pull(address(erc20Vault_), tokens_, extraTokenAmountsForPull, "");
                _compareAmounts(restrictions.pulledFromUniV3Vault, pulledFromUniV3Vault);
            }
        }

        {
            uint256[] memory extraTokenAmountsForPull = hStrategyHelper_.calculateExtraTokenAmountsForMoneyVault(
                moneyVault_,
                expectedTokenAmounts
            );

            if (extraTokenAmountsForPull[0] > 0 || extraTokenAmountsForPull[1] > 0) {
                moneyVault_.pull(address(erc20Vault_), tokens_, extraTokenAmountsForPull, moneyVaultOptions);
            }
        }
    }

    /// @notice pulling missing tokens from erc20 vault on money and uniV3 vaults
    /// @param missingTokenAmounts the amount of missing tokens
    /// @param restrictions the restrictions of the amount of tokens to be transferred
    /// @param moneyVaultOptions additional parameters for pulling for `pull` method for money vault
    /// @param erc20Vault_ ERC20 vault of the strategy
    /// @param moneyVault_ Money vault of the strategy
    /// @param uniV3Vault_ UniswapV3 vault of the strategy
    /// @param tokens_ the addresses of the tokens managed by the strategy
    /// @return pulledToUniV3Vault the actual amount of tokens pulled into UniV3Vault
    function _pullMissingTokens(
        TokenAmounts memory missingTokenAmounts,
        RebalanceTokenAmounts memory restrictions,
        bytes memory moneyVaultOptions,
        IIntegrationVault erc20Vault_,
        IIntegrationVault moneyVault_,
        IUniV3Vault uniV3Vault_,
        address[] memory tokens_
    ) internal returns (uint256[] memory pulledToUniV3Vault) {
        pulledToUniV3Vault = new uint256[](2);
        uint256[] memory extraTokenAmountsForPull = new uint256[](2);
        {
            if (missingTokenAmounts.uniV3Token0 > 0 || missingTokenAmounts.uniV3Token1 > 0) {
                extraTokenAmountsForPull[0] = missingTokenAmounts.uniV3Token0;
                extraTokenAmountsForPull[1] = missingTokenAmounts.uniV3Token1;
                pulledToUniV3Vault = erc20Vault_.pull(address(uniV3Vault_), tokens_, extraTokenAmountsForPull, "");
                _compareAmounts(restrictions.pulledToUniV3Vault, pulledToUniV3Vault);
            }
        }
        {
            if (missingTokenAmounts.moneyToken0 > 0 || missingTokenAmounts.moneyToken1 > 0) {
                extraTokenAmountsForPull[0] = missingTokenAmounts.moneyToken0;
                extraTokenAmountsForPull[1] = missingTokenAmounts.moneyToken1;
                erc20Vault_.pull(address(moneyVault_), tokens_, extraTokenAmountsForPull, moneyVaultOptions);
            }
        }
    }

    /// @notice minting new position inside the domain interval
    /// @param pool_ address of uniV3 pool
    /// @param deadline maximal duration of swap offer on uniV3
    /// @param positionManager_ uniV3 position manager
    /// @param uniV3Vault_ UniswapV3 vault of the strategy
    /// @param oldNft the nft of the burning position
    /// @param tokens_ addresses of tokens of strategy
    /// @param tokens_ the addresses of the tokens managed by the strategy
    function _mintPosition(
        IUniswapV3Pool pool_,
        uint256 deadline,
        INonfungiblePositionManager positionManager_,
        IUniV3Vault uniV3Vault_,
        uint256 oldNft,
        address[] memory tokens_
    ) internal {
        uint256 minToken0ForOpening;
        uint256 minToken1ForOpening;
        {
            MintingParams memory mintingParams_ = mintingParams;
            minToken0ForOpening = mintingParams_.minToken0ForOpening;
            minToken1ForOpening = mintingParams_.minToken1ForOpening;
        }
        IERC20(tokens_[0]).safeApprove(address(positionManager_), minToken0ForOpening);
        IERC20(tokens_[1]).safeApprove(address(positionManager_), minToken1ForOpening);
        Interval memory shortInterval_ = shortInterval;
        (uint256 newNft, , , ) = positionManager_.mint(
            INonfungiblePositionManager.MintParams({
                token0: tokens_[0],
                token1: tokens_[1],
                fee: pool_.fee(),
                tickLower: shortInterval_.lowerTick,
                tickUpper: shortInterval_.upperTick,
                amount0Desired: minToken0ForOpening,
                amount1Desired: minToken1ForOpening,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: deadline
            })
        );
        IERC20(tokens_[0]).safeApprove(address(positionManager_), 0);
        IERC20(tokens_[1]).safeApprove(address(positionManager_), 0);

        positionManager_.safeTransferFrom(address(this), address(uniV3Vault_), newNft);
        if (oldNft != 0) {
            positionManager_.burn(oldNft);
        }
        newPositionMinted = true;
        emit MintUniV3Position(newNft, shortInterval_.lowerTick, shortInterval_.upperTick);
    }

    /// @notice draining all assets from uniV3
    /// @param restrictions the restrictions of the amount of tokens to be transferred
    /// @param erc20Vault_ ERC20 vault of the strategy
    /// @param uniV3Vault_ UniswapV3 vault of the strategy
    /// @param uniV3Nft the nft of the position from position manager
    /// @param tokens_ the addresses of the tokens managed by the strategy
    /// @return drainedTokens actual amount of tokens got from draining position
    function _drainPosition(
        RebalanceTokenAmounts memory restrictions,
        IIntegrationVault erc20Vault_,
        IUniV3Vault uniV3Vault_,
        uint256 uniV3Nft,
        address[] memory tokens_
    ) internal returns (uint256[] memory drainedTokens) {
        drainedTokens = uniV3Vault_.liquidityToTokenAmounts(type(uint128).max);
        drainedTokens = uniV3Vault_.pull(address(erc20Vault_), tokens_, drainedTokens, "");
        _compareAmounts(restrictions.burnedAmounts, drainedTokens);
        emit BurnUniV3Position(uniV3Nft);
    }

    /// @notice swapping tokens
    /// @param amountIn amount of tokens to be swapped
    /// @param tokenInIndex the index of token to be swapped (0 or 1)
    /// @param restrictions the restrictions of the amount of tokens to be transferred
    /// @param erc20Vault_ ERC20 vault of the strategy
    /// @param tokens_ the addresses of the tokens managed by the strategy
    /// @return amountsOut actual amount of tokens got from swap
    function _swapTokensOnERC20Vault(
        uint256 amountIn,
        uint256 tokenInIndex,
        RebalanceTokenAmounts memory restrictions,
        IIntegrationVault erc20Vault_,
        address[] memory tokens_
    ) internal returns (int256[] memory amountsOut) {
        {
            (uint256[] memory tvl, ) = erc20Vault_.tvl();
            if (tvl[tokenInIndex] < amountIn) {
                amountIn = tvl[tokenInIndex];
            }
        }

        bytes memory routerResult;
        if (amountIn > 0) {
            ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: tokens_[tokenInIndex],
                tokenOut: tokens_[tokenInIndex ^ 1],
                fee: swapFees,
                recipient: address(erc20Vault_),
                deadline: restrictions.deadline,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
            bytes memory data = abi.encode(swapParams);
            erc20Vault_.externalCall(tokens_[tokenInIndex], APPROVE_SELECTOR, abi.encode(address(router), amountIn)); // approve
            routerResult = erc20Vault_.externalCall(address(router), EXACT_INPUT_SINGLE_SELECTOR, data); // swap
            erc20Vault_.externalCall(tokens_[tokenInIndex], APPROVE_SELECTOR, abi.encode(address(router), 0)); // reset allowance
            uint256 amountOut = abi.decode(routerResult, (uint256));

            require(
                restrictions.swappedAmounts[tokenInIndex ^ 1] >= 0 && restrictions.swappedAmounts[tokenInIndex] <= 0,
                ExceptionsLibrary.INVARIANT
            );
            require(
                restrictions.swappedAmounts[tokenInIndex ^ 1] <= int256(amountOut),
                ExceptionsLibrary.LIMIT_UNDERFLOW
            );
            require(restrictions.swappedAmounts[tokenInIndex] >= -int256(amountIn), ExceptionsLibrary.LIMIT_OVERFLOW);

            amountsOut = new int256[](2);
            amountsOut[tokenInIndex ^ 1] = int256(amountOut);
            amountsOut[tokenInIndex] = -int256(amountIn);

            emit SwapTokensOnERC20Vault(tx.origin, swapParams);
        } else {
            require(restrictions.swappedAmounts[tokenInIndex ^ 1] == 0, ExceptionsLibrary.LIMIT_OVERFLOW);
            require(restrictions.swappedAmounts[tokenInIndex] == 0, ExceptionsLibrary.LIMIT_UNDERFLOW);
            return new int256[](2);
        }
    }

    // -------------------  INTERNAL, VIEW  -------------------

    /// @notice method comparing needed amount of tokens and actual. Reverts in for any elent holds needed[i] > actual[i]
    /// @param needed the needed amount of tokens from some action
    /// @param actual actual amount of tokens from the action
    function _compareAmounts(uint256[] memory needed, uint256[] memory actual) internal pure {
        for (uint256 i = 0; i < 2; i++) {
            require(needed[i] <= actual[i], ExceptionsLibrary.LIMIT_UNDERFLOW);
        }
    }

    /// @notice method calculates sums for both tokens along all vaults
    /// @param tokenAmouts given token amounts
    /// @return token0 amount of token 0 over all vaults for given tokenAmouts
    /// @return token1 amount of token 1 over all vaults for given tokenAmouts
    function _accumulateTokens(TokenAmounts memory tokenAmouts) internal pure returns (uint256 token0, uint256 token1) {
        token0 = tokenAmouts.erc20Token0 + tokenAmouts.moneyToken0 + tokenAmouts.uniV3Token0;
        token1 = tokenAmouts.erc20Token1 + tokenAmouts.moneyToken1 + tokenAmouts.uniV3Token1;
    }

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("HStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    /// @notice Emitted when new position in UniV3Pool has been minted.
    /// @param uniV3Nft nft of new minted position
    /// @param lowerTick lowerTick of that position
    /// @param upperTick upperTick of that position
    event MintUniV3Position(uint256 uniV3Nft, int24 lowerTick, int24 upperTick);

    /// @notice Emitted when position in UniV3Pool has been burnt.
    /// @param uniV3Nft nft of new minted position
    event BurnUniV3Position(uint256 uniV3Nft);

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

    /// @notice Emitted when new swap fees for UniV3Pool swaps are set.
    /// @param newSwapFees new swap fee
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    event UpdateSwapFees(address indexed origin, address indexed sender, uint24 newSwapFees);
}
