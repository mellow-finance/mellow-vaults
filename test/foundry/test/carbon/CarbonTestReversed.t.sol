// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/ProtocolGovernance.sol";
import "../../src/MockOracle.sol";
import "../../src/ERC20RootVaultHelper.sol";
import "../../src/VaultRegistry.sol";

import "../../src/vaults/CarbonVault.sol";
import "../../src/vaults/ERC20RootVault.sol";
import "../../src/vaults/ERC20Vault.sol";

import "../../src/vaults/CarbonVaultGovernance.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";

contract CarbonTestB is Test {

    IERC20RootVault rootVault;
    IERC20Vault erc20Vault;
    ICarbonVault carbonVault;

    address sAdmin = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;
    address admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;
    address protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public dai = 0xD33526068D116cE69F19A9ee46F0bd304F21A51f;
    address public eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public rootGovernance = 0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public carbonGovernance;

    address public controller = 0xC537e898CD774e2dCBa3B14Ea6f34C93d5eA45e1;

    IERC20RootVaultGovernance rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

    function firstDeposit() public {

        deal(weth, deployer, 10**10);
        deal(dai, deployer, 10**10);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10**10;
        amounts[1] = 10**10;

        IERC20(weth).approve(address(rootVault), type(uint256).max);
        IERC20(dai).approve(address(rootVault), type(uint256).max);

        rootVault.deposit(amounts, 0, "");
    }

    function deposit(uint256 amount) public {

        if (rootVault.totalSupply() == 0) {
            firstDeposit();
        }

        deal(dai, deployer, amount * 10**15);
        deal(weth, deployer, amount * 10**15);

        uint256[] memory amounts = new uint256[](2);

        amounts[0] = amount * 10**15;
        amounts[1] = amount * 10**15;

        rootVault.deposit(amounts, 0, "");

        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = dai;

        erc20Vault.pull(
            address(carbonVault),
            tokens,
            amounts,
            ""
        );
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

    function kek() public payable {

        {
            vm.stopPrank();
            vm.startPrank(admin);

            uint8[] memory RE = new uint8[](1);
            RE[0] = 3;
            ProtocolGovernance(governance).stagePermissionGrants(dai, RE);

            vm.warp(block.timestamp + 86400);

            ProtocolGovernance(governance).commitPermissionGrants(dai);

            vm.stopPrank();
            vm.startPrank(deployer);
        }

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = dai;

        ICarbonController(controller).createPair(Token.wrap(dai), Token.wrap(eth));

        {
            CarbonVault singleton = new CarbonVault();
            IVaultGovernance.InternalParams memory ip = IVaultGovernance.InternalParams({
                protocolGovernance: IProtocolGovernance(governance),
                registry: IVaultRegistry(registry),
                singleton: singleton
            });
            
            
            ICarbonVaultGovernance.DelayedProtocolParams memory dpp = ICarbonVaultGovernance.DelayedProtocolParams({
                controller: ICarbonController(controller),
                weth: weth
            });

            ICarbonVaultGovernance gg = new CarbonVaultGovernance(ip, dpp);

            vm.stopPrank();
            vm.startPrank(admin);

            uint8[] memory R = new uint8[](1);
            ProtocolGovernance(governance).stagePermissionGrants(address(gg), R);

            vm.warp(block.timestamp + 86400);

            ProtocolGovernance(governance).commitPermissionGrants(address(gg));
            carbonGovernance = address(gg);

            vm.stopPrank();
            vm.startPrank(deployer);

        }

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, deployer);
        }

        {
            ICarbonVaultGovernance carGovernance = ICarbonVaultGovernance(carbonGovernance);
            carGovernance.createVault(tokens, deployer);

            ICarbonVaultGovernance.DelayedStrategyParams memory dsp = ICarbonVaultGovernance.DelayedStrategyParams({
                maximalPositionsCount: 5
            });

            carGovernance.stageDelayedStrategyParams(erc20VaultNft + 1, dsp);
            carGovernance.commitDelayedStrategyParams(erc20VaultNft + 1);

        }

        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));
        carbonVault = ICarbonVault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }

        IVaultRegistry(registry).transferFrom(deployer, sAdmin, erc20VaultNft + 2);
    }

    function setUp() public {
        vm.startPrank(deployer);
        kek();
    }

    function testSetup() public {
        deposit(1000);
    }

    function convert(uint256 p) public returns (uint256) {
        uint256 S = p * (1 << 96);
        return S;
    }

    function testSimpleAddingPositionWorksR() public {
        uint256 A = 500;
        uint256 B = 1000;
        uint256 C = 3000;
        uint256 D = 4000;

        deposit(1000);

        carbonVault.addPosition(convert(A), convert(B), convert(B), convert(C), convert(C), convert(D), 1000 * 10**15, 1000 * 10**15);
    } 

    function testSimpleDeletingPositionWorks() public {
        uint256 A = 500;
        uint256 B = 1000;
        uint256 C = 3000;
        uint256 D = 4000;

        deposit(1000);

        uint256 nft = carbonVault.addPosition(convert(A), convert(B), convert(B), convert(C), convert(C), convert(D), 1000 * 10**15, 1000 * 10**15);
        carbonVault.closePosition(nft);
    }

    function testSimpleUpdatingPositionWorksNoChange() public {
        uint256 A = 500;
        uint256 B = 1000;
        uint256 C = 3000;
        uint256 D = 4000;

        deposit(2000);

        uint256 nft = carbonVault.addPosition(convert(A), convert(B), convert(B), convert(C), convert(C), convert(D), 1000 * 10**15, 1000 * 10**15);
        carbonVault.updatePosition(nft, 1000 * 10**15, 1000 * 10**15);
    }

    function testSimpleUpdatingPositionWorksIncrease() public {
        uint256 A = 500;
        uint256 B = 1000;
        uint256 C = 3000;
        uint256 D = 4000;

        deposit(2000);

        uint256 nft = carbonVault.addPosition(convert(A), convert(B), convert(B), convert(C), convert(C), convert(D), 1000 * 10**15, 1000 * 10**15);
        carbonVault.updatePosition(nft, 2000 * 10**15, 2000 * 10**15);
    }

    function testSimpleUpdatingPositionWorksDecrease() public {
        uint256 A = 500;
        uint256 B = 1000;
        uint256 C = 3000;
        uint256 D = 4000;

        deposit(2000);

        uint256 nft = carbonVault.addPosition(convert(A), convert(B), convert(B), convert(C), convert(C), convert(D), 1000 * 10**15, 1000 * 10**15);
        carbonVault.updatePosition(nft, 500 * 10**15, 500 * 10**15);
    }

    function testFailNonStrategyToAddPosition() public {
        uint256 A = 500;
        uint256 B = 1000;
        uint256 C = 3000;
        uint256 D = 4000;

        deposit(1000);

        vm.stopPrank();
        vm.startPrank(operator);

        uint256 nft = carbonVault.addPosition(convert(A), convert(B), convert(B), convert(C), convert(C), convert(D), 1000 * 10**15, 1000 * 10**15);
    }

    function testFailNonStrategyToClosePosition() public {
        uint256 A = 500;
        uint256 B = 1000;
        uint256 C = 3000;
        uint256 D = 4000;

        deposit(1000);
        uint256 nft = carbonVault.addPosition(convert(A), convert(B), convert(B), convert(C), convert(C), convert(D), 1000 * 10**15, 1000 * 10**15);

        vm.stopPrank();
        vm.startPrank(operator);

        carbonVault.closePosition(nft);
    }

    function testFailNonStrategyToUpdatePosition() public {
        uint256 A = 500;
        uint256 B = 1000;
        uint256 C = 3000;
        uint256 D = 4000;

        deposit(2000);
        uint256 nft = carbonVault.addPosition(convert(A), convert(B), convert(B), convert(C), convert(C), convert(D), 1000 * 10**15, 1000 * 10**15);

        vm.stopPrank();
        vm.startPrank(operator);

        carbonVault.updatePosition(nft, 1000 * 10**15, 1000 * 10**15);
    }

    function testSeveralPositions() public {
        uint256 A = 500;
        uint256 B = 1000;
        uint256 C = 3000;
        uint256 D = 4000;

        deposit(2000);
        uint256 nft = carbonVault.addPosition(convert(A), convert(B), convert(B), convert(C), convert(C), convert(D), 1000 * 10**15, 1000 * 10**15);

        A = 1100;
        B = 1200;
        C = 2800;
        D = 2900;

        uint256 nft2 = carbonVault.addPosition(convert(A), convert(B), convert(B), convert(C), convert(C), convert(D), 1000 * 10**15, 1000 * 10**15);
    }

    function testFailALotOfPositions() public {

        uint256 A = 500;
        uint256 B = 1000;
        uint256 C = 3000;
        uint256 D = 4000;

        deposit(20000);

        for (uint256 i = 0; i < 6; ++i) {
            carbonVault.addPosition(convert(A), convert(B), convert(B), convert(C), convert(C), convert(D), 1000 * 10**15, 1000 * 10**15);
        }
    }

    function testPassALotOfPositionsWhenDeleted() public {
        uint256 A = 500;
        uint256 B = 1000;
        uint256 C = 3000;
        uint256 D = 4000;

        deposit(20000);

        for (uint256 i = 0; i < 6; ++i) {
            uint256 nft = carbonVault.addPosition(convert(A), convert(B), convert(B), convert(C), convert(C), convert(D), 1000 * 10**15, 1000 * 10**15);
            if (i == 0) {
                carbonVault.closePosition(nft);
            }
        }
    }

    function testSuccessfullMicroTradeOneSideB() public {
        uint256 A = 500;
        uint256 B = 1000;
        uint256 C = 3000;
        uint256 D = 4000;

        deposit(1000);
        uint256 nft = carbonVault.addPosition(convert(A), convert(B), convert(B), convert(C), convert(C), convert(D), 1000 * 10**15, 1000 * 10**15);

        TradeAction[] memory ta = new TradeAction[](1);
        ta[0] = TradeAction({
            strategyId: nft,
            amount: 10**12
        });

        uint128 g = carbonVault.controller().tradeBySourceAmount{value: 10**12}(Token.wrap(eth), Token.wrap(dai), ta, type(uint256).max, 100);

        require(g <= 10**15 && g >= 995 * 10**12);
    }

    function testSuccessfullTradeOneSide() public {
        uint256 A = 500;
        uint256 B = 1000;
        uint256 C = 3000;
        uint256 D = 4000;

        deposit(1000);
        uint256 nft = carbonVault.addPosition(convert(A), convert(B), convert(B), convert(C), convert(C), convert(D), 1000 * 10**15, 1000 * 10**15);

        TradeAction[] memory ta = new TradeAction[](1);
        ta[0] = TradeAction({
            strategyId: nft,
            amount: 500 * 10**12
        });

        uint128 g = carbonVault.controller().tradeBySourceAmount{value: 500 * 10**12}(Token.wrap(eth), Token.wrap(dai), ta, type(uint256).max, 100);

        require(g <= 45 * 10**16 && g >= 35 * 10**16);
    }

    function testSuccessfullMicroTradeOtherSide() public {
        uint256 A = 500;
        uint256 B = 1000;
        uint256 C = 3000;
        uint256 D = 4000;

        deposit(1000);
        uint256 nft = carbonVault.addPosition(convert(A), convert(B), convert(B), convert(C), convert(C), convert(D), 1000 * 10**12, 1000 * 10**12);

        TradeAction[] memory ta = new TradeAction[](1);
        ta[0] = TradeAction({
            strategyId: nft,
            amount: 10**15
        });

        deal(dai, deployer, 10**15);
        IERC20(dai).approve(address(carbonVault.controller()), type(uint256).max);

        uint128 g = carbonVault.controller().tradeBySourceAmount(Token.wrap(dai), Token.wrap(eth), ta, type(uint256).max, 10**9);

        require(g <= 334 * 10**9 && g >= 329 * 10**9);
    }

    function testSuccessfullTradeOtherSide() public {
        uint256 A = 500;
        uint256 B = 1000;
        uint256 C = 3000;
        uint256 D = 4000;

        deposit(1000);
        uint256 nft = carbonVault.addPosition(convert(A), convert(B), convert(B), convert(C), convert(C), convert(D), 1000 * 10**12, 1000 * 10**12);

        TradeAction[] memory ta = new TradeAction[](1);
        ta[0] = TradeAction({
            strategyId: nft,
            amount: 3 * 10**18
        });

        deal(dai, deployer, 3 * 10**18);
        IERC20(dai).approve(address(carbonVault.controller()), type(uint256).max);

        uint128 g = carbonVault.controller().tradeBySourceAmount(Token.wrap(dai), Token.wrap(eth), ta, type(uint256).max, 10**9);

        require(g <= 900 * 10**12 && g >= 600 * 10**12);
    }

}
