// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../src/ProtocolGovernance.sol";
import "../src/MockOracle.sol";
import "./helpers/MockRouter.t.sol";
import "../src/ERC20RootVaultHelper.sol";
import "../src/VaultRegistry.sol";

import "../src/vaults/GearboxVault.sol";
import "../src/vaults/GearboxRootVault.sol";
import "../src/vaults/ERC20Vault.sol";

import "../src/vaults/GearboxVaultGovernance.sol";
import "../src/vaults/ERC20VaultGovernance.sol";
import "../src/vaults/ERC20RootVaultGovernance.sol";

import "../src/external/ConvexBaseRewardPool.sol";

contract GearboxWBTCTest is Test {

    uint256 satoshiOfUsdc = 5284;

    ProtocolGovernance governance;
    VaultRegistry registry;

    GearboxRootVault rootVault = new GearboxRootVault();
    ERC20Vault erc20Vault = new ERC20Vault();
    GearboxVault gearboxVault = new GearboxVault();   

    address usdc = 0x1F2cd0D7E5a7d8fE41f886063E9F11A05dE217Fa;
    address weth = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6; 
    address wbtc = 0x34852e54D9B4Ec4325C7344C28b584Ce972e5E62;
    address creditAccount;
    uint256 nftStart;

    ICurveV1Adapter curveAdapter;
    IConvexV1BaseRewardPoolAdapter convexAdapter;
    GearboxVaultGovernance governanceC;

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

        address creditAccount = gearboxVault.creditAccount();

        uint256 usdcBalance = IERC20(usdc).balanceOf(creditAccount);
        uint256 curveLpBalance = IERC20(curveAdapter.lp_token()).balanceOf(creditAccount);
        uint256 convexLpBalance = IERC20(convexAdapter.stakingToken()).balanceOf(creditAccount);

        if (usdcBalance > 1 || curveLpBalance > 1 || convexLpBalance > 1) {
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
        governance.stageUnitPrice(usdc, 1);
        governance.commitUnitPrice(usdc);

        {
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
            univ3Adapter: 0xA417851DdbB7095c76Ac69Df6152c86F01328C5f,
            crv: 0x976d27eC7ebb1136cd7770F5e06aC917Aa9C672b,
            cvx: 0x6D75eb70402CF06a0cB5B8fdc1836dAe29702B17,
            minSlippageD9: 1000000,
            uniswapRouter: address(router)
        });

        MockOracle oracle = new MockOracle();
        ERC20RootVaultHelper helper = new ERC20RootVaultHelper();

        IERC20RootVaultGovernance.DelayedProtocolParams memory delayedParamsA = IERC20RootVaultGovernance.DelayedProtocolParams({
            managementFeeChargeDelay: 0,
            oracle: IOracle(oracle)
        });
        
        ERC20RootVaultGovernance governanceA = new ERC20RootVaultGovernance(internalParamsA, delayedParamsA, IERC20RootVaultHelper(helper));
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
            primaryToken: usdc,
            curveAdapter: 0x6f3A4EFe549c2Fa397ed40FD4DE9FEB922C0FE31,
            convexAdapter: 0xb26586F4a9F157117651Da1A6DFa5b310790dd8A,
            facade: 0xCd290664b0AE34D8a7249bc02d7bdbeDdf969820,
            initialMarginalValueD9: 3000000000
        });

        governanceA.stageDelayedStrategyParams(nftStart + 2, delayedStrategyParams);
        governanceC.stageDelayedProtocolPerVaultParams(nftStart + 1, delayedVaultParams);
        vm.warp(block.timestamp + governance.governanceDelay());
        governanceC.commitDelayedProtocolPerVaultParams(nftStart + 1);
        governanceA.commitDelayedStrategyParams(nftStart + 2);

        address[] memory tokens = new address[](1);
        tokens[0] = wbtc; 

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
        IERC20(wbtc).approve(address(rootVault), type(uint256).max);
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

    function deposit(uint256 amount, address user) public {

        deal(wbtc, user, amount * satoshiOfUsdc); 

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount * satoshiOfUsdc;
        IERC20(usdc).approve(address(rootVault), type(uint256).max);

        rootVault.deposit(amounts, 0, "");
        if (gearboxVault.creditAccount() == address(0)) {
            gearboxVault.openCreditAccount();
        }
    }

    function invokeExecution() public {

        IGearboxVaultGovernance.DelayedProtocolParams memory delayedParams = governanceC.delayedProtocolParams();
        delayedParams.minSlippageD9 = 10**7;

        governanceC.stageDelayedProtocolParams(delayedParams);
        vm.warp(block.timestamp + governance.governanceDelay());
        governanceC.commitDelayedProtocolParams();

        vm.roll(block.number + 1);
        rootVault.invokeExecution();

        delayedParams = governanceC.delayedProtocolParams();
        delayedParams.minSlippageD9 = 10**6;

        governanceC.stageDelayedProtocolParams(delayedParams);
        vm.warp(block.timestamp + governance.governanceDelay());
        governanceC.commitDelayedProtocolParams();
    }

    function claimMoney(address recipient, uint256 lpAmount) public {
        uint256[] memory minTokenAmounts = new uint256[](1);
        bytes[] memory vaultOptions = new bytes[](2);
        rootVault.withdraw(recipient, lpAmount, minTokenAmounts, vaultOptions);
    }

    function setNewRewardInRewardPool(uint256 nominator, uint256 denominator) public {
        ICreditManagerV2 manager = gearboxVault.creditManager();
        address cont = manager.adapterToContract(gearboxVault.convexAdapter());

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
        uint256 usdcBalance = IERC20(usdc).balanceOf(creditAccount);
        uint256 wbtcBalance = IERC20(wbtc).balanceOf(creditAccount);
        assertTrue(usdcBalance == 0);
        assertTrue(wbtcBalance == 0);
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

        deposit(500, address(this));

        creditAccount = gearboxVault.creditAccount();

        uint256 usdcBalance = IERC20(usdc).balanceOf(creditAccount);
        uint256 wbtcBalance = IERC20(wbtc).balanceOf(creditAccount);
        uint256 curveLpBalance = IERC20(curveAdapter.lp_token()).balanceOf(creditAccount);
        uint256 convexLpBalance = IERC20(convexAdapter.stakingToken()).balanceOf(creditAccount);
        uint256 convexFantomBalance = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(usdcBalance == 15 * 10 ** 8);
        assertTrue(wbtcBalance < 1000); // very small because all btc were swapped
        assertTrue(curveLpBalance == 0);
        assertTrue(convexLpBalance == 0);
        assertTrue(convexFantomBalance == 0);
        console2.log(tvl());
        assertTrue(isClose(tvl(), 500 * satoshiOfUsdc, 100));
    }

    function testTwoDepositsWBTC() public {
        
        deposit(500, address(this));
        uint256 lpAmountBefore = rootVault.balanceOf(address(this));

        deposit(100, address(this));
        uint256 lpAmountAfter = rootVault.balanceOf(address(this));

        creditAccount = gearboxVault.creditAccount();

        uint256 usdcBalance = IERC20(usdc).balanceOf(creditAccount);
        uint256 wbtcBalance = IERC20(wbtc).balanceOf(creditAccount);
        uint256 curveLpBalance = IERC20(curveAdapter.lp_token()).balanceOf(creditAccount);
        uint256 convexLpBalance = IERC20(convexAdapter.stakingToken()).balanceOf(creditAccount);
        uint256 convexFantomBalance = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(usdcBalance == 15 * 10 ** 8);
        assertTrue(isClose(wbtcBalance * 10**6 / satoshiOfUsdc, 100 * 10**6, 100));
        assertTrue(convexLpBalance == 0);
        assertTrue(convexFantomBalance == 0);

        assertTrue(isClose(lpAmountBefore * 6, lpAmountAfter * 5, 100));
        assertTrue(isClose(tvl(), 600 * satoshiOfUsdc, 100));
    }


    function testFailTooSmallInitialDepositFail() public {
        deposit(100, address(this));
    }

    function testTvlOfEmptyVault() public {
        assertTrue(tvl() == 0);
    }

    function testTvlAfterSingleDeposit() public {
        deposit(500, address(this));
        assertTrue(isClose(tvl(), 500 * satoshiOfUsdc, 100));
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
        console2.log(tvl());
        assertTrue(tvl() < 49999 * satoshiOfUsdc / 100); // some fees accrued
    }

    function testTvlAfterMultipleDeposits() public {
        deposit(500, address(this));
        deposit(100, address(this));
        deposit(50, address(this));
        assertTrue(isClose(tvl(), 650 * satoshiOfUsdc, 100));
    }

    function testWithdrawalOrders() public {
        deposit(500, address(this));
        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2);

        assertTrue(rootVault.currentWithdrawalRequested(address(this)) == lpTokens / 2);
        rootVault.cancelWithdrawal(lpTokens / 4);
        assertTrue(rootVault.currentWithdrawalRequested(address(this)) == lpTokens / 2 - lpTokens / 4);
    }

    function testWithdrawalOrderCancelTooMuch() public {
        deposit(500, address(this));
        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2);
        rootVault.cancelWithdrawal(lpTokens);
        assertTrue(rootVault.currentWithdrawalRequested(address(this)) == 0);
    }

    function testTooBigWithdrawalOrder() public {
        deposit(500, address(this));
        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(2 * lpTokens);
        assertTrue(rootVault.currentWithdrawalRequested(address(this)) == lpTokens);
    }

    function testSimpleAdjustingPosition() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        creditAccount = gearboxVault.creditAccount();

        assertTrue(checkNotNonExpectedBalance());
        uint256 convexFantomBalance = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(convexFantomBalance > 0);

        deposit(100, address(this));
        gearboxVault.adjustPosition();
        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(isClose(IERC20(wbtc).balanceOf(creditAccount), 100 * satoshiOfUsdc, 100));

        console2.log(convexFantomBalance);
        console2.log(convexFantomBalanceAfter);

        assertTrue(isClose(convexFantomBalance * 17, convexFantomBalanceAfter * 15, 100));
    }

    function testSimpleAdjustingPositionAndTvl() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), 500 * satoshiOfUsdc, 100));
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

    function testSeveralAdjustingPositionAfterChangeInMarginalFactor() public {
        deposit(500, address(this));
        deposit(200, address(this)); // 1900 USDC in staking
        creditAccount = gearboxVault.creditAccount();
        gearboxVault.adjustPosition();
        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        gearboxVault.updateTargetMarginalFactor(2500000000); // 1550 USDC in staking
        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(isClose(convexFantomBalanceBefore * 155, convexFantomBalanceAfter * 190, 100));
        assertTrue(isClose(tvl(), 700 * satoshiOfUsdc, 100));

        assertTrue(checkNotNonExpectedBalance());

        gearboxVault.updateTargetMarginalFactor(2700000000); // 1690 USDC in staking
        assertTrue(isClose(tvl(), 700 * satoshiOfUsdc, 100));
        uint256 convexFantomBalanceFinal = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(isClose(convexFantomBalanceFinal * 155, convexFantomBalanceAfter * 169, 100));
    }

    function testEarnedRewards() public {
        deposit(500, address(this));
        deposit(200, address(this)); // 1900 USD in staking
        creditAccount = gearboxVault.creditAccount();
        gearboxVault.adjustPosition();

        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        setNewRewardInRewardPool(5, 1); // + 96 USD
        assertTrue(isClose(tvl(), 796 * satoshiOfUsdc, 100));
        gearboxVault.adjustPosition(); // 2188 USD in staking now
        assertTrue(isClose(tvl(), 796 * satoshiOfUsdc, 100));

        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(isClose(convexFantomBalanceBefore * 2188, convexFantomBalanceAfter * 1900, 50));

        setNewRewardInRewardPool(12, 10); // + 24 USD
        assertTrue(isClose(tvl(), 820 * satoshiOfUsdc, 100));
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), 820 * satoshiOfUsdc, 100));
    }

    function testMultipleDepositsAndRewardsAndAdjustmentsTvlCorrectness() public {
        deposit(500, address(this));
        deposit(200, address(this));
        gearboxVault.adjustPosition();
        setNewRewardInRewardPool(2, 1); // + 24 USD

        assertTrue(isClose(tvl(), 724 * satoshiOfUsdc, 100));
        deposit(100, address(this));
        assertTrue(isClose(tvl(), 824 * satoshiOfUsdc, 100));
        deposit(30, address(this));
        assertTrue(isClose(tvl(), 854 * satoshiOfUsdc, 100));
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), 854 * satoshiOfUsdc, 100));
        gearboxVault.updateTargetMarginalFactor(2000000000);
        assertTrue(isClose(tvl(), 854 * satoshiOfUsdc, 100));
        deposit(16, address(this));
        assertTrue(isClose(tvl(), 870 * satoshiOfUsdc, 100));
        gearboxVault.updateTargetMarginalFactor(2222222222);
        assertTrue(isClose(tvl(), 870 * satoshiOfUsdc, 100));
    }

    function testWithValueFallingAndRewardsCovering() public {
        deposit(500, address(this));
        deposit(200, address(this));
        gearboxVault.adjustPosition();

        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        setNewRewardInRewardPool(10, 1); // + 216 USD

        gearboxVault.updateTargetMarginalFactor(2900000000);
        assertTrue(isClose(tvl(), 916 * satoshiOfUsdc, 100));

        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(checkNotNonExpectedBalance());
        assertTrue(isClose(convexFantomBalanceAfter*1900, convexFantomBalanceBefore*2548, 100));
    }

    function testVaultCloseWithoutOrdersAndConvexWBTC() public {
        deposit(500, address(this));
        deposit(200, address(this));
        invokeExecution();

        assertTrue(isClose(IERC20(usdc).balanceOf(address(gearboxVault)), 500 * 10**6, 100));
        assertTrue(isClose(IERC20(wbtc).balanceOf(address(gearboxVault)) * 10**6 / satoshiOfUsdc, 200 * 10**6, 100));
        assertTrue(IERC20(usdc).balanceOf(address(erc20Vault)) == 0);
        assertTrue(IERC20(usdc).balanceOf(address(rootVault)) == 0);

        assertTrue(gearboxVault.creditAccount() == address(0));
    }

    function checkIfSimpleCloseIsOkay() public returns (bool) {
        if (IERC20(usdc).balanceOf(address(erc20Vault)) != 0) {
            return false;
        }
        if (IERC20(usdc).balanceOf(address(rootVault)) != 0) {
            return false;
        }

        if (gearboxVault.creditAccount() != address(0)) {
            return false;
        }
        return true;
    }

    function testVaultCloseWithoutOrdersButWithConvex() public {
        deposit(500, address(this));
        deposit(200, address(this));
        gearboxVault.adjustPosition();
        invokeExecution();

        assertTrue(isClose(IERC20(usdc).balanceOf(address(gearboxVault)), 500 * 10**6, 100));
        assertTrue(isClose(IERC20(wbtc).balanceOf(address(gearboxVault)) * 10**6 / satoshiOfUsdc, 200 * 10**6, 100));

        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testSimpleCloseVaultTvl() public {
        deposit(500, address(this));
        deposit(200, address(this));
        gearboxVault.adjustPosition();
        invokeExecution();

        assertTrue(isClose(tvl(), 700 * satoshiOfUsdc, 100));
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testSimpleCloseVaultOkayAfterMultipleOperationsWBTC() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();
        deposit(100, address(this));
        gearboxVault.updateTargetMarginalFactor(2000000000);
        gearboxVault.adjustPosition();
        gearboxVault.updateTargetMarginalFactor(2500000000);

        setNewRewardInRewardPool(10, 1); // + 160 USD

        invokeExecution();

        assertTrue(isClose(IERC20(usdc).balanceOf(address(gearboxVault)), 660 * 10**6, 100));
        assertTrue(isClose(tvl(), 760 * satoshiOfUsdc, 100));
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testCloseVaultAfterNegativeAdjusting() public {
        deposit(500, address(this));
        deposit(200, address(this));
        gearboxVault.updateTargetMarginalFactor(2000000000);

        invokeExecution();
        assertTrue(isClose(IERC20(usdc).balanceOf(address(gearboxVault)), 500 * 10**6, 100));
        assertTrue(isClose(IERC20(wbtc).balanceOf(address(gearboxVault)) * 10**6 / satoshiOfUsdc, 200 * 10**6, 100));
        assertTrue(checkIfSimpleCloseIsOkay());
    }

        /*

    function testCloseVaultWithOneOrder() public {
        deposit(500, address(this));
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));

        rootVault.registerWithdrawal(lpTokens / 2);
        vm.warp(block.timestamp + YEAR / 12); // to impose root vault fees
        invokeExecution();

        uint256 leftOnGearbox = IERC20(usdc).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(usdc).balanceOf(address(erc20Vault));

        assertTrue(leftOnGearbox * 995 > wentForWithdrawal * 1000); // the result of fees

        deposit(300, address(this));
        gearboxVault.adjustPosition();

        assertTrue(isClose(tvl(), 552 * 10**6, 100));

        address recipient = getNextUserAddress();

        uint256 oldSupply = rootVault.totalSupply();

        claimMoney(recipient, lpTokens / 2);

        console2.log(IERC20(usdc).balanceOf(recipient));

        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), 248 * 10**6, 100));
        uint256 newSupply = rootVault.totalSupply();
        
        assertTrue(oldSupply - lpTokens / 2 == newSupply);
    }

    function testCloseVaultWithSeveralDepositsAndPartialWithdrawals() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 USD

        address secondUser = getNextUserAddress();
        vm.startPrank(secondUser);

        deposit(100, secondUser);
        uint256 secondUserLpTokens = rootVault.balanceOf(secondUser);
        rootVault.registerWithdrawal(secondUserLpTokens / 4); // 25 USD

        vm.stopPrank();
        invokeExecution();

        uint256 leftOnGearbox = IERC20(usdc).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(usdc).balanceOf(address(erc20Vault));
        assertTrue(isClose(leftOnGearbox, 325 * 10**6, 100));
        assertTrue(isClose(wentForWithdrawal, 275 * 10**6, 100));


        address recipient = getNextUserAddress();
        claimMoney(recipient, lpTokens / 4);
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), 125 * 10**6, 100));

        claimMoney(recipient, lpTokens / 8);
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), 1875 * 10**5, 100));

        vm.startPrank(secondUser);
        claimMoney(recipient, secondUserLpTokens / 8);
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), 2000 * 10**5, 100));
        vm.stopPrank();

        claimMoney(recipient, lpTokens / 8);
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), 2625 * 10**5, 100));
    }

    function testSeveralInvocationsWhenFirstNotTakenAndNewSumIsMore() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 USD

        invokeExecution();
        vm.warp(block.timestamp + 86400 * 10);

        deposit(500, address(this));

        rootVault.registerWithdrawal(lpTokens * 2 / 3); // ~333 USD
        invokeExecution();

        uint256 leftOnGearbox = IERC20(usdc).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(usdc).balanceOf(address(erc20Vault));
        assertTrue(isClose(leftOnGearbox, 666 * 10**6, 100));
        assertTrue(isClose(wentForWithdrawal, 333 * 10**6, 100));
    }

    function testSeveralInvocationsWhenFirstNotTakenAndNewSumIsLess() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 USD

        invokeExecution();
        vm.warp(block.timestamp + 86400 * 10);

        deposit(500, address(this));

        rootVault.registerWithdrawal(lpTokens / 3); // ~166 USD
        invokeExecution();

        uint256 leftOnGearbox = IERC20(usdc).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(usdc).balanceOf(address(erc20Vault));
        assertTrue(isClose(tvl(), 833*10**6, 100));
        assertTrue(isClose(leftOnGearbox, 0, 100));
        assertTrue(isClose(wentForWithdrawal, 166 * 10**6, 100));
    }

    function testSeveralInvocationsWhenFirstPartiallyClaimedAndNewSumIsMore() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 USD

        invokeExecution();

        vm.warp(block.timestamp + 86400 * 10);

        deposit(500, address(this));
        address recipient = getNextUserAddress();
        claimMoney(recipient, lpTokens / 4);//125 USD claimed

        rootVault.registerWithdrawal(lpTokens / 3); // ~166 USD more taken
        invokeExecution();

        uint256 leftOnGearbox = IERC20(usdc).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(usdc).balanceOf(address(erc20Vault));
        assertTrue(isClose(leftOnGearbox, 709 * 10**6, 100));
        assertTrue(isClose(wentForWithdrawal, 166 * 10**6, 100));
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), 1250 * 10**5, 100));
    }

    function testSeveralInvocationsWhenFirstPartiallyClaimedAndNewSumIsLess() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 USD

        invokeExecution();

        vm.warp(block.timestamp + 86400 * 10);

        deposit(500, address(this));
        address recipient = getNextUserAddress();
        claimMoney(recipient, lpTokens / 4); //125 USD claimed

        rootVault.registerWithdrawal(lpTokens / 5); // ~100 USD more taken
        invokeExecution();

        uint256 leftOnGearbox = IERC20(usdc).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(usdc).balanceOf(address(erc20Vault));
        assertTrue(isClose(tvl(), 775*10**6, 100));
        assertTrue(isClose(leftOnGearbox, 0, 100));
        assertTrue(isClose(wentForWithdrawal, 100 * 10**6, 100));
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), 1250 * 10**5, 100));
    }

    function testCancelWithdrawalIsOkay() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 USD
        rootVault.cancelWithdrawal(lpTokens / 4); // cancel 125 USD

        invokeExecution();
        address recipient = getNextUserAddress();
        claimMoney(recipient, lpTokens / 2);

        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), 1250 * 10**5, 100)); // anyway only 125 usd claimed
    }

    function valueIncreasesAfterWithdrawal() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 USD

        invokeExecution();

        address secondUser = getNextUserAddress();
        vm.startPrank(secondUser);
        deposit(500, secondUser);
        vm.stopPrank();
        
        setNewRewardInRewardPool(10, 1); // + 171 USD => 921 USD in pool
        address recipient = getNextUserAddress();
        claimMoney(recipient, lpTokens / 2); // 250 USD claimed

        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), 2500 * 10**5, 100)); // anyway only 250 usd claimed
        vm.startPrank(secondUser);
        rootVault.registerWithdrawal(lpTokens / 2); // the same lp amount as previous but already 307 usd
        vm.stopPrank();

        vm.warp(block.timestamp + 86400 * 10);
        invokeExecution();

        vm.startPrank(secondUser);
        claimMoney(recipient, lpTokens / 2); // 307 usd claimed
        vm.stopPrank();

        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), 5570 * 10**5, 100));
        claimMoney(recipient, lpTokens / 2); // try to claim by the first user
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), 5570 * 10**5, 100));
    }

    function testWitdrawalOrderCancelsAfterTime() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 USD

        invokeExecution();
        deposit(500, address(this));
        vm.warp(block.timestamp + 86400 * 10);
        invokeExecution();

        address recipient = getNextUserAddress();
        claimMoney(recipient, lpTokens / 2); // claim money on a dead order

        assertTrue(IERC20(usdc).balanceOf(recipient) == 0);
    }

    function testFailTwoInvocationsInShortTime() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        invokeExecution();
        deposit(500, address(this));
        vm.warp(block.timestamp + 86400 * 3); // only 3 days
        invokeExecution();
    }
    
    */

}
