// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import {IVault as IBalancerVault, IAsset, IERC20 as IBalancerERC20} from "../../../src/interfaces/external/balancer/vault/IVault.sol";
import {IBasePool} from "../../../src/interfaces/external/balancer/vault/IBasePool.sol";

import "../../../src/vaults/AuraVaultGovernance.sol";
import "../../../src/vaults/ERC20RootVaultGovernance.sol";
import "../../../src/vaults/ERC20VaultGovernance.sol";

import "../../../src/vaults/AuraVault.sol";
import "../../../src/vaults/ERC20RootVault.sol";
import "../../../src/vaults/ERC20Vault.sol";

import "../../../src/utils/DepositWrapper.sol";

import "../../../src/strategies/SingleVaultStrategy.sol";

import {AuraOracle} from "../../../src/oracles/AuraOracle.sol";

contract AuraVaultTest is Test {
    IBalancerVault public vault = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    address public constant AURA = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant GHO = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;

    address public constant GHO_LUSD_POOL = 0x3FA8C89704e5d07565444009e5d9e624B40Be813;

    address public sAdmin = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;
    address public protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address public strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address public admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;

    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public rootGovernance = 0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public mellowOracle = 0x9d992650B30C6FB7a83E7e7a430b4e015433b838;

    IAuraVaultGovernance public auraVaultGovernance;
    IERC20RootVaultGovernance public rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);
    DepositWrapper public depositWrapper = DepositWrapper(0x231002439E1BD5b610C3d98321EA760002b9Ff64);

    uint256 public constant Q96 = 2 ** 96;

    IERC20RootVault rootVault;
    IERC20Vault erc20Vault;
    IAuraVault auraVault;
    SingleVaultStrategy strategy;

    function withdraw() public returns (uint256[] memory amounts) {
        vm.startPrank(deployer);
        uint256 lpAmount = rootVault.balanceOf(deployer) / 2;
        amounts = rootVault.withdraw(deployer, lpAmount, new uint256[](2), new bytes[](2));
        vm.stopPrank();
    }

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(address(rootVaultGovernance), nfts[i]);
        }

        uint256 nft;
        (rootVault, nft) = rootVaultGovernance.createVault(tokens, address(strategy), nfts, deployer);
        rootVaultGovernance.setStrategyParams(
            nft,
            IERC20RootVaultGovernance.StrategyParams({
                tokenLimitPerAddress: type(uint256).max,
                tokenLimit: type(uint256).max
            })
        );

        rootVaultGovernance.stageDelayedStrategyParams(
            nft,
            IERC20RootVaultGovernance.DelayedStrategyParams({
                strategyTreasury: strategyTreasury,
                strategyPerformanceTreasury: protocolTreasury,
                managementFee: 0,
                performanceFee: 0,
                privateVault: true,
                depositCallbackAddress: address(0),
                withdrawCallbackAddress: address(0)
            })
        );

        address[] memory wl = new address[](1);
        wl[0] = address(depositWrapper);
        rootVault.addDepositorsToAllowlist(wl);
        rootVaultGovernance.commitDelayedStrategyParams(nft);
    }

    function deployVaults() public {
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = GHO;
        tokens[1] = LUSD;
        vm.startPrank(deployer);
        IERC20VaultGovernance(erc20Governance).createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        IAuraVaultGovernance(auraVaultGovernance).createVault(
            tokens,
            deployer,
            GHO_LUSD_POOL,
            0xBA12222222228d8Ba445958a75a0704d566BF2C8,
            0xA57b8d98dAE62B26Ec3bcC4a365338157060B234,
            0x9305F7B6017c08BB71004A85fd78Adf3E32ce5CE
        );

        auraVault = IAuraVault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        IAuraVaultGovernance.SwapParams[] memory swapParams = new IAuraVaultGovernance.SwapParams[](2);
        {
            IBalancerVault.BatchSwapStep[] memory swaps = new IBalancerVault.BatchSwapStep[](3);
            swaps[0] = IBalancerVault.BatchSwapStep({
                poolId: IBasePool(0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56).getPoolId(),
                assetInIndex: 0,
                assetOutIndex: 1,
                amount: 0,
                userData: new bytes(0)
            });
            swaps[1] = IBalancerVault.BatchSwapStep({
                poolId: IBasePool(0x32296969Ef14EB0c6d29669C550D4a0449130230).getPoolId(),
                assetInIndex: 1,
                assetOutIndex: 2,
                amount: 0,
                userData: new bytes(0)
            });
            swaps[2] = IBalancerVault.BatchSwapStep({
                poolId: IBasePool(0x7D98f308Db99FDD04BbF4217a4be8809F38fAa64).getPoolId(),
                assetInIndex: 2,
                assetOutIndex: 3,
                amount: 0,
                userData: new bytes(0)
            });

            IAsset[] memory assets = new IAsset[](4);
            assets[0] = IAsset(BAL);
            assets[1] = IAsset(WETH);
            assets[2] = IAsset(WSTETH);
            assets[3] = IAsset(GHO);

            IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
                sender: address(auraVault),
                fromInternalBalance: false,
                recipient: payable(address(erc20Vault)),
                toInternalBalance: false
            });
            IAggregatorV3 rewardOracle = IAggregatorV3(0xdF2917806E30300537aEB49A7663062F4d1F2b5F);
            IAggregatorV3 underlyingOracle = IAggregatorV3(0x3f12643D3f6f874d39C2a4c9f2Cd6f2DbAC877FC);
            uint256 slippageD = 1e8;
            swapParams[0] = IAuraVaultGovernance.SwapParams({
                swaps: swaps,
                assets: assets,
                funds: funds,
                rewardOracle: rewardOracle,
                underlyingOracle: underlyingOracle,
                slippageD: slippageD
            });
        }

        {
            IBalancerVault.BatchSwapStep[] memory swaps = new IBalancerVault.BatchSwapStep[](3);
            swaps[0] = IBalancerVault.BatchSwapStep({
                poolId: IBasePool(0xCfCA23cA9CA720B6E98E3Eb9B6aa0fFC4a5C08B9).getPoolId(),
                assetInIndex: 0,
                assetOutIndex: 1,
                amount: 0,
                userData: new bytes(0)
            });
            swaps[1] = IBalancerVault.BatchSwapStep({
                poolId: IBasePool(0x32296969Ef14EB0c6d29669C550D4a0449130230).getPoolId(),
                assetInIndex: 1,
                assetOutIndex: 2,
                amount: 0,
                userData: new bytes(0)
            });
            swaps[2] = IBalancerVault.BatchSwapStep({
                poolId: IBasePool(0x7D98f308Db99FDD04BbF4217a4be8809F38fAa64).getPoolId(),
                assetInIndex: 2,
                assetOutIndex: 3,
                amount: 0,
                userData: new bytes(0)
            });

            IAsset[] memory assets = new IAsset[](4);
            assets[0] = IAsset(AURA);
            assets[1] = IAsset(WETH);
            assets[2] = IAsset(WSTETH);
            assets[3] = IAsset(GHO);

            IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
                sender: address(auraVault),
                fromInternalBalance: false,
                recipient: payable(address(erc20Vault)),
                toInternalBalance: false
            });

            IAggregatorV3 rewardOracle = IAggregatorV3(new AuraOracle());
            IAggregatorV3 underlyingOracle = IAggregatorV3(0x3f12643D3f6f874d39C2a4c9f2Cd6f2DbAC877FC);
            uint256 slippageD = 1e8;
            swapParams[1] = IAuraVaultGovernance.SwapParams({
                swaps: swaps,
                assets: assets,
                funds: funds,
                rewardOracle: rewardOracle,
                underlyingOracle: underlyingOracle,
                slippageD: slippageD
            });
        }

        IAuraVaultGovernance.StrategyParams memory strategyParams = IAuraVaultGovernance.StrategyParams(swapParams);

        auraVaultGovernance.setStrategyParams(auraVault.nft(), strategyParams);
        strategy = new SingleVaultStrategy(erc20Vault, address(auraVault));

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }

        vm.stopPrank();
    }

    function deployGovernances() public {
        auraVaultGovernance = new AuraVaultGovernance(
            IVaultGovernance.InternalParams({
                protocolGovernance: IProtocolGovernance(governance),
                registry: IVaultRegistry(registry),
                singleton: IVault(address(new AuraVault()))
            })
        );

        vm.startPrank(admin);
        IProtocolGovernance(governance).stagePermissionGrants(address(auraVaultGovernance), new uint8[](1));

        uint8[] memory permissions = new uint8[](2);
        permissions[0] = 2;
        permissions[1] = 3;

        IProtocolGovernance(governance).stagePermissionGrants(address(LUSD), permissions);
        IProtocolGovernance(governance).stageValidator(address(LUSD), 0xf7A19974dC36E1Ad9A74e967B0Bc9B24e0f4C4b3);
        IProtocolGovernance(governance).stageUnitPrice(address(LUSD), 1e18);

        skip(24 * 3600);

        IProtocolGovernance(governance).commitAllPermissionGrantsSurpassedDelay();
        IProtocolGovernance(governance).commitAllValidatorsSurpassedDelay();
        IProtocolGovernance(governance).commitUnitPrice(address(LUSD));
        IProtocolGovernance(governance).commitUnitPrice(address(GHO));

        vm.stopPrank();
    }

    function deposit() public {
        (, uint256[] memory tvl) = rootVault.tvl();

        if (tvl[0] == 0) {
            tvl = new uint256[](2);
            tvl[0] = 1e10 * 76;
            tvl[1] = 1e10 * 23;
        } else {
            tvl[0] *= 10;
            tvl[1] *= 10;
            tvl[0] /= 3;
            tvl[1] /= 3;
        }

        deal(GHO, deployer, tvl[0]);
        deal(LUSD, deployer, tvl[1]);

        vm.startPrank(deployer);
        IERC20(LUSD).approve(address(depositWrapper), type(uint256).max);
        IERC20(GHO).approve(address(depositWrapper), type(uint256).max);

        depositWrapper.addNewStrategy(address(rootVault), address(strategy), true);
        depositWrapper.deposit(rootVault, tvl, 0, new bytes(0));

        vm.stopPrank();
    }

    function test() external {
        deployGovernances();
        deployVaults();
        deposit();
        deposit();
        deposit();
        deposit();
        (uint256[] memory tvlBeforeClaim, ) = rootVault.tvl();
        auraVault.claimRewards();
        (uint256[] memory tvlAfterClaim, ) = rootVault.tvl();
        uint256[] memory withdrawedAmount = withdraw();
        (uint256[] memory tvlAfterWithdraw, ) = rootVault.tvl();
        console2.log("tvlBeforeClaim: ", tvlBeforeClaim[0], tvlBeforeClaim[1]);
        console2.log("tvlAfterClaim: ", tvlAfterClaim[0], tvlAfterClaim[1]);
        console2.log("tvlAfterWithdraw: ", tvlAfterWithdraw[0], tvlAfterWithdraw[1]);
        console2.log("withdrawedAmount: ", withdrawedAmount[0], withdrawedAmount[1]);

        // skip(60 * 10);
        deal(AURA, address(auraVault), 1e18 * 1000);
        deal(BAL, address(auraVault), 1e18 * 1000);

        auraVault.claimRewards();
        withdraw();
    }
}
