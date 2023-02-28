// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/ProtocolGovernance.sol";
import "../../src/MockOracle.sol";
import "../../src/MockAggregator.sol";
import "../../src/oracles/MellowOracle.sol";
import "../helpers/MockRouter.t.sol";
import "../../src/ERC20RootVaultHelper.sol";
import "../../src/VaultRegistry.sol";

import "../../src/vaults/GearboxVault.sol";
import "../../src/vaults/GearboxRootVault.sol";
import "../../src/vaults/GearboxERC20Vault.sol";
import "../../src/vaults/ERC20Vault.sol";

import "../../src/vaults/GearboxVaultGovernance.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../src/utils/GearboxHelper.sol";
import "../../src/utils/GearboxERC20Helper.sol";

import "../../src/external/ConvexBaseRewardPool.sol";
import "../../src/external/VirtualPool.sol";
import "../../src/interfaces/IDegenNft.sol";

import "../helpers/MockDistributor.t.sol";


contract GearboxWETHTest is Test {

    uint256 weiofUsdc = 10**15;
    uint256 V = 3;

    ProtocolGovernance governance;
    VaultRegistry registry;

    GearboxERC20Helper gHelper;

    GearboxRootVault rootVault = new GearboxRootVault();
    GearboxERC20Vault erc20Vault = new GearboxERC20Vault();

    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; 
    address admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;
    address minter = 0x6cA68adc7eC07a4bD97c97e8052510FBE6b67d10;
    MockDegenDistributor distributor = new MockDegenDistributor();
    address configurator = 0xA7D5DDc1b8557914F158076b228AA91eF613f1D5;
    address cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address mellowOracle = 0x9d992650B30C6FB7a83E7e7a430b4e015433b838;

    address creditAccount;
    uint256 nftStart;

    ICurveV1Adapter curveAdapter;
    IConvexV1BaseRewardPoolAdapter convexAdapter;
    GearboxVaultGovernance governanceC;
    ERC20RootVaultGovernance governanceA;

    uint256 YEAR = 365 * 24 * 60 * 60;

    uint256 FIRST_DEPOSIT = 35000;
    uint256 LIMIT = 100000;

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

        IGearboxVault gearboxVault = new GearboxVault();

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
            crv3Pool: 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7,
            crv: 0xD533a949740bb3306d119CC777fa900bA034cd52,
            cvx: cvx,
            maxSlippageD9: 10000000,
            maxSmallPoolsSlippageD9: 50000000,
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
            univ3Adapter: 0xed5B30F8604c0743F167a19F42fEC8d284963a7D,
            facade: 0xC59135f449bb623501145443c70A30eE648Fa304,
            initialMarginalValueD9: 5000000000,
            referralCode: 0
        });

        IGearboxVaultGovernance.StrategyParams memory strategyParamsB = IGearboxVaultGovernance.StrategyParams({
            largePoolFeeUsed: 500
        });

        {

            vm.startPrank(admin);

            governanceA.stageDelayedStrategyParams(nftStart + 1 + V, delayedStrategyParams);
            for (uint256 i = 0; i < V; ++i) {
                governanceC.stageDelayedProtocolPerVaultParams(nftStart + 1 + i, delayedVaultParams);
                governanceC.setStrategyParams(nftStart + 1 + i, strategyParamsB);
            }
            vm.warp(block.timestamp + governance.governanceDelay());
            for (uint256 i = 0; i < V; ++i) {
                governanceC.commitDelayedProtocolPerVaultParams(nftStart + 1 + i);
            }
            governanceA.commitDelayedStrategyParams(nftStart + 1 + V);

            vm.stopPrank();

        }

        address[] memory tokens = new address[](1);
        tokens[0] = weth; 

        governanceB.createVault(tokens, address(this));

        for (uint256 i = 0; i < V; ++i) {
            helper2 = new GearboxHelper(mellowOracle);
            governanceC.createVault(tokens, address(this), address(helper2));
        }

        uint256[] memory nfts = new uint256[](1);

        nfts[0] = nftStart;

        registry.approve(address(governanceA), nftStart);

        governanceA.createVault(tokens, address(this), nfts, address(this));

        rootVault = GearboxRootVault(registry.vaultForNft(nftStart + 4));
        erc20Vault = GearboxERC20Vault(registry.vaultForNft(nftStart));
        rootVault.changeDepositCurveFeeBurdenShareD(5 * 10**8);

        curveAdapter = ICurveV1Adapter(0x0Ad2Fc10F677b2554553DaF80312A98ddb38f8Ef);
        convexAdapter = IConvexV1BaseRewardPoolAdapter(0xeBE13b1874bB2913CB3F04d4231837867ff77999);
        
        governanceA.setStrategyParams(nftStart + 1 + V, strategyParams);
        IERC20(weth).approve(address(rootVault), type(uint256).max);

        for (uint256 i = 0; i < 3; ++i) {

            GearboxVault gearboxVault = GearboxVault(registry.vaultForNft(nftStart + 1 + i));

            address degenNft = ICreditFacade(gearboxVault.creditFacade()).degenNFT();
            vm.startPrank(configurator);
            IDegenNFT(degenNft).setMinter(address(distributor));
            vm.stopPrank();

            bytes32[] memory arr = new bytes32[](1);
            arr[0] = DegenConstants.DEGEN;

            gearboxVault.setMerkleParameters(0, 20, arr);

            uint256[] memory arr2 = new uint256[](2);
            arr2[0] = 25;
            arr2[1] = 100;

            gearboxVault.addPoolsToAllowList(arr2);

            registry.transferFrom(address(this), address(rootVault), nftStart + 1 + i);

        }

        erc20Vault.setAdapters(address(curveAdapter), address(convexAdapter));
        gHelper = new GearboxERC20Helper(address(erc20Vault));
        erc20Vault.setHelper(address(gHelper));

        GearboxRootVault.Params memory params = GearboxRootVault.Params({
            withdrawDelay: 86400 * 7,
            priceFeed: 0x86392dC19c0b719886221c78AB11eb8Cf5c52812,
            minPoolDeltaD18: 99 * 10**16
        });

        rootVault.setParams(params);

    }

    function getVault(uint256 i) public returns (address) {
        if (i < V) {
            return VaultRegistry(0xFD23F971696576331fCF96f80a20B4D3b31ca5b2).vaultForNft(nftStart + i + 1);
        }
        else {
            return VaultRegistry(0xFD23F971696576331fCF96f80a20B4D3b31ca5b2).vaultForNft(nftStart + i + 2);
        }
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

    function firstDeposit(address user) public {

        deal(weth, user, 10**10);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10**10;
        IERC20(weth).approve(address(rootVault), type(uint256).max);

        rootVault.deposit(amounts, 0, "");
    }


    function deposit(uint256 amount, address user) public {

        uint256 subtract = 0;

        if (rootVault.totalSupply() == 0) {
            firstDeposit(user);
            subtract = 10**10;
        }

        deal(weth, user, amount * weiofUsdc - subtract); 

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount * weiofUsdc - subtract;
        IERC20(weth).approve(address(rootVault), type(uint256).max);

        rootVault.deposit(amounts, 0, "");
    }

    function depositExactAmount(uint256 amount, address user) public {

        if (rootVault.totalSupply() == 0) {
            firstDeposit(user);
        }

        deal(weth, user, amount);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        vm.startPrank(user);
        IERC20(weth).approve(address(rootVault), type(uint256).max);
        rootVault.deposit(amounts, 0, "");
        vm.stopPrank();
    }

    function invokeExecution() public {

        vm.roll(block.number + 1);
        rootVault.invokeExecution();

    }

    function claimMoney(address recipient) public {
        uint256[] memory minTokenAmounts = new uint256[](1);
        bytes[] memory vaultOptions = new bytes[](1);
        rootVault.withdraw(recipient, vaultOptions);
    }

    function runRewarding() public {
        ICreditManagerV2 manager = IGearboxVault(getVault(0)).creditManager();
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

        VirtualBalanceRewardPool rewardsPool2 = VirtualBalanceRewardPool(0x008aEa5036b819B4FEAEd10b2190FBb3954981E8);
        vm.startPrank(rewardsPool2.operator());
        for (uint256 i = 0; i < 1; ++i) {
            uint256 multiplier = 1;
            if (i == 0) {
                multiplier = 1000;
            }
            rewardsPool2.queueNewRewards(10**18);
            vm.warp(block.timestamp + rewardsPool2.duration() + 1);
        }
        vm.stopPrank();
    }

    function placeLidoRewarding() public {
        VirtualBalanceRewardPool rewardsPool2 = VirtualBalanceRewardPool(0x008aEa5036b819B4FEAEd10b2190FBb3954981E8);
        vm.startPrank(rewardsPool2.operator());
        for (uint256 i = 0; i < 1; ++i) {
            uint256 multiplier = 1;
            if (i == 0) {
                multiplier = 1000;
            }
            rewardsPool2.queueNewRewards(10**18);
            vm.warp(block.timestamp + 86400);
        }
        vm.stopPrank();
    }

    function tvl() public returns (uint256) {
        (uint256[] memory result, ) = rootVault.tvl();
        assertTrue(result.length == 1);
        return result[0];
    }

    function addVaults() public {
        for (uint256 i = 0; i < V; ++i) {
            address addr = getVault(i);
            erc20Vault.addSubvault(addr, LIMIT * weiofUsdc);
        }
    }

    function addMoreVaults() public {
        for (uint256 i = 0; i < 10; ++i) {
            address addr = getVault(i + V);
            erc20Vault.addSubvault(addr, LIMIT * weiofUsdc);
        }
    }

    function testSetup() public {
    }

    function testSimpleGearboxVaultsAdding() public {
        addVaults();
    }

    function testFailAddingGearboxVaultLowLimit() public {
        address addr = getVault(0);
        erc20Vault.addSubvault(addr, 10000 * weiofUsdc);
    }

    function testFailAddingGearboxVaultHighLimit() public {
        address addr = getVault(0);
        erc20Vault.addSubvault(addr, 1000000 * weiofUsdc);
    }

    function testInititalTvl() public {
        assertTrue(tvl() == 0);
    }

    function testFailSimpleDepositAsTotalLimitZero() public {

        deposit(FIRST_DEPOSIT, address(this));

        for (uint256 i = 0; i < 3; ++i) {
            creditAccount = IGearboxVault(getVault(i)).getCreditAccount();
            assertTrue(creditAccount == address(0));
        }

        uint256 wethBalance = IERC20(weth).balanceOf(address(erc20Vault));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc, 10000));
        _checkTvlsAreEqual();
    }

    function testDepositsToAddedVaultsWork() public {
        addVaults();

        deposit(FIRST_DEPOSIT, address(this));

        for (uint256 i = 0; i < 3; ++i) {
            creditAccount = IGearboxVault(getVault(i)).getCreditAccount();
            assertTrue(creditAccount == address(0));
        }

        uint256 wethBalance = IERC20(weth).balanceOf(address(erc20Vault));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc, 10000));
        _checkTvlsAreEqual();
    }

    function testDepositToAddedVaultsDistributed() public {
        addVaults();

        deposit(FIRST_DEPOSIT, address(this));

        for (uint256 i = 0; i < 3; ++i) {
            creditAccount = IGearboxVault(getVault(i)).getCreditAccount();
            assertTrue(creditAccount == address(0));
        }

        erc20Vault.distributeDeposits();

        uint256 wethBalance = IERC20(weth).balanceOf(address(erc20Vault));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc, 200));
        _checkTvlsAreEqual();
    }

    function testBigDepositToAddedVaultsDistributed() public {
        addVaults();

        deposit(205000, address(this));

        for (uint256 i = 0; i < 3; ++i) {
            creditAccount = IGearboxVault(getVault(i)).getCreditAccount();
            assertTrue(creditAccount == address(0));
        }

        erc20Vault.distributeDeposits();

        uint256 wethBalance = IERC20(weth).balanceOf(address(erc20Vault));
        assertTrue(isClose(tvl(), 205000 * weiofUsdc, 200));
        assertTrue(IERC20(weth).balanceOf(address(erc20Vault)) > 0);
        _checkTvlsAreEqual();
    }

    function testFailTooBigDepositRejected() public {
        addVaults();

        deposit(350000, address(this));
    }


    function testTwoDepositsWETH() public {

        addVaults();
        
        deposit(170000, address(this));
        uint256 lpAmountBefore = rootVault.balanceOf(address(this));

        erc20Vault.distributeDeposits();

        deposit(34000, address(this));
        uint256 lpAmountAfter = rootVault.balanceOf(address(this));

        erc20Vault.distributeDeposits();

        assertTrue(isClose(lpAmountBefore * 6, lpAmountAfter * 5, 100));
        assertTrue(isClose(tvl(), 170000 * weiofUsdc * 6 / 5, 100));
        assertTrue(erc20Vault.subvaultsStatusMask() == 10);
        _checkTvlsAreEqual();
    }

    function testSmallInitialDepositOk() public {

        addVaults();

        deposit(FIRST_DEPOSIT / 5, address(this));
        erc20Vault.distributeDeposits();
        assertTrue(IERC20(weth).balanceOf(address(erc20Vault)) == FIRST_DEPOSIT / 5 * weiofUsdc);
    }


    function testTvlOfEmptyVault() public {
        assertTrue(tvl() == 0);
    }

    function testTvlAfterSingleDeposit() public {
        addVaults();
        deposit(FIRST_DEPOSIT, address(this));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc, 100));
    }

    function testTvlAfterTimePasses() public {
        addVaults();
        deposit(260000, address(this));
        erc20Vault.distributeDeposits();
        vm.warp(block.timestamp + YEAR / 12);
        assertTrue(isClose(tvl(), 260000 * weiofUsdc, 100)); // some fees accrued
    }

    function testTvlAfterMultipleDeposits() public {
        addVaults();
        deposit(95000, address(this));
        deposit(95000 / 5, address(this));
        deposit(95000 / 10, address(this));
        assertTrue(isClose(tvl(), 95000 * weiofUsdc * 13 / 10, 100));
    }


    function testWithdrawalOrders() public {
        addVaults();
        deposit(FIRST_DEPOSIT, address(this));
        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2);

        assertTrue(rootVault.withdrawalRequests(address(this)) == lpTokens / 2);
        rootVault.cancelWithdrawal(lpTokens / 4);
        assertTrue(rootVault.withdrawalRequests(address(this)) == lpTokens / 2 - lpTokens / 4);
    }

    function testWithdrawalOrderCancelTooMuch() public {
        addVaults();
        deposit(FIRST_DEPOSIT, address(this));
        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2);
        rootVault.cancelWithdrawal(lpTokens);
        assertTrue(rootVault.withdrawalRequests(address(this)) == 0);
    }

    function testTooBigWithdrawalOrder() public {
        addVaults();
        deposit(FIRST_DEPOSIT, address(this));
        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(2 * lpTokens);
        assertTrue(rootVault.withdrawalRequests(address(this)) == lpTokens);
    }

    function checkNotNonExpectedBalance(IGearboxVault gearboxVault) public returns (bool) {

        address creditAccount = gearboxVault.getCreditAccount();

        uint256 wethBalance = IERC20(weth).balanceOf(creditAccount);
        uint256 curveLpBalance = IERC20(curveAdapter.lp_token()).balanceOf(creditAccount);
        uint256 convexLpBalance = IERC20(convexAdapter.stakingToken()).balanceOf(creditAccount);

        if (wethBalance > 1 || curveLpBalance > 1 || convexLpBalance > 1) {
            return false;
        }

        return true;
    }

    function testSimpleAdjustingPositionWETH() public {
        addVaults();
        deposit(80000, address(this));
        erc20Vault.distributeDeposits();

        creditAccount = IGearboxVault(getVault(0)).getCreditAccount();

        assertTrue(checkNotNonExpectedBalance(IGearboxVault(getVault(0))));
        uint256 convexFantomBalance = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(convexFantomBalance > 0);

        deposit(16000, address(this));
        erc20Vault.distributeDeposits();
        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(IERC20(weth).balanceOf(creditAccount) <= 1);
        assertTrue(isClose(convexFantomBalance * 6, convexFantomBalanceAfter * 5, 100));
        _checkTvlsAreEqual();
    }

    function testSimpleAdjustingPositionAndTvlWETH() public {
        addVaults();
        deposit(75000, address(this));
        erc20Vault.distributeDeposits();
        assertTrue(isClose(tvl(), 75000 * weiofUsdc, 80));
        _checkTvlsAreEqual();
    }

    function testFailDistributeDepositsFromSomeAddress() public {
        addVaults();
        address addr = getNextUserAddress();
        deposit(90000, address(this));
        vm.prank(addr);
        erc20Vault.distributeDeposits();
    }

    function testFailChangingMarginalFactorFromSomeAddress() public {
        addVaults();
        address addr = getNextUserAddress();
        deposit(FIRST_DEPOSIT, address(this));
        vm.prank(addr);
        erc20Vault.changeLimitAndFactor(0, 90000 * weiofUsdc, 4000000000);
    }

    function testFailChangingMarginalFactorLowerThanOne() public {
        addVaults();
        address addr = getNextUserAddress();
        deposit(FIRST_DEPOSIT, address(this));
        erc20Vault.changeLimitAndFactor(0, 90000 * weiofUsdc, 400000000);
    }

    function testSeveralAdjustingPositionAfterChangeInMarginalFactorWETH() public {
        addVaults();
        deposit(60000, address(this));
        deposit(24000, address(this)); // 700% in staking
        erc20Vault.distributeDeposits();

        creditAccount = IGearboxVault(getVault(0)).getCreditAccount();
        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        erc20Vault.changeLimitAndFactor(0, 90000 * weiofUsdc, 4500000000); // 630% in staking

        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(isClose(convexFantomBalanceBefore * 630, convexFantomBalanceAfter * 700, 100));
        assertTrue(isClose(tvl(), 60000 / 5 * 7 * weiofUsdc, 100));

        erc20Vault.changeLimitAndFactor(0, 90000 * weiofUsdc, 4700000000); // 630% in staking

        assertTrue(checkNotNonExpectedBalance(IGearboxVault(getVault(0))));
        assertTrue(isClose(tvl(), 60000 / 5 * 7 * weiofUsdc, 100));
        uint256 convexFantomBalanceFinal = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(isClose(convexFantomBalanceFinal * 630, convexFantomBalanceAfter * 658, 100));
        _checkTvlsAreEqual();
    }

    function _getTvl(address vault) internal view returns (uint256) {
        (uint256[] memory vaultTvls, ) = IGearboxVault(vault).tvl();
        return vaultTvls[0];
    }

    function _checkTvlsAreEqual() internal {
        uint256 oldSchoolTvl = erc20Vault.totalDeposited();
        for (uint256 i = 0; i < V + 10; ++i) {
            address addr = getVault(i);
            if (addr != address(0)) {
                oldSchoolTvl += _getTvl(addr);
            }
        }

        uint256 newSchoolTvl = tvl();
        console2.log("T1", oldSchoolTvl);
        console2.log("T2", newSchoolTvl);
        require(isClose(oldSchoolTvl, newSchoolTvl, 100000));

    }

    function testEarnedRewardsWETH() public {
        addVaults();
        deposit(120000, address(this));
        deposit(48000, address(this)); // 700% in staking
        erc20Vault.distributeDeposits();

        creditAccount = IGearboxVault(getVault(0)).getCreditAccount();

        IBaseRewardPool kek = IBaseRewardPool(0x008aEa5036b819B4FEAEd10b2190FBb3954981E8);
        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        runRewarding(); // +1.63% on staking money

        uint256 S = _getTvl(getVault(0)) + _getTvl(getVault(1));

        assertTrue(isClose(tvl(), 120000 * weiofUsdc * 151 / 100, 100));
        erc20Vault.adjustAllPositions();
        assertTrue(isClose(tvl(), 120000 * weiofUsdc * 151 / 100, 100));

        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        assertTrue(isClose(convexFantomBalanceBefore * 1081, convexFantomBalanceAfter * 1000, 100));
        _checkTvlsAreEqual();
    }

    function testRewardingSpoilering() public {
        addVaults();
        deposit(80000, address(this));

        erc20Vault.distributeDeposits();
        runRewarding(); 

        ICreditManagerV2 manager = IGearboxVault(getVault(0)).creditManager();
        address cont = manager.adapterToContract(address(convexAdapter));

        BaseRewardPool rewardsPool = BaseRewardPool(cont);

        deal(address(rewardsPool.stakingToken()), address(this), 10**18);
        rewardsPool.stakingToken().approve(address(rewardsPool), 10**18);
        rewardsPool.stakeFor(IGearboxVault(getVault(0)).getCreditAccount(), 10**18);

        erc20Vault.adjustAllPositions();
        tvl();

    }

    function testMultipleDepositsAndRewardsAndAdjustmentsTvlCorrectnessWETH() public {
        addVaults();
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5 * 2, address(this));
        erc20Vault.distributeDeposits();
        runRewarding(); // +1.63% on staking money

        erc20Vault.adjustAllPositions();

        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 151 / 100, 100));
        deposit(FIRST_DEPOSIT / 5, address(this));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 171 / 100, 100));
        deposit(FIRST_DEPOSIT / 50 * 3, address(this));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 177 / 100, 100));
        erc20Vault.distributeDeposits();
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 177 / 100, 100));
        erc20Vault.changeLimitAndFactor(0, 100000 * weiofUsdc, 4000000000);
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 177 / 100, 100));
        deposit(FIRST_DEPOSIT / 10, address(this));
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 187 / 100, 100));
        erc20Vault.changeLimitAndFactor(0, 100000 * weiofUsdc, 5555555555);
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 187 / 100, 100));
        _checkTvlsAreEqual();
    }

    function testWithValueFallingAndRewardsCovering() public {
        addVaults();
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT / 5 * 2, address(this)); // 700% in convex
        erc20Vault.distributeDeposits();

        creditAccount = IGearboxVault(getVault(0)).getCreditAccount();

        uint256 convexFantomBalanceBefore = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);

        runRewarding(); // +1.63% on staking money => 11.4% earned => 757% in convex

        erc20Vault.adjustAllPositions();

        erc20Vault.changeLimitAndFactor(0, 100000 * weiofUsdc, 4500000000); // 681% in convex
        assertTrue(isClose(tvl(), FIRST_DEPOSIT * weiofUsdc * 151 / 100, 100));

        uint256 convexFantomBalanceAfter = IERC20(convexAdapter.stakedPhantomToken()).balanceOf(creditAccount);
        assertTrue(isClose(convexFantomBalanceAfter*700, convexFantomBalanceBefore*681, 100));
        _checkTvlsAreEqual();
    }

    function testVaultCloseWithoutOrdersAndConvexWETH() public {
        addVaults();
        deposit(150000, address(this));
        deposit(150000 / 5 * 2, address(this));

        invokeExecution();

        assertTrue(isClose(IERC20(weth).balanceOf(address(erc20Vault)), 210000 * weiofUsdc, 500));
        assertTrue(IERC20(weth).balanceOf(address(rootVault)) == 0);

        assertTrue(IGearboxVault(getVault(0)).getCreditAccount() == address(0));
        assertTrue(IGearboxVault(getVault(1)).getCreditAccount() == address(0));
        assertTrue(IGearboxVault(getVault(2)).getCreditAccount() == address(0));
        _checkTvlsAreEqual();
    }

    function testWithdrawWorks() public {

        addVaults();
        deposit(150000, address(this));
        deposit(150000 / 5 * 2, address(this));

        _checkTvlsAreEqual();

        erc20Vault.distributeDeposits();

        _checkTvlsAreEqual();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 10 * 4);

        invokeExecution();
        uint256 oldAmount = IERC20(weth).balanceOf(address(this));

        claimMoney(address(this));

        uint256 newAmount = IERC20(weth).balanceOf(address(this));
        assertTrue(isClose(newAmount - oldAmount, 84000 * weiofUsdc, 100));
        assertTrue(erc20Vault.subvaultsStatusMask() == 8);

        _checkTvlsAreEqual();

        assertTrue(IGearboxVault(getVault(1)).getCreditAccount() != address(0));
        assertTrue(IGearboxVault(getVault(0)).getCreditAccount() == address(0));
        assertTrue(IGearboxVault(getVault(2)).getCreditAccount() == address(0));

        assertTrue(isClose(IERC20(weth).balanceOf(address(erc20Vault)), 26000 * weiofUsdc, 500));

        deposit(150000, address(this));

        _checkTvlsAreEqual();

        erc20Vault.distributeDeposits();
        _checkTvlsAreEqual();
        assertTrue(erc20Vault.subvaultsStatusMask() == 26);
    }

    function testWithdrawWorksWhenPartially() public {
        addVaults();
        deposit(270000, address(this));
        erc20Vault.distributeDeposits();

        _checkTvlsAreEqual();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 10 * 9);

        invokeExecution();
        uint256 oldAmount = IERC20(weth).balanceOf(address(this));

        claimMoney(address(this));

        uint256 newAmount = IERC20(weth).balanceOf(address(this));
        assertTrue(isClose(newAmount - oldAmount, 243000 * weiofUsdc, 100));

        assertTrue(IGearboxVault(getVault(1)).getCreditAccount() == address(0));
        assertTrue(IGearboxVault(getVault(0)).getCreditAccount() == address(0));
        assertTrue(IGearboxVault(getVault(2)).getCreditAccount() == address(0));

        assertTrue(erc20Vault.subvaultsStatusMask() == 0);
        assertTrue(isClose(IERC20(weth).balanceOf(address(erc20Vault)), 27000 * weiofUsdc, 500));
    }

    function testWithdrawWorksWhenFully() public {
        addVaults();
        deposit(270000, address(this));
        erc20Vault.distributeDeposits();

        _checkTvlsAreEqual();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens);

        invokeExecution();
        uint256 oldAmount = IERC20(weth).balanceOf(address(this));

        claimMoney(address(this));

        uint256 newAmount = IERC20(weth).balanceOf(address(this));
        assertTrue(isClose(newAmount - oldAmount, 270000 * weiofUsdc, 100));

        assertTrue(IGearboxVault(getVault(1)).getCreditAccount() == address(0));
        assertTrue(IGearboxVault(getVault(0)).getCreditAccount() == address(0));
        assertTrue(IGearboxVault(getVault(2)).getCreditAccount() == address(0));

        assertTrue(erc20Vault.subvaultsStatusMask() == 0);
        assertTrue(IERC20(weth).balanceOf(address(erc20Vault)) < 10**12);
    }

    function testTinyWithdrawal() public {
        addVaults();
        deposit(140000, address(this));
        erc20Vault.distributeDeposits();

        _checkTvlsAreEqual();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 100);

        invokeExecution();
        uint256 oldAmount = IERC20(weth).balanceOf(address(this));

        claimMoney(address(this));

        uint256 newAmount = IERC20(weth).balanceOf(address(this));
        assertTrue(isClose(newAmount - oldAmount, 1400 * weiofUsdc, 100));

        assertTrue(IGearboxVault(getVault(1)).getCreditAccount() != address(0));
        assertTrue(IGearboxVault(getVault(0)).getCreditAccount() == address(0));
        assertTrue(IGearboxVault(getVault(2)).getCreditAccount() == address(0));

        assertTrue(erc20Vault.subvaultsStatusMask() == 4);
    }

    function testVaultCloseWithoutOrdersButWithConvexWETH() public {
        addVaults();
        deposit(120000, address(this));
        deposit(120000 / 5 * 2, address(this));
        erc20Vault.distributeDeposits();
        invokeExecution();

        assertTrue(IERC20(weth).balanceOf(address(erc20Vault)) <= 10**12);
        assertTrue(IERC20(weth).balanceOf(address(rootVault)) == 0);

        assertTrue(IGearboxVault(getVault(0)).getCreditAccount() != address(0));
        assertTrue(IGearboxVault(getVault(1)).getCreditAccount() != address(0));
        assertTrue(IGearboxVault(getVault(2)).getCreditAccount() == address(0));
        _checkTvlsAreEqual();
        assertTrue(erc20Vault.subvaultsStatusMask() == 6);
    }

    function testSimpleCloseVaultTvl() public {
        addVaults();
        deposit(200000, address(this));
        deposit(200000 / 5 * 2, address(this));
        erc20Vault.distributeDeposits();
        _checkTvlsAreEqual();
        invokeExecution();

        assertTrue(isClose(tvl(), 200000 / 5 * 7 * weiofUsdc, 300));
    }

    function testSimpleCloseVaultOkayAfterMultipleOperationsWETH() public {
        addVaults();
        deposit(200000, address(this));
        erc20Vault.distributeDeposits();
        deposit(200000 * 2 / 5, address(this));
        erc20Vault.distributeDeposits();
        _checkTvlsAreEqual();
        erc20Vault.changeLimitAndFactor(0, 100000 * weiofUsdc, 4000000000);
        erc20Vault.changeLimitAndFactor(1, 100000 * weiofUsdc, 4000000000);
        erc20Vault.changeLimitAndFactor(2, 100000 * weiofUsdc, 4000000000);
        _checkTvlsAreEqual();
        erc20Vault.adjustAllPositions();
        _checkTvlsAreEqual();
        erc20Vault.changeLimitAndFactor(0, 100000 * weiofUsdc, 4500000000);
        erc20Vault.changeLimitAndFactor(1, 100000 * weiofUsdc, 4500000000);
        erc20Vault.changeLimitAndFactor(2, 100000 * weiofUsdc, 4500000000); // 630% on convex
        _checkTvlsAreEqual();

        runRewarding(); // +1.63% on staking money => 10.3% earned

        erc20Vault.adjustAllPositions();
        _checkTvlsAreEqual();

        invokeExecution();

        assertTrue(isClose(tvl(), 200000 * 150 / 100 * weiofUsdc, 100));
    }

    function testCloseVaultAfterNegativeAdjusting() public {
        addVaults();
        deposit(FIRST_DEPOSIT, address(this));
        deposit(FIRST_DEPOSIT * 2 / 5, address(this));
        erc20Vault.distributeDeposits();
        _checkTvlsAreEqual();
        erc20Vault.changeLimitAndFactor(0, 100000 * weiofUsdc, 4000000000);

        console2.log("???");

        _checkTvlsAreEqual();

        invokeExecution();
        assertTrue(isClose(tvl(), FIRST_DEPOSIT / 5 * 7 * weiofUsdc, 300));
        _checkTvlsAreEqual();
    }

    function testCloseVaultWithOneOrderWETH() public {
        addVaults();
        deposit(160000, address(this)); // 500 mETH
        erc20Vault.distributeDeposits();

        uint256 lpTokens = rootVault.balanceOf(address(this));

        rootVault.registerWithdrawal(lpTokens / 2);
        vm.warp(block.timestamp + YEAR / 12); // to impose root vault fees

        invokeExecution();

        _checkTvlsAreEqual();
        deposit(160000 / 5 * 3, address(this));
        erc20Vault.adjustAllPositions();
        erc20Vault.distributeDeposits();
        erc20Vault.adjustAllPositions();

        assertTrue(isClose(tvl(), 160000 / 10 * 11 * weiofUsdc, 100));
        _checkTvlsAreEqual();

        address recipient = getNextUserAddress();

        uint256 oldSupply = rootVault.totalSupply();

        uint256 oldBalance = IERC20(weth).balanceOf(address(this));
        claimMoney(address(this));
        assertTrue(isClose(IERC20(weth).balanceOf(address(this)) - oldBalance, 160000 / 2 * weiofUsdc, 50));
        uint256 newSupply = rootVault.totalSupply();
        assertTrue(oldSupply - lpTokens / 2 == newSupply);
    }

    function testTvlIsConsistent() public {
        addVaults();
        deposit(160000, address(this)); // 500 mETH
        erc20Vault.distributeDeposits();

        deal(weth, address(this), 10**20);
        IERC20(weth).transfer(getVault(0), 10**20);

        _checkTvlsAreEqual();
    }

    function testLargeOrderLoss() public {
        addVaults();
        deposit(100000, address(this));
        deposit(200000, address(this));

        erc20Vault.distributeDeposits();

        uint256 tvlBefore = tvl();
        uint256 lpTokens = rootVault.balanceOf(address(this));

        rootVault.registerWithdrawal(lpTokens / 3 * 2);
        invokeExecution();

        assertTrue(erc20Vault.subvaultsStatusMask() == 0);
        uint256 balanceBefore = IERC20(weth).balanceOf(address(this));
        claimMoney(address(this));
        uint256 balanceAfter = IERC20(weth).balanceOf(address(this));

        assertTrue((balanceAfter - balanceBefore) * 100000 < tvlBefore / 3 * 2 * 99999); // PI loss
    }

    function addBatchOfVaults() public {
            
        vm.startPrank(admin);

        IGearboxVaultGovernance.DelayedProtocolPerVaultParams memory delayedVaultParams = IGearboxVaultGovernance.DelayedProtocolPerVaultParams({
            primaryToken: weth,
            univ3Adapter: 0xed5B30F8604c0743F167a19F42fEC8d284963a7D,
            facade: 0xC59135f449bb623501145443c70A30eE648Fa304,
            initialMarginalValueD9: 5000000000,
            referralCode: 0
        });

        IGearboxVaultGovernance.StrategyParams memory strategyParamsB = IGearboxVaultGovernance.StrategyParams({
            largePoolFeeUsed: 500
        });

        for (uint256 i = 0; i < 10; ++i) {
            governanceC.stageDelayedProtocolPerVaultParams(nftStart + 2 + V + i, delayedVaultParams);
            governanceC.setStrategyParams(nftStart + 2 + V + i, strategyParamsB);
        }

        vm.warp(block.timestamp + governance.governanceDelay());
        for (uint256 i = 0; i < 10; ++i) {
            governanceC.commitDelayedProtocolPerVaultParams(nftStart + 2 + V + i);
        }

        vm.stopPrank();

        address[] memory tokens = new address[](1);
        tokens[0] = weth; 

        for (uint256 i = 0; i < 10; ++i) {
            helper2 = new GearboxHelper(mellowOracle);
            governanceC.createVault(tokens, address(this), address(helper2));
        

            GearboxVault gearboxVault = GearboxVault(registry.vaultForNft(nftStart + 2 + V + i));

            address degenNft = ICreditFacade(gearboxVault.creditFacade()).degenNFT();
            vm.startPrank(configurator);
            IDegenNFT(degenNft).setMinter(address(distributor));
            vm.stopPrank();

            bytes32[] memory arr = new bytes32[](1);
            arr[0] = DegenConstants.DEGEN;

            gearboxVault.setMerkleParameters(0, 20, arr);

            uint256[] memory arr2 = new uint256[](2);
            arr2[0] = 25;
            arr2[1] = 100;

            gearboxVault.addPoolsToAllowList(arr2);

            registry.transferFrom(address(this), address(rootVault), nftStart + 2 + V + i);

        }

        addMoreVaults();

    }

    function testStressALotOfOrders() public {

        addVaults();
        addBatchOfVaults();

        uint256 ptr = 0;

        uint256[] memory lpBalances = new uint256[](100);
        address[] memory users = new address[](100);

        uint256 kek = 1;

        for (uint256 i = 0; i < 100; ++i) {
            kek = (228 * kek + 1337) % 1488;
            if (i == 0 || kek % 10 <= 2) {
                users[ptr] = getNextUserAddress();
                ptr += 1;
            }
            else if (kek % 10 <= 4) {
                kek = (228 * kek + 1337) % 1488;
                uint256 index = kek % ptr;

                vm.startPrank(users[index]);

                kek = (228 * kek + 1337) % 1488;

                deposit(5000 * (kek % 10 + 1), users[index]);
                lpBalances[index] = rootVault.balanceOf(users[index]);

                vm.stopPrank();

                erc20Vault.distributeDeposits();
            }
            else if (kek % 10 == 4) {
                invokeExecution();
                erc20Vault.distributeDeposits();
            }
            else if (kek % 10 <= 8) {
                kek = (228 * kek + 1337) % 1488;
                uint256 index = kek % ptr;
                kek = (228 * kek + 1337) % 1488;
                uint256 A = kek % 3;

                vm.startPrank(users[index]);

                rootVault.registerWithdrawal(lpBalances[index] * (A + 1) / 3);

                vm.stopPrank();
            }

            else {
                kek = (228 * kek + 1337) % 1488;
                uint256 index = kek % ptr;
                uint256 oldBalance = IERC20(weth).balanceOf(users[index]);
                uint256 waiting = rootVault.lpTokensWaitingForClaim(users[index]);
                if (rootVault.currentEpoch() != rootVault.latestRequestEpoch(users[index])) {
                    waiting += rootVault.withdrawalRequests(users[index]);
                }
                vm.startPrank(users[index]);
                claimMoney(users[index]);
                vm.stopPrank();

                uint256 newBalance = IERC20(weth).balanceOf(users[index]);
                require(isClose(newBalance - oldBalance, waiting, 50));
            }

            _checkTvlsAreEqual();
        }

    }

    function testFailOnlyRootVaultCanCallWithdraw() public {
        addVaults();
        deposit(100000, address(this));

        erc20Vault.withdraw(10**20, (10**27) / 2);
    }

    function testSortingWorks() public {
        addVaults();

        address[] memory prev = new address[](V);
        for (uint256 i = 0; i < V; ++i) {
           prev[i] = erc20Vault.subvaultsList(i);
        }

        erc20Vault.changeLimitAndFactor(0, 120000 * weiofUsdc, 4000000000);
        erc20Vault.changeLimitAndFactor(1, 60000 * weiofUsdc, 4000000000);

        for (uint256 i = 0; i < V; ++i) {
           assertTrue(erc20Vault.subvaultsList(i) == prev[V - i - 1]);
        }

    }


    function testCloseVaultWithOneLargerOrderWETH() public {

        addVaults();

        deposit(90000, address(this)); // 500 mETH
        erc20Vault.distributeDeposits();

        uint256 lpTokens = rootVault.balanceOf(address(this));

        rootVault.registerWithdrawal(lpTokens * 3 / 4); // 375 mETH
        invokeExecution();

        deposit(90000 / 5 * 4, address(this));
        erc20Vault.distributeDeposits();

        assertTrue(isClose(tvl(), 90000 / 20 * 21 * weiofUsdc, 100));

        _checkTvlsAreEqual();

        address recipient = getNextUserAddress();

        uint256 oldSupply = rootVault.totalSupply();

        claimMoney(recipient);
        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 90000 / 4 * 3 * weiofUsdc, 100));
        uint256 newSupply = rootVault.totalSupply();
        
        assertTrue(oldSupply - lpTokens * 3 / 4 == newSupply);
    }

    function testCloseVaultWithOneFullWETH() public {
        addVaults();
        deposit(150000, address(this));
        deposit(150000 / 5 * 3, address(this));
        erc20Vault.distributeDeposits();

        uint256 lpTokens = rootVault.balanceOf(address(this));

        rootVault.registerWithdrawal(lpTokens); // 800 mETH
        invokeExecution();

        _checkTvlsAreEqual();

        address recipient = getNextUserAddress();

        claimMoney(recipient);
        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 150000 / 5 * 8 * weiofUsdc, 100));

        _checkTvlsAreEqual();
    }


    function testCloseVaultWithSeveralDepositsAndPartialWithdrawalsWETH() public {
        addVaults();
        deposit(80000, address(this));
        erc20Vault.distributeDeposits();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 mETH

        address secondUser = getNextUserAddress();
        vm.startPrank(secondUser);

        deposit(80000 / 5, secondUser);
        _checkTvlsAreEqual();
        uint256 secondUserLpTokens = rootVault.balanceOf(secondUser);
        rootVault.registerWithdrawal(secondUserLpTokens / 4); // 25 mETH

        vm.stopPrank();
        invokeExecution();
        _checkTvlsAreEqual();

        address recipient = getNextUserAddress();
        claimMoney(recipient);
        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 80000 / 2 * weiofUsdc, 80));

        vm.startPrank(secondUser);
        claimMoney(recipient);
        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 80000 * 11 / 20 * weiofUsdc, 80));
        vm.stopPrank();
        _checkTvlsAreEqual();

        claimMoney(recipient);
        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 80000 * 11 / 20 * weiofUsdc, 80));
        _checkTvlsAreEqual();
    }

    function testSeveralInvocationsWhenFirstNotTakenAndNewSumIsMoreWETH() public {
        addVaults();
        deposit(60000, address(this));
        erc20Vault.distributeDeposits();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 mETH

        invokeExecution();
        vm.warp(block.timestamp + 86400 * 10);

        deposit(60000, address(this));

        rootVault.registerWithdrawal(lpTokens * 2 / 3); // ~333 mETH
        invokeExecution();

        _checkTvlsAreEqual();

        address recipient = getNextUserAddress();
        claimMoney(recipient);

        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 60000 / 6 * 7 * weiofUsdc, 80));
    }

    function testSeveralInvocationsWhenFirstNotTakenAndNewSumIsLessWETH() public {
        addVaults();
        deposit(123000, address(this));
        erc20Vault.distributeDeposits();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 mETH

        invokeExecution();
        vm.warp(block.timestamp + 86400 * 10);

        deposit(123000, address(this));

        rootVault.registerWithdrawal(lpTokens / 3); // ~166 mETH
        invokeExecution();

        assertTrue(isClose(tvl(), 123000 / 6 * 7 * weiofUsdc, 100));
    }

    function testCancelWithdrawalIsOkayWETH() public {
        addVaults();
        deposit(275000, address(this)); 
        erc20Vault.distributeDeposits();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 USD
        rootVault.cancelWithdrawal(lpTokens / 4); // cancel 125 USD

        invokeExecution();
        address recipient = getNextUserAddress();
        claimMoney(recipient);

        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 275000 / 4 * weiofUsdc, 50)); // anyway only 125 usd claimed
    }

    function testWitdrawalOrderCancelsAfterTime() public {
        addVaults();
        deposit(80000, address(this));
        erc20Vault.distributeDeposits();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2); // 250 mETH

        invokeExecution();
        deposit(80000, address(this));
        vm.warp(block.timestamp + 86400 * 10);
        invokeExecution();

        address recipient = getNextUserAddress();
        claimMoney(recipient); 

        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 80000 / 2 * weiofUsdc, 20));
    }

    function testFailTwoInvocationsInShortTime() public {
        addVaults();
        deposit(120000, address(this));
        erc20Vault.distributeDeposits();

        invokeExecution();
        deposit(120000, address(this));
        vm.warp(block.timestamp + 86400 * 3); // only 3 days
        invokeExecution();
    }

    function testFailExcessiveLpTokensTransfer() public {
        addVaults();
        deposit(115000, address(this));
        erc20Vault.distributeDeposits();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2);

        address recipient = getNextUserAddress();

        rootVault.transfer(recipient, lpTokens / 4 * 3);
    }

    function testFailExcessiveLpTokensTransferAfterInvocation() public {
        addVaults();
        deposit(280000, address(this));
        erc20Vault.distributeDeposits();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2);

        invokeExecution();

        address recipient = getNextUserAddress();

        rootVault.transfer(recipient, lpTokens / 4 * 3);
    }

    function testFailExcessiveLpTokensTransferAfterWithdrawal() public {
        addVaults();
        deposit(280000, address(this));
        erc20Vault.distributeDeposits();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2);

        invokeExecution();

        rootVault.registerWithdrawal(lpTokens / 10);

        address recipient = getNextUserAddress();
        claimMoney(recipient); 

        rootVault.transfer(recipient, lpTokens / 20 * 9);
    }

    function testRegisterAfterTransferIsOkay() public {
        addVaults();
        deposit(175000, address(this));
        erc20Vault.distributeDeposits();

        address recipient = getNextUserAddress();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.transfer(recipient, lpTokens / 2);

        vm.startPrank(recipient);
        rootVault.registerWithdrawal(lpTokens / 2);
        vm.stopPrank();

        invokeExecution();
        vm.startPrank(recipient);
        claimMoney(recipient); 
        vm.stopPrank();

        assertTrue(isClose(IERC20(weth).balanceOf(recipient), 175000 / 2 * weiofUsdc, 100));
    }

    function testCancelAndTransferIsOkay() public {
        addVaults();
        deposit(50000, address(this));
        erc20Vault.distributeDeposits();

        uint256 lpTokens = rootVault.balanceOf(address(this));

        address recipient = getNextUserAddress();
        rootVault.registerWithdrawal(lpTokens / 2);
        rootVault.cancelWithdrawal(lpTokens / 4);

        rootVault.transfer(recipient, lpTokens / 5 * 3);
    }

    function testTransferNormalAmountWorks() public {
        addVaults();
        deposit(200000, address(this));
        erc20Vault.distributeDeposits();

        uint256 lpTokens = rootVault.balanceOf(address(this));
        rootVault.registerWithdrawal(lpTokens / 2);

        address recipient = getNextUserAddress();

        rootVault.transfer(recipient, lpTokens / 4);
        assertTrue(rootVault.balanceOf(address(this)) == lpTokens - lpTokens / 4);
    }

    function testLpTokensFeeWorksAsExpected() public {
        addVaults();
        deposit(120000, address(this));
        erc20Vault.distributeDeposits();

        uint256 lpAmount = rootVault.balanceOf(address(this));
        uint256 currentTvl = tvl();

        depositExactAmount(currentTvl, address(this));

        uint256 lpReceived = rootVault.balanceOf(address(this)) - lpAmount;
        require(lpReceived * 1000 < lpAmount * 999); // 0.01% taken
        require(lpReceived * 1000 > lpAmount * 997); // but < 0.03% taken
    }

    function testLpTokensFeeNotComingWithoutOpeningAccount() public {
        addVaults();
        deposit(130000, address(this));

        uint256 lpAmount = rootVault.balanceOf(address(this));
        uint256 currentTvl = tvl();

        depositExactAmount(currentTvl, address(this));

        uint256 lpReceived = rootVault.balanceOf(address(this)) - lpAmount;
        require(isClose(lpReceived, lpAmount, 10000));
    }

    function testLpTokensFeesComingWithOpeningAccount() public {
        addVaults();
        deposit(75000, address(this));

        erc20Vault.distributeDeposits();

        uint256 lpAmount = rootVault.balanceOf(address(this));
        uint256 currentTvl = tvl();

        depositExactAmount(currentTvl, address(this));

        uint256 lpReceived = rootVault.balanceOf(address(this)) - lpAmount;
        require(lpReceived * 1000 < lpAmount * 999); // 0.01% taken
        require(lpReceived * 1000 > lpAmount * 997); // but < 0.03% taken
    }

    function testLpTokensFeesComingAfterClosingAccount() public {
        addVaults();
        deposit(100000, address(this));
        erc20Vault.distributeDeposits();
        invokeExecution();

        uint256 lpAmount = rootVault.balanceOf(address(this));
        uint256 currentTvl = tvl();

        depositExactAmount(currentTvl, address(this));

        uint256 lpReceived = rootVault.balanceOf(address(this)) - lpAmount;
        require(lpReceived * 1000 < lpAmount * 999); // 0.01% taken
        require(lpReceived * 1000 > lpAmount * 997); // but < 0.03% taken
    }

    function testFailDepositIfPoolDisbalanced() public {
        deal(weth, address(this), 3 * 10**23);
        ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).exchange{value: 3*10**23}(0, 1, 3 * 10**23, 0);
        addVaults();
        deposit(100000, address(this));
    }

    function testLidoRewardsToBeCalculatedCorrectly() public {
        addVaults();
        deposit(100000, address(this));
        erc20Vault.distributeDeposits();
        placeLidoRewarding();

        uint256 tvlBeforeOracleSetting = tvl();

        IChainlinkOracle chainlink = MellowOracle(mellowOracle).chainlinkOracle();

        MockAggregator agg = new MockAggregator();

        address[] memory tokens = new address[](1);
        address[] memory oracles = new address[](1);

        tokens[0] = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
        oracles[0] = address(agg);

        vm.startPrank(admin);

        chainlink.addChainlinkOracles(tokens, oracles);

        vm.stopPrank();
        uint256 tvlAfterOracleSetting = tvl();

        assertTrue(tvlAfterOracleSetting > tvlBeforeOracleSetting);
        assertTrue(999 * tvlAfterOracleSetting < 1000 * tvlBeforeOracleSetting); // < 0.1% fees for a day

        _checkTvlsAreEqual();

    }
    
}
