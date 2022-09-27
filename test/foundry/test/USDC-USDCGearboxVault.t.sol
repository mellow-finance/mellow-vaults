// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../src/ProtocolGovernance.sol";
import "../src/MockOracle.sol";
import "../src/ERC20RootVaultHelper.sol";
import "../src/VaultRegistry.sol";

import "../src/vaults/GearboxVault.sol";
import "../src/vaults/GearboxRootVault.sol";
import "../src/vaults/ERC20Vault.sol";

import "../src/vaults/GearboxVaultGovernance.sol";
import "../src/vaults/ERC20VaultGovernance.sol";
import "../src/vaults/ERC20RootVaultGovernance.sol";

import "../src/external/ConvexBaseRewardPool.sol";


contract GearboxTest is Test {

    ProtocolGovernance governance;
    VaultRegistry registry;

    GearboxRootVault rootVault = new GearboxRootVault();
    ERC20Vault erc20Vault = new ERC20Vault();
    GearboxVault gearboxVault = new GearboxVault();   

    address usdc = 0x1F2cd0D7E5a7d8fE41f886063E9F11A05dE217Fa;
    address weth = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6; 
    address creditAccount;

    ICurveV1Adapter curveAdapter;
    IConvexV1BaseRewardPoolAdapter convexAdapter;

    uint256 YEAR = 365 * 24 * 60 * 60;

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory
    ) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function setUp() public {
        governance = new ProtocolGovernance(address(this));
        registry = new VaultRegistry("Mellow LP", "MLP", governance);

        IProtocolGovernance.Params memory governanceParams = IProtocolGovernance.Params({
            maxTokensPerVault: 10,
            governanceDelay: 86400,
            protocolTreasury: address(this),
            forceAllowMask: 0,
            withdrawLimit: type(uint256).max
        });

        governance.stageParams(governanceParams);
        governance.commitParams();

        {
            uint8[] memory args = new uint8[](1);
            args[0] = PermissionIdsLibrary.ERC20_VAULT_TOKEN;
            governance.stagePermissionGrants(usdc, args);
            governance.stagePermissionGrants(weth, args);

            vm.warp(block.timestamp + governance.governanceDelay());
            governance.commitPermissionGrants(usdc);
            governance.commitPermissionGrants(weth);

            args[0] = PermissionIdsLibrary.CREATE_VAULT;
            governance.stagePermissionGrants(address(this), args);

            vm.warp(block.timestamp + governance.governanceDelay());
            governance.commitPermissionGrants(address(this));
        }

        IVaultGovernance.InternalParams memory internalParamsC = IVaultGovernance.InternalParams({
            protocolGovernance: governance,
            registry: registry,
            singleton: gearboxVault
        });

        IVaultGovernance.InternalParams memory internalParamsB = IVaultGovernance.InternalParams({
            protocolGovernance: governance,
            registry: registry,
            singleton: erc20Vault
        });

        IVaultGovernance.InternalParams memory internalParamsA = IVaultGovernance.InternalParams({
            protocolGovernance: governance,
            registry: registry,
            singleton: rootVault
        });

        IGearboxVaultGovernance.DelayedProtocolParams memory delayedParams = IGearboxVaultGovernance.DelayedProtocolParams({
            withdrawDelay: 86400 * 7,
            referralCode: 0,
            univ3Adapter: 0xA417851DdbB7095c76Ac69Df6152c86F01328C5f,
            crv: 0x976d27eC7ebb1136cd7770F5e06aC917Aa9C672b,
            cvx: 0x6D75eb70402CF06a0cB5B8fdc1836dAe29702B17,
            minSlippageD: 100000000
        });

        MockOracle oracle = new MockOracle();
        ERC20RootVaultHelper helper = new ERC20RootVaultHelper();

        IERC20RootVaultGovernance.DelayedProtocolParams memory delayedParamsA = IERC20RootVaultGovernance.DelayedProtocolParams({
            managementFeeChargeDelay: 0,
            oracle: IOracle(oracle)
        });
        
        ERC20RootVaultGovernance governanceA = new ERC20RootVaultGovernance(internalParamsA, delayedParamsA, IERC20RootVaultHelper(helper));
        ERC20VaultGovernance governanceB = new ERC20VaultGovernance(internalParamsB);
        GearboxVaultGovernance governanceC = new GearboxVaultGovernance(internalParamsC, delayedParams);
        
        {
            uint8[] memory args = new uint8[](1);
            args[0] = PermissionIdsLibrary.REGISTER_VAULT;
            governance.stagePermissionGrants(address(governanceA), args);
            governance.stagePermissionGrants(address(governanceB), args);
            governance.stagePermissionGrants(address(governanceC), args);

            vm.warp(block.timestamp + governance.governanceDelay());
            governance.commitPermissionGrants(address(governanceA));
            governance.commitPermissionGrants(address(governanceB));
            governance.commitPermissionGrants(address(governanceC));
        }

        IERC20RootVaultGovernance.StrategyParams memory strategyParams = IERC20RootVaultGovernance.StrategyParams({
            tokenLimitPerAddress: type(uint256).max,
            tokenLimit: type(uint256).max
        });

        uint256 nftStart = registry.vaultsCount() + 1;

        IGearboxVaultGovernance.DelayedProtocolPerVaultParams memory delayedVaultParams = IGearboxVaultGovernance.DelayedProtocolPerVaultParams({
            primaryToken: usdc,
            curveAdapter: 0x6f3A4EFe549c2Fa397ed40FD4DE9FEB922C0FE31,
            convexAdapter: 0xb26586F4a9F157117651Da1A6DFa5b310790dd8A,
            facade: 0xCd290664b0AE34D8a7249bc02d7bdbeDdf969820,
            initialMarginalValue: 3000000000
        });

        governanceC.stageDelayedProtocolPerVaultParams(nftStart + 1, delayedVaultParams);
        vm.warp(block.timestamp + governance.governanceDelay());
        governanceC.commitDelayedProtocolPerVaultParams(nftStart + 1);

        address[] memory tokens = new address[](1);
        tokens[0] = usdc; 

        deal(usdc, address(governanceC), 5*10**8);

        governanceB.createVault(tokens, address(this));
        governanceC.createVault(tokens, address(this));

        uint256[] memory nfts = new uint256[](2);

        nfts[0] = nftStart;
        nfts[1] = nftStart + 1;

        registry.approve(address(governanceA), nftStart);
        registry.approve(address(governanceA), nftStart + 1);

        governanceA.createVault(tokens, address(this), nfts, address(this));

        rootVault = GearboxRootVault(registry.vaultForNft(nftStart + 2));
        erc20Vault = ERC20Vault(registry.vaultForNft(nftStart));

        gearboxVault = GearboxVault(registry.vaultForNft(nftStart + 1));

        curveAdapter = ICurveV1Adapter(gearboxVault.curveAdapter());
        convexAdapter = IConvexV1BaseRewardPoolAdapter(gearboxVault.convexAdapter());
        
        governanceA.setStrategyParams(nftStart + 2, strategyParams);
        IERC20(usdc).approve(address(rootVault), type(uint256).max);
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

    function deposit(uint256 amount) public {
        deal(usdc, address(this), amount * 10**6);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount * 10**6;

        rootVault.deposit(amounts, 0, "");
    }

    function tvl() public returns (uint256) {
        (uint256[] memory result, ) = gearboxVault.tvl();
        assertTrue(result.length == 1);
        return result[0];
    }

    function testSetup() public {
        uint256 usdcBalance = IERC20(usdc).balanceOf(creditAccount);
        assertTrue(usdcBalance == 0);
    }

    function testSimpleDeposit() public {

        deposit(500);

        creditAccount = gearboxVault.creditAccount();

        uint256 usdcBalance = IERC20(usdc).balanceOf(creditAccount);
        uint256 curveLpBalance = IERC20(curveAdapter.lp_token()).balanceOf(creditAccount);
        uint256 convexLpBalance = IERC20(convexAdapter.stakingToken()).balanceOf(creditAccount);
        uint256 convexFantomBalance = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(usdcBalance == 15 * 10 ** 8);
        assertTrue(curveLpBalance == 0);
        assertTrue(convexLpBalance == 0);
        assertTrue(convexFantomBalance == 0);
    }

    function testTwoDeposits() public {
        
        deposit(500);
        uint256 lpAmountBefore = rootVault.balanceOf(address(this));

        deposit(100);
        uint256 lpAmountAfter = rootVault.balanceOf(address(this));

        creditAccount = gearboxVault.creditAccount();

        uint256 usdcBalance = IERC20(usdc).balanceOf(creditAccount);
        uint256 curveLpBalance = IERC20(curveAdapter.lp_token()).balanceOf(creditAccount);
        uint256 convexLpBalance = IERC20(convexAdapter.stakingToken()).balanceOf(creditAccount);
        uint256 convexFantomBalance = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(usdcBalance == 16 * 10 ** 8);
        assertTrue(curveLpBalance == 0);
        assertTrue(convexLpBalance == 0);
        assertTrue(convexFantomBalance == 0);

        assertTrue(isClose(lpAmountBefore * 6, lpAmountAfter * 5, 100));
    }

    function testFailTooSmallInitialDepositFail() public {

        deposit(100);

        uint256[] memory amounts = new uint256[](1);

        amounts[0] = 10 ** 8;
        rootVault.deposit(amounts, 0, "");
    }

    function testTvlOfEmptyVault() public {
        assertTrue(tvl() == 0);
    }

    function testTvlAfterSingleDeposit() public {
        deposit(500);
        assertTrue(tvl() == 5 * 10**8);
    }

    function testTvlAfterTimePasses() public {
        deposit(500);
        vm.warp(block.timestamp + YEAR);
        console2.log(tvl());
        assertTrue(tvl() < 49999 * 10**4); // some fees accrued
    }

    function testTvlAfterMultipleDeposits() public {
        deposit(500);
        deposit(100);
        deposit(50);
        assertTrue(tvl() == 65 * 10**7);
    }

    function testWithdrawalOrders() public {
        deposit(500);
        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2);

        assertTrue(rootVault.currentWithdrawalRequested(address(this)) == lpTokens / 2);
        rootVault.cancelWithdrawal(lpTokens / 4);
        assertTrue(rootVault.currentWithdrawalRequested(address(this)) == lpTokens / 2 - lpTokens / 4);
    }

    function testWithdrawalOrderCancelTooMuch() public {
        deposit(500);
        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2);
        rootVault.cancelWithdrawal(lpTokens);
        assertTrue(rootVault.currentWithdrawalRequested(address(this)) == 0);
    }

    function testTooBigWithdrawalOrder() public {
        deposit(500);
        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(2 * lpTokens);
        assertTrue(rootVault.currentWithdrawalRequested(address(this)) == lpTokens);
    }

    function testSimpleAdjustingPosition() public {
        deposit(500);
        gearboxVault.adjustPosition();

        creditAccount = gearboxVault.creditAccount();

        uint256 usdcBalance = IERC20(usdc).balanceOf(creditAccount);
        uint256 curveLpBalance = IERC20(curveAdapter.lp_token()).balanceOf(creditAccount);
        uint256 convexLpBalance = IERC20(convexAdapter.stakingToken()).balanceOf(creditAccount);
        uint256 convexFantomBalance = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(usdcBalance == 0);
        assertTrue(curveLpBalance == 0);
        assertTrue(convexLpBalance == 0);
        assertTrue(convexFantomBalance > 0);

        deposit(100);
        gearboxVault.adjustPosition();
        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        console2.log(convexFantomBalance);
        console2.log(convexFantomBalanceAfter);

        assertTrue(isClose(convexFantomBalance * 6, convexFantomBalanceAfter * 5, 100));
    }

    function testSimpleAdjustingPositionAndTvl() public {
        deposit(500);
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), 500 * 10**6, 100));
    }

    function testSeveralAdjustingPositionAfterChangeInMarginalFactor() public {
        deposit(500);
        creditAccount = gearboxVault.creditAccount();
        gearboxVault.adjustPosition();
        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        gearboxVault.updateTargetMarginalFactor(2500000000);
        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(isClose(convexFantomBalanceBefore * 5, convexFantomBalanceAfter * 6, 100));
        assertTrue(isClose(tvl(), 500 * 10**6, 100));

        uint256 usdcBalance = IERC20(usdc).balanceOf(creditAccount);
        uint256 curveLpBalance = IERC20(curveAdapter.lp_token()).balanceOf(creditAccount);
        uint256 convexLpBalance = IERC20(convexAdapter.stakingToken()).balanceOf(creditAccount);
        assertTrue(usdcBalance <= 1); // gearbox count value = 1 as some analogue of 0
        assertTrue(curveLpBalance <= 1);
        assertTrue(convexLpBalance <= 1);

        gearboxVault.updateTargetMarginalFactor(2700000000);
        assertTrue(isClose(tvl(), 500 * 10**6, 100));
        uint256 convexFantomBalanceFinal = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(isClose(convexFantomBalanceFinal * 25, convexFantomBalanceAfter * 27, 100));
    }

    function testEarnedRewards() public {
        deposit(500);
        creditAccount = gearboxVault.creditAccount();
        gearboxVault.adjustPosition();

        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        ICreditManagerV2 manager = gearboxVault.creditManager();
        address cont = manager.adapterToContract(gearboxVault.convexAdapter());

        BaseRewardPool rewardsPool = BaseRewardPool(cont);
        
        vm.startPrank(rewardsPool.rewardManager());
        rewardsPool.sync(
            rewardsPool.periodFinish(),
            rewardsPool.rewardRate(),
            rewardsPool.lastUpdateTime(),
            5 * rewardsPool.rewardPerTokenStored(),
            rewardsPool.queuedRewards(),
            rewardsPool.currentRewards(),
            rewardsPool.historicalRewards()
        ); // + 76 USD OF REWARDS

        vm.stopPrank();

        assertTrue(isClose(tvl(), 576 * 10**6, 100));
        
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), 576 * 10**6, 100));

        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(isClose(convexFantomBalanceBefore * 576, convexFantomBalanceAfter * 500, 50));

    }




}
