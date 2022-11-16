// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../libraries/ExceptionsLibrary.sol";

import "../utils/ContractMeta.sol";
import "../utils/DefaultAccessControl.sol";
import "../utils/HStrategyRebalancer.sol";

contract HStrategyV3 is ContractMeta, DefaultAccessControl {
    using SafeERC20 for IERC20;

    address public immutable token0;
    address public immutable token1;
    address public immutable erc20Vault;
    address public immutable moneyVault;
    address public immutable pool;
    address public immutable router;
    HStrategyRebalancer public immutable rebalancer;

    // also immutable
    address[] public uniV3Vaults;

    struct MutableParams {
        int24 halfOfShortInterval;
        int24 domainLowerTick;
        int24 domainUpperTick;
        uint256 amount0ForMint;
        uint256 amount1ForMint;
        uint256 erc20CapitalD;
        uint256[] uniV3Weights;
    }

    struct VolatileParams {
        int24 shortLowerTick;
        int24 shortUpperTick;
    }

    MutableParams public mutableParams;
    VolatileParams public volatileParams;

    constructor(
        address token0_,
        address token1_,
        address erc20Vault_,
        address moneyVault_,
        address pool_,
        address router_,
        address rebalancer_,
        address admin,
        address[] memory uniV3Vaults_
    ) DefaultAccessControl(admin) {
        require(token0_ != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(token1_ != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(erc20Vault_ != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(moneyVault_ != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(pool_ != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(router_ != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(rebalancer_ != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(admin != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(uniV3Vaults_.length > 0, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < uniV3Vaults_.length; ++i) {
            require(uniV3Vaults_[i] != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        }
        token0 = token0_;
        token1 = token1_;
        erc20Vault = erc20Vault_;
        moneyVault = moneyVault_;
        pool = pool_;
        router = router_;
        uniV3Vaults = uniV3Vaults_;
        rebalancer = HStrategyRebalancer(rebalancer_).createRebalancer(address(this));
    }

    function updateMutableParams(MutableParams memory newParams) external {
        _requireAdmin();

        // TODO: add more checks

        mutableParams = newParams;
    }

    function rebalance() external {
        _requireAdmin();
        MutableParams memory mutableParams_ = mutableParams;
        VolatileParams memory volatileParams_ = volatileParams;
        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;
        HStrategyRebalancer.StrategyData memory data = HStrategyRebalancer.StrategyData({
            tokens: tokens,
            uniV3Vaults: uniV3Vaults,
            erc20Vault: erc20Vault,
            moneyVault: moneyVault,
            halfOfShortInterval: mutableParams_.halfOfShortInterval,
            domainLowerTick: mutableParams_.domainLowerTick,
            domainUpperTick: mutableParams_.domainUpperTick,
            shortLowerTick: volatileParams_.shortLowerTick,
            shortUpperTick: volatileParams_.shortUpperTick,
            pool: pool,
            amount0ForMint: mutableParams_.amount0ForMint,
            amount1ForMint: mutableParams_.amount1ForMint,
            router: router,
            erc20CapitalD: mutableParams_.erc20CapitalD,
            uniV3Weights: mutableParams_.uniV3Weights
        });
        (bool newShortInterval, int24 lowerTick, int24 upperTick) = rebalancer.processRebalance(data);
        if (newShortInterval) {
            volatileParams = VolatileParams({shortLowerTick: lowerTick, shortUpperTick: upperTick});
        }
    }

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("HStrategyV3");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }
}
