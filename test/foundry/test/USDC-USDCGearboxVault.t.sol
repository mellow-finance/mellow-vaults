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

        IERC20RootVaultGovernance.DelayedStrategyParams memory delayedStrategyParams = IERC20RootVaultGovernance.DelayedStrategyParams({
            strategyTreasury: address(this),
            strategyPerformanceTreasury: address(this),
            privateVault: false,
            managementFee: 10**8,
            performanceFee: 10**8,
            depositCallbackAddress: address(0),
            withdrawCallbackAddress: address(0)
        });

        uint256 nftStart = registry.vaultsCount() + 1;

        IGearboxVaultGovernance.DelayedProtocolPerVaultParams memory delayedVaultParams = IGearboxVaultGovernance.DelayedProtocolPerVaultParams({
            primaryToken: usdc,
            curveAdapter: 0x6f3A4EFe549c2Fa397ed40FD4DE9FEB922C0FE31,
            convexAdapter: 0xb26586F4a9F157117651Da1A6DFa5b310790dd8A,
            facade: 0xCd290664b0AE34D8a7249bc02d7bdbeDdf969820,
            initialMarginalValue: 3000000000
        });

        governanceA.stageDelayedStrategyParams(nftStart + 2, delayedStrategyParams);
        governanceC.stageDelayedProtocolPerVaultParams(nftStart + 1, delayedVaultParams);
        vm.warp(block.timestamp + governance.governanceDelay());
        governanceC.commitDelayedProtocolPerVaultParams(nftStart + 1);
        governanceA.commitDelayedStrategyParams(nftStart + 2);

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

    function deposit(uint256 amount, address user) public {

        deal(usdc, user, amount * 10**6);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount * 10**6;
        IERC20(usdc).approve(address(rootVault), type(uint256).max);

        rootVault.deposit(amounts, 0, "");
        if (gearboxVault.creditAccount() == address(0)) {
            gearboxVault.openCreditAccount();
        }
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
        assertTrue(usdcBalance == 0);
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
        
        deposit(500, address(this));
        uint256 lpAmountBefore = rootVault.balanceOf(address(this));

        deposit(100, address(this));
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

        deposit(100, address(this));

        uint256[] memory amounts = new uint256[](1);

        amounts[0] = 10 ** 8;
        rootVault.deposit(amounts, 0, "");
    }

    function testTvlOfEmptyVault() public {
        assertTrue(tvl() == 0);
    }

    function testTvlAfterSingleDeposit() public {
        deposit(500, address(this));
        assertTrue(tvl() == 5 * 10**8);
    }

    function testTvlAfterTimePasses() public {
        deposit(500, address(this));
        vm.warp(block.timestamp + YEAR);
        console2.log(tvl());
        assertTrue(tvl() < 49999 * 10**4); // some fees accrued
    }

    function testTvlAfterMultipleDeposits() public {
        deposit(500, address(this));
        deposit(100, address(this));
        deposit(50, address(this));
        assertTrue(tvl() == 65 * 10**7);
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

        console2.log(convexFantomBalance);
        console2.log(convexFantomBalanceAfter);

        assertTrue(isClose(convexFantomBalance * 6, convexFantomBalanceAfter * 5, 100));
    }

    function testSimpleAdjustingPositionAndTvl() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), 500 * 10**6, 100));
    }

    function testFailAdjustingPositionFromSomeAddress() public {
        address addr = getNextUserAddress();
        deposit(500, address(this));
        vm.prank(addr);
        gearboxVault.adjustPosition();
    }

    function testSeveralAdjustingPositionAfterChangeInMarginalFactor() public {
        deposit(500, address(this));
        creditAccount = gearboxVault.creditAccount();
        gearboxVault.adjustPosition();
        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        gearboxVault.updateTargetMarginalFactor(2500000000);
        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(isClose(convexFantomBalanceBefore * 5, convexFantomBalanceAfter * 6, 100));
        assertTrue(isClose(tvl(), 500 * 10**6, 100));

        assertTrue(checkNotNonExpectedBalance());

        gearboxVault.updateTargetMarginalFactor(2700000000);
        assertTrue(isClose(tvl(), 500 * 10**6, 100));
        uint256 convexFantomBalanceFinal = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(isClose(convexFantomBalanceFinal * 25, convexFantomBalanceAfter * 27, 100));
    }

    function testEarnedRewards() public {
        deposit(500, address(this));
        creditAccount = gearboxVault.creditAccount();
        gearboxVault.adjustPosition();

        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        setNewRewardInRewardPool(5, 1); // + 76 USD
        assertTrue(isClose(tvl(), 576 * 10**6, 100));
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), 576 * 10**6, 100));

        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(isClose(convexFantomBalanceBefore * 576, convexFantomBalanceAfter * 500, 50));

        setNewRewardInRewardPool(12, 10); // + 19 USD
        assertTrue(isClose(tvl(), 595 * 10**6, 100));
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), 595 * 10**6, 100));
    }

    function testMultipleDepositsAndRewardsAndAdjustmentsTvlCorrectness() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();
        setNewRewardInRewardPool(2, 1); // + 19 USD

        assertTrue(isClose(tvl(), 519 * 10**6, 100));
        deposit(100, address(this));
        assertTrue(isClose(tvl(), 619 * 10**6, 100));
        deposit(30, address(this));
        assertTrue(isClose(tvl(), 649 * 10**6, 100));
        gearboxVault.adjustPosition();
        assertTrue(isClose(tvl(), 649 * 10**6, 100));
        gearboxVault.updateTargetMarginalFactor(2000000000);
        assertTrue(isClose(tvl(), 649 * 10**6, 100));
        deposit(16, address(this));
        assertTrue(isClose(tvl(), 665 * 10**6, 100));
        gearboxVault.updateTargetMarginalFactor(2222222222);
        assertTrue(isClose(tvl(), 665 * 10**6, 100));
    }

    function testWithValueFallingAndRewardsCovering() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        setNewRewardInRewardPool(10, 1); // + 171 USD

        gearboxVault.updateTargetMarginalFactor(2900000000);
        assertTrue(isClose(tvl(), 671 * 10**6, 100));

        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(checkNotNonExpectedBalance());
        assertTrue(isClose(convexFantomBalanceAfter*500, convexFantomBalanceBefore*671, 100));
    }

    function testVaultCloseWithoutOrdersAndConvex() public {
        deposit(500, address(this));
        vm.roll(block.number + 1);
        rootVault.invokeExecution();

        assertTrue(isClose(IERC20(usdc).balanceOf(address(gearboxVault)), 500 * 10**6, 100));
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
        gearboxVault.adjustPosition();
        vm.roll(block.number + 1);
        rootVault.invokeExecution();

        assertTrue(isClose(IERC20(usdc).balanceOf(address(gearboxVault)), 500 * 10**6, 100));
        assertTrue(IERC20(usdc).balanceOf(address(gearboxVault)) < 4999 * 10**5); //some funds spent to comissions
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testSimpleCloseVaultTvl() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();
        vm.roll(block.number + 1);
        rootVault.invokeExecution();

        assertTrue(isClose(tvl(), 500 * 10**6, 100));
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testSimpleCloseVaultOkayAfterMultipleOperations() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();
        deposit(100, address(this));
        gearboxVault.updateTargetMarginalFactor(2000000000);
        gearboxVault.adjustPosition();
        gearboxVault.updateTargetMarginalFactor(2500000000);

        setNewRewardInRewardPool(10, 1); // + 171 USD

        vm.roll(block.number + 1);
        rootVault.invokeExecution();

        assertTrue(isClose(IERC20(usdc).balanceOf(address(gearboxVault)), 771 * 10**6, 100));
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testCloseVaultAfterNegativeAdjusting() public {
        deposit(500, address(this));
        gearboxVault.updateTargetMarginalFactor(2000000000);

        vm.roll(block.number + 1);
        rootVault.invokeExecution();
        assertTrue(isClose(IERC20(usdc).balanceOf(address(gearboxVault)), 500 * 10**6, 100));
        assertTrue(checkIfSimpleCloseIsOkay());
    }

    function testCloseVaultWithOneOrder() public {
        deposit(500, address(this));
        gearboxVault.adjustPosition();

        uint256 lpTokens = rootVault.balanceOf(address(this));

        rootVault.registerWithdrawal(lpTokens / 2);
        vm.warp(block.timestamp + YEAR / 12); // to impose root vault fees
        vm.roll(block.number + 1);
        rootVault.invokeExecution();

        uint256 leftOnGearbox = IERC20(usdc).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(usdc).balanceOf(address(erc20Vault));

        assertTrue(leftOnGearbox * 995 > wentForWithdrawal * 1000); // the result of fees

        deposit(300, address(this));
        gearboxVault.adjustPosition();

        assertTrue(isClose(tvl(), 552 * 10**6, 100));

        address recipient = getNextUserAddress();

        uint256[] memory minTokenAmounts = new uint256[](1);
        bytes[] memory vaultOptions = new bytes[](2);
        uint256 oldSupply = rootVault.totalSupply();

        rootVault.withdraw(recipient, lpTokens / 2, minTokenAmounts, vaultOptions);

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
        vm.roll(block.number + 1);
        rootVault.invokeExecution();

        uint256 leftOnGearbox = IERC20(usdc).balanceOf(address(gearboxVault));
        uint256 wentForWithdrawal = IERC20(usdc).balanceOf(address(erc20Vault));
        assertTrue(isClose(leftOnGearbox, 325 * 10**6, 100));
        assertTrue(isClose(wentForWithdrawal, 275 * 10**6, 100));

        uint256[] memory minTokenAmounts = new uint256[](1);
        bytes[] memory vaultOptions = new bytes[](2);

        address recipient = getNextUserAddress();
        rootVault.withdraw(recipient, lpTokens / 4, minTokenAmounts, vaultOptions);
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), 125 * 10**6, 100));

        rootVault.withdraw(recipient, lpTokens / 8, minTokenAmounts, vaultOptions);
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), 1875 * 10**5, 100));

        vm.startPrank(secondUser);
        rootVault.withdraw(recipient, secondUserLpTokens / 8, minTokenAmounts, vaultOptions);
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), 2000 * 10**5, 100));
        vm.stopPrank();

        rootVault.withdraw(recipient, lpTokens / 8, minTokenAmounts, vaultOptions);
        assertTrue(isClose(IERC20(usdc).balanceOf(recipient), 2625 * 10**5, 100));
    }


}
