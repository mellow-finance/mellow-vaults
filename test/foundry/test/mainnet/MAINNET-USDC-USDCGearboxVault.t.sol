// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/ProtocolGovernance.sol";
import "../../src/MockOracle.sol";
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

import "../../src/interfaces/external/gearbox/ICreditFacade.sol";

import "../../src/interfaces/IDegenNft.sol";

import "../helpers/MockDistributor.t.sol";

contract GearboxUSDCTest is Test {

    event CreditAccountOpened(address indexed origin, address indexed sender, address indexed creditAccount);

    ProtocolGovernance governance;
    VaultRegistry registry;

    GearboxRootVault rootVault = new GearboxRootVault();
    ERC20Vault erc20Vault = new ERC20Vault();
    GearboxVault gearboxVault = new GearboxVault();   

    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;
    address cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    MockDegenDistributor distributor = new MockDegenDistributor();
    address configurator = 0xA7D5DDc1b8557914F158076b228AA91eF613f1D5;

    address treasuryA;
    address treasuryB;
    address creditAccount;

    ICurveV1Adapter curveAdapter;
    IConvexV1BaseRewardPoolAdapter convexAdapter;

    ERC20RootVaultGovernance governanceA;
    uint256 nftStart;

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

        uint256 usdcBalance = IERC20(usdc).balanceOf(creditAccount);
        uint256 curveLpBalance = IERC20(curveAdapter.lp_token()).balanceOf(creditAccount);
        uint256 convexLpBalance = IERC20(convexAdapter.stakingToken()).balanceOf(creditAccount);

        if (usdcBalance > 1 || curveLpBalance > 1 || convexLpBalance > 1) {
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
            univ3Adapter: 0x3883500A0721c09DC824421B00F79ae524569E09,
            crv: 0xD533a949740bb3306d119CC777fa900bA034cd52,
            cvx: cvx,
            maxSlippageD9: 100000000,
            maxSmallPoolsSlippageD9: 20000000,
            maxCurveSlippageD9: 500000000,
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
        GearboxVaultGovernance governanceC = new GearboxVaultGovernance(internalParamsC, delayedParams);
        
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

        treasuryA = getNextUserAddress();
        treasuryB = getNextUserAddress();

        IERC20RootVaultGovernance.DelayedStrategyParams memory delayedStrategyParams = IERC20RootVaultGovernance.DelayedStrategyParams({
            strategyTreasury: treasuryA,
            strategyPerformanceTreasury: treasuryB,
            privateVault: false,
            managementFee: 10**8,
            performanceFee: 10**8,
            depositCallbackAddress: address(0),
            withdrawCallbackAddress: address(0)
        });

        nftStart = registry.vaultsCount() + 1;

        IGearboxVaultGovernance.DelayedProtocolPerVaultParams memory delayedVaultParams = IGearboxVaultGovernance.DelayedProtocolPerVaultParams({
            primaryToken: usdc,
            curveAdapter: 0xa4b2b3Dede9317fCbd9D78b8250ac44Bf23b64F4,
            convexAdapter: 0x023e429Df8129F169f9756A4FBd885c18b05Ec2d,
            facade: 0x61fbb350e39cc7bF22C01A469cf03085774184aa,
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
            governanceC.commitDelayedProtocolPerVaultParams(nftStart + 1);
            governanceA.commitDelayedStrategyParams(nftStart + 2);

            vm.stopPrank();

        }

        address[] memory tokens = new address[](1);
        tokens[0] = usdc; 

        deal(usdc, address(governanceC), 5*10**8);

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

        curveAdapter = ICurveV1Adapter(0xa4b2b3Dede9317fCbd9D78b8250ac44Bf23b64F4);
        convexAdapter = IConvexV1BaseRewardPoolAdapter(0x023e429Df8129F169f9756A4FBd885c18b05Ec2d);
        
        governanceA.setStrategyParams(nftStart + 2, strategyParams);
        IERC20(usdc).approve(address(rootVault), type(uint256).max);

        address degenNft = ICreditFacade(gearboxVault.creditFacade()).degenNFT();
        vm.startPrank(configurator);
        IDegenNFT(degenNft).setMinter(address(distributor));
        vm.stopPrank();

        bytes32[] memory arr = new bytes32[](1);
        arr[0] = DegenConstants.DEGEN;

        gearboxVault.setMerkleParameters(0, 20, arr);
    }

    function testSetup() public {
        uint256 usdcBalance = IERC20(usdc).balanceOf(address(gearboxVault));
        assertTrue(usdcBalance == 0);
        assertTrue(gearboxVault.getCreditAccount() == address(0));
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

        deal(usdc, address(this), 10**4);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10**4;
        IERC20(usdc).approve(address(rootVault), type(uint256).max);

        rootVault.deposit(amounts, 0, "");
    }

    function deposit(uint256 amount, address user) public {

        if (rootVault.totalSupply() == 0) {
            firstDeposit();
        }

        deal(usdc, user, amount * 10**6);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount * 10**6;

        vm.startPrank(user);
        IERC20(usdc).approve(address(rootVault), type(uint256).max);
        rootVault.deposit(amounts, 0, "");
        vm.stopPrank();

        if (gearboxVault.getCreditAccount() == address(0)) {
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

    function tvl() public returns (uint256) {
        (uint256[] memory result, ) = gearboxVault.tvl();
        assertTrue(result.length == 1);
        return result[0];
    }

    function testFailOpenVaultWithoutFunds() public {
        gearboxVault.openCreditAccount();
    }

    function testFailOpenVaultFromAnyAddress() public {
        vm.startPrank(getNextUserAddress());
        gearboxVault.openCreditAccount();
        vm.stopPrank();
    }

    function testSimpleDepositUSDC() public {

        deposit(FIRST_DEPOSIT, address(this));

        creditAccount = gearboxVault.getCreditAccount();

        uint256 usdcBalance = IERC20(usdc).balanceOf(creditAccount);
        uint256 curveLpBalance = IERC20(curveAdapter.lp_token()).balanceOf(creditAccount);
        uint256 convexLpBalance = IERC20(convexAdapter.stakingToken()).balanceOf(creditAccount);
        uint256 convexFantomBalance = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(usdcBalance == FIRST_DEPOSIT * 5 * 10**6 + 5 * 10**4);
        assertTrue(curveLpBalance == 0);
        assertTrue(convexLpBalance == 0);
        assertTrue(convexFantomBalance == 0);
    }

    function testTwoDepositsUSDC() public {
        
        deposit(FIRST_DEPOSIT, address(this));
        uint256 lpAmountBefore = rootVault.balanceOf(address(this));

        deposit(FIRST_DEPOSIT / 5, address(this));
        uint256 lpAmountAfter = rootVault.balanceOf(address(this));

        creditAccount = gearboxVault.getCreditAccount();

        uint256 usdcBalance = IERC20(usdc).balanceOf(creditAccount);
        uint256 curveLpBalance = IERC20(curveAdapter.lp_token()).balanceOf(creditAccount);
        uint256 convexLpBalance = IERC20(convexAdapter.stakingToken()).balanceOf(creditAccount);
        uint256 convexFantomBalance = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(usdcBalance >= (FIRST_DEPOSIT / 5 * 26) * 10 ** 6 + 4*10**4 && usdcBalance <= (FIRST_DEPOSIT / 5 * 26) * 10 ** 6 + 6*10**4);
        assertTrue(curveLpBalance == 0);
        assertTrue(convexLpBalance == 0);
        assertTrue(convexFantomBalance == 0);

        assertTrue(isClose(lpAmountBefore * 6, lpAmountAfter * 5, 100));
    }

    function testFailTooSmallInitialDepositFail() public {
        deposit(100, address(this));
    }

    function testTvlOfEmptyVault() public {
        assertTrue(tvl() == 0);
    }

    function testTvlAfterSingleDepositUSDC() public {
        deposit(FIRST_DEPOSIT, address(this));
        assertTrue(tvl() == FIRST_DEPOSIT * 10**6 + 10**4 - 1);
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
        console.log(tvl());
        assertTrue(tvl() < FIRST_DEPOSIT * 10**6 * 995 / 1000); // some fees > 0.5% accrued
    }

    function testTvlAfterMultipleDepositsUSDC() public {
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5, address(this));
        deposit(FIRST_DEPOSIT / 10, address(this));
        assertTrue(tvl() >= (FIRST_DEPOSIT / 10 * 13) * 10**6 + 5*10**3 && tvl() <= (FIRST_DEPOSIT / 10 * 13) * 10**6 + 15*10**3);
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

    function testSimpleAdjustingPosition() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        creditAccount = gearboxVault.getCreditAccount();

        assertTrue(checkNotNonExpectedBalance());
        uint256 convexFantomBalance = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(convexFantomBalance > 0);

        deposit(FIRST_DEPOSIT / 5, address(this));
        gearboxVault.adjustPosition();
        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(isClose(convexFantomBalance * 6, convexFantomBalanceAfter * 5, 100));
    }

    function testSimpleAdjustingPositionAndTvl() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 10**6, 100));
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
        gearboxVault.updateTargetMarginalFactor(2000000000);
    }

    function testFailChangingMarginalFactorLowerThanOne() public {
        address addr = getNextUserAddress();
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.updateTargetMarginalFactor(200000000);
    }

    function testFailTooSmallDepositButPreviouslyConsideredOkay() public {
        deposit(23000, address(this));
    }

    function testSeveralAdjustingPositionAfterChangeInMarginalFactor() public {
        deposit(FIRST_DEPOSIT, address(this));
        creditAccount = gearboxVault.getCreditAccount();
        gearboxVault.adjustPosition();
        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        gearboxVault.updateTargetMarginalFactor(4500000000);
        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(isClose(convexFantomBalanceBefore * 45, convexFantomBalanceAfter * 50, 100));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 10**6, 100));

        assertTrue(checkNotNonExpectedBalance());

        gearboxVault.updateTargetMarginalFactor(4700000000);
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 10**6, 100));
        uint256 convexFantomBalanceFinal = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(isClose(convexFantomBalanceFinal * 45, convexFantomBalanceAfter * 47, 100));
    }

    function testTvlIsCloseToRealValue() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();
        uint256 currentTvl = tvl();

        assertTrue(currentTvl >= FIRST_DEPOSIT * 10**6 * 998 / 1000 && currentTvl <= FIRST_DEPOSIT * 10**6 * 1002 / 1000); // ~0.2% deviation seems acceptable
    }

    function runRewarding() public {
        ICreditManagerV2 manager = gearboxVault.creditManager();
        address cont = manager.adapterToContract(address(convexAdapter));

        BaseRewardPool rewardsPool = BaseRewardPool(cont);
        vm.startPrank(rewardsPool.operator());
        for (uint256 i = 0; i < 53; ++i) {
            rewardsPool.queueNewRewards(rewardsPool.currentRewards() - rewardsPool.queuedRewards());
            vm.warp(block.timestamp + rewardsPool.duration() + 1);
        }
        vm.stopPrank();
    }

    function testTvlAfterYearIsNetPositive() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();
        runRewarding();
        vm.warp(block.timestamp + YEAR);
        uint256 currentTvl = tvl();

        assertTrue(currentTvl >= FIRST_DEPOSIT * 10**6 * 105 / 100); // earn at least 5%
    }

    function testCrvAndCvxIsOkay() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();
        runRewarding();

        ICreditManagerV2 manager = gearboxVault.creditManager();
        address cont = manager.adapterToContract(address(convexAdapter));

        BaseRewardPool rewardsPool = BaseRewardPool(cont);
        creditAccount = gearboxVault.getCreditAccount();

        uint256 crvAmount = rewardsPool.earned(creditAccount);

        assertTrue(crvAmount > 0);
        assertTrue(helper2.calculateEarnedCvxAmountByEarnedCrvAmount(crvAmount, cvx) > 0);
    }


    function testMultipleDepositsAndRewardsAndAdjustmentsTvlCorrectness() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();
        runRewarding(); // +12.2%

        console.log(tvl());

        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 10**6 * 1122 / 1000, 100));
        deposit(FIRST_DEPOSIT / 5, address(this));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 10**6 * 1322 / 1000, 100));
        deposit(FIRST_DEPOSIT / 20, address(this));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 10**6 * 1372 / 1000, 100));
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 10**6 * 1372 / 1000, 100));
        gearboxVault.updateTargetMarginalFactor(6000000000);
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 10**6 * 1372 / 1000, 100));
        deposit(FIRST_DEPOSIT / 20, address(this));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 10**6 * 1422 / 1000, 100));
        gearboxVault.updateTargetMarginalFactor(6666666666);
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 10**6 * 1422 / 1000, 100));
    }

    function testWithValueFallingAndRewardsCovering() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        runRewarding(); // +12.2%

        gearboxVault.updateTargetMarginalFactor(5900000000);
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 10**6 * 1122 / 1000, 100));

        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(checkNotNonExpectedBalance());
        assertTrue(isClose(convexFantomBalanceAfter*1000, convexFantomBalanceBefore*1122, 100));
    }

    function testVaultCloseWithoutOrdersAndConvex() public {
        deposit(FIRST_DEPOSIT, address(this));
        invokeExecution();

        assertTrue(isClose(IERC20(usdc).balanceOf(address(gearboxVault)), FIRST_DEPOSIT * 10**6, 100));
        assertTrue(IERC20(usdc).balanceOf(address(erc20Vault)) == 0);
        assertTrue(IERC20(usdc).balanceOf(address(rootVault)) == 0);

        assertTrue(gearboxVault.getCreditAccount() == address(0));
    }


    function checkIfSimpleCloseIsOkay() public returns (bool) {
        if (IERC20(usdc).balanceOf(address(erc20Vault)) != 0) {
            return false;
        }
        if (IERC20(usdc).balanceOf(address(rootVault)) != 0) {
            return false;
        }

        if (gearboxVault.getCreditAccount() != address(0)) {
            return false;
        }
        return true;
    }

    function testVaultCloseWithoutOrdersButWithConvex() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();
        invokeExecution();

        assertTrue(isClose(IERC20(usdc).balanceOf(address(gearboxVault)), FIRST_DEPOSIT * 10**6, 100));
        assertTrue(IERC20(usdc).balanceOf(address(gearboxVault)) < FIRST_DEPOSIT * 10**6 * 9999 / 10000); //some funds spent to comissions
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testSimpleCloseVaultTvl() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();
        invokeExecution();

        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 10**6, 100));
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testSimpleCloseVaultOkayAfterMultipleOperations() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();
        deposit(FIRST_DEPOSIT / 5, address(this));
        gearboxVault.updateTargetMarginalFactor(6000000000);
        gearboxVault.adjustPosition();
        gearboxVault.updateTargetMarginalFactor(5000000000);

        runRewarding(); // +12.2%

        invokeExecution();

        assertTrue(isClose(IERC20(usdc).balanceOf(address(gearboxVault)), FIRST_DEPOSIT * 10**6 * 6 / 5 * 1122 / 1000, 100));
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testCloseVaultAfterNegativeAdjusting() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.updateTargetMarginalFactor(4000000000);

        invokeExecution();
        assertTrue(isClose(IERC20(usdc).balanceOf(address(gearboxVault)), FIRST_DEPOSIT * 10**6, 100));
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testCloseVaultWithOneOrder() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));

        rootVault.registerWithdrawal(lpTokens / 2);
        vm.warp(block.timestamp + YEAR / 12); // to impose root vault fees
        invokeExecution();

        uint256 leftOnGearbox = IERC20(usdc).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(usdc).balanceOf(address(erc20Vault));

        assertTrue(leftOnGearbox * 995 > wentForWithdrawal * 1000); // the result of fees

        deposit(FIRST_DEPOSIT * 3 / 5, address(this));
        gearboxVault.adjustPosition();
        

        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 10**6 * 1102 / 1000, 100));

        address recipient = getNextUserAddress();

        uint256 oldSupply = rootVault.totalSupply();

        claimMoney(recipient);

        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), FIRST_DEPOSIT * 10**6 * 498 / 1000, 100));
        uint256 newSupply = rootVault.totalSupply();
        
        assertTrue(oldSupply - lpTokens / 2 == newSupply);
    }

    function testCloseVaultWithSeveralDepositsAndPartialWithdrawalsUSDC() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 50%

        address secondUser = getNextUserAddress();

        deposit(FIRST_DEPOSIT / 5, secondUser);
        uint256 secondUserLpTokens = rootVault.balanceOf(secondUser);
        vm.startPrank(secondUser);
        rootVault.registerWithdrawal(secondUserLpTokens / 4); // 5% 

        vm.stopPrank();
        invokeExecution();

        uint256 leftOnGearbox = IERC20(usdc).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(usdc).balanceOf(address(erc20Vault));
        assertTrue(isClose(leftOnGearbox, FIRST_DEPOSIT * 10**6 * 65 / 100, 100));
        assertTrue(isClose(wentForWithdrawal, FIRST_DEPOSIT * 10**6 * 55 / 100, 100));


        address recipient = getNextUserAddress();
        claimMoney(recipient);
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), FIRST_DEPOSIT * 10**6 / 2, 100));

        vm.startPrank(secondUser);
        claimMoney(recipient);
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), FIRST_DEPOSIT * 10**6 * 55 / 100, 100));
        vm.stopPrank();

        claimMoney(recipient);
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), FIRST_DEPOSIT * 10**6 * 55 / 100, 100));
    }

    function testSeveralInvocationsWhenFirstNotTakenAndNewSumIsMore() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 50%

        invokeExecution();
        vm.warp(block.timestamp + 86400 * 10);

        deposit(FIRST_DEPOSIT, address(this));

        rootVault.registerWithdrawal(lpTokens * 2 / 3); // 66.6%
        invokeExecution();

        uint256 leftOnGearbox = IERC20(usdc).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(usdc).balanceOf(address(erc20Vault));
        assertTrue(isClose(leftOnGearbox, FIRST_DEPOSIT * 10**6 * 5 / 6, 100));
        assertTrue(isClose(wentForWithdrawal, FIRST_DEPOSIT * 10**6 * 7 / 6, 100));
    }

    function testSeveralInvocationsWhenFirstNotTakenAndNewSumIsLessUSDC() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 50%

        invokeExecution();
        vm.warp(block.timestamp + 86400 * 10);

        deposit(FIRST_DEPOSIT, address(this));

        rootVault.registerWithdrawal(lpTokens / 3); // 33.3%
        invokeExecution();

        uint256 leftOnGearbox = IERC20(usdc).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(usdc).balanceOf(address(erc20Vault));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 10**6 * 7 / 6, 100));
        assertTrue(isClose(leftOnGearbox, FIRST_DEPOSIT * 10**6 * 7 / 6, 100));
        assertTrue(isClose(wentForWithdrawal, FIRST_DEPOSIT * 10**6 * 5 / 6, 100));
    }

    function testCancelWithdrawalIsOkayUSDC() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 50%
        rootVault.cancelWithdrawal(lpTokens / 4); // 25%

        invokeExecution();
        address recipient = getNextUserAddress();
        claimMoney(recipient);

        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), FIRST_DEPOSIT * 10**6 / 4, 100)); // anyway only 125 usd claimed
    }

    function valueIncreasesAfterWithdrawal() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 50%

        invokeExecution();

        address secondUser = getNextUserAddress();
        vm.startPrank(secondUser);
        deposit(FIRST_DEPOSIT, secondUser);
        vm.stopPrank();
        
        runRewarding(); // +12.2% => (150%) * 1.122 = 168.3%
        address recipient = getNextUserAddress();
        claimMoney(recipient); // 50% claimed

        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), FIRST_DEPOSIT * 10**6 / 2, 100)); // anyway only 250 usd claimed
        vm.startPrank(secondUser);
        rootVault.registerWithdrawal(lpTokens / 2); // the same lp amount but this is 56.1%
        vm.stopPrank();

        vm.warp(block.timestamp + 86400 * 10);
        invokeExecution();

        vm.startPrank(secondUser);
        claimMoney(recipient);
        vm.stopPrank();

        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), FIRST_DEPOSIT * 10**6 * 1061 / 1000, 100));
        claimMoney(recipient); // try to claim by the first user
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), FIRST_DEPOSIT * 10**6 * 1061 / 1000, 100));
    }

    function testWitdrawalOrderCancelsAfterTime() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 50%

        invokeExecution();
        deposit(FIRST_DEPOSIT, address(this));
        vm.warp(block.timestamp + 86400 * 10);
        invokeExecution();

        address recipient = getNextUserAddress();
        claimMoney(recipient); 

        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), FIRST_DEPOSIT * 10**6 / 2, 100)); // successfully claimed
    }

    function testFailTwoInvocationsInShortTime() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        invokeExecution();
        deposit(FIRST_DEPOSIT, address(this));
        vm.warp(block.timestamp + 86400 * 3); // only 3 days
        invokeExecution();
    }

    function testCreditAccountGetter() public {
        assertTrue(gearboxVault.getCreditAccount() == address(0));
        deposit(FIRST_DEPOSIT, address(this));
        assertTrue(gearboxVault.getCreditAccount() != address(0));
        invokeExecution();
        assertTrue(gearboxVault.getCreditAccount() == address(0));
    }

    function testPullFromEmptyVault() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        invokeExecution();
        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 50%

        address recipient = getNextUserAddress();
        
        vm.warp(block.timestamp + 86400 * 10);

        invokeExecution();
        claimMoney(recipient); 

        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), FIRST_DEPOSIT * 10**6 / 2, 100)); // successfully claimed
        uint256 leftOnGearbox = IERC20(usdc).balanceOf(address(gearboxVault));
        assertTrue(isClose(leftOnGearbox, FIRST_DEPOSIT*10**6 / 2, 100));
    }

    function requestWithdrawal(uint256 lpTokensAmount, address addr) public {
        vm.startPrank(addr);
        rootVault.registerWithdrawal(lpTokensAmount); 
        vm.stopPrank();
    }

    function cancelWithdrawal(uint256 lpTokensAmount, address addr) public {
        vm.startPrank(addr);
        rootVault.cancelWithdrawal(lpTokensAmount); 
        vm.stopPrank();
    }


    function claimMoneySpecial(address recipient, address addr) public {
        vm.startPrank(addr);
        claimMoney(recipient); 
        vm.stopPrank();
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

    function testALotOfClaims() public {
        setZeroFees();
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();
        address actorA = getNextUserAddress();
        address actorB = getNextUserAddress();
        address actorC = getNextUserAddress();
        address recipient = getNextUserAddress();

        deposit(FIRST_DEPOSIT / 5 * 2, actorA);
        gearboxVault.adjustPosition();
        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2);  // 50%

        invokeExecution();
        vm.warp(block.timestamp + 86400 * 10);

        deposit(FIRST_DEPOSIT / 5, actorA);
        deposit(FIRST_DEPOSIT / 5 * 2, actorB);
        gearboxVault.adjustPosition();

        uint256 lpTokens2 = rootVault.balanceOf(actorA);
        requestWithdrawal(lpTokens2 / 6, actorA); // 10%
        requestWithdrawal(lpTokens2 / 6, actorA); // 10%
        requestWithdrawal(lpTokens2 / 6, actorA); // 10%
        cancelWithdrawal(5 * lpTokens2 / 12, actorA); // 25%
        requestWithdrawal(lpTokens2 / 12, actorA); // 5%
        requestWithdrawal(lpTokens / 4, address(this)); //25%

        deposit(FIRST_DEPOSIT / 10, actorB); //10%
        requestWithdrawal(lpTokens / 50, address(this)); // 2%

        claimMoney(recipient); 
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), FIRST_DEPOSIT * 10**6 / 2, 100)); 

        // HERE 425% are on convex

        runRewarding(); // +12.2% => 425 * (1.122) = 477%

        invokeExecution();
        vm.warp(block.timestamp + 86400 * 10);
        claimMoneySpecial(recipient, actorA); // 11.22%
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), FIRST_DEPOSIT * 10**6 / 2 + FIRST_DEPOSIT * 10**6 / 9, 100)); 

        deposit(FIRST_DEPOSIT / 25, actorC); //4%
        deposit(FIRST_DEPOSIT / 25, actorB); //4%

        claimMoney(recipient);  // 28%
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), FIRST_DEPOSIT * 10**6 * 90 / 100, 50)); 

        uint256 lpTokens3 = rootVault.balanceOf(actorB);
        requestWithdrawal(lpTokens3, actorB);

        invokeExecution();
        vm.warp(block.timestamp + 86400 * 10);
        claimMoneySpecial(recipient, actorB); // 55%
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), FIRST_DEPOSIT * 10**6 * 149 / 100, 50)); 

        claimMoneySpecial(recipient, actorC); 
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), FIRST_DEPOSIT * 10**6 * 149 / 100, 50)); 

        uint256 lpTokens4 = rootVault.balanceOf(actorC);
        deposit(FIRST_DEPOSIT / 5 * 3, actorC); // 60%
        deposit(FIRST_DEPOSIT / 50 * 4, address(this)); // 8%

        requestWithdrawal(lpTokens4 / 2, actorC); //4%

        invokeExecution();
        claimMoneySpecial(recipient, actorC);
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), FIRST_DEPOSIT * 10**6 * 153 / 100, 50)); 
    }


    function testShutdownAndReopen() public {
        deposit(FIRST_DEPOSIT * 6 / 5, address(this));
        gearboxVault.adjustPosition();

        vm.roll(block.number + 1);
        rootVault.shutdown();
        assertTrue(gearboxVault.getCreditAccount() == address(0));
        rootVault.reopen();
        deposit(FIRST_DEPOSIT / 5, address(this));
        assertTrue(gearboxVault.getCreditAccount() != address(0));
    }

    function testFailDoubleShutdown() public {
        deposit(FIRST_DEPOSIT * 6 / 5, address(this));
        gearboxVault.adjustPosition();

        vm.roll(block.number + 1);
        rootVault.shutdown();
        vm.roll(block.number + 1);
        rootVault.shutdown();
    }

    function testFailShutdownFromWrongAddress() public {
        address addr = getNextUserAddress();
        vm.startPrank(addr);
        vm.roll(block.number + 1);
        rootVault.shutdown();
        vm.stopPrank();
    }

    function testFailDepositAfterShutdown() public {
        deposit(FIRST_DEPOSIT * 6 / 5, address(this));
        gearboxVault.adjustPosition();

        vm.roll(block.number + 1);
        rootVault.shutdown();
        deposit(FIRST_DEPOSIT / 5, address(this));
    }

    function testWithdrawAfterShutdownIsOkay() public {
        deposit(FIRST_DEPOSIT * 6 / 5, address(this));
        gearboxVault.adjustPosition();

        vm.roll(block.number + 1);
        rootVault.shutdown();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2);  // 60%
        invokeExecution();
        rootVault.registerWithdrawal(lpTokens / 20);  // 6%
        invokeExecution();
        rootVault.registerWithdrawal(lpTokens / 20);  // 6%
        invokeExecution();
        rootVault.registerWithdrawal(lpTokens / 20);  // 6%
        invokeExecution();
        rootVault.registerWithdrawal(lpTokens / 20);  // 6%
        rootVault.registerWithdrawal(lpTokens / 20);  // 6%
        rootVault.registerWithdrawal(lpTokens / 20);  // 6%
        invokeExecution();

        address recipient = getNextUserAddress();
        claimMoney(recipient); 
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), FIRST_DEPOSIT * 10**6 * 48 / 50, 100)); 
    }

    function testZeroBalanceAfterAdjusting() public {
        deposit(FIRST_DEPOSIT * 6 / 5, address(this));
        deposit(FIRST_DEPOSIT / 5, address(this));
        gearboxVault.adjustPosition();
        assertTrue(IERC20(usdc).balanceOf(address(gearboxVault)) == 0);

        deposit(FIRST_DEPOSIT * 2 / 5, address(this));
        assertTrue(IERC20(usdc).balanceOf(address(gearboxVault)) == 0);

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2);
        invokeExecution();

        deposit(FIRST_DEPOSIT * 2 / 5, address(this));
        assertTrue(IERC20(usdc).balanceOf(address(gearboxVault)) == 0);
    }


    function testFailLiquidationCaseGoesAndSubsequentDepositDown() public {
        deposit(FIRST_DEPOSIT * 6 / 5, address(this));
        //gearboxVault.adjustPosition();

        vm.warp(block.timestamp + YEAR * 50);

        address liquidator = getNextUserAddress();
        deal(usdc, liquidator, 10**20);

        vm.startPrank(liquidator);

        MultiCall[] memory noCalls = new MultiCall[](0);

        vm.roll(block.number + 1);
        IERC20(usdc).approve(address(gearboxVault.creditManager()), type(uint256).max);
        ICreditFacade(gearboxVault.creditFacade()).liquidateCreditAccount(address(gearboxVault), liquidator, 0, false, noCalls);
        vm.stopPrank();

        assertTrue(gearboxVault.getCreditAccount() == address(0));
        assertTrue(tvl() == 0);

        gearboxVault.adjustPosition();
        gearboxVault.updateTargetMarginalFactor(2000000000);
        assertTrue(tvl() == 0);

        deposit(FIRST_DEPOSIT * 6 / 5, address(this));
    }

    function testFailNotLiquidatedUntilTvlLessZeroWithDeposit() public {
        deposit(FIRST_DEPOSIT * 6 / 5, address(this));
        vm.warp(block.timestamp + YEAR * 10000);
        assertTrue(tvl() == 0);
        assertTrue(gearboxVault.getCreditAccount() != address(0));
        deposit(FIRST_DEPOSIT * 6 / 5, address(this));
    }

    function testShutdownAndPriceDown() public {
        deposit(FIRST_DEPOSIT * 6 / 5, address(this));
        vm.warp(block.timestamp + YEAR * 10);

        vm.roll(block.number + 1);
        rootVault.shutdown();
        vm.warp(block.timestamp + YEAR * 40);
        assertTrue(tvl() > FIRST_DEPOSIT * 3 / 5 * 10**6);

        rootVault.reopen();
        deposit(FIRST_DEPOSIT, address(this));
    }

    function testPerformanceFees() public {
        deposit(FIRST_DEPOSIT * 6 / 5, address(this));
        gearboxVault.adjustPosition();
        assertTrue(rootVault.balanceOf(treasuryB) == 0);
        deposit(1, address(this));
        runRewarding(); // +12.2%
        deposit(1, address(this));

        uint256 treasuryBalance = rootVault.balanceOf(treasuryB);
        assertTrue(treasuryBalance > 0);

        requestWithdrawal(treasuryBalance, treasuryB);

        invokeExecution();

        address recipient = getNextUserAddress();
        claimMoneySpecial(recipient, treasuryB);

        assertTrue(IERC20(usdc).balanceOf(recipient) > FIRST_DEPOSIT / 100 * 10**6);
    }


    function testManagementFees() public {
        deposit(FIRST_DEPOSIT * 6 / 5, address(this));
        gearboxVault.adjustPosition();
        assertTrue(rootVault.balanceOf(treasuryA) == 0);

        vm.warp(block.timestamp + YEAR);
        deposit(1, address(this));

        uint256 treasuryBalance = rootVault.balanceOf(treasuryA);
        assertTrue(treasuryBalance > 0);

        requestWithdrawal(treasuryBalance, treasuryA);

        invokeExecution();

        address recipient = getNextUserAddress();
        claimMoneySpecial(recipient, treasuryA);

        assertTrue(IERC20(usdc).balanceOf(recipient) > FIRST_DEPOSIT / 10 * 10**6);
    }


}
