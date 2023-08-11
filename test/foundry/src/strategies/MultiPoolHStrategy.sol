// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Multicall.sol";

import "../utils/ContractMeta.sol";
import "../utils/MultiPoolHStrategyRebalancer.sol";
import "../utils/DefaultAccessControlLateInit.sol";

contract MultiPoolHStrategy is ContractMeta, Multicall, DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 1000_000_000;

    /// @param tokens sorted array of length two with addresses of tokens of the strategy
    /// @param erc20Vault erc20Vault of the root vault system
    /// @param moneyVault erc20Vault of the root vault system
    /// @param router uniV3 router for swapping tokens
    /// @param rebalancer address of helper needed to process rebalance
    /// @param uniV3Vaults array of uniV3Vault of the root vault system sorted by fees of pools
    /// @param tickSpacing LCM of all tick spacings over all uniV3Vaults pools
    struct ImmutableParams {
        address[] tokens;
        IERC20Vault erc20Vault;
        IIntegrationVault moneyVault;
        address router;
        MultiPoolHStrategyRebalancer rebalancer;
        IUniV3Vault[] uniV3Vaults;
        int24 tickSpacing;
    }

    /// @param halfOfShortInterval half of the width of the uniV3 position measured in the strategy in ticks
    /// @param domainLowerTick lower tick of the domain uniV3 position
    /// @param domainUpperTick upper tick of the domain uniV3 position
    /// @param maxTickDeviation upper bound for an absolute deviation between the spot price and the price for a given number of seconds ago
    /// @param averageTickTimespan delta in seconds, passed to the oracle to get the average tick over the last averageTickTimespan seconds
    /// @param amount0ForMint amount of token0 is tried to be deposited on the new position
    /// @param amount1ForMint amount of token1 is tried to be deposited on the new position
    /// @param erc20CapitalRatioD ratio of tokens kept in the money vault instead of erc20. The ratio is maintained for each token
    /// @param uniV3Weights array of weights for each uniV3Vault of uniV3Vault array, that shows the relative part of liquidity to be added in each uniV3Vault
    /// @param swapPool uniswapV3 Pool needed to process swaps and for calculations of average tick
    struct MutableParams {
        int24 halfOfShortInterval;
        int24 domainLowerTick;
        int24 domainUpperTick;
        int24 maxTickDeviation;
        uint32 averageTickTimespan;
        uint256 amount0ForMint;
        uint256 amount1ForMint;
        uint256 erc20CapitalRatioD;
        uint256[] uniV3Weights;
        IUniswapV3Pool swapPool;
    }

    /// @param lowerTick lower tick of interval
    /// @param upperTick upper tick of interval
    struct Interval {
        int24 lowerTick;
        int24 upperTick;
    }

    // Immutable params
    ImmutableParams public immutableParams;

    // Mutable params
    MutableParams public mutableParams;

    /// @notice current positions in uniV3Vaults
    Interval public shortInterval;

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @notice constructs a strategy
    constructor() {
        DefaultAccessControlLateInit.init(address(this));
    }

    /// @notice initializes the strategy
    /// @param immutableParams_ structure with all immutable params of the strategy
    /// @param mutableParams_ structure with all mutable params of strategy for initial set
    /// @param admin the addres of the admin of the strategy
    function initialize(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        address admin
    ) external {
        require(immutableParams_.tokens[0] != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(immutableParams_.tokens[1] != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(immutableParams_.tokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(address(immutableParams_.erc20Vault) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        address[] memory erc20VaultTokens = immutableParams_.erc20Vault.vaultTokens();
        require(erc20VaultTokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(erc20VaultTokens[0] == immutableParams_.tokens[0], ExceptionsLibrary.INVARIANT);
        require(erc20VaultTokens[1] == immutableParams_.tokens[1], ExceptionsLibrary.INVARIANT);

        require(address(immutableParams_.moneyVault) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        address[] memory moneyVaultTokens = immutableParams_.erc20Vault.vaultTokens();
        require(moneyVaultTokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(moneyVaultTokens[0] == immutableParams_.tokens[0], ExceptionsLibrary.INVARIANT);
        require(moneyVaultTokens[1] == immutableParams_.tokens[1], ExceptionsLibrary.INVARIANT);

        require(immutableParams_.router != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(immutableParams_.rebalancer) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(admin != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(immutableParams_.uniV3Vaults.length > 0, ExceptionsLibrary.INVALID_LENGTH);

        uint24 lastPoolFee = 0;
        for (uint256 i = 0; i < immutableParams_.uniV3Vaults.length; ++i) {
            require(address(immutableParams_.uniV3Vaults[i]) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
            address[] memory uniV3VaultTokens = immutableParams_.uniV3Vaults[i].vaultTokens();
            require(uniV3VaultTokens[0] == immutableParams_.tokens[0], ExceptionsLibrary.INVARIANT);
            require(uniV3VaultTokens[1] == immutableParams_.tokens[1], ExceptionsLibrary.INVARIANT);
            IUniswapV3Pool pool = immutableParams_.uniV3Vaults[i].pool();
            require(immutableParams_.tickSpacing % pool.tickSpacing() == 0, ExceptionsLibrary.INVARIANT);
            uint24 poolFee = pool.fee();
            require(lastPoolFee < poolFee, ExceptionsLibrary.INVARIANT);
            lastPoolFee = poolFee;
        }

        require(immutableParams_.tickSpacing < TickMath.MAX_TICK / 4, ExceptionsLibrary.LIMIT_OVERFLOW);
        immutableParams_.rebalancer = immutableParams_.rebalancer.createRebalancer(address(this));
        immutableParams = immutableParams_;
        checkMutableParams(mutableParams_);
        mutableParams = mutableParams_;
        DefaultAccessControlLateInit.init(admin);
    }

    /// @notice creates the clone of the strategy
    /// @param immutableParams_ structure with all immutable params of the strategy
    /// @param mutableParams_ structure with all mutable params of strategy for initial set
    /// @param admin the addres of the admin of the strategy
    /// @return strategy new cloned strategy with for given params
    function createStrategy(
        ImmutableParams memory immutableParams_,
        MutableParams memory mutableParams_,
        address admin
    ) external returns (MultiPoolHStrategy strategy) {
        strategy = MultiPoolHStrategy(Clones.clone(address(this)));
        strategy.initialize(immutableParams_, mutableParams_, admin);
    }

    /// @notice updates parameters of the strategy. Can be called only by admin
    /// @param mutableParams_ the new parameters
    function updateMutableParams(MutableParams memory mutableParams_) external {
        _requireAdmin();
        checkMutableParams(mutableParams_);
        mutableParams = mutableParams_;
        emit UpdateMutableParams(tx.origin, msg.sender, mutableParams_);
    }

    /// @notice rebalance method. Need to be called if the new position is needed
    /// @param restrictions the restrictions of the amount of tokens to be transferred and positions to be minted
    /// @return actualAmounts actual transferred token amounts and minted positions
    function rebalance(
        MultiPoolHStrategyRebalancer.Restrictions memory restrictions
    ) external returns (MultiPoolHStrategyRebalancer.Restrictions memory actualAmounts) {
        _requireAtLeastOperator();
        MutableParams memory mutableParams_ = mutableParams;
        Interval memory shortInterval_ = shortInterval;
        ImmutableParams memory immutableParams_ = immutableParams;
        MultiPoolHStrategyRebalancer.StrategyData memory data = MultiPoolHStrategyRebalancer.StrategyData({
            tokens: immutableParams_.tokens,
            uniV3Vaults: immutableParams_.uniV3Vaults,
            erc20Vault: immutableParams_.erc20Vault,
            moneyVault: immutableParams_.moneyVault,
            swapPool: mutableParams_.swapPool,
            maxTickDeviation: mutableParams_.maxTickDeviation,
            averageTickTimespan: mutableParams_.averageTickTimespan,
            halfOfShortInterval: mutableParams_.halfOfShortInterval,
            domainLowerTick: mutableParams_.domainLowerTick,
            domainUpperTick: mutableParams_.domainUpperTick,
            shortLowerTick: shortInterval_.lowerTick,
            shortUpperTick: shortInterval_.upperTick,
            amount0ForMint: mutableParams_.amount0ForMint,
            amount1ForMint: mutableParams_.amount1ForMint,
            router: immutableParams_.router,
            erc20CapitalRatioD: mutableParams_.erc20CapitalRatioD,
            uniV3Weights: mutableParams_.uniV3Weights
        });

        actualAmounts = MultiPoolHStrategyRebalancer(immutableParams_.rebalancer).processRebalance(data, restrictions);
        if (actualAmounts.newShortLowerTick < actualAmounts.newShortUpperTick) {
            shortInterval = Interval({
                lowerTick: actualAmounts.newShortLowerTick,
                upperTick: actualAmounts.newShortUpperTick
            });
        }

        emit Rebalance(msg.sender, tx.origin, restrictions, actualAmounts);
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @notice the function checks that mutableParams_ pass the necessary checks
    /// @param mutableParams_ params to be checked
    function checkMutableParams(MutableParams memory mutableParams_) public view {
        ImmutableParams memory immutableParams_ = immutableParams;
        int24 tickSpacing_ = immutableParams_.tickSpacing;
        int24 globalIntervalWidth = mutableParams_.domainUpperTick - mutableParams_.domainLowerTick;

        require(mutableParams_.halfOfShortInterval > 0, ExceptionsLibrary.VALUE_ZERO);
        require(mutableParams_.halfOfShortInterval % tickSpacing_ == 0, ExceptionsLibrary.INVALID_VALUE);
        require(mutableParams_.maxTickDeviation > 0, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(mutableParams_.maxTickDeviation < mutableParams_.halfOfShortInterval, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(mutableParams_.domainLowerTick % tickSpacing_ == 0, ExceptionsLibrary.INVALID_VALUE);
        require(mutableParams_.domainUpperTick % tickSpacing_ == 0, ExceptionsLibrary.INVALID_VALUE);
        require(globalIntervalWidth > mutableParams_.halfOfShortInterval, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(globalIntervalWidth % mutableParams_.halfOfShortInterval == 0, ExceptionsLibrary.INVALID_VALUE);
        require(mutableParams_.averageTickTimespan > 0, ExceptionsLibrary.VALUE_ZERO);

        require(mutableParams_.erc20CapitalRatioD > 0, ExceptionsLibrary.VALUE_ZERO);
        require(mutableParams_.erc20CapitalRatioD < DENOMINATOR, ExceptionsLibrary.LIMIT_OVERFLOW);

        require(mutableParams_.amount0ForMint > 0, ExceptionsLibrary.VALUE_ZERO);
        require(mutableParams_.amount0ForMint <= 1000_000_000, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(mutableParams_.amount1ForMint > 0, ExceptionsLibrary.VALUE_ZERO);
        require(mutableParams_.amount1ForMint <= 1000_000_000, ExceptionsLibrary.LIMIT_OVERFLOW);

        require(
            mutableParams_.uniV3Weights.length == immutableParams_.uniV3Vaults.length,
            ExceptionsLibrary.INVALID_LENGTH
        );
        uint256 newTotalWeight = 0;
        for (uint256 i = 0; i < mutableParams_.uniV3Weights.length; ++i) {
            newTotalWeight += mutableParams_.uniV3Weights[i];
        }
        require(newTotalWeight > 0, ExceptionsLibrary.VALUE_ZERO);

        require(address(mutableParams_.swapPool) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(mutableParams_.swapPool.token0() == immutableParams_.tokens[0], ExceptionsLibrary.INVALID_TOKEN);
        require(mutableParams_.swapPool.token1() == immutableParams_.tokens[1], ExceptionsLibrary.INVALID_TOKEN);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("MultiPoolHStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    /// @notice Emitted when Strategy mutableParams are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param mutableParams Updated mutableParams
    event UpdateMutableParams(address indexed origin, address indexed sender, MutableParams mutableParams);

    /// @notice Emitted when Strategy mutableParams are set.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param expectedAmounts expected amounts to be transferred and positions to be minted
    /// @param actualAmounts actual transferred amounts and minted positions
    event Rebalance(
        address indexed sender,
        address indexed origin,
        MultiPoolHStrategyRebalancer.Restrictions expectedAmounts,
        MultiPoolHStrategyRebalancer.Restrictions actualAmounts
    );
}
