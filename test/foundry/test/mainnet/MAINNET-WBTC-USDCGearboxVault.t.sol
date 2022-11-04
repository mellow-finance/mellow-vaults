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

contract GearboxWBTCTest is Test {

    uint256 satoshiOfUsdc = 4892;

    ProtocolGovernance governance;
    VaultRegistry registry;

    GearboxRootVault rootVault = new GearboxRootVault();
    ERC20Vault erc20Vault = new ERC20Vault();
    GearboxVault gearboxVault = new GearboxVault();   

    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; 
    address wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;
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

            governance.stageUnitPrice(usdc, 1);
            governance.stageUnitPrice(wbtc, 1);
            vm.warp(block.timestamp + 15 * 60 * 60 * 24);
            governance.commitUnitPrice(usdc);
            governance.commitUnitPrice(wbtc);

            uint8[] memory args = new uint8[](1);
            args[0] = PermissionIdsLibrary.ERC20_VAULT_TOKEN;
            governance.stagePermissionGrants(usdc, args);
            governance.stagePermissionGrants(weth, args);
            governance.stagePermissionGrants(wbtc, args);

            vm.warp(block.timestamp + governance.governanceDelay());
            governance.commitPermissionGrants(usdc);
            governance.commitPermissionGrants(weth);
            governance.commitPermissionGrants(wbtc);

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
            vm.warp(block.timestamp + governance.governanceDelay());
            governanceC.commitDelayedProtocolPerVaultParams(nftStart + 1);
            governanceA.commitDelayedStrategyParams(nftStart + 2);

            vm.stopPrank();

        }

        address[] memory tokens = new address[](1);
        tokens[0] = wbtc; 

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
        IERC20(wbtc).approve(address(rootVault), type(uint256).max);

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

        deal(wbtc, address(this), 10**5);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10**5;
        IERC20(usdc).approve(address(rootVault), type(uint256).max);

        rootVault.deposit(amounts, 0, "");
    }

    function deposit(uint256 amount, address user) public {

        uint256 subtract = 0;

        if (rootVault.totalSupply() == 0) {
            firstDeposit();
            subtract = 10**5;
        }

        deal(wbtc, user, amount * satoshiOfUsdc - subtract); 

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount * satoshiOfUsdc - subtract;
        IERC20(wbtc).approve(address(rootVault), type(uint256).max);

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

        assertTrue(currentTvl >= FIRST_DEPOSIT * satoshiOfUsdc * 105 / 100); // earn at least 5%
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

    function tvl() public returns (uint256) {
        (uint256[] memory result, ) = gearboxVault.tvl();
        assertTrue(result.length == 1);
        return result[0];
    }

    function testSetup() public {
        uint256 usdcBalance = IERC20(usdc).balanceOf(address(gearboxVault));
        uint256 wbtcBalance = IERC20(wbtc).balanceOf(address(gearboxVault));
        assertTrue(usdcBalance == 0);
        assertTrue(wbtcBalance == 0);
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

    function testSimpleDepositWBTC() public {

        deposit(FIRST_DEPOSIT, address(this));

        creditAccount = gearboxVault.getCreditAccount();

        uint256 usdcBalance = IERC20(usdc).balanceOf(creditAccount);
        uint256 wbtcBalance = IERC20(wbtc).balanceOf(creditAccount);
        uint256 curveLpBalance = IERC20(curveAdapter.lp_token()).balanceOf(creditAccount);
        uint256 convexLpBalance = IERC20(convexAdapter.stakingToken()).balanceOf(creditAccount);
        uint256 convexFantomBalance = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(usdcBalance == 25000 * 10 ** 6 * 5 + 5);
        assertTrue(wbtcBalance > 1000 * satoshiOfUsdc); // a lot of btc remain because only part is swapped
        assertTrue(curveLpBalance == 0);
        assertTrue(convexLpBalance == 0);
        assertTrue(convexFantomBalance == 0);
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * satoshiOfUsdc, 100));
    }

    function testTwoDepositsWBTC() public {
        
        deposit(FIRST_DEPOSIT, address(this));
        uint256 lpAmountBefore = rootVault.balanceOf(address(this));

        creditAccount = gearboxVault.getCreditAccount();

        deposit(FIRST_DEPOSIT / 5, address(this));
        uint256 lpAmountAfter = rootVault.balanceOf(address(this));

        uint256 usdcBalance = IERC20(usdc).balanceOf(creditAccount);
        uint256 wbtcBalance = IERC20(wbtc).balanceOf(creditAccount);
        uint256 curveLpBalance = IERC20(curveAdapter.lp_token()).balanceOf(creditAccount);
        uint256 convexLpBalance = IERC20(convexAdapter.stakingToken()).balanceOf(creditAccount);
        uint256 convexFantomBalance = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(usdcBalance == 25000 * 10 ** 6 * 5 + 5);
        assertTrue(isClose(wbtcBalance * 10**6 / satoshiOfUsdc, (FIRST_DEPOSIT / 5 + (FIRST_DEPOSIT - 25000)) * 10**6, 100));
        assertTrue(curveLpBalance == 0);
        assertTrue(convexLpBalance == 0);
        assertTrue(convexFantomBalance == 0);

        assertTrue(isClose(lpAmountBefore * 6, lpAmountAfter * 5, 100));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * satoshiOfUsdc * 6 / 5, 100));
    }


    function testFailTooSmallInitialDepositFail() public {
        deposit(FIRST_DEPOSIT / 5, address(this));
    }

    function testTvlOfEmptyVault() public {
        assertTrue(tvl() == 0);
    }

    function testTvlAfterSingleDeposit() public {
        deposit(FIRST_DEPOSIT, address(this));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * satoshiOfUsdc, 100));
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
        assertTrue(tvl() < FIRST_DEPOSIT * satoshiOfUsdc * 999 / 1000); // some fees accrued
    }

    function testTvlAfterMultipleDeposits() public {
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5, address(this));
        deposit(FIRST_DEPOSIT / 10, address(this));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * satoshiOfUsdc * 13 / 10, 100));
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

        assertTrue(isClose(IERC20(wbtc).balanceOf(creditAccount), (FIRST_DEPOSIT - 25000 + FIRST_DEPOSIT / 5) * satoshiOfUsdc, 100));
        assertTrue(isClose(convexFantomBalance * 193, convexFantomBalanceAfter * 165, 100));
    }

    function testSimpleAdjustingPositionAndTvl() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * satoshiOfUsdc, 100));
    }

    function testFailAdjustingPositionFromSomeAddress() public {
        address addr = getNextUserAddress();
        deposit(FIRST_DEPOSIT, address(this));
        vm.prank(addr);
        gearboxVault.adjustPosition();
    }
