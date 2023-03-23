// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/ProtocolGovernance.sol";
import "../../src/VaultRegistry.sol";
import "../../src/ERC20RootVaultHelper.sol";
import "../../src/MockOracle.sol";

import "../../src/utils/UniV3Helper.sol";
import "../../src/utils/LStrategyHelper.sol";
import "../../src/utils/FarmingPool.sol";
import "../../src/utils/LidoDepositWrapper.sol";
import "../../src/vaults/ERC20Vault.sol";
import "../../src/vaults/ERC20RootVault.sol";
import "../../src/vaults/ERC20RootVaultL.sol";

import "../../src/vaults/GearboxVaultGovernance.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";
import "../../src/vaults/UniV3VaultGovernance.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";
import "../../src/vaults/ERC20RootVaultGovernanceL.sol";
import "../../src/strategies/LStrategy.sol";
import "../../src/interfaces/external/lido/ISTETH.sol";
import "../../src/interfaces/external/lido/IWSTETH.sol";

contract LidoDepositingTest is Test {

    IERC20RootVault public rootVault;
    IERC20Vault erc20Vault;
    IUniV3Vault uniV3LowerVault;
    IUniV3Vault uniV3UpperVault;

    LidoDepositWrapper wrapper;


    uint256 nftStart;
    address sAdmin = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;
    address protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;

    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public uniswapV3PositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public uniGovernance = 0x9c319DC47cA6c8c5e130d5aEF5B8a40Cce9e877e;
    address public mellowOracle = 0x9d992650B30C6FB7a83E7e7a430b4e015433b838;

    uint256 width = 280;

    function firstDeposit() public {

        deal(weth, deployer, 10**10);
        deal(wsteth, deployer, 2 * 10**10);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2 * 10**10;
        amounts[1] = 10 ** 10;

        IERC20(weth).approve(address(rootVault), type(uint256).max);
        IERC20(wsteth).approve(address(rootVault), type(uint256).max);

        uint256 x = 0;
        bytes memory depositInfo = abi.encode(x, x, x, x);

        rootVault.deposit(amounts, 0, depositInfo);
    }

    function deposit(uint256 amount) public {

        if (rootVault.totalSupply() == 0) {
            firstDeposit();
        }

        deal(weth, deployer, amount * 10**15);
        deal(wsteth, deployer, 2 * amount * 10**15);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2 * amount * 10**15;
        amounts[1] = amount * 10**15;

        IERC20(weth).approve(address(rootVault), type(uint256).max);
        IERC20(wsteth).approve(address(rootVault), type(uint256).max);

        uint256 x = 0;
        bytes memory depositInfo = abi.encode(x, x, x, x);

        rootVault.deposit(amounts, 0, depositInfo);
    }

    address public constant steth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {

        ERC20RootVaultL singleton = new ERC20RootVaultL();

        IProtocolGovernance protocolGovernance = IProtocolGovernance(governance);
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        IERC20RootVaultGovernanceL.DelayedProtocolParams memory paramsB = IERC20RootVaultGovernanceL.DelayedProtocolParams({
            managementFeeChargeDelay: 0,
            oracle: IOracle(mellowOracle)
        });

        IVaultGovernance.InternalParams memory paramsA = IVaultGovernance.InternalParams({
            protocolGovernance: protocolGovernance,
            registry: vaultRegistry,
            singleton: singleton
        });

        IERC20RootVaultHelper helper = new ERC20RootVaultHelper();

        IERC20RootVaultGovernanceL rootVaultGovernance = new ERC20RootVaultGovernanceL(paramsA, paramsB, helper);
        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(address(rootVaultGovernance), nfts[i]);
        }

        vm.stopPrank();
        vm.startPrank(admin);

        uint8[] memory grant = new uint8[](1);
        protocolGovernance.stagePermissionGrants(address(rootVaultGovernance), grant);
        vm.warp(block.timestamp + 86400);
        protocolGovernance.commitPermissionGrants(address(rootVaultGovernance));

        vm.stopPrank();
        vm.startPrank(deployer);

        (IERC20RootVault w, uint256 nft) = rootVaultGovernance.createVault(tokens, address(0), nfts, deployer);
        rootVault = w;
        rootVaultGovernance.setStrategyParams(
            nft,
            IERC20RootVaultGovernanceL.StrategyParams({
                tokenLimitPerAddress: type(uint256).max,
                tokenLimit: type(uint256).max,
                maxTimeOneRebalance: 0,
                minTimeBetweenRebalances: 3600
            })
        );

        rootVaultGovernance.stageDelayedStrategyParams(
            nft,
            IERC20RootVaultGovernanceL.DelayedStrategyParams({
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

    function kek() public payable returns (uint256 startNft) {

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 uniV3LowerVaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = wsteth;
        tokens[1] = weth;

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, deployer);
        }

        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(uniV3LowerVaultNft));

        {
            uint256[] memory nfts = new uint256[](1);
            nfts[0] = uniV3LowerVaultNft;
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
        wrapper = new LidoDepositWrapper();

        firstDeposit();

    }

    function testEth() external {
        deal(deployer, 10**20);
        uint256 x = 0;
        bytes memory depositInfo = abi.encode(x, x, x, x);
        wrapper.deposit{value:10**20}(rootVault, 0, 0, 10**20, 0, depositInfo);

        uint256 depositedAmount = 10**20;

        uint256 oldBalance0 = IERC20(wsteth).balanceOf(deployer);
        uint256 oldBalance1 = IERC20(weth).balanceOf(deployer);

        uint256[] memory minAmounts = new uint256[](2);
        bytes[] memory bb = new bytes[](1);
        bb[0] = depositInfo;
        rootVault.withdraw(deployer, rootVault.balanceOf(deployer), minAmounts, bb);

        uint256 newBalance0 = IERC20(wsteth).balanceOf(deployer);
        uint256 newBalance1 = IERC20(weth).balanceOf(deployer);

        (uint256 sqrtPriceX96, , , , , ,) = IUniswapV3Pool(0xD340B57AAcDD10F96FC1CF10e15921936F41E29c).slot0();
        uint256 priceX96 = sqrtPriceX96 * sqrtPriceX96 / 2**96;
        uint256 withdrawnAmount = (newBalance1 - oldBalance1) + priceX96 * (newBalance0 - oldBalance0) / 2**96;

        require(isClose(depositedAmount, withdrawnAmount, 500)); // <0.2% loss 
    }

    function testEth2() external {
        deal(deployer, 1008 * 10**17);
        uint256 x = 0;
        bytes memory depositInfo = abi.encode(x, x, x, x);
        wrapper.deposit{value:1008 * 10**17}(rootVault, 0, 1, 1008 * 10**17, 0, depositInfo);

        uint256 depositedAmount = 10**20;

        uint256 oldBalance0 = IERC20(wsteth).balanceOf(deployer);
        uint256 oldBalance1 = IERC20(weth).balanceOf(deployer);

        uint256[] memory minAmounts = new uint256[](2);
        bytes[] memory bb = new bytes[](1);
        bb[0] = depositInfo;
        rootVault.withdraw(deployer, rootVault.balanceOf(deployer), minAmounts, bb);

        uint256 newBalance0 = IERC20(wsteth).balanceOf(deployer);
        uint256 newBalance1 = IERC20(weth).balanceOf(deployer);

        (uint256 sqrtPriceX96, , , , , ,) = IUniswapV3Pool(0xD340B57AAcDD10F96FC1CF10e15921936F41E29c).slot0();
        uint256 priceX96 = sqrtPriceX96 * sqrtPriceX96 / 2**96;
        uint256 withdrawnAmount = (newBalance1 - oldBalance1) + priceX96 * (newBalance0 - oldBalance0) / 2**96;

        require(isClose(depositedAmount, withdrawnAmount, 500)); // <0.2% loss 
    }

    function testWeth() external {
        deal(weth, deployer, 10**20);
        IERC20(weth).approve(address(wrapper), type(uint256).max);

        uint256 x = 0;
        bytes memory depositInfo = abi.encode(x, x, x, x);
        wrapper.deposit(rootVault, 1, 0, 10**20, 0, depositInfo);

        uint256 depositedAmount = 10**20;

        uint256 oldBalance0 = IERC20(wsteth).balanceOf(deployer);
        uint256 oldBalance1 = IERC20(weth).balanceOf(deployer);

        uint256[] memory minAmounts = new uint256[](2);
        bytes[] memory bb = new bytes[](1);
        bb[0] = depositInfo;
        rootVault.withdraw(deployer, rootVault.balanceOf(deployer), minAmounts, bb);

        uint256 newBalance0 = IERC20(wsteth).balanceOf(deployer);
        uint256 newBalance1 = IERC20(weth).balanceOf(deployer);

        (uint256 sqrtPriceX96, , , , , ,) = IUniswapV3Pool(0xD340B57AAcDD10F96FC1CF10e15921936F41E29c).slot0();
        uint256 priceX96 = sqrtPriceX96 * sqrtPriceX96 / 2**96;
        uint256 withdrawnAmount = (newBalance1 - oldBalance1) + priceX96 * (newBalance0 - oldBalance0) / 2**96;

        require(isClose(depositedAmount, withdrawnAmount, 500)); // <0.2% loss 
    }

    function testWeth2() external {
        deal(weth, deployer, 1008 * 10**17);
        IERC20(weth).approve(address(wrapper), type(uint256).max);

        uint256 x = 0;
        bytes memory depositInfo = abi.encode(x, x, x, x);
        wrapper.deposit(rootVault, 1, 1, 1008 * 10**17, 0, depositInfo);

        uint256 depositedAmount = 10**20;

        uint256 oldBalance0 = IERC20(wsteth).balanceOf(deployer);
        uint256 oldBalance1 = IERC20(weth).balanceOf(deployer);

        uint256[] memory minAmounts = new uint256[](2);
        bytes[] memory bb = new bytes[](1);
        bb[0] = depositInfo;
        rootVault.withdraw(deployer, rootVault.balanceOf(deployer), minAmounts, bb);

        uint256 newBalance0 = IERC20(wsteth).balanceOf(deployer);
        uint256 newBalance1 = IERC20(weth).balanceOf(deployer);

        (uint256 sqrtPriceX96, , , , , ,) = IUniswapV3Pool(0xD340B57AAcDD10F96FC1CF10e15921936F41E29c).slot0();
        uint256 priceX96 = sqrtPriceX96 * sqrtPriceX96 / 2**96;
        uint256 withdrawnAmount = (newBalance1 - oldBalance1) + priceX96 * (newBalance0 - oldBalance0) / 2**96;

        require(isClose(depositedAmount, withdrawnAmount, 500)); // <0.2% loss 
    }

    function testSteth() external {
        deal(deployer, 1008 * 10**17);
        ISTETH(steth).submit{value:1008 * 10**17}(deployer);
        IERC20(steth).approve(address(wrapper), type(uint256).max);

        uint256 x = 0;
        bytes memory depositInfo = abi.encode(x, x, x, x);
        wrapper.deposit(rootVault, 2, 0, IERC20(steth).balanceOf(deployer), 0, depositInfo);

        uint256 depositedAmount = 10**20;

        uint256 oldBalance0 = IERC20(wsteth).balanceOf(deployer);
        uint256 oldBalance1 = IERC20(weth).balanceOf(deployer);

        uint256[] memory minAmounts = new uint256[](2);
        bytes[] memory bb = new bytes[](1);
        bb[0] = depositInfo;
        rootVault.withdraw(deployer, rootVault.balanceOf(deployer), minAmounts, bb);

        uint256 newBalance0 = IERC20(wsteth).balanceOf(deployer);
        uint256 newBalance1 = IERC20(weth).balanceOf(deployer);

        (uint256 sqrtPriceX96, , , , , ,) = IUniswapV3Pool(0xD340B57AAcDD10F96FC1CF10e15921936F41E29c).slot0();
        uint256 priceX96 = sqrtPriceX96 * sqrtPriceX96 / 2**96;
        uint256 withdrawnAmount = (newBalance1 - oldBalance1) + priceX96 * (newBalance0 - oldBalance0) / 2**96;

        console2.log(withdrawnAmount);

        require(isClose(depositedAmount, withdrawnAmount, 500));
    }

    function testWsteth() external {
        deal(deployer, 1008 * 10**17);
        ISTETH(steth).submit{value:1008 * 10**17}(deployer);
        IERC20(steth).approve(wsteth, type(uint256).max);
        IwstETH(wsteth).wrap(IERC20(steth).balanceOf(deployer));
        IERC20(wsteth).approve(address(wrapper), type(uint256).max);

        uint256 x = 0;
        bytes memory depositInfo = abi.encode(x, x, x, x);
        wrapper.deposit(rootVault, 3, 0, IERC20(wsteth).balanceOf(deployer), 0, depositInfo);

        uint256 depositedAmount = 10**20;

        uint256 oldBalance0 = IERC20(wsteth).balanceOf(deployer);
        uint256 oldBalance1 = IERC20(weth).balanceOf(deployer);

        uint256[] memory minAmounts = new uint256[](2);
        bytes[] memory bb = new bytes[](1);
        bb[0] = depositInfo;
        rootVault.withdraw(deployer, rootVault.balanceOf(deployer), minAmounts, bb);

        uint256 newBalance0 = IERC20(wsteth).balanceOf(deployer);
        uint256 newBalance1 = IERC20(weth).balanceOf(deployer);

        (uint256 sqrtPriceX96, , , , , ,) = IUniswapV3Pool(0xD340B57AAcDD10F96FC1CF10e15921936F41E29c).slot0();
        uint256 priceX96 = sqrtPriceX96 * sqrtPriceX96 / 2**96;
        uint256 withdrawnAmount = (newBalance1 - oldBalance1) + priceX96 * (newBalance0 - oldBalance0) / 2**96;

        console2.log(withdrawnAmount);

        require(isClose(depositedAmount, withdrawnAmount, 500));
    }

 }