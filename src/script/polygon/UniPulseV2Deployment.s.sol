// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../../src/vaults/ERC20RetroRootVault.sol";
import "../../../src/vaults/ERC20RetroRootVaultGovernance.sol";

import "../../../src/vaults/ERC20Vault.sol";
import "../../../src/vaults/ERC20VaultGovernance.sol";

import "../../../src/vaults/UniV3VaultGovernance.sol";

import {IUniV3Vault, UniV3Vault} from "../../../src/vaults/UniV3Vault.sol";

import "../../../src/strategies/PulseStrategyV2.sol";

import {UniV3Helper} from "../../../src/utils/UniV3RetroHelper.sol";
import "../../../src/utils/DepositWrapper.sol";
import "../../../src/utils/PulseStrategyV2Helper.sol";

import "./Constants.sol";

// import "./PermissionsCheck.sol";

contract Deploy is Script {
    using SafeERC20 for IERC20;

    IERC20RetroRootVault public rootVault;
    IERC20Vault public erc20Vault;
    IUniV3Vault public uniV3Vault;

    PulseStrategyV2 public baseStrategy = PulseStrategyV2(0x2b6CD8d562D9c6De13F026FA833b6bBA0E6384F0);
    PulseStrategyV2Helper public strategyHelper = PulseStrategyV2Helper(0x02Cd1F10252d41b996a31CBcB3cC676F5d89Dd34);

    UniV3Helper public vaultHelper = UniV3Helper(0xC2Ef057b5D99e8cC70073F4be29F6C49c92CAC6b);

    INonfungiblePositionManager public positionManager =
        INonfungiblePositionManager(0x8aAc493fd8C78536eF193882AeffEAA3E0B8b5c5);

    IUniV3VaultGovernance public uniV3VaultGovernance = IUniV3VaultGovernance(Constants.uniV3RetroVaultGovernance);

    IERC20RetroRootVaultGovernance public rootVaultGovernance =
        IERC20RetroRootVaultGovernance(Constants.erc20RetroRootVaultGovernance);

    DepositWrapper public depositWrapper = DepositWrapper(Constants.depositWrapper);

    uint256 public constant Q96 = 2**96;

    function firstDeposit(address strategy, uint256[] memory depositAmounts_) public {
        address[] memory vaultTokens = rootVault.vaultTokens();
        for (uint256 i = 0; i < vaultTokens.length; i++) {
            if (IERC20(vaultTokens[i]).allowance(msg.sender, address(depositWrapper)) == 0) {
                IERC20(vaultTokens[i]).safeIncreaseAllowance(address(depositWrapper), type(uint128).max);
            }
        }

        depositWrapper.addNewStrategy(address(rootVault), address(strategy), false);
        depositWrapper.deposit(IERC20RootVault(address(rootVault)), depositAmounts_, 0, new bytes(0));
        depositWrapper.addNewStrategy(address(rootVault), address(strategy), true);
    }

    function combineVaults(
        address strategy_,
        address[] memory tokens,
        uint256[] memory nfts
    ) public {
        IVaultRegistry vaultRegistry = IVaultRegistry(Constants.registry);
        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(address(rootVaultGovernance), nfts[i]);
        }

        uint256 nft;
        (rootVault, nft) = rootVaultGovernance.createVault(tokens, address(strategy_), nfts, Constants.deployer);
        rootVaultGovernance.setStrategyParams(
            nft,
            IERC20RetroRootVaultGovernance.StrategyParams({
                tokenLimitPerAddress: type(uint256).max,
                tokenLimit: type(uint256).max
            })
        );

        rootVaultGovernance.stageDelayedStrategyParams(
            nft,
            IERC20RetroRootVaultGovernance.DelayedStrategyParams({
                strategyTreasury: Constants.strategyTreasury,
                strategyPerformanceTreasury: Constants.protocolTreasury,
                managementFee: 0,
                performanceFee: 0,
                privateVault: true,
                depositCallbackAddress: address(0),
                withdrawCallbackAddress: address(0)
            })
        );

        address[] memory wl = new address[](1);
        wl[0] = address(Constants.depositWrapper);
        rootVault.addDepositorsToAllowlist(wl);

        rootVaultGovernance.commitDelayedStrategyParams(nft);
    }

    function deployVaults(
        address strategy,
        address[] memory tokens,
        uint24 fee
    ) public {
        IVaultRegistry vaultRegistry = IVaultRegistry(Constants.registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        IERC20VaultGovernance(Constants.erc20Governance).createVault(tokens, Constants.deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        uniV3VaultGovernance.createVault(tokens, Constants.deployer, fee, address(vaultHelper));

        uniV3Vault = IUniV3Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        uniV3VaultGovernance.stageDelayedStrategyParams(
            erc20VaultNft + 1,
            IUniV3VaultGovernance.DelayedStrategyParams({safetyIndicesSet: 2})
        );

        uniV3VaultGovernance.commitDelayedStrategyParams(erc20VaultNft + 1);

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(address(strategy), tokens, nfts);
        }
    }

    function initializeStrategy(
        PulseStrategyV2 strategy,
        PulseStrategyV2.MutableParams memory mutableParams_,
        PulseStrategyV2.DesiredAmounts memory desiredAmounts_
    ) public {
        strategy.initialize(
            PulseStrategyV2.ImmutableParams({
                erc20Vault: erc20Vault,
                uniV3Vault: uniV3Vault,
                router: address(Constants.oneInchRouter),
                tokens: erc20Vault.vaultTokens()
            }),
            Constants.operator
        );
        strategy.updateMutableParams(mutableParams_);
        strategy.updateDesiredAmounts(desiredAmounts_);
        strategy.rebalance(type(uint256).max, new bytes(0), 0);
    }

    function deploySingle(
        address[] memory tokens_,
        uint256[] memory depositAmounts_,
        uint24 fee,
        string memory strategyName_,
        PulseStrategyV2.MutableParams memory mutableParams_,
        PulseStrategyV2.DesiredAmounts memory desiredAmounts_
    ) public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));
        TransparentUpgradeableProxy newStrategy = new TransparentUpgradeableProxy(
            address(baseStrategy),
            Constants.deployer,
            new bytes(0)
        );

        deployVaults(address(newStrategy), tokens_, fee);
        firstDeposit(address(newStrategy), depositAmounts_);

        IERC20(tokens_[0]).safeTransfer(address(newStrategy), desiredAmounts_.amount0Desired * 10);
        IERC20(tokens_[1]).safeTransfer(address(newStrategy), desiredAmounts_.amount1Desired * 10);

        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("OPERATOR_PK"));

        initializeStrategy(PulseStrategyV2(address(newStrategy)), mutableParams_, desiredAmounts_);
        vm.stopBroadcast();

        console2.log(
            strategyName_,
            "(strategy address, root vault address): ",
            address(newStrategy),
            address(rootVault)
        );
        rootVault.tvl();
    }

    address[][] public strategyTokens;
    uint256[][] public depositAmounts;
    uint24[] public fees;
    string[] public names;
    PulseStrategyV2.MutableParams[] public mutableParams;
    PulseStrategyV2.DesiredAmounts[] public desiredAmounts;

    function sort(
        address[2] memory a,
        uint256[2] memory x,
        uint256[2] memory w,
        uint256[2] memory c
    )
        public
        pure
        returns (
            address[] memory b,
            uint256[] memory y,
            uint256[] memory v,
            uint256[] memory d
        )
    {
        b = new address[](2);
        y = new uint256[](2);
        v = new uint256[](2);
        d = new uint256[](2);
        if (a[0] < a[1]) {
            b[0] = a[0];
            b[1] = a[1];
            y[0] = x[0];
            y[1] = x[1];
            v[0] = w[0];
            v[1] = w[1];
            d[0] = c[0];
            d[1] = c[1];
        } else {
            b[0] = a[1];
            b[1] = a[0];
            y[0] = x[1];
            y[1] = x[0];
            v[0] = w[1];
            v[1] = w[0];
            d[0] = c[1];
            d[1] = c[0];
        }
    }

    PulseStrategyV2.MutableParams public volatileParams =
        PulseStrategyV2.MutableParams({
            priceImpactD6: 0,
            defaultIntervalWidth: 4200,
            maxPositionLengthInTicks: 10000,
            maxDeviationForVaultPool: 100,
            timespanForAverageTick: 30,
            neighborhoodFactorD: 150000000,
            extensionFactorD: 2000000000,
            swapSlippageD: 1e7,
            swappingAmountsCoefficientD: 1e7,
            minSwapAmounts: new uint256[](2)
        });

    PulseStrategyV2.MutableParams public stableParams =
        PulseStrategyV2.MutableParams({
            priceImpactD6: 0,
            defaultIntervalWidth: 10,
            maxPositionLengthInTicks: 40,
            maxDeviationForVaultPool: 5,
            timespanForAverageTick: 30,
            neighborhoodFactorD: 150000000,
            extensionFactorD: 2000000000,
            swapSlippageD: 1e7,
            swappingAmountsCoefficientD: 1e7,
            minSwapAmounts: new uint256[](2)
        });

    PulseStrategyV2.MutableParams public lowVolatileParams =
        PulseStrategyV2.MutableParams({
            priceImpactD6: 0,
            defaultIntervalWidth: 2000,
            maxPositionLengthInTicks: 6000,
            maxDeviationForVaultPool: 80,
            timespanForAverageTick: 30,
            neighborhoodFactorD: 150000000,
            extensionFactorD: 2000000000,
            swapSlippageD: 1e7,
            swappingAmountsCoefficientD: 1e7,
            minSwapAmounts: new uint256[](2)
        });

    function setStrategyParams() public {
        if (false) {
            (
                address[] memory tokens,
                uint256[] memory amounts,
                uint256[] memory desiredAmounts_,
                uint256[] memory minSwapAmounts
            ) = sort([Constants.weth, Constants.usdc], [uint256(1e12), 1e4], [uint256(1e9), 1e5], [uint256(1e15), 1e6]);
            volatileParams.minSwapAmounts = minSwapAmounts;
            mutableParams.push(volatileParams);

            strategyTokens.push(tokens);
            depositAmounts.push(amounts);
            fees.push(500);
            names.push("RetroPulse_WETH_USDC_500");

            desiredAmounts.push(
                PulseStrategyV2.DesiredAmounts({amount0Desired: desiredAmounts_[0], amount1Desired: desiredAmounts_[1]})
            );
        }

        if (false) {
            (
                address[] memory tokens,
                uint256[] memory amounts,
                uint256[] memory desiredAmounts_,
                uint256[] memory minSwapAmounts
            ) = sort([Constants.cash, Constants.usdc], [uint256(1e10), 1e6], [uint256(1e9), 1e5], [uint256(1e18), 1e6]);
            stableParams.minSwapAmounts = minSwapAmounts;
            mutableParams.push(stableParams);

            strategyTokens.push(tokens);
            depositAmounts.push(amounts);
            fees.push(100);
            names.push("RetroPulse_CASH_USDC_100");

            desiredAmounts.push(
                PulseStrategyV2.DesiredAmounts({amount0Desired: desiredAmounts_[0], amount1Desired: desiredAmounts_[1]})
            );
        }

        if (false) {
            (
                address[] memory tokens,
                uint256[] memory amounts,
                uint256[] memory desiredAmounts_,
                uint256[] memory minSwapAmounts
            ) = sort([Constants.wbtc, Constants.weth], [uint256(1e5), 1e14], [uint256(1e3), 1e9], [uint256(1e5), 1e15]);
            lowVolatileParams.minSwapAmounts = minSwapAmounts;
            mutableParams.push(lowVolatileParams);

            strategyTokens.push(tokens);
            depositAmounts.push(amounts);
            fees.push(500);
            names.push("RetroPulse_WETH_WBTC_500");

            desiredAmounts.push(
                PulseStrategyV2.DesiredAmounts({amount0Desired: desiredAmounts_[0], amount1Desired: desiredAmounts_[1]})
            );
        }

        if (false) {
            (
                address[] memory tokens,
                uint256[] memory amounts,
                uint256[] memory desiredAmounts_,
                uint256[] memory minSwapAmounts
            ) = sort(
                    [Constants.wmatic, Constants.usdc],
                    [uint256(1e10), 1e4],
                    [uint256(1e9), 1e4],
                    [uint256(1e15), 1e6]
                );
            volatileParams.minSwapAmounts = minSwapAmounts;
            mutableParams.push(volatileParams);

            strategyTokens.push(tokens);
            depositAmounts.push(amounts);
            fees.push(500);
            names.push("RetroPulse_WMATIC_USDC_500");

            desiredAmounts.push(
                PulseStrategyV2.DesiredAmounts({amount0Desired: desiredAmounts_[0], amount1Desired: desiredAmounts_[1]})
            );
        }

        if (false) {
            (
                address[] memory tokens,
                uint256[] memory amounts,
                uint256[] memory desiredAmounts_,
                uint256[] memory minSwapAmounts
            ) = sort([Constants.usdt, Constants.usdc], [uint256(1e4), 1e4], [uint256(1e4), 1e4], [uint256(1e6), 1e6]);
            stableParams.minSwapAmounts = minSwapAmounts;
            mutableParams.push(stableParams);

            strategyTokens.push(tokens);
            depositAmounts.push(amounts);
            fees.push(100);
            names.push("RetroPulse_USDC_USDT_100");

            desiredAmounts.push(
                PulseStrategyV2.DesiredAmounts({amount0Desired: desiredAmounts_[0], amount1Desired: desiredAmounts_[1]})
            );
        }

        if (false) {
            (
                address[] memory tokens,
                uint256[] memory amounts,
                uint256[] memory desiredAmounts_,
                uint256[] memory minSwapAmounts
            ) = sort(
                    [Constants.wmatic, Constants.weth],
                    [uint256(1e10), 1e10],
                    [uint256(1e9), 1e9],
                    [uint256(1e18), 1e15]
                );
            lowVolatileParams.minSwapAmounts = minSwapAmounts;
            mutableParams.push(lowVolatileParams);

            strategyTokens.push(tokens);
            depositAmounts.push(amounts);
            fees.push(500);
            names.push("RetroPulse_WMATIC_WETH_500");

            desiredAmounts.push(
                PulseStrategyV2.DesiredAmounts({amount0Desired: desiredAmounts_[0], amount1Desired: desiredAmounts_[1]})
            );
        }

        if (true) {
            (
                address[] memory tokens,
                uint256[] memory amounts,
                uint256[] memory desiredAmounts_,
                uint256[] memory minSwapAmounts
            ) = sort(
                    [Constants.wmatic, Constants.cash],
                    [uint256(1e10), 1e10],
                    [uint256(1e9), 1e9],
                    [uint256(1e18), 1e18]
                );
            volatileParams.minSwapAmounts = minSwapAmounts;
            mutableParams.push(volatileParams);

            strategyTokens.push(tokens);
            depositAmounts.push(amounts);
            fees.push(500);
            names.push("RetroPulse_WMATIC_CASH_500");

            desiredAmounts.push(
                PulseStrategyV2.DesiredAmounts({amount0Desired: desiredAmounts_[0], amount1Desired: desiredAmounts_[1]})
            );
        }
    }

    function run() external {
        // {
        //     address[] memory tokens = new address[](3);
        //     tokens[0] = Constants.wmatic;
        //     tokens[1] = Constants.cash;
        //     tokens[2] = Constants.usdt;
        //     PermissionsCheck.checkTokens(tokens);
        // }

        setStrategyParams();
        for (uint256 i = 0; i < names.length; i++) {
            address[] memory tokens_ = new address[](2);
            tokens_[0] = strategyTokens[i][0];
            tokens_[1] = strategyTokens[i][1];

            uint256[] memory depositAmounts_ = new uint256[](2);
            depositAmounts_[0] = depositAmounts[i][0];
            depositAmounts_[1] = depositAmounts[i][1];

            uint24 fee = fees[i];
            deploySingle(tokens_, depositAmounts_, fee, names[i], mutableParams[i], desiredAmounts[i]);
        }
    }
}
