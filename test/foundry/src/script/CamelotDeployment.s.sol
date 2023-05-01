// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Script.sol";

import "../../src/utils/CamelotHelper.sol";
import "../../src/MockOracle.sol";
import "../../src/MockRouter.sol";

import "../../src/vaults/CamelotVaultGovernance.sol";
import "../../src/strategies/CamelotPulseStrategyV2.sol";

import "../../src/interfaces/vaults/IERC20RootVaultGovernance.sol";
import "../../src/interfaces/vaults/IERC20VaultGovernance.sol";
import "../../src/interfaces/vaults/ICamelotVaultGovernance.sol";

import "../../src/interfaces/vaults/IERC20RootVault.sol";
import "../../src/interfaces/vaults/IERC20Vault.sol";
import "../../src/interfaces/vaults/ICamelotVault.sol";

import "../../src/vaults/CamelotVault.sol";

contract CamelotDeployment is Script {

    IERC20RootVault public rootVault;
    IERC20Vault erc20Vault;
    ICamelotVault camelotVault;

    CamelotPulseStrategyV2 camelotStrategy;

    uint256 nftStart;
    address sAdmin = 0x49e99fd160a04304b6CFd251Fce0ACB0A79c626d;
    address protocolTreasury = 0xDF6780faC92ec8D5f366584c29599eA1c97C77F5;
    address strategyTreasury = 0xb0426fDFEfF47B23E5c2794D406A3cC8E77Ec001;
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address admin = 0x160cda72DEc5E7ECc82E0a98CF13c29B0a2396E4;

    address public weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    address public governance = 0x65a440a89824AB464d7c94B184eF494c1457258D;
    address public registry = 0x7D7fEF7bF8bE4DB0FFf06346C59efc24EE8e4c22;

    address public rootGovernance = 0xC75825C5539968648632ec6207f8EDeC407dF891;
    address public erc20Governance = 0x7D62E2c0516B8e747d95323Ca350c847C4Dea533;
    address public mellowOracle = 0x3EFf1DA9e5f72d51F268937d3A5426c2bf5eFf4A;

    address public manager = 0xAcDcC3C6A2339D08E0AC9f694E4DE7c52F890Db3;

    IERC20RootVaultGovernance rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

    function firstDeposit() public {

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10**10;
        amounts[1] = 10**4;

        IERC20(weth).approve(address(rootVault), type(uint256).max);
        IERC20(usdc).approve(address(rootVault), type(uint256).max);

        bytes memory depositInfo;

        rootVault.deposit(amounts, 0, depositInfo);
    }

    function deposit(uint256 amount) public {

        if (rootVault.totalSupply() == 0) {
            firstDeposit();
        }

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount * 10**15;
        amounts[1] = amount * 10**6;

        IERC20(weth).approve(address(rootVault), type(uint256).max);
        IERC20(usdc).approve(address(rootVault), type(uint256).max);

        bytes memory depositInfo;

        rootVault.deposit(amounts, 0, depositInfo);
    }

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(address(rootVaultGovernance), nfts[i]);
        }

        (IERC20RootVault w, uint256 nft) = rootVaultGovernance.createVault(tokens, address(camelotStrategy), nfts, deployer);
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
        tokens[1] = usdc;

        CamelotHelper helper = new CamelotHelper(IAlgebraNonfungiblePositionManager(manager), weth, usdc);

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, deployer);
        }

        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        {

            ICamelotVaultGovernance camelotVaultGovernance = ICamelotVaultGovernance(0x08F07A1F678b55ECa970ca0ec7139B8bf002Dc93);
            camelotVaultGovernance.createVault(tokens, deployer, address(erc20Vault));
        }

        camelotVault = ICamelotVault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        camelotStrategy = new CamelotPulseStrategyV2(IAlgebraNonfungiblePositionManager(manager));

        CamelotPulseStrategyV2.ImmutableParams memory sParams = CamelotPulseStrategyV2.ImmutableParams({
            erc20Vault: erc20Vault,
            camelotVault: camelotVault,
            router: 0x1111111254EEB25477B68fb85Ed929f73A960582,
            tokens: tokens
        });

        uint256[] memory AA = new uint256[](2);
        AA[0] = 10**12;
        AA[1] = 10**3;

        CamelotPulseStrategyV2.MutableParams memory smParams = CamelotPulseStrategyV2.MutableParams({
            priceImpactD6: 0,
            defaultIntervalWidth: 4200,
            maxPositionLengthInTicks: 15000,
            maxDeviationForVaultPool: 50,
            timespanForAverageTick: 300,
            neighborhoodFactorD: 15 * 10**7,
            extensionFactorD: 175 * 10**7,
            swapSlippageD: 10 ** 7,
            swappingAmountsCoefficientD: 10 ** 7,
            minSwapAmounts: AA
        });

        CamelotPulseStrategyV2.DesiredAmounts memory smmParams = CamelotPulseStrategyV2.DesiredAmounts({
            amount0Desired: 10 ** 9,
            amount1Desired: 10 ** 9
        });

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }

        camelotStrategy.initialize(sParams, deployer);
        camelotStrategy.updateMutableParams(smParams);
        camelotStrategy.updateDesiredAmounts(smmParams);

        IERC20(weth).transfer(address(camelotStrategy), 10**9);
        IERC20(usdc).transfer(address(camelotStrategy), 10**3);

        bytes32 ADMIN_ROLE =
        bytes32(0xf23ec0bb4210edd5cba85afd05127efcd2fc6a781bfed49188da1081670b22d8); // keccak256("admin)
        bytes32 ADMIN_DELEGATE_ROLE =
            bytes32(0xc171260023d22a25a00a2789664c9334017843b831138c8ef03cc8897e5873d7); // keccak256("admin_delegate")
        bytes32 OPERATOR_ROLE =
            bytes32(0x46a52cf33029de9f84853745a87af28464c80bf0346df1b32e205fc73319f622); // keccak256("operator")

        camelotStrategy.grantRole(ADMIN_ROLE, sAdmin);
        camelotStrategy.grantRole(ADMIN_DELEGATE_ROLE, sAdmin);
        camelotStrategy.grantRole(ADMIN_DELEGATE_ROLE, deployer);
        camelotStrategy.grantRole(OPERATOR_ROLE, sAdmin);
        camelotStrategy.revokeRole(ADMIN_DELEGATE_ROLE, deployer);
        camelotStrategy.revokeRole(ADMIN_ROLE, deployer);

        vaultRegistry.safeTransferFrom(deployer, sAdmin, erc20VaultNft + 2);

        console2.log("strategy:", address(camelotStrategy));
        console2.log("erc20 vault:", address(erc20Vault));
        console2.log("root vault:", address(rootVault));
        console2.log("camelot vault:", address(camelotVault));

    }

    function run() external {

        vm.startBroadcast();
        kek();
        deposit(1);
    }
}