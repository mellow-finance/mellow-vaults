// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

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

import "../vaults/UniV3VaultGovernance.sol";
import "../vaults/ERC20VaultGovernance.sol";
import "../vaults/ERC20RootVaultGovernance.sol";

import "../strategies/PulseStrategyV2.sol";


contract MainnetDeployment is Script {

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

    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public rootGovernance = 0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public uniV3Governance = 0x9c319DC47cA6c8c5e130d5aEF5B8a40Cce9e877e;
    address public mellowOracle = 0x9d992650B30C6FB7a83E7e7a430b4e015433b838;

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
                depositCallbackAddress: address(strategy),
                withdrawCallbackAddress: address(strategy)
            })
        );

        rootVaultGovernance.commitDelayedStrategyParams(nft);
    }

    function kek() public payable returns (uint256 startNft) {

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = wsteth;
        tokens[1] = weth;

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, deployer);
        }

        IOracle oracle = IOracle(0x27AeBFEBDd0fde261Ec3E1DF395061C56EEC5836);

        UniV3Helper helper = new UniV3Helper(INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88));

        {
            IUniV3VaultGovernance uniGovernance = IUniV3VaultGovernance(uniV3Governance);
            uniGovernance.createVault(tokens, deployer, 500, address(helper));
        }

        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));
        uniV3Vault = IUniV3Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        strategy = new PulseStrategyV2(INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88));

        PulseStrategyV2.ImmutableParams memory sParams = PulseStrategyV2.ImmutableParams({
            erc20Vault: erc20Vault,
            uniV3Vault: uniV3Vault,
            router: 0x1111111254EEB25477B68fb85Ed929f73A960582,
            tokens: tokens
        });

        uint256[] memory AA = new uint256[](2);
        AA[0] = 10**15;
        AA[1] = 10**15;

        PulseStrategyV2.MutableParams memory smParams = PulseStrategyV2.MutableParams({
            priceImpactD6: 0,
            defaultIntervalWidth: 280,
            maxPositionLengthInTicks: 700,
            maxDeviationForVaultPool: 50,
            timespanForAverageTick: 60,
            neighborhoodFactorD: 10 ** 7 * 15,
            extensionFactorD: 10 ** 9 * 2,
            swapSlippageD: 10 ** 7,
            swappingAmountsCoefficientD: 10 ** 7,
            minSwapAmounts: AA
        });

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }

        strategy.initialize(sParams, deployer);
        strategy.updateMutableParams(smParams);

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
        strategy.revokeRole(ADMIN_DELEGATE_ROLE, deployer);
        strategy.revokeRole(ADMIN_ROLE, deployer);

        console2.log("strategy:", address(strategy));
        console2.log("root vault:", address(rootVault));
        console2.log("erc20 vault:", address(erc20Vault));
        console2.log("uni vault:", address(uniV3Vault));
    }

    function run() external {
        vm.startBroadcast();

        IERC20(weth).transfer(0xFDF8B88D77a9B65646e0D9Cd5880E3677B94Af01, 10**12);
        IERC20(wsteth).transfer(0xFDF8B88D77a9B65646e0D9Cd5880E3677B94Af01, 10**12);

        rootVault = IERC20RootVault(0x5Fd7eA4e9F96BBBab73D934618a75746Fd88e460);

      //  IERC20(weth).approve(address(rootVault), 10**20);
      //  IERC20(wsteth).approve(address(rootVault), 10**20);

        uint256[] memory A = new uint256[](2);
        A[0] = 4 * 10**16;
        A[1] = 4 * 10**16;

        //rootVault.deposit(A, 0, "");


     //   kek();
    }
}