// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/utils/KyberHelper.sol";
import "../../src/MockOracle.sol";

import "../../src/vaults/KyberVaultGovernance.sol";


import "../../src/interfaces/external/kyber/periphery/helpers/TicksFeeReader.sol";

import "../../src/interfaces/vaults/IERC20RootVaultGovernance.sol";
import "../../src/interfaces/vaults/IERC20VaultGovernance.sol";
import "../../src/interfaces/vaults/IKyberVaultGovernance.sol";

import "../../src/interfaces/vaults/IERC20RootVault.sol";
import "../../src/interfaces/vaults/IERC20Vault.sol";
import "../../src/interfaces/vaults/IKyberVault.sol";

import "../../src/vaults/KyberVault.sol";

contract KyberTestWithoutFarm is Test {

    IERC20RootVault public rootVault;
    IERC20Vault erc20Vault;
    IKyberVault kyberVault;

    uint256 nftStart;
    address sAdmin = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;
    address protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address admin = 0xdbA69aa8be7eC788EF5F07Ce860C631F5395E3B1;

    address public bob = 0xB0B195aEFA3650A6908f15CdaC7D92F8a5791B0B;
    address public stmatic = 0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4;
    address public governance = 0x8Ff3148CE574B8e135130065B188960bA93799c6;
    address public registry = 0xd3D0e85F225348a2006270Daf624D8c46cAe4E1F;
    address public rootGovernance = 0xC12885af1d4eAfB8176905F16d23CD7A33D21f37;
    address public erc20Governance = 0x05164eC2c3074A4E8eA20513Fbe98790FfE930A4;
    address public mellowOracle = 0x27AeBFEBDd0fde261Ec3E1DF395061C56EEC5836;

    address public knc = 0x1C954E8fe737F99f68Fa1CCda3e51ebDB291948C;
    address public usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    IERC20RootVaultGovernance rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

    function firstDeposit() public {
        
        deal(stmatic, deployer, 10**10);
        deal(bob, deployer, 10**10);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10**10;
        amounts[1] = 10**10;

        IERC20(stmatic).approve(address(rootVault), type(uint256).max);
        IERC20(bob).approve(address(rootVault), type(uint256).max);

        bytes memory depositInfo;

        rootVault.deposit(amounts, 0, depositInfo);
    }

    function deposit(uint256 amount) public {

        if (rootVault.totalSupply() == 0) {
            firstDeposit();
        }

        deal(stmatic, deployer, amount * 10**18);
        deal(bob, deployer, amount * 10**18);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount * 10**18;
        amounts[1] = amount * 10**18;

        IERC20(stmatic).approve(address(rootVault), type(uint256).max);
        IERC20(bob).approve(address(rootVault), type(uint256).max);

        bytes memory depositInfo;

        rootVault.deposit(amounts, 0, depositInfo);
    }

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(address(rootVaultGovernance), nfts[i]);
        }

        (IERC20RootVault w, uint256 nft) = rootVaultGovernance.createVault(tokens, deployer, nfts, deployer);
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

    uint256 A0;
    uint256 A1;

    function preparePush(address vault) public {

        int24 tickLower = 0;
        int24 tickUpper = 4000;

        IPool pool = kyberVault.pool();

        (int24 tickLowerQ, ) = pool.initializedTicks(tickLower); 
        (int24 tickUpperQ, ) = pool.initializedTicks(tickUpper);

        int24[2] memory Qticks;
        Qticks[0] = tickLowerQ;
        Qticks[1] = tickUpperQ; 
        
        IERC20(bob).approve(0x2B1c7b41f6A8F2b2bc45C3233a5d5FB3cD6dC9A8, type(uint256).max);
        IERC20(stmatic).approve(0x2B1c7b41f6A8F2b2bc45C3233a5d5FB3cD6dC9A8, type(uint256).max);
        deal(bob, deployer, 10**9);
        deal(stmatic, deployer, 10**9);

        (uint256 nft, , uint256 A0_, uint256 A1_) = IBasePositionManager(0x2B1c7b41f6A8F2b2bc45C3233a5d5FB3cD6dC9A8).mint(
            IBasePositionManager.MintParams({
                token0: stmatic,
                token1: bob,
                fee: 1000,
                tickLower: 0,
                tickUpper: 4000,
                ticksPrevious: Qticks,
                amount0Desired: 10**9,
                amount1Desired: 10**9,
                amount0Min: 0,
                amount1Min: 0,
                recipient: operator,
                deadline: type(uint256).max
            })
        );

        A0 = A0_;
        A1 = A1_;

        IVaultRegistry(registry).approve(operator, IVault(vault).nft());

        vm.stopPrank();
        vm.startPrank(operator);

        IBasePositionManager(0x2B1c7b41f6A8F2b2bc45C3233a5d5FB3cD6dC9A8).safeTransferFrom(operator, vault, nft);

        vm.stopPrank();
        vm.startPrank(deployer);
    }

    function kek() public payable returns (uint256 startNft) {

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = stmatic;
        tokens[1] = bob;

        TicksFeesReader reader = new TicksFeesReader();

        KyberHelper kyberHelper = new KyberHelper(IBasePositionManager(0x2B1c7b41f6A8F2b2bc45C3233a5d5FB3cD6dC9A8), reader);

        {
            uint8[] memory grant = new uint8[](2);
            grant[0] = 2;
            grant[1] = 3;

            IProtocolGovernance gv = IProtocolGovernance(governance);

            vm.stopPrank();
            vm.startPrank(admin);

            gv.stagePermissionGrants(stmatic, grant);
            vm.warp(block.timestamp + 86400);
            gv.commitPermissionGrants(stmatic);

            vm.stopPrank();
            vm.startPrank(deployer);

        }

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, deployer);
        }

        {

            MockOracle mockOracle = new MockOracle();
            mockOracle.updatePrice(6507009 * 10**22);

            KyberVault k = new KyberVault(IBasePositionManager(0x2B1c7b41f6A8F2b2bc45C3233a5d5FB3cD6dC9A8), IRouter(0xC1e7dFE73E1598E3910EF4C7845B68A9Ab6F4c83), kyberHelper, IOracle(address(mockOracle)));

            IVaultGovernance.InternalParams memory paramsA = IVaultGovernance.InternalParams({
                protocolGovernance: IProtocolGovernance(0x8Ff3148CE574B8e135130065B188960bA93799c6),
                registry: vaultRegistry,
                singleton: k
            });

            IKyberVaultGovernance kyberVaultGovernance = new KyberVaultGovernance(paramsA);

            {

                uint8[] memory grant2 = new uint8[](1);

                IProtocolGovernance gv = IProtocolGovernance(governance);

                vm.stopPrank();
                vm.startPrank(admin);

                gv.stagePermissionGrants(address(kyberVaultGovernance), grant2);
                vm.warp(block.timestamp + 86400);
                gv.commitPermissionGrants(address(kyberVaultGovernance));

                vm.stopPrank();
                vm.startPrank(deployer);

            }

            vm.stopPrank();
            vm.startPrank(admin);

            bytes[] memory P = new bytes[](1);
            P[0] = abi.encodePacked(knc, uint24(1000), usdc, uint24(8), bob);

            IKyberVaultGovernance.StrategyParams memory paramsC = IKyberVaultGovernance.StrategyParams({
                farm: IKyberSwapElasticLM(0xBdEc4a045446F583dc564C0A227FFd475b329bf0),
                paths: P,
                pid: 117
            });

            vm.stopPrank();
            vm.startPrank(deployer);

            kyberVaultGovernance.createVault(tokens, deployer, 1000);

           // kyberVaultGovernance.setStrategyParams(erc20VaultNft + 1, paramsC);
        }

        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));
        kyberVault = IKyberVault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

     //   kyberVault.updateFarmInfo();

        preparePush(address(kyberVault));

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }
    }

    function isClose(uint256 x, uint256 y, uint256 measure) public returns (bool) {
        uint256 delta;
        if (x < y) {
            delta = y - x;
        }
        else {
            delta = x - y;
        }

        delta = delta * measure;
        if (delta <= x || delta <= y) {
            return true;
        }
        return false;
    }

    function setUp() external {

        vm.startPrank(deployer);

        uint256 startNft = kek();
    }

    function testSetupTvl() public {
        (uint256[] memory tvl, ) = kyberVault.tvl();
        require(tvl[0] == A0);
        require(tvl[1] == A1);
    }

    function testPush() public {

        (uint256[] memory oldTvl, ) = kyberVault.tvl();

        firstDeposit();
        deposit(10);

        address[] memory tokens = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        tokens[0] = stmatic;
        tokens[1] = bob;
        amounts[0] = IERC20(stmatic).balanceOf(address(erc20Vault));
        amounts[1] = IERC20(bob).balanceOf(address(erc20Vault));

        bytes memory Q = bytes("");

        erc20Vault.pull(address(kyberVault), tokens, amounts, Q);

        (uint256[] memory newTvl, ) = kyberVault.tvl();
        require(isClose(newTvl[1] * oldTvl[0], newTvl[0] * oldTvl[1], 100));
    }

    function testPullQ() public {
        firstDeposit();
        deposit(10);

        address[] memory tokens = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        tokens[0] = stmatic;
        tokens[1] = bob;
        amounts[0] = IERC20(stmatic).balanceOf(address(erc20Vault));
        amounts[1] = IERC20(bob).balanceOf(address(erc20Vault));

        bytes memory Q = bytes("");

        erc20Vault.pull(address(kyberVault), tokens, amounts, Q);

        (uint256[] memory tvl, ) = kyberVault.tvl();
        amounts[0] = tvl[0] / 2;
        amounts[1] = tvl[1] / 2;

        (uint256[] memory ercOldTvl, ) = erc20Vault.tvl();

        kyberVault.pull(address(erc20Vault), tokens, amounts, Q);

        (uint256[] memory ercNewTvl, ) = erc20Vault.tvl();

        require(isClose(ercOldTvl[0] + tvl[0] / 2, ercNewTvl[0], 100000));
        require(isClose(ercOldTvl[1] + tvl[1] / 2, ercNewTvl[1], 100000));

        amounts[0] = IERC20(stmatic).balanceOf(address(erc20Vault));
        amounts[1] = IERC20(bob).balanceOf(address(erc20Vault));

        erc20Vault.pull(address(kyberVault), tokens, amounts, Q);
        (uint256[] memory tvl2, ) = kyberVault.tvl();

        require(isClose(tvl[0], tvl2[0], 100000));
        require(isClose(tvl[1], tvl2[1], 100000));
    }

    function testPullRewards() public {
        firstDeposit();
        deposit(10);

        address[] memory tokens = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        tokens[0] = stmatic;
        tokens[1] = bob;
        amounts[0] = IERC20(stmatic).balanceOf(address(erc20Vault));
        amounts[1] = IERC20(bob).balanceOf(address(erc20Vault));

        bytes memory Q = bytes("");

        erc20Vault.pull(address(kyberVault), tokens, amounts, Q);

        (uint256[] memory tvl, ) = kyberVault.tvl();

        vm.warp(block.timestamp + 86400 * 7);

        (uint256[] memory tvl3, ) = kyberVault.tvl();

        console2.log(tvl[0]);
        console2.log(tvl[1]);
        console2.log(tvl3[0]);
        console2.log(tvl3[1]);

        require(tvl3[0] == tvl[0] && tvl3[1] == tvl[1]);

        amounts[0] = tvl3[0];
        amounts[1] = tvl3[1];

        (uint256[] memory ercOldTvl, ) = erc20Vault.tvl();

        kyberVault.pull(address(erc20Vault), tokens, amounts, Q);

        (uint256[] memory ercNewTvl, ) = erc20Vault.tvl();

        require(isClose(ercOldTvl[0] + tvl3[0], ercNewTvl[0], 1000));
        require(isClose(ercOldTvl[1] + tvl3[1], ercNewTvl[1], 1000));
    }

    function testSwap() public {
        firstDeposit();
        deposit(10);

        address[] memory tokens = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        tokens[0] = stmatic;
        tokens[1] = bob;
        amounts[0] = IERC20(stmatic).balanceOf(address(erc20Vault));
        amounts[1] = IERC20(bob).balanceOf(address(erc20Vault));

        bytes memory Q = bytes("");

        erc20Vault.pull(address(kyberVault), tokens, amounts, Q);

        (uint256[] memory tvl, ) = kyberVault.tvl();

        {

            deal(stmatic, deployer, 10**24);

            IERC20(stmatic).approve(0xC1e7dFE73E1598E3910EF4C7845B68A9Ab6F4c83, 10**24);
            IERC20(bob).approve(0xC1e7dFE73E1598E3910EF4C7845B68A9Ab6F4c83, 10**25);
            uint256 A = IRouter(0xC1e7dFE73E1598E3910EF4C7845B68A9Ab6F4c83).swapExactInput(IRouter.ExactInputParams({
                path: abi.encodePacked(stmatic, uint24(1000), bob),
                recipient: deployer,
                deadline: block.timestamp + 1,
                amountIn: 10**24,
                minAmountOut: 0
            }));

            IRouter(0xC1e7dFE73E1598E3910EF4C7845B68A9Ab6F4c83).swapExactInput(IRouter.ExactInputParams({
                path: abi.encodePacked(bob, uint24(1000), stmatic),
                recipient: deployer,
                deadline: block.timestamp + 1,
                amountIn: A,
                minAmountOut: 0
            }));

        }

        (uint256[] memory tvl3, ) = kyberVault.tvl();

        require(tvl3[0] > tvl[0] && tvl3[1] > tvl[1]);

        amounts[0] = tvl3[0];
        amounts[1] = tvl3[1];

        (uint256[] memory ercOldTvl, ) = erc20Vault.tvl();

        vm.warp(block.timestamp + 360);

        kyberVault.pull(address(erc20Vault), tokens, amounts, Q);

        (uint256[] memory ercNewTvl, ) = erc20Vault.tvl();

        require(isClose(ercOldTvl[0] + tvl3[0], ercNewTvl[0], 100000));
        require(isClose(ercOldTvl[1] + tvl3[1], ercNewTvl[1], 100000));
    }
}