// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../utils/ContractMeta.sol";
import "../utils/MultiPoolHStrategyRebalancer.sol";
import "../utils/DefaultAccessControl.sol";

contract MultiPoolHStrategy is ContractMeta, DefaultAccessControl {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 1000_000_000;

    /// @param halfOfShortInterval half of width of the uniV3 position measured in the strategy in ticks
    /// @param domainLowerTick the lower tick of the domain uniV3 position
    /// @param domainUpperTick the upper tick of the domain uniV3 position
    /// @param amount0ForMint the amount of token0 are tried to be depositted on the new position
    /// @param amount1ForMint the amount of token1 are tried to be depositted on the new position
    /// @param erc20CapitalRatioD the ratio of tokens kept in money vault instead of erc20. The ratio is maintained for each token
    /// @param uniV3Weights array of weights that shows ratio of liquidity accoss UniswapV3 pools in strategy
    struct MutableParams {
        int24 halfOfShortInterval;
        int24 domainLowerTick;
        int24 domainUpperTick;
        uint256 amount0ForMint;
        uint256 amount1ForMint;
        uint256 erc20CapitalRatioD;
        uint256[] uniV3Weights;
    }

    /// @notice parameters of the current short position
    /// @param lowerTick lower tick of interval
    /// @param upperTick upper tick of interval
    struct Interval {
        int24 lowerTick;
        int24 upperTick;
    }

    // Immutable params
    address public immutable token0;
    address public immutable token1;
    IERC20Vault public immutable erc20Vault;
    IIntegrationVault public immutable moneyVault;
    address public immutable router;
    MultiPoolHStrategyRebalancer public immutable rebalancer;
    IUniV3Vault[] public uniV3Vaults;
    int24 public immutable tickSpacing;

    // Mutable params
    MutableParams public mutableParams;

    // Internal params
    Interval public shortInterval;

    // -------------------  EXTERNAL, MUTATING  -------------------
    /// @notice constructs a strategy
    /// @param token0_ first token of strategy
    /// @param token1_ second token of strategy
    /// @param erc20Vault_  erc20Vault of RootVault system
    /// @param moneyVault_ YearnVault or AaveVault in RootVault system to gerenate additional yield
    /// @param router_ the UniswapV3 router for swapping tokens
    /// @param rebalancer_ strategy rebalances which is needed to process rebalance
    /// @param admin admin of this strategy
    /// @param uniV3Vaults_ UniV3Vaults of strategy for UniswapV3Pools with different fees
    constructor(
        address token0_,
        address token1_,
        IERC20Vault erc20Vault_,
        IIntegrationVault moneyVault_,
        address router_,
        MultiPoolHStrategyRebalancer rebalancer_,
        address admin,
        IUniV3Vault[] memory uniV3Vaults_,
        int24 tickSpacing_
    ) DefaultAccessControl(admin) {
        require(token0_ != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(token1_ != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(erc20Vault_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        address[] memory erc20VaultTokens = erc20Vault_.vaultTokens();
        require(erc20VaultTokens[0] == token0_, ExceptionsLibrary.INVARIANT);
        require(erc20VaultTokens[1] == token1_, ExceptionsLibrary.INVARIANT);

        require(address(moneyVault_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        address[] memory moneyVaultTokens = erc20Vault_.vaultTokens();
        require(moneyVaultTokens[0] == token0_, ExceptionsLibrary.INVARIANT);
        require(moneyVaultTokens[1] == token1_, ExceptionsLibrary.INVARIANT);

        require(router_ != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(rebalancer_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(admin != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(uniV3Vaults_.length > 0, ExceptionsLibrary.INVALID_LENGTH);

        uint24 lastPoolFee = 0;
        for (uint256 i = 0; i < uniV3Vaults_.length; ++i) {
            require(address(uniV3Vaults_[i]) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
            address[] memory uniV3VaultTokens = uniV3Vaults_[i].vaultTokens();
            require(uniV3VaultTokens[0] == token0_, ExceptionsLibrary.INVARIANT);
            require(uniV3VaultTokens[1] == token1_, ExceptionsLibrary.INVARIANT);
            IUniswapV3Pool pool = uniV3Vaults_[i].pool();
            require(tickSpacing_ % pool.tickSpacing() == 0, ExceptionsLibrary.INVARIANT);
            uint24 poolFee = pool.fee();
            require(lastPoolFee < poolFee, ExceptionsLibrary.INVARIANT);
            lastPoolFee = poolFee;
        }

        require(tickSpacing_ < TickMath.MAX_TICK / 4, ExceptionsLibrary.LIMIT_OVERFLOW);
        tickSpacing = tickSpacing_;
        token0 = token0_;
        token1 = token1_;
        erc20Vault = erc20Vault_;
        moneyVault = moneyVault_;
        router = router_;
        uniV3Vaults = uniV3Vaults_;
        rebalancer = rebalancer_.createRebalancer(address(this));
    }

    /// @notice updates mutable parameters of the strategy. Can be called only by admin
    /// @param newStrategyParams the new parameters
    function updateMutableParams(MutableParams memory newStrategyParams) external {
        _requireAdmin();
        int24 tickSpacing_ = tickSpacing;
        int24 globalIntervalWidth = newStrategyParams.domainUpperTick - newStrategyParams.domainLowerTick;

        require(newStrategyParams.halfOfShortInterval > 0, ExceptionsLibrary.VALUE_ZERO);
        require(newStrategyParams.halfOfShortInterval % tickSpacing_ == 0, ExceptionsLibrary.INVALID_VALUE);
        require(newStrategyParams.domainLowerTick % tickSpacing_ == 0, ExceptionsLibrary.INVALID_VALUE);
        require(newStrategyParams.domainUpperTick % tickSpacing_ == 0, ExceptionsLibrary.INVALID_VALUE);
        require(globalIntervalWidth > newStrategyParams.halfOfShortInterval, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(globalIntervalWidth % newStrategyParams.halfOfShortInterval == 0, ExceptionsLibrary.INVALID_VALUE);

        require(newStrategyParams.erc20CapitalRatioD > 0, ExceptionsLibrary.VALUE_ZERO);
        require(newStrategyParams.erc20CapitalRatioD < DENOMINATOR, ExceptionsLibrary.LIMIT_UNDERFLOW);

        require(newStrategyParams.amount0ForMint > 0, ExceptionsLibrary.VALUE_ZERO);
        require(newStrategyParams.amount0ForMint <= 1000_000_000, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(newStrategyParams.amount1ForMint > 0, ExceptionsLibrary.VALUE_ZERO);
        require(newStrategyParams.amount1ForMint <= 1000_000_000, ExceptionsLibrary.LIMIT_OVERFLOW);

        require(newStrategyParams.uniV3Weights.length == uniV3Vaults.length, ExceptionsLibrary.INVALID_LENGTH);
        uint256 newTotalWeight = 0;
        for (uint256 i = 0; i < newStrategyParams.uniV3Weights.length; ++i) {
            newTotalWeight += newStrategyParams.uniV3Weights[i];
        }
        require(newTotalWeight > 0, ExceptionsLibrary.VALUE_ZERO);
        mutableParams = newStrategyParams;

        emit UpdateMutableParams(tx.origin, msg.sender, newStrategyParams);
    }

    /// @notice rebalance method. Need to be called if the new position or new ratio of tokens are needed
    /// @param restrictions the restrictions of the amounts of tokens to be transferred and ticks of new position
    /// @return actualAmounts actual transferred amounts
    function rebalance(MultiPoolHStrategyRebalancer.Restrictions memory restrictions)
        external
        returns (MultiPoolHStrategyRebalancer.Restrictions memory actualAmounts)
    {
        _requireAtLeastOperator();
        MutableParams memory mutableParams_ = mutableParams;
        Interval memory shortInterval_ = shortInterval;
        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;
        MultiPoolHStrategyRebalancer.StrategyData memory data = MultiPoolHStrategyRebalancer.StrategyData({
            tokens: tokens,
            uniV3Vaults: uniV3Vaults,
            erc20Vault: erc20Vault,
            moneyVault: moneyVault,
            halfOfShortInterval: mutableParams_.halfOfShortInterval,
            domainLowerTick: mutableParams_.domainLowerTick,
            domainUpperTick: mutableParams_.domainUpperTick,
            shortLowerTick: shortInterval_.lowerTick,
            shortUpperTick: shortInterval_.upperTick,
            amount0ForMint: mutableParams_.amount0ForMint,
            amount1ForMint: mutableParams_.amount1ForMint,
            router: router,
            erc20CapitalRatioD: mutableParams_.erc20CapitalRatioD,
            uniV3Weights: mutableParams_.uniV3Weights
        });

        actualAmounts = MultiPoolHStrategyRebalancer(rebalancer).processRebalance(data, restrictions);
        if (actualAmounts.newShortLowerTick < actualAmounts.newShortUpperTick) {
            shortInterval = Interval({
                lowerTick: actualAmounts.newShortLowerTick,
                upperTick: actualAmounts.newShortUpperTick
            });
        }

        emit Rebalance(msg.sender, restrictions, actualAmounts);
    }

    // -------------------  INTERNAL, PURE  -------------------

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

    /// @notice Emitted when the rebalance function is called.
    /// @param sender Sender of the call (msg.sender)
    /// @param expectedAmounts restrictions for token transfers and minting positions
    /// @param actualAmounts actual transferred amounts and minted positions
    event Rebalance(
        address indexed sender,
        MultiPoolHStrategyRebalancer.Restrictions expectedAmounts,
        MultiPoolHStrategyRebalancer.Restrictions actualAmounts
    );
}
