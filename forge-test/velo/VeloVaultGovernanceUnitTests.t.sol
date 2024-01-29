// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

import "./../../src/strategies/BaseAmmStrategy.sol";

import "./../../src/test/MockRouter.sol";

import "./../../src/utils/VeloDepositWrapper.sol";
import "./../../src/utils/VeloHelper.sol";
import "./../../src/utils/VeloFarm.sol";

import "./../../src/vaults/ERC20Vault.sol";
import "./../../src/vaults/ERC20VaultGovernance.sol";

import "./../../src/vaults/ERC20RootVault.sol";
import "./../../src/vaults/ERC20RootVaultGovernance.sol";

import "./../../src/vaults/VeloVault.sol";
import "./../../src/vaults/VeloVaultGovernance.sol";

import "./../../src/adapters/VeloAdapter.sol";

import "./../../src/strategies/PulseOperatorStrategy.sol";

import {SwapRouter, ISwapRouter} from "./contracts/periphery/SwapRouter.sol";

contract Unit is Test {
    using SafeERC20 for IERC20;

    uint256 public constant Q96 = 2**96;
    int24 public constant TICK_SPACING = 200;

    address public protocolTreasury = address(bytes20(keccak256("treasury-1")));
    address public strategyTreasury = address(bytes20(keccak256("treasury-2")));
    address public randomVaultOwner = address(bytes20(keccak256("random-vault-owner")));
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public protocolAdmin = 0xAe259ed3699d1416840033ABAf92F9dD4534b2DC;

    uint256 public protocolFeeD9 = 1e8; // 10%

    address public weth = 0x4200000000000000000000000000000000000006;
    address public usdc = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    address public velo = 0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db;

    address public governance = 0x6CeFdD08d633c4A92380E8F6217238bE2bd1d841;
    address public registry = 0x5cC7Cb6fD996dD646cF613ac94E9E0D2436a083A;
    address public allowAllValidator = 0x0f4A979597E16ec87d2344fD78c2cec53f37D263;
    address public mellowOracle = 0xA9FC72eE105D43C885E48Ab18148D308A55d04c7;

    IERC20RootVaultGovernance public rootVaultGovernance =
        IERC20RootVaultGovernance(0x65a440a89824AB464d7c94B184eF494c1457258D);
    IERC20VaultGovernance public erc20Governance = IERC20VaultGovernance(0xb55ef318B5F73414c91201Af4F467b6c5fE73Ece);

    ICLPool public pool = ICLPool(0xC358c95b146E9597339b376063A2cB657AFf84eb);
    ICLGauge public gauge = ICLGauge(0x5f090Fc694aa42569aB61397E4c996E808f0BBf2);
    INonfungiblePositionManager public positionManager =
        INonfungiblePositionManager(0xd557d3b47D159EB3f9B48c0f1B4a6e67e82e8B3f);
    SwapRouter public swapRouter = new SwapRouter(positionManager.factory(), weth);

    VeloAdapter public adapter = new VeloAdapter(positionManager);
    VeloHelper public veloHelper = new VeloHelper(positionManager);
    VeloDepositWrapper public depositWrapper = new VeloDepositWrapper(deployer);

    BaseAmmStrategy public strategy = new BaseAmmStrategy();
    PulseOperatorStrategy public operatorStrategy = new PulseOperatorStrategy();

    VeloVaultGovernance public ammGovernance;

    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IVeloVault public ammVault;

    VeloFarm public farm;

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

        {
            address[] memory whitelist = new address[](1);
            whitelist[0] = address(depositWrapper);
            rootVault.addDepositorsToAllowlist(whitelist);
        }

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

        rootVaultGovernance.commitDelayedStrategyParams(nft);
    }

    function deployVaults() public {
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;
        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = usdc;
        IERC20VaultGovernance(erc20Governance).createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));
        IVeloVaultGovernance(ammGovernance).createVault(tokens, deployer, TICK_SPACING);
        ammVault = IVeloVault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        farm = new VeloFarm();

        ammGovernance.setStrategyParams(
            erc20VaultNft + 1,
            IVeloVaultGovernance.StrategyParams({farm: address(farm), gauge: address(gauge)})
        );

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }

        farm.initialize(
            address(rootVault),
            address(deployer),
            address(protocolTreasury),
            address(gauge.rewardToken()),
            protocolFeeD9
        );
    }

    function deployGovernance() public {
        VeloVault singleton = new VeloVault(positionManager, veloHelper);
        ammGovernance = new VeloVaultGovernance(
            IVaultGovernance.InternalParams({
                singleton: singleton,
                registry: IVaultRegistry(registry),
                protocolGovernance: IProtocolGovernance(governance)
            })
        );

        vm.stopPrank();
        vm.startPrank(protocolAdmin);

        IProtocolGovernance(governance).stagePermissionGrants(address(ammGovernance), new uint8[](1));
        uint8[] memory per = new uint8[](1);
        per[0] = 4;
        IProtocolGovernance(governance).stagePermissionGrants(address(swapRouter), per);
        IProtocolGovernance(governance).stageValidator(address(swapRouter), allowAllValidator);

        skip(24 * 3600);
        IProtocolGovernance(governance).commitPermissionGrants(address(ammGovernance));
        IProtocolGovernance(governance).commitPermissionGrants(address(swapRouter));
        IProtocolGovernance(governance).commitValidator(address(swapRouter));

        vm.stopPrank();
        vm.startPrank(deployer);
    }

    function _setUp() private {
        vm.startPrank(deployer);

        deployGovernance();
        deployVaults();

        vm.stopPrank();
    }

    function testContractMetaParameters() external {
        _setUp();
        assertEq(ammGovernance.contractName(), "VeloVaultGovernance");
        assertEq(ammGovernance.contractVersion(), "1.0.0");
    }

    function testSetStrategyParams() external {
        _setUp();
        IVeloVaultGovernance.StrategyParams memory invalidStrategyParams;
        IVeloVaultGovernance.StrategyParams memory validStrategyParams = IVeloVaultGovernance.StrategyParams({
            farm: address(1),
            gauge: address(1)
        });
        uint256 vaultNft = ammVault.nft();

        vm.expectRevert(abi.encodePacked("FRB"));
        ammGovernance.setStrategyParams(vaultNft, validStrategyParams);

        vm.startPrank(protocolAdmin);

        vm.expectRevert(abi.encodePacked("AZ"));
        ammGovernance.setStrategyParams(vaultNft, invalidStrategyParams);

        ammGovernance.setStrategyParams(vaultNft, validStrategyParams);

        vm.stopPrank();
    }

    function testStrategyParams() external {
        vm.startPrank(deployer);
        deployGovernance();
        vm.stopPrank();

        uint256 randomNft = 1234;

        IVeloVaultGovernance.StrategyParams memory emptyParams = ammGovernance.strategyParams(randomNft);

        assertEq(emptyParams.gauge, address(0));
        assertEq(emptyParams.farm, address(0));

        vm.startPrank(deployer);
        deployVaults();
        vm.stopPrank();

        uint256 vaultNft = ammVault.nft();

        IVeloVaultGovernance.StrategyParams memory nonEmptyParams = ammGovernance.strategyParams(vaultNft);

        assertEq(nonEmptyParams.gauge, address(gauge));
        assertEq(nonEmptyParams.farm, address(farm));
    }

    function testSupportsInterface() external {
        _setUp();

        assertTrue(ammGovernance.supportsInterface(type(IVeloVaultGovernance).interfaceId));
        assertTrue(ammGovernance.supportsInterface(type(IVaultGovernance).interfaceId));
        assertFalse(ammGovernance.supportsInterface(type(IVeloVault).interfaceId));
    }

    function testCreateVault() external {
        vm.startPrank(deployer);
        deployGovernance();
        vm.stopPrank();

        address[] memory vaultTokens = new address[](2);
        vaultTokens[0] = weth;
        vaultTokens[1] = usdc;

        vm.expectRevert(abi.encodePacked("FRB"));
        ammGovernance.createVault(vaultTokens, randomVaultOwner, TICK_SPACING);

        vm.startPrank(deployer);

        vm.expectRevert(abi.encodePacked("INVL"));
        ammGovernance.createVault(new address[](3), randomVaultOwner, TICK_SPACING);

        vm.expectRevert(abi.encodePacked("NF"));
        ammGovernance.createVault(vaultTokens, randomVaultOwner, 0);

        vaultTokens[0] = usdc;
        vaultTokens[1] = weth;
        vm.expectRevert(abi.encodePacked("INVA"));
        ammGovernance.createVault(vaultTokens, randomVaultOwner, TICK_SPACING);

        vaultTokens[0] = weth;
        vaultTokens[1] = address(uint160(weth) + 1);

        address unregisteredToken1 = address(0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db);
        address unregisteredToken2 = address(0x8a6039fC7A479928B1d73f88040362e9C50Db275);

        if (unregisteredToken1 > unregisteredToken2) {
            (unregisteredToken1, unregisteredToken2) = (unregisteredToken2, unregisteredToken1);
        }

        ICLFactory(positionManager.factory()).createPool(
            unregisteredToken1,
            unregisteredToken2,
            TICK_SPACING,
            uint160(TickMath.getSqrtRatioAtTick(0))
        );

        vaultTokens[0] = unregisteredToken1;
        vaultTokens[1] = unregisteredToken2;
        vm.expectRevert(abi.encodePacked("FRB"));
        VeloVaultGovernance(ammGovernance).createVault(vaultTokens, randomVaultOwner, TICK_SPACING);

        vaultTokens[0] = weth;
        vaultTokens[1] = usdc;
        VeloVaultGovernance(ammGovernance).createVault(vaultTokens, randomVaultOwner, TICK_SPACING);

        vm.stopPrank();
    }
}