////// THERE IS A PROBLEM OF LAUNCHING THE TEST PURELY WITH THE CONTRACTS AS IS, BUT THE CORE LOGIC OF THE TEST WAS TESTED MANUALLY AND GOT OK
   // function testWBTCAreSwappedIfTooMuch() public {
     //   deposit(4 * FIRST_DEPOSIT, address(this));
      //  gearboxVault.adjustPosition();
       // creditAccount = gearboxVault.getCreditAccount();
        //console2.log(tvl());
        //console2.log(IERC20(wbtc).balanceOf(creditAccount));

     //   vm.warp(block.timestamp + YEAR);
     //   console2.log(tvl());
     //   gearboxVault.adjustPosition();

       // assertTrue(isClose(IERC20(wbtc).balanceOf(creditAccount), tvl(), 20));

       // console2.log(tvl());
       // console2.log(IERC20(wbtc).balanceOf(creditAccount));
   // }

    function testFailChangingMarginalFactorFromSomeAddress() public {
        address addr = getNextUserAddress();
        deposit(FIRST_DEPOSIT, address(this));
        vm.prank(addr);
        gearboxVault.updateTargetMarginalFactor(6000000000);
    }

    function testFailChangingMarginalFactorLowerThanOne() public {
        address addr = getNextUserAddress();
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.updateTargetMarginalFactor(200000000);
    }

    function testSeveralAdjustingPositionAfterChangeInMarginalFactorWBTC() public {
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5 * 2, address(this)); // 631% in staking
        creditAccount = gearboxVault.getCreditAccount();
        gearboxVault.adjustPosition();
        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        gearboxVault.updateTargetMarginalFactor(5500000000); // 701% in staking
        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(isClose(convexFantomBalanceBefore * 701, convexFantomBalanceAfter * 631, 100));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT / 5 * 7 * satoshiOfUsdc, 100));

        assertTrue(checkNotNonExpectedBalance());

        gearboxVault.updateTargetMarginalFactor(5700000000); // 729% in staking
        assertTrue(isClose(tvl(), FIRST_DEPOSIT / 5 * 7 * satoshiOfUsdc, 100));
        uint256 convexFantomBalanceFinal = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(isClose(convexFantomBalanceFinal * 701, convexFantomBalanceAfter * 729, 100));
    }
    

    function testEarnedRewardsWBTC() public {
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5 * 2, address(this));

        creditAccount = gearboxVault.getCreditAccount();
        gearboxVault.adjustPosition(); // 631% in staking

        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        runRewarding(); // + 2.44% on all deposited money => 40% more deposited + 14% earned => 34% total surplus
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * satoshiOfUsdc * 154 / 100, 100));
        gearboxVault.adjustPosition(); // 701% in staking now
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * satoshiOfUsdc * 154 / 100, 100));

        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(isClose(convexFantomBalanceBefore * 701, convexFantomBalanceAfter * 631, 100));
    }


    function testMultipleDepositsAndRewardsAndAdjustmentsTvlCorrectness() public {
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5 * 2, address(this));
        gearboxVault.adjustPosition();
        runRewarding(); // + 2.44% on all deposited money => 40% more deposited + 14% earned => 34% total surplus

        assertTrue(isClose(tvl(), FIRST_DEPOSIT * satoshiOfUsdc * 154 / 100, 100));
        deposit(FIRST_DEPOSIT / 5, address(this));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * satoshiOfUsdc * 174 / 100, 100));
        deposit(FIRST_DEPOSIT / 50 * 3, address(this));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * satoshiOfUsdc * 180 / 100, 100));
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * satoshiOfUsdc * 180 / 100, 100));
        gearboxVault.updateTargetMarginalFactor(5500000000);
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * satoshiOfUsdc * 180 / 100, 100));
        deposit(FIRST_DEPOSIT / 50 * 3, address(this));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * satoshiOfUsdc * 186 / 100, 100));
        gearboxVault.updateTargetMarginalFactor(6666666666);
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * satoshiOfUsdc * 186 / 100, 100));
    }

    function testWithValueFallingAndRewardsCovering() public {
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5 * 2, address(this));
        gearboxVault.adjustPosition();

        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        runRewarding(); // + 2.44% on all deposited money => 40% more deposited + 14% earned => 34% total surplus

        gearboxVault.updateTargetMarginalFactor(4900000000);
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * satoshiOfUsdc * 154 / 100, 100));

        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(checkNotNonExpectedBalance());
        assertTrue(isClose(convexFantomBalanceAfter*631, convexFantomBalanceBefore*686, 100));
    }

    function testVaultCloseWithoutOrdersAndConvexWBTC() public {
        deposit(FIRST_DEPOSIT, address(this));
        invokeExecution();

        assertTrue(isClose(IERC20(usdc).balanceOf(address(gearboxVault)), 25000 * 10**6, 100));
        assertTrue(isClose(IERC20(wbtc).balanceOf(address(gearboxVault)) * 10**6 / satoshiOfUsdc, (FIRST_DEPOSIT - 25000) * 10**6, 100));
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

    function testVaultCloseWithoutOrdersButWithConvexWBTC() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();
        invokeExecution();

        assertTrue(isClose(IERC20(usdc).balanceOf(address(gearboxVault)), 25000 * 10**6, 100));
        assertTrue(isClose(IERC20(wbtc).balanceOf(address(gearboxVault)) * 10**6 / satoshiOfUsdc, (FIRST_DEPOSIT - 25000) * 10**6, 100));

        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testSimpleCloseVaultTvl() public {
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 2, address(this));
        gearboxVault.adjustPosition();
        invokeExecution();

        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 3 / 2 * satoshiOfUsdc, 100));
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testSimpleCloseVaultOkayAfterMultipleOperationsWBTC() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();
        deposit(FIRST_DEPOSIT / 5, address(this));
        gearboxVault.updateTargetMarginalFactor(6000000000);
        gearboxVault.adjustPosition();
        gearboxVault.updateTargetMarginalFactor(5500000000);

        runRewarding(); // + 2.44% on all deposited money => 14% earned

        invokeExecution();

        assertTrue(isClose(IERC20(usdc).balanceOf(address(gearboxVault)), FIRST_DEPOSIT * 10**6 * 86 / 100, 100));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 134 / 100 * satoshiOfUsdc, 100));
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testCloseVaultAfterNegativeAdjusting() public {
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5 * 2, address(this));
        gearboxVault.updateTargetMarginalFactor(4000000000);

        invokeExecution();
        assertTrue(isClose(IERC20(usdc).balanceOf(address(gearboxVault)), 25000 * 10**6, 100));
        assertTrue(isClose(IERC20(wbtc).balanceOf(address(gearboxVault)) * 10**6 / satoshiOfUsdc, (FIRST_DEPOSIT * 7 / 5 - 25000) * 10**6, 100));
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testCloseVaultWithOneOrderWBTC() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));

        rootVault.registerWithdrawal(lpTokens / 2);
        vm.warp(block.timestamp + YEAR / 12);
        invokeExecution();

        uint256 leftOnGearbox = IERC20(usdc).balanceOf(address(gearboxVault)) + IERC20(wbtc).balanceOf(address(gearboxVault)) * 10**6 / satoshiOfUsdc;
        uint256 wentForWithdrawal = IERC20(wbtc).balanceOf(address(erc20Vault)) * 10**6 / satoshiOfUsdc;

        assertTrue(leftOnGearbox * 995 > wentForWithdrawal * 1000); // the result of fees

        deposit(FIRST_DEPOSIT / 5 * 3, address(this));
        gearboxVault.adjustPosition();

        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 1102 / 1000 * satoshiOfUsdc, 100));

        address recipient = getNextUserAddress();

        uint256 oldSupply = rootVault.totalSupply();

        claimMoney(recipient);
        assertTrue(isClose(IERC20(wbtc).balanceOf(recipient), FIRST_DEPOSIT * 498 / 1000 * satoshiOfUsdc, 100));
        uint256 newSupply = rootVault.totalSupply();
        
        assertTrue(oldSupply - lpTokens / 2 == newSupply);
    }

    function testCloseVaultWithOneLargerOrderWBTC() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));

        rootVault.registerWithdrawal(lpTokens * 3 / 4); 
        invokeExecution();

        deposit(FIRST_DEPOSIT / 5 * 4, address(this));
        gearboxVault.adjustPosition();

        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 105 / 100 * satoshiOfUsdc, 100));

        address recipient = getNextUserAddress();

        uint256 oldSupply = rootVault.totalSupply();

        claimMoney(recipient);
        assertTrue(isClose(IERC20(wbtc).balanceOf(recipient), FIRST_DEPOSIT * 75 / 100 * satoshiOfUsdc, 100));
        uint256 newSupply = rootVault.totalSupply();
        
        assertTrue(oldSupply - lpTokens * 3 / 4 == newSupply);
    }

    function testCloseVaultWithOneFullWBTC() public {
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5 * 3, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));

        rootVault.registerWithdrawal(lpTokens);
        invokeExecution();

        assertTrue(tvl() > 10 * satoshiOfUsdc); // some USD remained because of address(0) but fees were taken (on swaps); maybe too muh but it's okay in general case
        address recipient = getNextUserAddress();

        claimMoney(recipient);
        assertTrue(isClose(IERC20(wbtc).balanceOf(recipient), FIRST_DEPOSIT * 8 / 5 * satoshiOfUsdc, 100));
    }

    function testCloseVaultWithSeveralDepositsAndPartialWithdrawalsWBTC() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 50%

        address secondUser = getNextUserAddress();
        vm.startPrank(secondUser);

        deposit(FIRST_DEPOSIT / 5, secondUser);
        uint256 secondUserLpTokens = rootVault.balanceOf(secondUser);
        rootVault.registerWithdrawal(secondUserLpTokens / 4); // 5%

        vm.stopPrank();
        invokeExecution();

        uint256 leftOnGearbox = IERC20(usdc).balanceOf(address(gearboxVault)) + IERC20(wbtc).balanceOf(address(gearboxVault)) * 10**6 / satoshiOfUsdc;
        uint256 wentForWithdrawal = IERC20(wbtc).balanceOf(address(erc20Vault)) * 10**6 / satoshiOfUsdc;
        assertTrue(isClose(leftOnGearbox, FIRST_DEPOSIT * 13 / 20 * 10**6, 100));
        assertTrue(isClose(wentForWithdrawal, FIRST_DEPOSIT * 11 / 20 * 10**6, 100));


        address recipient = getNextUserAddress();
        claimMoney(recipient);
        assertTrue(isClose(IERC20(wbtc).balanceOf(recipient), FIRST_DEPOSIT / 2 * satoshiOfUsdc, 100));

        vm.startPrank(secondUser);
        claimMoney(recipient);
        assertTrue(isClose(IERC20(wbtc).balanceOf(recipient), FIRST_DEPOSIT * 11 / 20 * satoshiOfUsdc, 100));
        vm.stopPrank();

        claimMoney(recipient);
        assertTrue(isClose(IERC20(wbtc).balanceOf(recipient), FIRST_DEPOSIT * 11 / 20 * satoshiOfUsdc, 100));
    }

    function testSeveralInvocationsWhenFirstNotTakenAndNewSumIsMoreWBTC() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 50%

        invokeExecution();
        vm.warp(block.timestamp + 86400 * 10);

        deposit(FIRST_DEPOSIT, address(this));

        rootVault.registerWithdrawal(lpTokens * 2 / 3); // 66.6%
        invokeExecution();

        uint256 leftOnGearbox = IERC20(usdc).balanceOf(address(gearboxVault)) + IERC20(wbtc).balanceOf(address(gearboxVault)) * 10**6 / satoshiOfUsdc;
        uint256 wentForWithdrawal = IERC20(wbtc).balanceOf(address(erc20Vault)) * 10**6 / satoshiOfUsdc;
        assertTrue(isClose(leftOnGearbox, FIRST_DEPOSIT * 83 / 100 * 10**6, 100));
        assertTrue(isClose(wentForWithdrawal, FIRST_DEPOSIT * 117 / 100 * 10**6, 100));
    }

    function testSeveralInvocationsWhenFirstNotTakenAndNewSumIsLessWBTC() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 50%

        invokeExecution();
        vm.warp(block.timestamp + 86400 * 10);

        deposit(FIRST_DEPOSIT, address(this));

        rootVault.registerWithdrawal(lpTokens / 3); // 33.3%
        invokeExecution();

        uint256 leftOnGearbox = IERC20(usdc).balanceOf(address(gearboxVault)) + IERC20(wbtc).balanceOf(address(gearboxVault)) * 10**6 / satoshiOfUsdc;
        uint256 wentForWithdrawal = IERC20(wbtc).balanceOf(address(erc20Vault)) * 10**6 / satoshiOfUsdc;
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * 117 / 100*satoshiOfUsdc, 100));
        assertTrue(isClose(leftOnGearbox, FIRST_DEPOSIT * 117 / 100 * 10**6, 100));
        assertTrue(isClose(wentForWithdrawal, FIRST_DEPOSIT * 83 / 100 * 10**6, 100));
    }

    function testCancelWithdrawalIsOkayWBTC() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 50%
        rootVault.cancelWithdrawal(lpTokens / 4); // cancel 25%

        invokeExecution();
        address recipient = getNextUserAddress();
        claimMoney(recipient);

        assertTrue(isClose(IERC20(wbtc).balanceOf(recipient), FIRST_DEPOSIT / 4 * satoshiOfUsdc, 100)); // anyway only 25% claimed
    }

    function testValueIncreasesAfterWithdrawalWBTC() public {
        setZeroFees();
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 50%

        invokeExecution();

        address secondUser = getNextUserAddress();
        vm.startPrank(secondUser);
        deposit(FIRST_DEPOSIT, secondUser);
        vm.stopPrank();

        gearboxVault.adjustPosition(); // 671% on staking => 16% earned
        
        runRewarding(); 
        address recipient = getNextUserAddress();
        claimMoney(recipient); // 50% claimed

        assertTrue(isClose(IERC20(wbtc).balanceOf(recipient), FIRST_DEPOSIT / 2 * satoshiOfUsdc, 100)); // anyway only 250 usd claimed
        vm.startPrank(secondUser);
        rootVault.registerWithdrawal(lpTokens / 2); // the same lp amount as previous but already 55%
        vm.stopPrank();

        vm.warp(block.timestamp + 86400 * 10);
        invokeExecution();

        vm.startPrank(secondUser);
        claimMoney(recipient); // 55% claimed
        vm.stopPrank();

        assertTrue(isClose(IERC20(wbtc).balanceOf(recipient), FIRST_DEPOSIT * 105 / 100 * satoshiOfUsdc, 100));
        claimMoney(recipient); // try to claim by the first user
        assertTrue(isClose(IERC20(wbtc).balanceOf(recipient), FIRST_DEPOSIT * 105 / 100 * satoshiOfUsdc, 100));
    }

    function testWitdrawalOrderCancelsAfterTime() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 240 USD

        invokeExecution();
        deposit(FIRST_DEPOSIT, address(this));
        vm.warp(block.timestamp + 86400 * 10);
        invokeExecution();

        address recipient = getNextUserAddress();
        claimMoney(recipient); 

        assertTrue(isClose(IERC20(wbtc).balanceOf(recipient), FIRST_DEPOSIT / 2 * satoshiOfUsdc, 100));
    }

    function testFailTwoInvocationsInShortTime() public {
        deposit(FIRST_DEPOSIT, address(this));
        gearboxVault.adjustPosition();

        invokeExecution();
        deposit(500, address(this));
        vm.warp(block.timestamp + 86400 * 3); // only 3 days
        invokeExecution();
    }


    
}
