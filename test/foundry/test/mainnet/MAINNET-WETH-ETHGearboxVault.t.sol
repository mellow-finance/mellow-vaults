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
import "../../src/interfaces/IDegenNft.sol";

import "../helpers/MockDistributor.t.sol";


contract GearboxWETHTest is Test {

    uint256 weiofUsdc = 10**15;

    ProtocolGovernance governance;
    VaultRegistry registry;

    GearboxRootVault rootVault = new GearboxRootVault();
    ERC20Vault erc20Vault = new ERC20Vault();
    GearboxVault gearboxVault = new GearboxVault();   

    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; 
    address admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;
    address minter = 0x6cA68adc7eC07a4bD97c97e8052510FBE6b67d10;
    MockDegenDistributor distributor = new MockDegenDistributor();
    address configurator = 0xA7D5DDc1b8557914F158076b228AA91eF613f1D5;
    address cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    address creditAccount;
    uint256 nftStart;

    ICurveV1Adapter curveAdapter;
    IConvexV1BaseRewardPoolAdapter convexAdapter;
    GearboxVaultGovernance governanceC;
    ERC20RootVaultGovernance governanceA;

    uint256 YEAR = 365 * 24 * 60 * 60;
    uint256 FIRST_DEPOSIT = 35000;

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

    GearboxHelper helper2;

    function setUp() public {

        governance = ProtocolGovernance(0xDc9C17662133fB865E7bA3198B67c53a617B2153);
        registry = VaultRegistry(0xFD23F971696576331fCF96f80a20B4D3b31ca5b2);

        {

            vm.startPrank(admin);

            uint8[] memory args = new uint8[](1);
            args[0] = PermissionIdsLibrary.ERC20_VAULT_TOKEN;
            governance.stagePermissionGrants(weth, args);

            vm.warp(block.timestamp + governance.governanceDelay());
            governance.commitPermissionGrants(weth);

            args[0] = PermissionIdsLibrary.CREATE_VAULT;
            governance.stagePermissionGrants(address(this), args);

            vm.warp(block.timestamp + governance.governanceDelay());
            governance.commitPermissionGrants(address(this));

            vm.stopPrank();
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
            univ3Adapter: 0xed5B30F8604c0743F167a19F42fEC8d284963a7D,
            crv: 0xD533a949740bb3306d119CC777fa900bA034cd52,
            cvx: cvx,
            maxSlippageD9: 10000000,
            maxSmallPoolsSlippageD9: 20000000,
            maxCurveSlippageD9: 30000000,
            uniswapRouter: 0xE592427A0AEce92De3Edee1F18E0157C05861564
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

            vm.startPrank(admin);

            uint8[] memory args = new uint8[](1);
            args[0] = PermissionIdsLibrary.REGISTER_VAULT;
            governance.stagePermissionGrants(address(governanceA), args);
            governance.stagePermissionGrants(address(governanceB), args);
            governance.stagePermissionGrants(address(governanceC), args);

            vm.warp(block.timestamp + governance.governanceDelay());
            governance.commitPermissionGrants(address(governanceA));
            governance.commitPermissionGrants(address(governanceB));
            governance.commitPermissionGrants(address(governanceC));

            vm.stopPrank();
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
            curveAdapter: 0x0Ad2Fc10F677b2554553DaF80312A98ddb38f8Ef,
            convexAdapter: 0xeBE13b1874bB2913CB3F04d4231837867ff77999,
            facade: 0xC59135f449bb623501145443c70A30eE648Fa304,
            initialMarginalValueD9: 5000000000
        });

        IGearboxVaultGovernance.StrategyParams memory strategyParamsB = IGearboxVaultGovernance.StrategyParams({
            largePoolFeeUsed: 500
        });

        {

            vm.startPrank(admin);

            governanceA.stageDelayedStrategyParams(nftStart + 2, delayedStrategyParams);
            governanceC.stageDelayedProtocolPerVaultParams(nftStart + 1, delayedVaultParams);
            governanceC.setStrategyParams(nftStart + 1, strategyParamsB);
            vm.warp(block.timestamp + governance.governanceDelay());
            governanceC.commitDelayedProtocolPerVaultParams(nftStart + 1);
            governanceA.commitDelayedStrategyParams(nftStart + 2);

            vm.stopPrank();

        }

        address[] memory tokens = new address[](1);
        tokens[0] = weth; 

        helper2 = new GearboxHelper();

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

        curveAdapter = ICurveV1Adapter(0x0Ad2Fc10F677b2554553DaF80312A98ddb38f8Ef);
        convexAdapter = IConvexV1BaseRewardPoolAdapter(0xeBE13b1874bB2913CB3F04d4231837867ff77999);
        
        governanceA.setStrategyParams(nftStart + 2, strategyParams);
        IERC20(weth).approve(address(rootVault), type(uint256).max);

        address degenNft = ICreditFacade(gearboxVault.creditFacade()).degenNFT();
        vm.startPrank(configurator);
        IDegenNFT(degenNft).setMinter(address(distributor));
        vm.stopPrank();

        bytes32[] memory arr = new bytes32[](1);
        arr[0] = DegenConstants.DEGEN;

        gearboxVault.setMerkleParameters(0, 20, arr);
    }

    function setZeroFees() public {
        vm.startPrank(admin);
        IERC20RootVaultGovernance.DelayedStrategyParams memory delayedStrategyParams = governanceA.delayedStrategyParams(nftStart + 2);
        delayedStrategyParams.managementFee = 0;
        delayedStrategyParams.performanceFee = 0;
        governanceA.stageDelayedStrategyParams(nftStart + 2, delayedStrategyParams);
        vm.warp(block.timestamp + governance.governanceDelay());
        governanceA.commitDelayedStrategyParams(nftStart + 2);
        vm.stopPrank();
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

    function invokeExecution() public {

        vm.roll(block.number + 1);
        rootVault.invokeExecution();

    }

    function claimMoney(address recipient) public {
        uint256[] memory minTokenAmounts = new uint256[](1);
        bytes[] memory vaultOptions = new bytes[](2);
        rootVault.withdraw(recipient, vaultOptions);
    }

    function runRewarding() public {
        ICreditManagerV2 manager = gearboxVault.creditManager();
        address cont = manager.adapterToContract(address(convexAdapter));

        BaseRewardPool rewardsPool = BaseRewardPool(cont);
        vm.startPrank(rewardsPool.operator());
        for (uint256 i = 0; i < 53; ++i) {
            uint256 multiplier = 1;
            if (i == 0) {
                multiplier = 1000;
            }
            rewardsPool.queueNewRewards(rewardsPool.currentRewards() * multiplier - rewardsPool.queuedRewards());
            vm.warp(block.timestamp + rewardsPool.duration() + 1);
        }
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

        deposit(FIRST_DEPOSIT, address(this));

        creditAccount = gearboxVault.getCreditAccount();

        uint256 wethBalance = IERC20(weth).balanceOf(creditAccount);
        uint256 curveLpBalance = IERC20(curveAdapter.lp_token()).balanceOf(creditAccount);
        uint256 convexLpBalance = IERC20(convexAdapter.stakingToken()).balanceOf(creditAccount);
        uint256 convexFantomBalance = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(wethBalance >= weiofUsdc * FIRST_DEPOSIT * 5 && wethBalance <= weiofUsdc * FIRST_DEPOSIT * 501 / 100);
        assertTrue(curveLpBalance == 0);
        assertTrue(convexLpBalance == 0);
        assertTrue(convexFantomBalance == 0);
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc, 100));
    }


    function testTwoDepositsWETH() public {
        
        deposit(FIRST_DEPOSIT, address(this));
        uint256 lpAmountBefore = rootVault.balanceOf(address(this));

        deposit(FIRST_DEPOSIT / 5, address(this));
        uint256 lpAmountAfter = rootVault.balanceOf(address(this));

        creditAccount = gearboxVault.getCreditAccount();

        uint256 wethBalance = IERC20(weth).balanceOf(creditAccount);
        uint256 curveLpBalance = IERC20(curveAdapter.lp_token()).balanceOf(creditAccount);
        uint256 convexLpBalance = IERC20(convexAdapter.stakingToken()).balanceOf(creditAccount);
        uint256 convexFantomBalance = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(wethBalance >= weiofUsdc * FIRST_DEPOSIT * 26 / 5 && wethBalance <= weiofUsdc * FIRST_DEPOSIT * 2601 / 500);
        assertTrue(curveLpBalance == 0);
        assertTrue(convexLpBalance == 0);
        assertTrue(convexFantomBalance == 0);

        assertTrue(isClose(lpAmountBefore * 6, lpAmountAfter * 5, 100));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 6 / 5, 100));
    }

    function testFailTooSmallInitialDepositFail() public {
        deposit(FIRST_DEPOSIT / 5, address(this));
    }

    function testTvlOfEmptyVault() public {
        assertTrue(tvl() == 0);
    }

    function testTvlAfterSingleDeposit() public {
        deposit(FIRST_DEPOSIT, address(this));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc, 100));
    }

    function testFailOpenCreditAccountTwice() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.openCreditAccount();
    }

    function testFailOpenCreditWithoutDeposit() public {
        gearboxVault.openCreditAccount();
    }

    function testTvlAfterTimePasses() public {
        deposit(FIRST_DEPOSIT, address(this));
        vm.warp(block.timestamp + YEAR);
        assertTrue(tvl() < FIRST_DEPOSIT * weiofUsdc * 999 / 1000); // some fees accrued
    }

    function testTvlAfterMultipleDeposits() public {
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5, address(this));
        deposit(FIRST_DEPOSIT / 10, address(this));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 13 / 10, 100));
    }


    function testWithdrawalOrders() public {
        deposit(FIRST_DEPOSIT, address(this));
        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2);

        assertTrue(rootVault.withdrawalRequests(address(this)) == lpTokens / 2);
        rootVault.cancelWithdrawal(lpTokens / 4);
        assertTrue(rootVault.withdrawalRequests(address(this)) == lpTokens / 2 - lpTokens / 4);
    }

    function testWithdrawalOrderCancelTooMuch() public {
        deposit(FIRST_DEPOSIT, address(this));
        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2);
        rootVault.cancelWithdrawal(lpTokens);
        assertTrue(rootVault.withdrawalRequests(address(this)) == 0);
    }

    function testTooBigWithdrawalOrder() public {
        deposit(FIRST_DEPOSIT, address(this));
        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(2 * lpTokens);
        assertTrue(rootVault.withdrawalRequests(address(this)) == lpTokens);
    }


    function testSimpleAdjustingPositionWETH() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        creditAccount = gearboxVault.getCreditAccount();

        assertTrue(checkNotNonExpectedBalance());
        uint256 convexFantomBalance = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(convexFantomBalance > 0);

        deposit(FIRST_DEPOSIT / 5, address(this));
        gearboxVault.adjustPosition();
        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(IERC20(weth).balanceOf(creditAccount) <= 1);
        assertTrue(isClose(convexFantomBalance * 6, convexFantomBalanceAfter * 5, 100));
    }

    function testSimpleAdjustingPositionAndTvlWETH() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc, 80));
    }

    function testFailAdjustingPositionFromSomeAddress() public {
        address addr = getNextUserAddress();
        deposit(FIRST_DEPOSIT, address(this));
        vm.prank(addr);
        gearboxVault.adjustPosition();
    }

    function testFailChangingMarginalFactorFromSomeAddress() public {
        address addr = getNextUserAddress();
        deposit(FIRST_DEPOSIT, address(this));
        vm.prank(addr);
        gearboxVault.updateTargetMarginalFactor(4000000000);
    }

    function testFailChangingMarginalFactorLowerThanOne() public {
        address addr = getNextUserAddress();
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.updateTargetMarginalFactor(400000000);
    }

    function testSeveralAdjustingPositionAfterChangeInMarginalFactorWETH() public {
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5 * 2, address(this)); // 700% in staking
        creditAccount = gearboxVault.getCreditAccount();
        gearboxVault.adjustPosition();
        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        gearboxVault.updateTargetMarginalFactor(4500000000); // 630% in staking
        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(isClose(convexFantomBalanceBefore * 630, convexFantomBalanceAfter * 700, 100));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT / 5 * 7 * weiofUsdc, 100));

        gearboxVault.updateTargetMarginalFactor(4700000000); // 658% in staking
        assertTrue(checkNotNonExpectedBalance());
        assertTrue(isClose(tvl(), FIRST_DEPOSIT / 5 * 7 * weiofUsdc, 100));
        uint256 convexFantomBalanceFinal = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(isClose(convexFantomBalanceFinal * 630, convexFantomBalanceAfter * 658, 100));
    }

    function testEarnedRewardsWETH() public {

        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5 * 2, address(this)); // 700% in staking

        creditAccount = gearboxVault.getCreditAccount();
        gearboxVault.adjustPosition();

        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        runRewarding(); // +1.63% on staking money

        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 151 / 100, 100));
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 151 / 100, 100));

        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(isClose(convexFantomBalanceBefore * 1081, convexFantomBalanceAfter * 1000, 100));
    }

    function testMultipleDepositsAndRewardsAndAdjustmentsTvlCorrectnessWETH() public {
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5 * 2, address(this));
        gearboxVault.adjustPosition();
        runRewarding(); // +1.63% on staking money

        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 151 / 100, 100));
        deposit(FIRST_DEPOSIT / 5, address(this));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 171 / 100, 100));
        deposit(FIRST_DEPOSIT / 50 * 3, address(this));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 177 / 100, 100));
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 177 / 100, 100));
        gearboxVault.updateTargetMarginalFactor(4000000000);
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 177 / 100, 100));
        deposit(FIRST_DEPOSIT / 10, address(this));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 187 / 100, 100));
        gearboxVault.updateTargetMarginalFactor(5555555555);
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 187 / 100, 100));
    }

    function testWithValueFallingAndRewardsCovering() public {
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5 * 2, address(this)); // 700% in convex
        creditAccount = gearboxVault.getCreditAccount();
        gearboxVault.adjustPosition();

        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        runRewarding(); // +1.63% on staking money => 11.4% earned => 757% in convex

        gearboxVault.updateTargetMarginalFactor(4500000000); // 681% in convex
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 151 / 100, 100));

        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(isClose(convexFantomBalanceAfter*700, convexFantomBalanceBefore*681, 100));
    }

    function testVaultCloseWithoutOrdersAndConvexWETH() public {
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5 * 2, address(this));
        invokeExecution();

        assertTrue(isClose(IERC20(weth).balanceOf(address(gearboxVault)), FIRST_DEPOSIT / 5 * 7 * weiofUsdc, 500));
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
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5 * 2, address(this));
        gearboxVault.adjustPosition();
        invokeExecution();

        assertTrue(isClose(IERC20(weth).balanceOf(address(gearboxVault)), FIRST_DEPOSIT / 5 * 7 * weiofUsdc, 300));

        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testSimpleCloseVaultTvl() public {
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5 * 2, address(this));
        gearboxVault.adjustPosition();
        invokeExecution();

        assertTrue(isClose(tvl(), FIRST_DEPOSIT / 5 * 7 * weiofUsdc, 300));
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testSimpleCloseVaultOkayAfterMultipleOperationsWETH() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();
        deposit(FIRST_DEPOSIT * 2 / 5, address(this));
        gearboxVault.updateTargetMarginalFactor(4000000000);
        gearboxVault.adjustPosition();
        gearboxVault.updateTargetMarginalFactor(4500000000); // 630% on convex

        runRewarding(); // +1.63% on staking money => 10.3% earned

        invokeExecution();

        assertTrue(isClose(IERC20(weth).balanceOf(address(gearboxVault)), FIRST_DEPOSIT * 150 / 100 * weiofUsdc, 100));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 150 / 100 * weiofUsdc, 100));
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testCloseVaultAfterNegativeAdjusting() public {
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT * 2 / 5, address(this));
        gearboxVault.updateTargetMarginalFactor(4000000000);

        invokeExecution();
        assertTrue(isClose(IERC20(weth).balanceOf(address(gearboxVault)), FIRST_DEPOSIT * 7 / 5 * weiofUsdc, 100));
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testCloseVaultWithOneOrderWETH() public {
        deposit(FIRST_DEPOSIT, address(this)); // 500 mETH
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));

        rootVault.registerWithdrawal(lpTokens / 2);
        vm.warp(block.timestamp + YEAR / 12); // to impose root vault fees
        invokeExecution();

        uint256 leftOnGearbox = IERC20(weth).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(weth).balanceOf(address(erc20Vault));

        assertTrue(leftOnGearbox * 995 > wentForWithdrawal * 1000); // the result of fees

        deposit(FIRST_DEPOSIT / 5 * 3, address(this));
        gearboxVault.adjustPosition();

        assertTrue(isClose(tvl(), FIRST_DEPOSIT / 10 * 11 * weiofUsdc, 100));

        address recipient = getNextUserAddress();

        uint256 oldSupply = rootVault.totalSupply();

        claimMoney(recipient);
        assertTrue(isClose(IERC20(weth).balanceOf(recipient), FIRST_DEPOSIT / 2 * weiofUsdc, 100));
        uint256 newSupply = rootVault.totalSupply();
        
        assertTrue(oldSupply - lpTokens / 2 == newSupply);
    }

    function testCloseVaultWithOneLargerOrderWETH() public {
        deposit(FIRST_DEPOSIT, address(this)); // 500 mETH
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));

        rootVault.registerWithdrawal(lpTokens * 3 / 4); // 375 mETH
        invokeExecution();

        deposit(FIRST_DEPOSIT / 5 * 4, address(this));
        gearboxVault.adjustPosition();

        assertTrue(isClose(tvl(), FIRST_DEPOSIT / 20 * 21 * weiofUsdc, 100));

        address recipient = getNextUserAddress();

        uint256 oldSupply = rootVault.totalSupply();

        claimMoney(recipient);
        assertTrue(isClose(IERC20(weth).balanceOf(recipient), FIRST_DEPOSIT / 4 * 3 * weiofUsdc, 100));
        uint256 newSupply = rootVault.totalSupply();
        
        assertTrue(oldSupply - lpTokens * 3 / 4 == newSupply);
    }

    function testCloseVaultWithOneFullWETH() public {
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5 * 3, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));

        rootVault.registerWithdrawal(lpTokens); // 800 mETH
        invokeExecution();

       // assertTrue(tvl() > 0);
        address recipient = getNextUserAddress();

        claimMoney(recipient);
        assertTrue(isClose(IERC20(weth).balanceOf(recipient), FIRST_DEPOSIT / 5 * 8 * weiofUsdc, 100));
    }


    function testCloseVaultWithSeveralDepositsAndPartialWithdrawalsWETH() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 mETH

        address secondUser = getNextUserAddress();
        vm.startPrank(secondUser);

        deposit(FIRST_DEPOSIT / 5, secondUser);
        uint256 secondUserLpTokens = rootVault.balanceOf(secondUser);
        rootVault.registerWithdrawal(secondUserLpTokens / 4); // 25 mETH

        vm.stopPrank();
        invokeExecution();

        uint256 leftOnGearbox = IERC20(weth).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(weth).balanceOf(address(erc20Vault));
        assertTrue(isClose(leftOnGearbox, FIRST_DEPOSIT * 13 / 20 * weiofUsdc, 100));
        assertTrue(isClose(wentForWithdrawal, FIRST_DEPOSIT * 11 / 20 * weiofUsdc, 100));


        address recipient = getNextUserAddress();
        claimMoney(recipient);
        assertTrue(isClose(IERC20(weth).balanceOf(recipient), FIRST_DEPOSIT / 2 * weiofUsdc, 80));

        vm.startPrank(secondUser);
        claimMoney(recipient);
        assertTrue(isClose(IERC20(weth).balanceOf(recipient), FIRST_DEPOSIT * 11 / 20 * weiofUsdc, 80));
        vm.stopPrank();

        claimMoney(recipient);
        assertTrue(isClose(IERC20(weth).balanceOf(recipient), FIRST_DEPOSIT * 11 / 20 * weiofUsdc, 80));
    }

    function testSeveralInvocationsWhenFirstNotTakenAndNewSumIsMoreWETH() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 mETH

        invokeExecution();
        vm.warp(block.timestamp + 86400 * 10);

        deposit(FIRST_DEPOSIT, address(this));

        rootVault.registerWithdrawal(lpTokens * 2 / 3); // ~333 mETH
        invokeExecution();

        uint256 leftOnGearbox = IERC20(weth).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(weth).balanceOf(address(erc20Vault));
        assertTrue(isClose(leftOnGearbox, FIRST_DEPOSIT / 6 * 5 * weiofUsdc, 100));
        assertTrue(isClose(wentForWithdrawal, FIRST_DEPOSIT / 6 * 7 * weiofUsdc, 100));
    }

    function testSeveralInvocationsWhenFirstNotTakenAndNewSumIsLessWETH() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 mETH

        invokeExecution();
        vm.warp(block.timestamp + 86400 * 10);

        deposit(FIRST_DEPOSIT, address(this));

        rootVault.registerWithdrawal(lpTokens / 3); // ~166 mETH
        invokeExecution();

        uint256 leftOnGearbox = IERC20(weth).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(weth).balanceOf(address(erc20Vault));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT / 6 * 7 * weiofUsdc, 100));
        assertTrue(isClose(leftOnGearbox, FIRST_DEPOSIT / 6 * 7 * weiofUsdc, 100));
        assertTrue(isClose(wentForWithdrawal, FIRST_DEPOSIT / 6 * 5 * weiofUsdc, 100));
    }

    function testCancelWithdrawalIsOkayWETH() public {
        deposit(FIRST_DEPOSIT, address(this)); 
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 USD
        rootVault.cancelWithdrawal(lpTokens / 4); // cancel 125 USD

        invokeExecution();
        address recipient = getNextUserAddress();
        claimMoney(recipient);

        assertTrue(isClose(IERC20(weth).balanceOf(recipient), FIRST_DEPOSIT / 4 * weiofUsdc, 50)); // anyway only 125 usd claimed
    }

    function testWitdrawalOrderCancelsAfterTime() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 mETH

        invokeExecution();
        deposit(FIRST_DEPOSIT, address(this));
        vm.warp(block.timestamp + 86400 * 10);
        invokeExecution();

        address recipient = getNextUserAddress();
        claimMoney(recipient); 

        assertTrue(isClose(IERC20(weth).balanceOf(recipient), FIRST_DEPOSIT / 2 * weiofUsdc, 20));
    }

    function testFailTwoInvocationsInShortTime() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        invokeExecution();
        deposit(FIRST_DEPOSIT, address(this));
        vm.warp(block.timestamp + 86400 * 3); // only 3 days
        invokeExecution();
    }

    
}
