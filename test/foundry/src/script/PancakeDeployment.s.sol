// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "forge-std/Script.sol";

import "../ProtocolGovernance.sol";
import "../VaultRegistry.sol";
import "../ERC20RootVaultHelper.sol";
import "../MockOracle.sol";

import "../vaults/GearboxVault.sol";
import "../vaults/GearboxRootVault.sol";
import "../vaults/ERC20Vault.sol";
import "../vaults/UniV3Vault.sol";

import "../utils/UniV3Helper.sol";
import "../utils/DepositWrapper.sol";

import "../vaults/UniV3VaultGovernance.sol";
import "../vaults/ERC20VaultGovernance.sol";
import "../vaults/ERC20RootVaultGovernance.sol";

import "../strategies/PulseStrategyV2.sol";


contract PancakeDeployment is Script {

    IERC20RootVault public rootVault;
    IERC20Vault erc20Vault;
    IUniV3Vault uniV3Vault;

    PulseStrategyV2 strategy;
    uint256 nftStart;

    address sAdmin = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;
    address protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address public usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public rootGovernance = 0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public uniV3Governance = 0xC2A195439ea4E88A7032c03B89f81e97FA200108;
    address public mellowOracle = 0x9d992650B30C6FB7a83E7e7a430b4e015433b838;

    address public manager = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;

    IERC20RootVaultGovernance rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(address(rootVaultGovernance), nfts[i]);
        }

        (IERC20RootVault w, uint256 nft) = rootVaultGovernance.createVault(tokens, address(strategy), nfts, deployer);
        rootVault = w;

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
                privateVault: false,
                depositCallbackAddress: address(0),
                withdrawCallbackAddress: address(0)
            })
        );

        rootVaultGovernance.commitDelayedStrategyParams(nft);
    }

    function kek() public payable returns (uint256 startNft) {

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = usdt;

        /*

        {
            UniV3Vault singleton = new UniV3Vault();
            IVaultGovernance.InternalParams memory ip = IVaultGovernance.InternalParams({
                protocolGovernance: IProtocolGovernance(governance),
                registry: IVaultRegistry(registry),
                singleton: singleton
            });
            
            
            IUniV3VaultGovernance.DelayedProtocolParams memory dpp = IUniV3VaultGovernance.DelayedProtocolParams({
                positionManager: INonfungiblePositionManager(manager),
                oracle: IOracle(mellowOracle)
            });

            IUniV3VaultGovernance gg = new UniV3VaultGovernance(ip, dpp);
            console2.log("uni governance for sushi:", address(gg));
            return 0;

        }

        */

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, deployer);
        }

        UniV3Helper helper = new UniV3Helper(INonfungiblePositionManager(manager));

        {
            IUniV3VaultGovernance uniGovernance = IUniV3VaultGovernance(uniV3Governance);
            uniGovernance.createVault(tokens, deployer, 500, address(helper));

            IUniV3VaultGovernance.DelayedStrategyParams memory dsp = IUniV3VaultGovernance.DelayedStrategyParams({
                safetyIndicesSet: 2
            });

            uniGovernance.stageDelayedStrategyParams(erc20VaultNft + 1, dsp);
            uniGovernance.commitDelayedStrategyParams(erc20VaultNft + 1);

        }

        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));
        uniV3Vault = IUniV3Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

       // PulseStrategyV2 protoS = new PulseStrategyV2(INonfungiblePositionManager(manager));
       // TransparentUpgradeableProxy kek = new TransparentUpgradeableProxy(address(protoS), sAdmin, "");
       
        strategy = new PulseStrategyV2(INonfungiblePositionManager(manager));

        PulseStrategyV2.ImmutableParams memory sParams = PulseStrategyV2.ImmutableParams({
            erc20Vault: erc20Vault,
            uniV3Vault: uniV3Vault,
            router: 0x1111111254EEB25477B68fb85Ed929f73A960582,
            tokens: tokens
        });

        uint256[] memory AA = new uint256[](2);
        AA[0] = 10**12;
        AA[1] = 10**12;

        PulseStrategyV2.MutableParams memory smParams = PulseStrategyV2.MutableParams({
            priceImpactD6: 0,
            defaultIntervalWidth: 5000,
            maxPositionLengthInTicks: 15000,
            maxDeviationForVaultPool: 50,
            timespanForAverageTick: 300,
            neighborhoodFactorD: 10 ** 7 * 15,
            extensionFactorD: 10 ** 7 * 175,
            swapSlippageD: 10 ** 7,
            swappingAmountsCoefficientD: 10 ** 7,
            minSwapAmounts: AA
        });

        PulseStrategyV2.DesiredAmounts memory kekK = PulseStrategyV2.DesiredAmounts({
            amount0Desired: 10**9,
            amount1Desired: 10**9
        });

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }

        strategy.initialize(sParams, deployer);
        strategy.updateMutableParams(smParams);
        strategy.updateDesiredAmounts(kekK);

        IVaultRegistry(registry).transferFrom(deployer, sAdmin, erc20VaultNft + 2);

        bytes32 ADMIN_ROLE =
        bytes32(0xf23ec0bb4210edd5cba85afd05127efcd2fc6a781bfed49188da1081670b22d8); // keccak256("admin)
        bytes32 ADMIN_DELEGATE_ROLE =
            bytes32(0xc171260023d22a25a00a2789664c9334017843b831138c8ef03cc8897e5873d7); // keccak256("admin_delegate")
        bytes32 OPERATOR_ROLE =
            bytes32(0x46a52cf33029de9f84853745a87af28464c80bf0346df1b32e205fc73319f622); // keccak256("operator")

        strategy.grantRole(ADMIN_ROLE, sAdmin);
        strategy.grantRole(ADMIN_DELEGATE_ROLE, sAdmin);
        strategy.grantRole(ADMIN_DELEGATE_ROLE, deployer);
        strategy.grantRole(OPERATOR_ROLE, sAdmin);
        strategy.grantRole(OPERATOR_ROLE, operator);
        strategy.revokeRole(ADMIN_DELEGATE_ROLE, deployer);
        strategy.revokeRole(ADMIN_ROLE, deployer);

        console2.log("strategy:", address(strategy));
        console2.log("root vault:", address(rootVault));
        console2.log("erc20 vault:", address(erc20Vault));
        console2.log("uni vault:", address(uniV3Vault));
    }

    function run() external {
        vm.startBroadcast();

        kek();

        //return;

       // strategy = PulseStrategyV2(0x53c238C350D1d71d2028d6676C4f2E1b681250E1);
       // rootVault = IERC20RootVault(0x943dD7a5f0971bDFA0e69DC39E5401E78127161C);

        IERC20(usdt).transfer(address(strategy), 10**3);
        IERC20(weth).transfer(address(strategy), 10**12);

      //  rootVault = IERC20RootVault(0x5Fd7eA4e9F96BBBab73D934618a75746Fd88e460);

        IERC20(usdt).approve(address(rootVault), 10**20);
        IERC20(weth).approve(address(rootVault), 10**20);

        uint256[] memory A = new uint256[](2);
        A[0] = 10**4;
        A[1] = 10**10;

        rootVault.deposit(A, 0, "");

        A = new uint256[](2);
        A[0] = 10**5;
        A[1] = 10**11;

        rootVault.deposit(A, 0, "");

    //    bytes memory z = "0x0502b1c5000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000000000c35000000000000000000000000000000000000000000000000000001415a950b9dc0000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000100000000000000003b6d0340397ff1542f962076d0bfe58ea045ffa2d347aca0cfee7c08";
    //    strategy.rebalance(100000000000000000000, z, 0);




     //   kek();
    }
}