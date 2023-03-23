// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/ProtocolGovernance.sol";
import "../../src/MockOracle.sol";
import "../helpers/MockRouter.t.sol";
import "../../src/ERC20RootVaultHelper.sol";
import "../../src/VaultRegistry.sol";

import "../../src/vaults/GearboxVault.sol";
import "../../src/vaults/GearboxRootVault.sol";
import "../../src/vaults/ERC20Vault.sol";

import "../../src/vaults/GearboxVaultGovernance.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../src/utils/GearboxHelper.sol";

import "../../src/external/ConvexBaseRewardPool.sol";

contract GearboxWETHTest is Test {

    uint256 weiofUsdc = 10**15;

    ProtocolGovernance governance;
    VaultRegistry registry;

    GearboxRootVault rootVault = new GearboxRootVault();
    ERC20Vault erc20Vault = new ERC20Vault();
    GearboxVault gearboxVault = new GearboxVault();   

    address weth = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6; 

    address creditAccount;
    uint256 nftStart;

    ICurveV1Adapter curveAdapter;
    IConvexV1BaseRewardPoolAdapter convexAdapter;
    GearboxVaultGovernance governanceC;
    ERC20RootVaultGovernance governanceA;

    uint256 YEAR = 365 * 24 * 60 * 60;

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory
    ) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    bytes32 internal nextUser = keccak256(abi.encodePacked("user address"));

    function getNextUserAddress() public returns (address payable) {
        //bytes32 to address conversion
        address payable user = payable(address(uint160(uint256(nextUser))));
        nextUser = keccak256(abi.encodePacked(nextUser));
        return user;
    }

    function checkNotNonExpectedBalance() public returns (bool) {

        address creditAccount = gearboxVault.getCreditAccount();

        uint256 wethBalance = IERC20(weth).balanceOf(creditAccount);
        uint256 curveLpBalance = IERC20(curveAdapter.lp_token()).balanceOf(creditAccount);
        uint256 convexLpBalance = IERC20(convexAdapter.stakingToken()).balanceOf(creditAccount);

        if (wethBalance > 1 || curveLpBalance > 1 || convexLpBalance > 1) {
            return false;
        }

        return true;
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
        governance.stageUnitPrice(weth, 1);

        {
            uint8[] memory args = new uint8[](1);
            args[0] = PermissionIdsLibrary.ERC20_VAULT_TOKEN;
            governance.stagePermissionGrants(weth, args);

            vm.warp(block.timestamp + governance.governanceDelay());
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

        MockSwapRouter router = new MockSwapRouter();

        IGearboxVaultGovernance.DelayedProtocolParams memory delayedParams = IGearboxVaultGovernance.DelayedProtocolParams({
            withdrawDelay: 86400 * 7,
            referralCode: 0,
            univ3Adapter: 0x8d4dDb8c50A3281FB4B87139e11D67E416509528,
            crv: 0x976d27eC7ebb1136cd7770F5e06aC917Aa9C672b,
            cvx: 0x6D75eb70402CF06a0cB5B8fdc1836dAe29702B17,
            maxSlippageD9: 1000000,
            maxSmallPoolsSlippageD9: 20000000,
            maxCurveSlippageD9: 50000000,
            uniswapRouter: address(router)
        });

        MockOracle oracle = new MockOracle();
        ERC20RootVaultHelper helper = new ERC20RootVaultHelper();

        IERC20RootVaultGovernance.DelayedProtocolParams memory delayedParamsA = IERC20RootVaultGovernance.DelayedProtocolParams({
            managementFeeChargeDelay: 0,
            oracle: IOracle(oracle)
        });
        
        governanceA = new ERC20RootVaultGovernance(internalParamsA, delayedParamsA, IERC20RootVaultHelper(helper));
        ERC20VaultGovernance governanceB = new ERC20VaultGovernance(internalParamsB);
        governanceC = new GearboxVaultGovernance(internalParamsC, delayedParams);
        
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

        IERC20RootVaultGovernance.DelayedStrategyParams memory delayedStrategyParams = IERC20RootVaultGovernance.DelayedStrategyParams({
            strategyTreasury: address(this),
            strategyPerformanceTreasury: address(this),
            privateVault: false,
            managementFee: 10**8,
            performanceFee: 10**8,
            depositCallbackAddress: address(0),
            withdrawCallbackAddress: address(0)
        });

        nftStart = registry.vaultsCount() + 1;

        IGearboxVaultGovernance.DelayedProtocolPerVaultParams memory delayedVaultParams = IGearboxVaultGovernance.DelayedProtocolPerVaultParams({
            primaryToken: weth,
            curveAdapter: 0xfB50859b3bb66F65623103A7C7852b96DaCCF0fd,
            convexAdapter: 0x15D07f782492b4998C39943AbD8ADeA4B8D3C566,
            facade: 0x2ADDB8489Eba8873277b39f15CF770f5e1eE21Fe,
            initialMarginalValueD9: 3000000000
        });

        IGearboxVaultGovernance.StrategyParams memory strategyParamsB = IGearboxVaultGovernance.StrategyParams({
            largePoolFeeUsed: 500
        });

        governanceA.stageDelayedStrategyParams(nftStart + 2, delayedStrategyParams);
        governanceC.stageDelayedProtocolPerVaultParams(nftStart + 1, delayedVaultParams);
        governanceC.setStrategyParams(nftStart + 1, strategyParamsB);
        vm.warp(block.timestamp + governance.governanceDelay());
        governanceC.commitDelayedProtocolPerVaultParams(nftStart + 1);
        governanceA.commitDelayedStrategyParams(nftStart + 2);

        address[] memory tokens = new address[](1);
        tokens[0] = weth; 

        GearboxHelper helper2 = new GearboxHelper();

        governanceB.createVault(tokens, address(this));
        governanceC.createVault(tokens, address(this), address(helper2));

        uint256[] memory nfts = new uint256[](2);

        nfts[0] = nftStart;
        nfts[1] = nftStart + 1;

        registry.approve(address(governanceA), nftStart);
        registry.approve(address(governanceA), nftStart + 1);

        governanceA.createVault(tokens, address(this), nfts, address(this));

        rootVault = GearboxRootVault(registry.vaultForNft(nftStart + 2));
        erc20Vault = ERC20Vault(registry.vaultForNft(nftStart));

        gearboxVault = GearboxVault(registry.vaultForNft(nftStart + 1));

        curveAdapter = ICurveV1Adapter(0xfB50859b3bb66F65623103A7C7852b96DaCCF0fd);
        convexAdapter = IConvexV1BaseRewardPoolAdapter(0x15D07f782492b4998C39943AbD8ADeA4B8D3C566);
        
        governanceA.setStrategyParams(nftStart + 2, strategyParams);
        IERC20(weth).approve(address(rootVault), type(uint256).max);
    }

    function setZeroManagementFees() public {
        IERC20RootVaultGovernance.DelayedStrategyParams memory delayedStrategyParams = governanceA.delayedStrategyParams(nftStart + 2);
        delayedStrategyParams.managementFee = 0;
        delayedStrategyParams.performanceFee = 0;
        governanceA.stageDelayedStrategyParams(nftStart + 2, delayedStrategyParams);
        vm.warp(block.timestamp + governance.governanceDelay());
        governanceA.commitDelayedStrategyParams(nftStart + 2);
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

    function firstDeposit() public {

        deal(weth, address(this), 10**10);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10**10;
        IERC20(weth).approve(address(rootVault), type(uint256).max);

        rootVault.deposit(amounts, 0, "");
    }

    function deposit(uint256 amount, address user) public {

        uint256 subtract = 0;

        if (rootVault.totalSupply() == 0) {
            firstDeposit();
            subtract = 10**10;
        }

        deal(weth, user, amount * weiofUsdc - subtract); 

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount * weiofUsdc - subtract;
        IERC20(weth).approve(address(rootVault), type(uint256).max);

        rootVault.deposit(amounts, 0, "");
        if (gearboxVault.getCreditAccount() == address(0)) {
            vm.stopPrank();
            gearboxVault.openCreditAccount();
        }
    }

    function changeSlippage(uint256 x) public {
        IGearboxVaultGovernance.DelayedProtocolParams memory delayedParams = governanceC.delayedProtocolParams();
        delayedParams.maxSlippageD9 = x;

        governanceC.stageDelayedProtocolParams(delayedParams);
        vm.warp(block.timestamp + governance.governanceDelay());
        governanceC.commitDelayedProtocolParams();
    }

    function invokeExecution() public {

        changeSlippage(10**7);

        vm.roll(block.number + 1);
        rootVault.invokeExecution();

        changeSlippage(10**6);
    }

    function claimMoney(address recipient) public {
        uint256[] memory minTokenAmounts = new uint256[](1);
        bytes[] memory vaultOptions = new bytes[](2);
        rootVault.withdraw(recipient, vaultOptions);
    }

    function setNewRewardInRewardPool(uint256 nominator, uint256 denominator) public {
        ICreditManagerV2 manager = gearboxVault.creditManager();
        address cont = manager.adapterToContract(address(convexAdapter));

        BaseRewardPool rewardsPool = BaseRewardPool(cont);
        
        vm.startPrank(rewardsPool.rewardManager());
        rewardsPool.sync(
            rewardsPool.periodFinish(),
            rewardsPool.rewardRate(),
            rewardsPool.lastUpdateTime(),
            nominator * rewardsPool.rewardPerTokenStored() / denominator,
            rewardsPool.queuedRewards(),
            rewardsPool.currentRewards(),
            rewardsPool.historicalRewards()
        ); // + 76 USD OF REWARDS

        vm.stopPrank();
    }

    function tvl() public returns (uint256) {
        (uint256[] memory result, ) = gearboxVault.tvl();
        assertTrue(result.length == 1);
        return result[0];
    }

    function testSetup() public {
        uint256 wethBalance = IERC20(weth).balanceOf(address(gearboxVault));
        assertTrue(wethBalance == 0);
        assertTrue(gearboxVault.getCreditAccount() == address(0));
    }

    function testFailOpenVaultWithoutFunds() public {
        gearboxVault.openCreditAccount();
    }

    function testFailOpenVaultFromAnyAddress() public {
        vm.startPrank(getNextUserAddress());
        gearboxVault.openCreditAccount();
        vm.stopPrank();
    }

    function testSimpleDeposit() public {

        deposit(500, address(this));

        creditAccount = gearboxVault.getCreditAccount();

        uint256 wethBalance = IERC20(weth).balanceOf(creditAccount);
        uint256 curveLpBalance = IERC20(curveAdapter.lp_token()).balanceOf(creditAccount);
        uint256 convexLpBalance = IERC20(convexAdapter.stakingToken()).balanceOf(creditAccount);
        uint256 convexFantomBalance = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(wethBalance >= weiofUsdc * 500 * 3 && wethBalance <= weiofUsdc * 501 * 3);
        assertTrue(curveLpBalance == 0);
        assertTrue(convexLpBalance == 0);
        assertTrue(convexFantomBalance == 0);
        assertTrue(isClose(tvl(), 500 * weiofUsdc, 100));
    }

    function testTwoDepositsWETH() public {
        
        deposit(500, address(this));
        uint256 lpAmountBefore = rootVault.balanceOf(address(this));

        deposit(100, address(this));
        uint256 lpAmountAfter = rootVault.balanceOf(address(this));

        creditAccount = gearboxVault.getCreditAccount();

        uint256 wethBalance = IERC20(weth).balanceOf(creditAccount);
        uint256 curveLpBalance = IERC20(curveAdapter.lp_token()).balanceOf(creditAccount);
        uint256 convexLpBalance = IERC20(convexAdapter.stakingToken()).balanceOf(creditAccount);
        uint256 convexFantomBalance = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(wethBalance >= weiofUsdc * 1600 && wethBalance <= weiofUsdc * 1601);
        assertTrue(curveLpBalance == 0);
        assertTrue(convexLpBalance == 0);
        assertTrue(convexFantomBalance == 0);

        assertTrue(isClose(lpAmountBefore * 6, lpAmountAfter * 5, 100));
        assertTrue(isClose(tvl(), 600 * weiofUsdc, 100));
    }

    function testFailTooSmallInitialDepositFail() public {
        deposit(100, address(this));
    }

    function testTvlOfEmptyVault() public {
        assertTrue(tvl() == 0);
    }

    function testTvlAfterSingleDeposit() public {
        deposit(500, address(this));
        assertTrue(isClose(tvl(), 500 * weiofUsdc, 100));
    }

    function testFailOpenCreditAccountTwice() public {
        deposit(500, address(this));
        gearboxVault.openCreditAccount();
    }

    function testFailOpenCreditWithoutDeposit() public {
        gearboxVault.openCreditAccount();
    }

    function testTvlAfterTimePasses() public {
        deposit(500, address(this));
        vm.warp(block.timestamp + YEAR);
        assertTrue(tvl() < 49999 * weiofUsdc / 100); // some fees accrued
    }

    function testTvlAfterMultipleDeposits() public {
        deposit(500, address(this));
        deposit(100, address(this));
        deposit(50, address(this));
        assertTrue(isClose(tvl(), 650 * weiofUsdc, 100));
    }

    function testWithdrawalOrders() public {
        deposit(500, address(this));
        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2);

        assertTrue(rootVault.withdrawalRequests(address(this)) == lpTokens / 2);
        rootVault.cancelWithdrawal(lpTokens / 4);
        assertTrue(rootVault.withdrawalRequests(address(this)) == lpTokens / 2 - lpTokens / 4);
    }

    function testWithdrawalOrderCancelTooMuch() public {
        deposit(500, address(this));
        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2);
        rootVault.cancelWithdrawal(lpTokens);
        assertTrue(rootVault.withdrawalRequests(address(this)) == 0);
    }

    function testTooBigWithdrawalOrder() public {
        deposit(500, address(this));
        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(2 * lpTokens);
        assertTrue(rootVault.withdrawalRequests(address(this)) == lpTokens);
    }

    function testSimpleAdjustingPositionWETH() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        creditAccount = gearboxVault.getCreditAccount();

        assertTrue(checkNotNonExpectedBalance());
        uint256 convexFantomBalance = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(convexFantomBalance > 0);

        deposit(100, address(this));
        gearboxVault.adjustPosition();
        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(IERC20(weth).balanceOf(creditAccount) <= 1);
        assertTrue(isClose(convexFantomBalance * 6, convexFantomBalanceAfter * 5, 100));
    }

    function testSimpleAdjustingPositionAndTvlWETH() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), 500 * weiofUsdc, 80));
    }

    function testFailAdjustingPositionFromSomeAddress() public {
        address addr = getNextUserAddress();
        deposit(500, address(this));
        vm.prank(addr);
        gearboxVault.adjustPosition();
    }

    function testFailChangingMarginalFactorFromSomeAddress() public {
        address addr = getNextUserAddress();
        deposit(500, address(this));
        vm.prank(addr);
        gearboxVault.updateTargetMarginalFactor(2000000000);
    }

    function testFailChangingMarginalFactorLowerThanOne() public {
        address addr = getNextUserAddress();
        deposit(500, address(this));
        gearboxVault.updateTargetMarginalFactor(200000000);
    }

    function testSeveralAdjustingPositionAfterChangeInMarginalFactorWETH() public {
        deposit(500, address(this));
        deposit(200, address(this)); // 2100 mETH in staking
        creditAccount = gearboxVault.getCreditAccount();
        gearboxVault.adjustPosition();
        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        gearboxVault.updateTargetMarginalFactor(2500000000); // 1750 mETH in staking
        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(isClose(convexFantomBalanceBefore * 175, convexFantomBalanceAfter * 210, 50));
        assertTrue(isClose(tvl(), 700 * weiofUsdc, 100));

        gearboxVault.updateTargetMarginalFactor(2700000000); // 1910 mETH in staking
        assertTrue(checkNotNonExpectedBalance());
        assertTrue(isClose(tvl(), 700 * weiofUsdc, 100));
        uint256 convexFantomBalanceFinal = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(isClose(convexFantomBalanceFinal * 191, convexFantomBalanceAfter * 210, 50));
    }

    function testEarnedRewardsWETH() public {
        deposit(500, address(this));
        deposit(200, address(this)); // 2100 mETH in staking

        creditAccount = gearboxVault.getCreditAccount();
        gearboxVault.adjustPosition();

        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        setNewRewardInRewardPool(5000, 1); // + 103 mETH
        assertTrue(isClose(tvl(), 803 * weiofUsdc, 50));
        gearboxVault.adjustPosition(); // 2409 mETH in staking now
        assertTrue(isClose(tvl(), 803 * weiofUsdc, 50));

        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(isClose(convexFantomBalanceBefore * 2409, convexFantomBalanceAfter * 2100, 50));

        setNewRewardInRewardPool(12, 10); // + 21 mETH
        assertTrue(isClose(tvl(), 824 * weiofUsdc, 50));
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), 824 * weiofUsdc, 50));
    }

    function testMultipleDepositsAndRewardsAndAdjustmentsTvlCorrectnessWETH() public {
        deposit(500, address(this));
        deposit(200, address(this));
        gearboxVault.adjustPosition();
        setNewRewardInRewardPool(5000, 1); // + 103 mETH

        assertTrue(isClose(tvl(), 803 * weiofUsdc, 50));
        deposit(100, address(this));
        assertTrue(isClose(tvl(), 903 * weiofUsdc, 50));
        deposit(30, address(this));
        assertTrue(isClose(tvl(), 933 * weiofUsdc, 50));
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), 933 * weiofUsdc, 50));
        gearboxVault.updateTargetMarginalFactor(2000000000);
        assertTrue(isClose(tvl(), 933 * weiofUsdc, 50));
        deposit(16, address(this));
        assertTrue(isClose(tvl(), 949 * weiofUsdc, 50));
        gearboxVault.updateTargetMarginalFactor(2222222222);
        assertTrue(isClose(tvl(), 949 * weiofUsdc, 50));
    }

    function testWithValueFallingAndRewardsCovering() public {
        deposit(500, address(this));
        deposit(200, address(this));
        gearboxVault.adjustPosition();

        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        setNewRewardInRewardPool(5000, 1); // + 103 mETH

        gearboxVault.updateTargetMarginalFactor(2900000000);
        assertTrue(isClose(tvl(), 803 * weiofUsdc, 50));

        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(isClose(convexFantomBalanceAfter*2100, convexFantomBalanceBefore*2328, 50));
    }

    function testVaultCloseWithoutOrdersAndConvexWETH() public {
        deposit(500, address(this));
        deposit(200, address(this));
        invokeExecution();

        assertTrue(isClose(IERC20(weth).balanceOf(address(gearboxVault)), 700 * weiofUsdc, 500));
        assertTrue(IERC20(weth).balanceOf(address(erc20Vault)) == 0);
        assertTrue(IERC20(weth).balanceOf(address(rootVault)) == 0);

        assertTrue(gearboxVault.getCreditAccount() == address(0));
    }

    function checkIfSimpleCloseIsOkay() public returns (bool) {
        if (IERC20(weth).balanceOf(address(erc20Vault)) != 0) {
            return false;
        }
        if (IERC20(weth).balanceOf(address(rootVault)) != 0) {
            return false;
        }

        if (gearboxVault.getCreditAccount() != address(0)) {
            return false;
        }
        return true;
    }

    function testVaultCloseWithoutOrdersButWithConvex() public {
        deposit(500, address(this));
        deposit(200, address(this));
        gearboxVault.adjustPosition();
        invokeExecution();

        assertTrue(isClose(IERC20(weth).balanceOf(address(gearboxVault)), 700 * weiofUsdc, 500));

        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testSimpleCloseVaultTvl() public {
        deposit(500, address(this));
        deposit(200, address(this));
        gearboxVault.adjustPosition();
        invokeExecution();

        assertTrue(isClose(tvl(), 700 * weiofUsdc, 500));
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testSimpleCloseVaultOkayAfterMultipleOperationsWETH() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();
        deposit(100, address(this));
        gearboxVault.updateTargetMarginalFactor(2000000000);
        gearboxVault.adjustPosition();
        gearboxVault.updateTargetMarginalFactor(2500000000);

        setNewRewardInRewardPool(5000, 1); // + 73 mETH

        invokeExecution();

        assertTrue(isClose(IERC20(weth).balanceOf(address(gearboxVault)), 673 * weiofUsdc, 100));
        assertTrue(isClose(tvl(), 673 * weiofUsdc, 100));
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testCloseVaultAfterNegativeAdjusting() public {
        deposit(500, address(this));
        deposit(200, address(this));
        gearboxVault.updateTargetMarginalFactor(2000000000);

        invokeExecution();
        assertTrue(isClose(IERC20(weth).balanceOf(address(gearboxVault)), 700 * weiofUsdc, 100));
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testCloseVaultWithOneOrderWETH() public {
        deposit(500, address(this)); // 500 mETH
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));

        rootVault.registerWithdrawal(lpTokens / 2);
        vm.warp(block.timestamp + YEAR / 12); // to impose root vault fees
        invokeExecution();

        uint256 leftOnGearbox = IERC20(weth).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(weth).balanceOf(address(erc20Vault));

        assertTrue(leftOnGearbox * 995 > wentForWithdrawal * 1000); // the result of fees

        deposit(300, address(this));
        gearboxVault.adjustPosition();

        assertTrue(isClose(tvl(), 550 * weiofUsdc, 50));

        address recipient = getNextUserAddress();

        uint256 oldSupply = rootVault.totalSupply();

        claimMoney(recipient);
        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 250 * weiofUsdc, 50));
        uint256 newSupply = rootVault.totalSupply();
        
        assertTrue(oldSupply - lpTokens / 2 == newSupply);
    }

    function testCloseVaultWithOneLargerOrderWETH() public {
        deposit(500, address(this)); // 500 mETH
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));

        rootVault.registerWithdrawal(lpTokens * 3 / 4); // 375 mETH
        invokeExecution();

        deposit(400, address(this));
        gearboxVault.adjustPosition();

        assertTrue(isClose(tvl(), 525 * weiofUsdc, 50));

        address recipient = getNextUserAddress();

        uint256 oldSupply = rootVault.totalSupply();

        claimMoney(recipient);
        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 375 * weiofUsdc, 50));
        uint256 newSupply = rootVault.totalSupply();
        
        assertTrue(oldSupply - lpTokens * 3 / 4 == newSupply);
    }

    function testCloseVaultWithOneFullWETH() public {
        deposit(500, address(this));
        deposit(300, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));

        rootVault.registerWithdrawal(lpTokens); // 800 mETH
        invokeExecution();

        assertTrue(tvl() > 0);
        address recipient = getNextUserAddress();

        claimMoney(recipient);
        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 800 * weiofUsdc, 50));
    }


    function testCloseVaultWithSeveralDepositsAndPartialWithdrawalsWETH() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 mETH

        address secondUser = getNextUserAddress();
        vm.startPrank(secondUser);

        deposit(100, secondUser);
        uint256 secondUserLpTokens = rootVault.balanceOf(secondUser);
        rootVault.registerWithdrawal(secondUserLpTokens / 4); // 25 mETH

        vm.stopPrank();
        invokeExecution();

        uint256 leftOnGearbox = IERC20(weth).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(weth).balanceOf(address(erc20Vault));
        assertTrue(isClose(leftOnGearbox, 325 * weiofUsdc, 50));
        assertTrue(isClose(wentForWithdrawal, 275 * weiofUsdc, 50));


        address recipient = getNextUserAddress();
        claimMoney(recipient);
        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 250 * weiofUsdc, 80));

        vm.startPrank(secondUser);
        claimMoney(recipient);
        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 275 * weiofUsdc, 80));
        vm.stopPrank();

        claimMoney(recipient);
        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 275 * weiofUsdc, 80));
    }

    function testSeveralInvocationsWhenFirstNotTakenAndNewSumIsMoreWETH() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 mETH

        invokeExecution();
        vm.warp(block.timestamp + 86400 * 10);

        deposit(500, address(this));

        rootVault.registerWithdrawal(lpTokens * 2 / 3); // ~333 mETH
        invokeExecution();

        uint256 leftOnGearbox = IERC20(weth).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(weth).balanceOf(address(erc20Vault));
        assertTrue(isClose(leftOnGearbox, 417 * weiofUsdc, 20));
        assertTrue(isClose(wentForWithdrawal, 583 * weiofUsdc, 20));
    }

    function testSeveralInvocationsWhenFirstNotTakenAndNewSumIsLessWETH() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 mETH

        invokeExecution();
        vm.warp(block.timestamp + 86400 * 10);

        deposit(500, address(this));

        rootVault.registerWithdrawal(lpTokens / 3); // ~166 mETH
        invokeExecution();

        uint256 leftOnGearbox = IERC20(weth).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(weth).balanceOf(address(erc20Vault));
        assertTrue(isClose(tvl(), 584*weiofUsdc, 50));
        assertTrue(isClose(leftOnGearbox, 584 * weiofUsdc, 20));
        assertTrue(isClose(wentForWithdrawal, 416 * weiofUsdc, 20));
    }

    function testCancelWithdrawalIsOkayWETH() public {
        deposit(500, address(this)); 
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 USD
        rootVault.cancelWithdrawal(lpTokens / 4); // cancel 125 USD

        invokeExecution();
        address recipient = getNextUserAddress();
        claimMoney(recipient);

        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 125 * weiofUsdc, 50)); // anyway only 125 usd claimed
    }

    function testValueIncreasesAfterWithdrawalWETH() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 mETH

        invokeExecution();

        address secondUser = getNextUserAddress();
        vm.startPrank(secondUser);
        deposit(500, secondUser);
        vm.stopPrank();

        gearboxVault.adjustPosition();
        
        setNewRewardInRewardPool(5000, 1); // + 110 mETH => 2580 mETH in pool
        address recipient = getNextUserAddress();
        claimMoney(recipient); // 250 mETH claimed

        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 250 * weiofUsdc, 50)); // anyway only 250 mETH claimed
        vm.startPrank(secondUser);
        rootVault.registerWithdrawal(lpTokens / 2); // the same lp amount as previous but already 290 mETH
        vm.stopPrank();

        vm.warp(block.timestamp + 86400 * 10);
        invokeExecution();

        vm.startPrank(secondUser);
        claimMoney(recipient); // 290 mETH claimed
        vm.stopPrank();

        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 540 * weiofUsdc, 20));
        claimMoney(recipient); // try to claim by the first user
        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 540 * weiofUsdc, 20));
    }

    function testWitdrawalOrderCancelsAfterTime() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 mETH

        invokeExecution();
        deposit(500, address(this));
        vm.warp(block.timestamp + 86400 * 10);
        invokeExecution();

        address recipient = getNextUserAddress();
        claimMoney(recipient); 

        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 250 * weiofUsdc, 20));
    }

    function testFailTwoInvocationsInShortTime() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        invokeExecution();
        deposit(500, address(this));
        vm.warp(block.timestamp + 86400 * 3); // only 3 days
        invokeExecution();
    }
    
}
