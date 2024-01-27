// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

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

import "./VeloFarm.sol";

import "./DefaultAccessControl.sol";

contract VeloDeployFactory is DefaultAccessControl {
    struct UserInfo {
        address rootVault;
        address farm;
        uint256 lpBalance;
        uint256 amount0;
        uint256 amount1;
        address pool;
        uint256 pendingRewards;
    }

    struct VaultInfo {
        IERC20RootVault rootVault;
        IERC20Vault erc20Vault;
        IVeloVault[] veloVaults;
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
    }

    INonfungiblePositionManager public immutable positionManager;
    ISwapRouter public immutable swapRouter;
    ICLFactory public immutable factory;
    ICLGaugeFactory public immutable gaugeFactory;

    mapping(address => address) public vaultForPool;

    InternalParams public internalParams;

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

        info.veloVaults = new IVeloVault[](params.positionsCount);
        int24 tickSpacing = info.pool.tickSpacing();
        for (uint256 i = 0; i < info.veloVaults.length; i++) {
            IVeloVaultGovernance(params.addresses.veloVaultGovernance).createVault(
                info.tokens,
                address(this),
                tickSpacing
            );
            info.veloVaults[i] = IVeloVault(vaultRegistry.vaultForNft(erc20VaultNft + 1));
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
            info.gauge.rewardToken(),
            params.addresses.protocolTreasury,
            params.protocolFeeD9
        );

        // vm.stopPrank();
        // vm.startPrank(protocolAdmin);

        // ammGovernance.setStrategyParams(
        //     erc20VaultNft + 1,
        //     IVeloVaultGovernance.StrategyParams({farm: address(farm), gauge: address(gauge)})
        // );
        // ammGovernance.setStrategyParams(
        //     erc20VaultNft + 2,
        //     IVeloVaultGovernance.StrategyParams({farm: address(farm), gauge: address(gauge)})
        // );

        // vm.stopPrank();
        // vm.startPrank(deployer);

        return info;
    }

    // function _initializeBaseStrategy() public {
    //     uint256[] memory minSwapAmounts = new uint256[](2);
    //     minSwapAmounts[0] = 1e9;
    //     minSwapAmounts[1] = 1e3;

    //     IIntegrationVault[] memory ammVaults = new IIntegrationVault[](2);
    //     ammVaults[0] = ammVault1;
    //     ammVaults[1] = ammVault2;

    //     strategy.initialize(
    //         deployer,
    //         BaseAmmStrategy.ImmutableParams({
    //             erc20Vault: erc20Vault,
    //             ammVaults: ammVaults,
    //             adapter: adapter,
    //             pool: address(ammVault1.pool())
    //         }),
    //         BaseAmmStrategy.MutableParams({
    //             securityParams: new bytes(0),
    //             maxPriceSlippageX96: (2 * Q96) / 100,
    //             maxTickDeviation: 50,
    //             minCapitalRatioDeviationX96: Q96 / 100,
    //             minSwapAmounts: minSwapAmounts,
    //             maxCapitalRemainderRatioX96: Q96 / 50,
    //             initialLiquidity: 1e9
    //         })
    //     );
    // }

    // function _deposit(IERC20RootVault rootVault, uint256[] memory tokenAmounts) public {
    //     for (uint256 i = 0; i < tokens.length; i++) {
    //         if (IERC20(tokens[i]).allowance(address(this), address(depositWrapper)) == 0) {
    //             IERC20(tokens[i]).approve(address(depositWrapper), type(uint256).max);
    //         }
    //     }
    //     depositWrapper.addNewStrategy(address(rootVault), address(farm), address(strategy), false);
    //     depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));
    //     depositWrapper.addNewStrategy(address(rootVault), address(farm), address(strategy), true);
    // }

    // function _initializeOperatorStrategy(int24 maxWidth) public {
    //     operatorStrategy.initialize(
    //         PulseOperatorStrategy.ImmutableParams({strategy: strategy, tickSpacing: pool.tickSpacing()}),
    //         PulseOperatorStrategy.MutableParams({
    //             positionWidth: 200,
    //             maxPositionWidth: maxWidth,
    //             extensionFactorD: 1e9,
    //             neighborhoodFactorD: 1e8
    //         }),
    //         deployer
    //     );
    //     strategy.grantRole(strategy.ADMIN_DELEGATE_ROLE(), address(deployer));
    //     strategy.grantRole(strategy.OPERATOR(), address(operatorStrategy));

    //     deal(usdc, address(strategy), 1e7);
    //     deal(weth, address(strategy), 1e16);
    // }

    // function _rebalance() public {
    //     (uint160 sqrtPriceX96, , , , , ) = pool.slot0();
    //     BaseAmmStrategy.Position[] memory target = new BaseAmmStrategy.Position[](2);
    //     (BaseAmmStrategy.Position memory newPosition, ) = operatorStrategy.calculateExpectedPosition();
    //     target[0].tickLower = newPosition.tickLower;
    //     target[0].tickUpper = newPosition.tickUpper;
    //     target[0].capitalRatioX96 = Q96;
    //     (address tokenIn, address tokenOut, uint256 amountIn, uint256 expectedAmountOut) = baseAmmStrategyHelper
    //         .calculateSwapAmounts(sqrtPriceX96, target, rootVault, 3000);
    //     uint256 amountOutMin = (expectedAmountOut * 99) / 100;
    //     bytes memory data = abi.encodeWithSelector(
    //         ISwapRouter.exactInputSingle.selector,
    //         ISwapRouter.ExactInputSingleParams({
    //             tokenIn: tokenIn,
    //             tokenOut: tokenOut,
    //             tickSpacing: TICK_SPACING,
    //             amountIn: amountIn,
    //             deadline: type(uint256).max,
    //             recipient: address(erc20Vault),
    //             amountOutMinimum: amountOutMin,
    //             sqrtPriceLimitX96: 0
    //         })
    //     );

    //     operatorStrategy.rebalance(
    //         BaseAmmStrategy.SwapData({
    //             router: address(swapRouter),
    //             data: data,
    //             tokenInIndex: tokenIn < tokenOut ? 0 : 1,
    //             amountIn: amountIn,
    //             amountOutMin: amountOutMin
    //         })
    //     );
    // }

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
            address vault = vaultForPool[address(info.pool)];
            if (vault != address(0)) revert(string(abi.encodePacked("Vault already exists:", vault)));
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
            if (pool_ != info.pool) revert("Invalid pool address"); // impossible scenario, but just in case
        } catch {
            revert("Gauge not found");
        }
        info = _deployVaults(params, info);
    }

    function getUserInfo(address user) public view returns (UserInfo[] memory info) {}
}
