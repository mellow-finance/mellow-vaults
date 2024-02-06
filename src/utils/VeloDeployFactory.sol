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

    /// @notice Struct containing information about a vault and its associated contracts.
    /// @param rootVault The address of the ERC20RootVault contract.
    /// @param erc20Vault The address of the ERC20Vault contract.
    /// @param veloVaults An array of VeloVault contracts.
    /// @param baseStrategy The address of the base strategy contract.
    /// @param operatorStrategy The address of the operator strategy contract.
    /// @param gauge The address of the CLGauge contract.
    /// @param pool The address of the CLPool contract.
    /// @param depositWrapper The address of the deposit wrapper contract.
    /// @param tokens An array of token addresses.
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

    /// @notice Struct containing addresses of various contracts within the Mellow protocol.
    /// @param erc20VaultGovernance The address of the ERC20VaultGovernance contract.
    /// @param erc20RootVaultGovernance The address of the ERC20RootVaultGovernance contract.
    /// @param veloVaultGovernance The address of the VeloVaultGovernance contract.
    /// @param protocolGovernance The address of the ProtocolGovernance contract.
    /// @param vaultRegistry The address of the VaultRegistry contract.
    /// @param protocolTreasury The address of the protocol treasury.
    /// @param strategyTreasury The address of the strategy treasury.
    /// @param farmTreasury The address of the farm treasury.
    /// @param veloAdapter The address of the VeloAdapter contract.
    /// @param veloHelper The address of the VeloHelper contract.
    /// @param baseStrategySingleton The address of the base strategy singleton.
    /// @param operatorStrategySingleton The address of the operator strategy singleton.
    /// @param depositWrapperSingleton The address of the deposit wrapper singleton.
    /// @param baseStrategyHelper The address of the BaseAmmStrategyHelper contract.
    /// @param operator The address of the operator, responsible for executing rebalances and parameter updates.
    /// @param proxyAdmin The address of the proxy admin.
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

    /// @notice Struct with internal parameters used within the VeloDeployFactory contract.
    /// @param addresses Addresses of various contracts within the Mellow protocol.
    /// @param protocolFeeD9 Protocol fee in a scaled format (1e9).
    /// @param positionsCount Number of positions that the baseStrategy will manage.
    /// @param liquidityCoefficient approximate measure of the number of positions that can be minted with the funds available in the baseAmmStrategy balance.
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

    /// @dev Helper contract that is used to reduce the contract size by offloading certain functions and logic.
    VeloDeployFactoryHelper public immutable helper;

    /// @dev Mapping to store default mutable parameters for base strategies, keyed by tick spacing.
    mapping(int24 => BaseAmmStrategy.MutableParams) public baseDefaultMutableParams;
    /// @dev Mapping to store default mutable parameters for operator strategies, keyed by tick spacing.
    mapping(int24 => PulseOperatorStrategy.MutableParams) public operatorDefaultMutableParams;

    /// @dev Mapping to associate a pool with its corresponding vault contract.
    mapping(address => address) public poolToVault;
    /// @dev Mapping to store information about vaults linked to specific pools, keyed by pool address.
    mapping(address => VaultInfo) private _poolToVaultInfo;
    /// @dev Mapping to associate a vault with its corresponding pool address.
    mapping(address => address) public vaultToPool;
    /// @dev flag indicating whether the OPERATOR role is required to create new policies.
    bool public operatorFlag;
    /// @dev Struct containing internal parameters used for configuration.
    InternalParams private _internalParams;

    address[] private _pools;
    address[] private _vaults;

    /// @notice Constructor to initialize the VeloDeployFactory contract.
    /// @param admin The address of the admin.
    /// @param positionManager_ The address of the Nonfungible Position Manager contract.
    /// @param factory_ The address of the Velo CLFactory contract.
    /// @param swapRouter_ The address of the Velo SwapRouter contract.
    /// @param gaugeFactory_ The address of the Velo CLGaugeFactory contract.
    /// @param helper_ The address of the VeloDeployFactoryHelper contract.
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

    /// @notice Get an array of addresses representing the deployed vault contracts.
    /// @return array of addresses representing the deployed vault contracts.
    function vaults() external view returns (address[] memory) {
        return _vaults;
    }

    /// @notice Get an array of addresses representing the deployed pool contracts.
    /// @return array of addresses representing the deployed pool contracts.
    function pools() external view returns (address[] memory) {
        return _pools;
    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @notice Update the internal parameters used by the contract.
    /// It can only be called by an address with the ADMIN_ROLE role.
    /// @param params The new internal parameters to be set.
    function updateInternalParams(InternalParams memory params) external {
        _requireAdmin();
        _internalParams = params;
    }

    /// @notice Update the default mutable parameters for the base strategy associated with a specific tick spacing.
    /// It can only be called by an address with the ADMIN_ROLE role.
    /// @param tickSpacing The tick spacing for which to update the default mutable parameters.
    /// @param params The new default mutable parameters to be set.
    function updateBaseDefaultMutableParams(int24 tickSpacing, BaseAmmStrategy.MutableParams memory params) external {
        _requireAdmin();
        baseDefaultMutableParams[tickSpacing] = params;
    }

    /// @notice Update the default mutable parameters for the operator strategy associated with a specific tick spacing.
    /// It can only be called by an address with the ADMIN_ROLE role.
    /// @param tickSpacing The tick spacing for which to update the default mutable parameters.
    /// @param params The new default mutable parameters to be set.
    function updateOperatorDefaultMutableParams(int24 tickSpacing, PulseOperatorStrategy.MutableParams memory params)
        external
    {
        _requireAdmin();
        operatorDefaultMutableParams[tickSpacing] = params;
    }

    /// @notice Set the operator flag.
    /// It can only be called by an address with the ADMIN_ROLE role.
    /// @param flag The boolean flag to set.
    function setOperatorFlag(bool flag) external {
        _requireAdmin();
        operatorFlag = flag;
    }

    /// @notice Initialize the strategies for a newly created vault.
    /// @param params Internal parameters of the VeloDeployFactory contract.
    /// @param info Information about the newly created ERC20RootVault.
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

    /// @notice Creates a new strategy for a given pair of tokens and tick spacing.
    /// If operatorFlag is set, only an address with ADMIN_ROLE or OPERATOR roles can call this function.
    /// Otherwise, any address can call this function.
    /// @param token0 The address of the first token.
    /// @param token1 The address of the second token.
    /// @param tickSpacing The tick spacing for the CLPool.
    /// @return info Information about the newly created ERC20RootVault.
    /// @notice To successfully execute this function, the deploy factory must hold a sufficient balance of token0 and token1
    /// to create a position with liquidity equal to initialLiquidity * liquidityCoefficient and a width of 2 * positionWidth.
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

    /// @notice Get information about a vault associated with a specific CLPool.
    /// @param pool The address of the CLPool.
    /// @return info Information about the associated vault.
    function getVaultInfoByPool(address pool) external view returns (VaultInfo memory) {
        return _poolToVaultInfo[pool];
    }

    /// @notice Get the internal parameters of the VeloDeployFactory contract.
    /// @return params The internal parameters.
    function getInternalParams() external view returns (InternalParams memory) {
        return _internalParams;
    }
}
