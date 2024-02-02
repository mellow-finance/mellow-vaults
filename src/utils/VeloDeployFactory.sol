// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../interfaces/vaults/IERC20RootVault.sol";
import "../interfaces/vaults/IERC20RootVaultGovernance.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IERC20VaultGovernance.sol";
import "../interfaces/vaults/IVeloVault.sol";
import "../interfaces/vaults/IVeloVaultGovernance.sol";
import "../interfaces/external/velo/ICLPool.sol";
import "../interfaces/external/velo/ICLFactory.sol";
import "../interfaces/external/velo/ICLGauge.sol";
import "../interfaces/external/velo/ICLGaugeFactory.sol";
import "../interfaces/external/velo/INonfungiblePositionManager.sol";
import "../interfaces/external/velo/ISwapRouter.sol";

import "../strategies/BaseAmmStrategy.sol";
import "../strategies/PulseOperatorStrategy.sol";

import "./BaseAmmStrategyHelper.sol";
import "./DefaultAccessControl.sol";
import "./VeloDepositWrapper.sol";
import "./VeloDeployFactoryHelper.sol";

contract VeloDeployFactory is DefaultAccessControl, IERC721Receiver {
    using SafeERC20 for IERC20;

    struct VaultInfo {
        IERC20RootVault rootVault;
        IERC20Vault erc20Vault;
        IIntegrationVault[] veloVaults;
        address baseStrategy;
        address operatorStrategy;
        ICLGauge gauge;
        ICLPool pool;
        address depositWrapper;
        address[] tokens;
    }

    struct MellowProtocolAddresses {
        address erc20VaultGovernance;
        address erc20RootVaultGovernance;
        address veloVaultGovernance;
        address protocolGovernance;
        address vaultRegistry;
        address protocolTreasury;
        address strategyTreasury;
        address farmTreasury;
        address veloAdapter;
        address veloHelper;
        address baseStrategySingleton;
        address operatorStrategySingleton;
        address depositWrapperSingleton;
        address baseStrategyHelper;
        address operator;
        address proxyAdmin;
    }

    struct InternalParams {
        MellowProtocolAddresses addresses;
        uint256 protocolFeeD9;
        uint256 positionsCount;
        uint128 liquidityCoefficient;
    }

    uint256 public constant Q96 = 2**96;

    ICLFactory public immutable factory;
    ISwapRouter public immutable swapRouter;
    ICLGaugeFactory public immutable gaugeFactory;
    INonfungiblePositionManager public immutable positionManager;
    VeloDeployFactoryHelper public immutable helper;

    mapping(int24 => BaseAmmStrategy.MutableParams) public baseDefaultMutableParams;
    mapping(int24 => PulseOperatorStrategy.MutableParams) public operatorDefaultMutableParams;

    mapping(address => address) public poolToVault;
    mapping(address => VaultInfo) private _poolToVaultInfo;
    mapping(address => address) public vaultToPool;

    bool public operatorFlag;

    InternalParams private _internalParams;

    address[] private _pools;
    address[] private _vaults;

    constructor(
        address admin,
        INonfungiblePositionManager positionManager_,
        ICLFactory factory_,
        ISwapRouter swapRouter_,
        ICLGaugeFactory gaugeFactory_,
        VeloDeployFactoryHelper helper_
    ) DefaultAccessControl(admin) {
        positionManager = positionManager_;
        factory = factory_;
        swapRouter = swapRouter_;
        gaugeFactory = gaugeFactory_;
        helper = helper_;
        operatorFlag = true;
    }

    function vaults() external view returns (address[] memory) {
        return _vaults;
    }

    function pools() external view returns (address[] memory) {
        return _pools;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function updateInternalParams(InternalParams memory params) external {
        _requireAdmin();
        _internalParams = params;
    }

    function updateBaseDefaultMutableParams(int24 tickSpacing, BaseAmmStrategy.MutableParams memory params) external {
        _requireAdmin();
        baseDefaultMutableParams[tickSpacing] = params;
    }

    function updateOperatorDefaultMutableParams(int24 tickSpacing, PulseOperatorStrategy.MutableParams memory params)
        external
    {
        _requireAdmin();
        operatorDefaultMutableParams[tickSpacing] = params;
    }

    function setOperatorFlag(bool flag) external {
        _requireAdmin();
        operatorFlag = flag;
    }

    function _initializeStrategies(InternalParams memory params, VaultInfo memory info) private {
        int24 tickSpacing = info.pool.tickSpacing();
        BaseAmmStrategy.MutableParams memory baseMutableParams = baseDefaultMutableParams[tickSpacing];
        PulseOperatorStrategy.MutableParams memory operatorMutableParams = operatorDefaultMutableParams[tickSpacing];
        BaseAmmStrategy(info.baseStrategy).initialize(
            address(this),
            BaseAmmStrategy.ImmutableParams({
                erc20Vault: info.erc20Vault,
                ammVaults: info.veloVaults,
                adapter: IAdapter(params.addresses.veloAdapter),
                pool: address(info.pool)
            }),
            baseMutableParams
        );

        BaseAmmStrategy(info.baseStrategy).grantRole(ADMIN_DELEGATE_ROLE, address(this));
        BaseAmmStrategy(info.baseStrategy).grantRole(OPERATOR, address(info.operatorStrategy));
        BaseAmmStrategy(info.baseStrategy).grantRole(ADMIN_ROLE, address(params.addresses.operator));
        BaseAmmStrategy(info.baseStrategy).revokeRole(ADMIN_DELEGATE_ROLE, address(this));
        BaseAmmStrategy(info.baseStrategy).revokeRole(ADMIN_ROLE, address(this));

        (uint160 sqrtRatioX96, int24 spotTick, , , , ) = info.pool.slot0();
        uint256[] memory tokenAmounts = new uint256[](2);
        (tokenAmounts[0], tokenAmounts[1]) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(spotTick - operatorMutableParams.positionWidth),
            TickMath.getSqrtRatioAtTick(spotTick + operatorMutableParams.positionWidth),
            baseMutableParams.initialLiquidity * params.liquidityCoefficient
        );

        for (uint256 i = 0; i < info.tokens.length; i++) {
            address token = info.tokens[i];
            uint256 amount = IERC20(token).balanceOf(address(this));
            if (amount < tokenAmounts[i]) {
                IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmounts[i] - amount);
            }
            IERC20(token).safeTransfer(info.baseStrategy, tokenAmounts[i]);
        }

        PulseOperatorStrategy(info.operatorStrategy).initialize(
            PulseOperatorStrategy.ImmutableParams({
                strategy: BaseAmmStrategy(info.baseStrategy),
                tickSpacing: tickSpacing
            }),
            operatorMutableParams,
            address(this)
        );
        PulseOperatorStrategy(info.operatorStrategy).grantRole(ADMIN_DELEGATE_ROLE, address(this));
        PulseOperatorStrategy(info.operatorStrategy).grantRole(ADMIN_ROLE, address(params.addresses.operator));
    }

    function createStrategy(
        address token0,
        address token1,
        int24 tickSpacing
    ) external returns (VaultInfo memory info) {
        if (operatorFlag) {
            _requireAtLeastOperator();
        }
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }
        info.pool = ICLPool(factory.getPool(token0, token1, tickSpacing));
        if (address(info.pool) == address(0)) revert("Pool not found");
        {
            address vault = poolToVault[address(info.pool)];
            if (vault != address(0)) {
                revert(string(abi.encodePacked("Vault already exists:", vault)));
            }
        }
        bytes32 salt = keccak256(abi.encode(token0, token1, tickSpacing));
        info.gauge = ICLGauge(
            Clones.predictDeterministicAddress(gaugeFactory.implementation(), salt, address(gaugeFactory))
        );

        InternalParams memory params = _internalParams;
        info.baseStrategy = address(
            new TransparentUpgradeableProxy(params.addresses.baseStrategySingleton, params.addresses.proxyAdmin, "")
        );
        info.operatorStrategy = address(
            new TransparentUpgradeableProxy(params.addresses.operatorStrategySingleton, params.addresses.proxyAdmin, "")
        );
        info.depositWrapper = address(
            new TransparentUpgradeableProxy(params.addresses.depositWrapperSingleton, params.addresses.proxyAdmin, "")
        );

        info.tokens = new address[](2);
        info.tokens[0] = token0;
        info.tokens[1] = token1;
        try ICLGauge(info.gauge).pool() returns (ICLPool pool_) {
            if (pool_ != info.pool) revert("Invalid pool address");
        } catch {
            revert("Gauge not found");
        }
        {
            (bool success, bytes memory data) = address(helper).delegatecall(
                abi.encodeWithSelector(helper.deployVaults.selector, params, info)
            );
            require(success, ExceptionsLibrary.INVALID_STATE);
            info = abi.decode(data, (VaultInfo));
        }
        _vaults.push(address(info.rootVault));
        _pools.push(address(info.pool));

        vaultToPool[address(info.rootVault)] = address(info.pool);
        poolToVault[address(info.pool)] = address(info.rootVault);
        _poolToVaultInfo[address(info.pool)] = info;

        _initializeStrategies(params, info);
        {
            (bool success, ) = address(helper).delegatecall(
                abi.encodeWithSelector(helper.initialDeposit.selector, info)
            );
            require(success, ExceptionsLibrary.INVALID_STATE);
        }
        {
            (bool success, ) = address(helper).delegatecall(
                abi.encodeWithSelector(helper.rebalance.selector, params, info)
            );
            require(success, ExceptionsLibrary.INVALID_STATE);
        }
    }

    function getVaultInfoByPool(address pool) external view returns (VaultInfo memory) {
        return _poolToVaultInfo[pool];
    }

    function getInternalParams() external view returns (InternalParams memory) {
        return _internalParams;
    }
}
