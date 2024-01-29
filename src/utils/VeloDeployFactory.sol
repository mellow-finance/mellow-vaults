// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

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
import "./VeloFarm.sol";

contract VeloDeployFactory is DefaultAccessControl, IERC721Receiver {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    struct UserInfo {
        address rootVault;
        address farm;
        uint256 farmFee;
        bool isClosed;
        uint256 lpBalance;
        uint256 amount0;
        uint256 amount1;
        address pool;
        uint256 pendingRewards;
    }

    struct VaultInfo {
        IERC20RootVault rootVault;
        IERC20Vault erc20Vault;
        IIntegrationVault[] veloVaults;
        address baseStrategy;
        address operatorStrategy;
        ICLGauge gauge;
        ICLPool pool;
        address farm;
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
        address depositWrapper;
        address baseStrategySingleton;
        address operatorStrategySingleton;
        address farmSingleton;
        address baseStrategyHelper;
        address operator;
    }

    struct InternalParams {
        MellowProtocolAddresses addresses;
        uint256 protocolFeeD9;
        uint256 positionsCount;
        uint128 liquidityCoefficient;
    }

    uint256 public constant Q96 = 2**96;

    ICLFactory public immutable factory;
    ICLGaugeFactory public immutable gaugeFactory;
    INonfungiblePositionManager public immutable positionManager;
    ISwapRouter public immutable swapRouter;

    mapping(int24 => BaseAmmStrategy.MutableParams) public baseDefaultMutableParams;
    mapping(int24 => PulseOperatorStrategy.MutableParams) public operatorDefaultMutableParams;

    mapping(address => address) public poolToVault;
    mapping(address => VaultInfo) public poolToVaultInfo;
    mapping(address => address) public vaultToPool;

    InternalParams public internalParams;

    EnumerableSet.AddressSet private _pools;
    EnumerableSet.AddressSet private _vaults;

    constructor(
        address admin,
        INonfungiblePositionManager positionManager_,
        ISwapRouter swapRouter_,
        ICLFactory factory_,
        ICLGaugeFactory gaugeFactory_
    ) DefaultAccessControl(admin) {
        positionManager = positionManager_;
        swapRouter = swapRouter_;
        factory = factory_;
        gaugeFactory = gaugeFactory_;
    }

    function vaults() external view returns (address[] memory) {
        return _vaults.values();
    }

    function pools() external view returns (address[] memory) {
        return _pools.values();
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
        internalParams = params;
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

    function _combineVaults(
        InternalParams memory params,
        VaultInfo memory info,
        uint256[] memory nfts
    ) private returns (VaultInfo memory) {
        IVaultRegistry vaultRegistry = IVaultRegistry(params.addresses.vaultRegistry);
        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(params.addresses.erc20RootVaultGovernance, nfts[i]);
        }
        uint256 nft;
        (info.rootVault, nft) = IERC20RootVaultGovernance(params.addresses.erc20RootVaultGovernance).createVault(
            info.tokens,
            info.baseStrategy,
            nfts,
            address(this)
        );
        IERC20RootVaultGovernance(params.addresses.erc20RootVaultGovernance).setStrategyParams(
            nft,
            IERC20RootVaultGovernance.StrategyParams({
                tokenLimitPerAddress: type(uint256).max,
                tokenLimit: type(uint256).max
            })
        );
        {
            address[] memory whitelist = new address[](1);
            whitelist[0] = params.addresses.depositWrapper;
            info.rootVault.addDepositorsToAllowlist(whitelist);
        }
        IERC20RootVaultGovernance(params.addresses.erc20RootVaultGovernance).stageDelayedStrategyParams(
            nft,
            IERC20RootVaultGovernance.DelayedStrategyParams({
                strategyTreasury: params.addresses.strategyTreasury,
                strategyPerformanceTreasury: params.addresses.protocolTreasury,
                managementFee: 0,
                performanceFee: 0,
                privateVault: true,
                depositCallbackAddress: address(0),
                withdrawCallbackAddress: address(0)
            })
        );
        IERC20RootVaultGovernance(params.addresses.erc20RootVaultGovernance).commitDelayedStrategyParams(nft);
        return info;
    }

    function _deployVaults(InternalParams memory params, VaultInfo memory info) private returns (VaultInfo memory) {
        IVaultRegistry vaultRegistry = IVaultRegistry(params.addresses.vaultRegistry);

        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;
        IERC20VaultGovernance(params.addresses.erc20VaultGovernance).createVault(info.tokens, address(this));
        info.erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        info.veloVaults = new IIntegrationVault[](params.positionsCount);
        int24 tickSpacing = info.pool.tickSpacing();
        for (uint256 i = 0; i < info.veloVaults.length; i++) {
            IVeloVaultGovernance(params.addresses.veloVaultGovernance).createVault(
                info.tokens,
                address(this),
                tickSpacing
            );
            uint256 nft = erc20VaultNft + 1 + i;
            info.veloVaults[i] = IIntegrationVault(vaultRegistry.vaultForNft(nft));
            IVeloVaultGovernance(params.addresses.veloVaultGovernance).setStrategyParams(
                nft,
                IVeloVaultGovernance.StrategyParams({farm: address(info.farm), gauge: address(info.gauge)})
            );
        }

        {
            uint256[] memory nfts = new uint256[](1 + info.veloVaults.length);
            for (uint256 i = 0; i < nfts.length; i++) {
                nfts[i] = erc20VaultNft + i;
            }
            info = _combineVaults(params, info, nfts);
        }

        VeloFarm(info.farm).initialize(
            address(info.rootVault),
            params.addresses.operator,
            params.addresses.protocolTreasury,
            info.gauge.rewardToken(),
            params.protocolFeeD9
        );

        return info;
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

        BaseAmmStrategy(info.baseStrategy).grantRole(
            BaseAmmStrategy(info.baseStrategy).ADMIN_DELEGATE_ROLE(),
            address(this)
        );
        BaseAmmStrategy(info.baseStrategy).grantRole(
            BaseAmmStrategy(info.baseStrategy).OPERATOR(),
            address(info.operatorStrategy)
        );
        BaseAmmStrategy(info.baseStrategy).grantRole(
            BaseAmmStrategy(info.baseStrategy).ADMIN_ROLE(),
            address(params.addresses.operator)
        );
        BaseAmmStrategy(info.baseStrategy).revokeRole(
            BaseAmmStrategy(info.baseStrategy).ADMIN_DELEGATE_ROLE(),
            address(this)
        );
        BaseAmmStrategy(info.baseStrategy).revokeRole(BaseAmmStrategy(info.baseStrategy).ADMIN_ROLE(), address(this));

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
        PulseOperatorStrategy(info.operatorStrategy).grantRole(
            PulseOperatorStrategy(info.operatorStrategy).ADMIN_DELEGATE_ROLE(),
            address(this)
        );
        PulseOperatorStrategy(info.operatorStrategy).grantRole(
            PulseOperatorStrategy(info.operatorStrategy).OPERATOR(),
            address(params.addresses.operator)
        );
        PulseOperatorStrategy(info.operatorStrategy).grantRole(
            PulseOperatorStrategy(info.operatorStrategy).ADMIN_DELEGATE_ROLE(),
            address(params.addresses.operator)
        );
        PulseOperatorStrategy(info.operatorStrategy).grantRole(
            PulseOperatorStrategy(info.operatorStrategy).ADMIN_ROLE(),
            address(params.addresses.operator)
        );
    }

    function _initialDeposit(InternalParams memory params, VaultInfo memory info) private {
        uint256[] memory tokenAmounts = info.rootVault.pullExistentials();
        for (uint256 i = 0; i < info.tokens.length; i++) {
            tokenAmounts[i] *= 10;
            address token = info.tokens[i];
            if (IERC20(token).allowance(address(this), address(params.addresses.depositWrapper)) == 0) {
                IERC20(token).safeApprove(address(params.addresses.depositWrapper), type(uint256).max);
            }

            uint256 amount = IERC20(token).balanceOf(address(this));
            if (amount < tokenAmounts[i]) {
                IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmounts[i] - amount);
            }
        }

        VeloDepositWrapper(params.addresses.depositWrapper).addNewStrategy(
            address(info.rootVault),
            address(info.farm),
            address(info.baseStrategy),
            false
        );
        VeloDepositWrapper(params.addresses.depositWrapper).deposit(info.rootVault, tokenAmounts, 0, new bytes(0));
        VeloDepositWrapper(params.addresses.depositWrapper).addNewStrategy(
            address(info.rootVault),
            address(info.farm),
            address(info.baseStrategy),
            true
        );
    }

    function _rebalance(InternalParams memory params, VaultInfo memory info) private {
        (uint160 sqrtPriceX96, , , , , ) = info.pool.slot0();
        BaseAmmStrategy.Position[] memory target = new BaseAmmStrategy.Position[](2);
        (BaseAmmStrategy.Position memory newPosition, ) = PulseOperatorStrategy(info.operatorStrategy)
            .calculateExpectedPosition();
        target[0].tickLower = newPosition.tickLower;
        target[0].tickUpper = newPosition.tickUpper;
        target[0].capitalRatioX96 = Q96;

        int24 tickSpacing = info.pool.tickSpacing();
        uint24 fee = factory.tickSpacingToFee(tickSpacing);
        (address tokenIn, address tokenOut, uint256 amountIn, uint256 expectedAmountOut) = BaseAmmStrategyHelper(
            params.addresses.baseStrategyHelper
        ).calculateSwapAmounts(sqrtPriceX96, target, info.rootVault, fee);

        uint256 amountOutMin = (expectedAmountOut * 99) / 100;
        bytes memory data = abi.encodeWithSelector(
            ISwapRouter.exactInputSingle.selector,
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                tickSpacing: tickSpacing,
                amountIn: amountIn,
                deadline: type(uint256).max,
                recipient: address(info.erc20Vault),
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            })
        );

        PulseOperatorStrategy(info.operatorStrategy).rebalance(
            BaseAmmStrategy.SwapData({
                router: address(swapRouter),
                data: data,
                tokenInIndex: tokenIn < tokenOut ? 0 : 1,
                amountIn: amountIn,
                amountOutMin: amountOutMin
            })
        );

        PulseOperatorStrategy(info.operatorStrategy).revokeRole(
            PulseOperatorStrategy(info.operatorStrategy).ADMIN_DELEGATE_ROLE(),
            address(this)
        );
        PulseOperatorStrategy(info.operatorStrategy).revokeRole(
            PulseOperatorStrategy(info.operatorStrategy).ADMIN_ROLE(),
            address(this)
        );
    }

    function createStrategy(
        address token0,
        address token1,
        int24 tickSpacing
    ) external returns (VaultInfo memory info) {
        _requireAtLeastOperator();
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
        InternalParams memory params = internalParams;
        info.baseStrategy = Clones.cloneDeterministic(params.addresses.baseStrategySingleton, salt);
        info.operatorStrategy = Clones.cloneDeterministic(params.addresses.operatorStrategySingleton, salt);
        info.farm = Clones.cloneDeterministic(params.addresses.farmSingleton, salt);
        info.tokens = new address[](2);
        info.tokens[0] = token0;
        info.tokens[1] = token1;
        try ICLGauge(info.gauge).pool() returns (ICLPool pool_) {
            if (pool_ != info.pool) revert("Invalid pool address");
        } catch {
            revert("Gauge not found");
        }
        info = _deployVaults(params, info);
        _initializeStrategies(params, info);
        _initialDeposit(params, info);
        _rebalance(params, info);

        _vaults.add(address(info.rootVault));
        _pools.add(address(info.pool));

        vaultToPool[address(info.rootVault)] = address(info.pool);
        poolToVault[address(info.pool)] = address(info.rootVault);
        poolToVaultInfo[address(info.pool)] = info;
    }

    function getUserInfo(address user) external view returns (UserInfo[] memory userInfos) {
        address[] memory pools_ = _pools.values();
        userInfos = new UserInfo[](pools_.length);
        InternalParams memory params = internalParams;

        uint256 iterator = 0;
        for (uint256 i = 0; i < pools_.length; i++) {
            address pool = pools_[i];
            VaultInfo memory info = poolToVaultInfo[pool];
            UserInfo memory userInfo;
            userInfo.rootVault = address(info.rootVault);
            userInfo.farm = address(info.farm);
            userInfo.farmFee = VeloFarm(info.farm).getStorage().protocolFeeD9;
            {
                userInfo.isClosed = true;
                address[] memory depositorsAllowlist = info.rootVault.depositorsAllowlist();
                for (uint256 j = 0; j < depositorsAllowlist.length; j++) {
                    if (depositorsAllowlist[j] == params.addresses.depositWrapper) {
                        userInfo.isClosed = false;
                        break;
                    }
                }
            }
            userInfo.lpBalance = info.rootVault.balanceOf(user);
            {
                (uint256[] memory tvl, ) = info.rootVault.tvl();
                uint256 totalSupply = info.rootVault.totalSupply();
                require(tvl.length == 2, "Invalid length");
                userInfo.amount0 = FullMath.mulDiv(tvl[0], userInfo.lpBalance, totalSupply);
                userInfo.amount1 = FullMath.mulDiv(tvl[1], userInfo.lpBalance, totalSupply);
            }
            userInfo.pool = address(info.pool);
            userInfo.pendingRewards = VeloFarm(info.farm).rewards(user);

            if (userInfo.amount0 > 0 || userInfo.amount1 > 0 || userInfo.pendingRewards > 0) {
                userInfos[iterator++] = userInfo;
            }
        }

        assembly {
            mstore(userInfos, iterator)
        }
    }
}
