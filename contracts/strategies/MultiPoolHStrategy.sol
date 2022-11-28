// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../utils/ContractMeta.sol";
import "../utils/MultiPoolHStrategyRebalancer.sol";
import "../utils/DefaultAccessControl.sol";

contract MultiPoolHStrategy is ContractMeta, DefaultAccessControl {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 1000_000_000;

    // TODO: add comments
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

    // TODO: add comments
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

    // TODO: add comments
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
        require(erc20VaultTokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        require(erc20VaultTokens[0] == token0_, ExceptionsLibrary.INVARIANT);
        require(erc20VaultTokens[1] == token1_, ExceptionsLibrary.INVARIANT);

        require(address(moneyVault_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        address[] memory moneyVaultTokens = erc20Vault_.vaultTokens();
        require(moneyVaultTokens.length == 2, ExceptionsLibrary.INVALID_LENGTH);
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

    // TODO: add comments
    function updateMutableParams(MutableParams memory newStrategyParams) external {
        _requireAdmin();
        int24 tickSpacing_ = tickSpacing;
        int24 globalIntervalWidth = newStrategyParams.domainUpperTick - newStrategyParams.domainLowerTick;

        require(newStrategyParams.halfOfShortInterval > 0, ExceptionsLibrary.VALUE_ZERO);
        require(newStrategyParams.halfOfShortInterval % tickSpacing_ == 0, ExceptionsLibrary.INVALID_VALUE);
        require(newStrategyParams.maxTickDeviation > 0, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(
            newStrategyParams.maxTickDeviation < newStrategyParams.halfOfShortInterval,
            ExceptionsLibrary.LIMIT_OVERFLOW
        );
        require(newStrategyParams.domainLowerTick % tickSpacing_ == 0, ExceptionsLibrary.INVALID_VALUE);
        require(newStrategyParams.domainUpperTick % tickSpacing_ == 0, ExceptionsLibrary.INVALID_VALUE);
        require(globalIntervalWidth > newStrategyParams.halfOfShortInterval, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(globalIntervalWidth % newStrategyParams.halfOfShortInterval == 0, ExceptionsLibrary.INVALID_VALUE);
        require(newStrategyParams.averageTickTimespan > 0, ExceptionsLibrary.VALUE_ZERO);

        require(newStrategyParams.erc20CapitalRatioD > 0, ExceptionsLibrary.VALUE_ZERO);
        require(newStrategyParams.erc20CapitalRatioD < DENOMINATOR, ExceptionsLibrary.LIMIT_OVERFLOW);

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

        require(address(newStrategyParams.swapPool) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(newStrategyParams.swapPool.token0() == token0, ExceptionsLibrary.INVALID_TOKEN);
        require(newStrategyParams.swapPool.token1() == token1, ExceptionsLibrary.INVALID_TOKEN);
        emit UpdateMutableParams(tx.origin, msg.sender, newStrategyParams);
    }

    // TODO: add comments
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

    // TODO: add comments
    event UpdateMutableParams(address indexed origin, address indexed sender, MutableParams mutableParams);

    // TODO: add comments
    event Rebalance(
        address indexed sender,
        MultiPoolHStrategyRebalancer.Restrictions expectedAmounts,
        MultiPoolHStrategyRebalancer.Restrictions actualAmounts
    );
}
