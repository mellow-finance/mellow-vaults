// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../utils/ContractMeta.sol";
import "../utils/MultiPoolHStrategyRebalancer.sol";
import "../utils/DefaultAccessControl.sol";

contract MultiPoolHStrategy is ContractMeta, DefaultAccessControl {
    using SafeERC20 for IERC20;

    struct MutableParams {
        int24 halfOfShortInterval;
        int24 domainLowerTick;
        int24 domainUpperTick;
        uint256 amount0ForMint;
        uint256 amount1ForMint;
        uint256 erc20CapitalD;
        uint256[] uniV3Weights;
    }

    struct Interval {
        int24 lowerTick;
        int24 upperTick;
    }

    // Immutable params
    address public immutable token0;
    address public immutable token1;
    IERC20Vault public immutable erc20Vault;
    IIntegrationVault public immutable moneyVault;
    IUniswapV3Pool public immutable pool;
    address public immutable router;
    MultiPoolHStrategyRebalancer public immutable rebalancer;
    IUniV3Vault[] public uniV3Vaults;

    // Mutable params
    MutableParams public mutableParams;

    // Internal params
    Interval public shortInterval;

    constructor(
        address token0_,
        address token1_,
        IERC20Vault erc20Vault_,
        IIntegrationVault moneyVault_,
        IUniswapV3Pool pool_,
        address router_,
        MultiPoolHStrategyRebalancer rebalancer_,
        address admin,
        IUniV3Vault[] memory uniV3Vaults_
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

        require(address(pool_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(pool_.token0() == token0_, ExceptionsLibrary.INVARIANT);
        require(pool_.token1() == token1_, ExceptionsLibrary.INVARIANT);

        require(router_ != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(address(rebalancer_) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(admin != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(uniV3Vaults_.length > 0, ExceptionsLibrary.INVALID_LENGTH);

        for (uint256 i = 0; i < uniV3Vaults_.length; ++i) {
            require(address(uniV3Vaults_[i]) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
            require(uniV3Vaults_[i].pool() == pool_);
        }

        token0 = token0_;
        token1 = token1_;
        erc20Vault = erc20Vault_;
        moneyVault = moneyVault_;
        pool = pool_;
        router = router_;
        uniV3Vaults = uniV3Vaults_;
        rebalancer = rebalancer_.createRebalancer(address(this));
    }

    function updateMutableParams(MutableParams memory newParams) external {
        _requireAdmin();

        // TODO: add more checks

        mutableParams = newParams;
    }

    function rebalance() external {
        _requireAdmin();
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
            pool: pool,
            amount0ForMint: mutableParams_.amount0ForMint,
            amount1ForMint: mutableParams_.amount1ForMint,
            router: router,
            erc20CapitalD: mutableParams_.erc20CapitalD,
            uniV3Weights: mutableParams_.uniV3Weights
        });
        (bool newShortInterval, int24 lowerTick, int24 upperTick) = MultiPoolHStrategyRebalancer(rebalancer)
            .processRebalance(data);
        if (newShortInterval) {
            shortInterval = Interval({lowerTick: lowerTick, upperTick: upperTick});
        }
    }

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("MultiPoolHStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }
}
