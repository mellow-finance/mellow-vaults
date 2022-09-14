// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../lib/forge-std/src/console2.sol";
import "../lib/forge-std/src/Vm.sol";
import "../lib/forge-std/src/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../test/helpers/IWETH.sol";
import "../test/helpers/IWSTETH.sol";
import "../test/helpers/ICurvePool.sol";
import "../test/helpers/ISwapRouter.sol";
import "../test/helpers/INonFungiblePositionManager.sol";
import "../test/helpers/IProtocolGovernance.sol";
import "../test/helpers/IUniV3Helper.sol";
import "../test/helpers/ILStrategyHelper.sol";
import "../test/helpers/IVaultRegistry.sol";
import "../test/helpers/IUniV3VaultGovernance.sol";
import "../test/helpers/IERC20VaultGovernance.sol";
import "../test/helpers/IERC20RootVaultGovernance.sol";
import "../test/helpers/libraries/PermissionIdsLibrary.sol";
import "../src/MockCowswap.sol";
import "../src/LStrategy.sol";
import "../src/ERC20Validator.sol";
import "../src/CowSwapValidator.sol";
import "../src/MockOracle.sol";
import "./Constants.sol";
import "./FeedContract.sol";

contract Backtest is Test {
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public uniswapV3PositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public deployer = address(this);
    address public admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;
    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public helper = 0x1E13A22d392584B24f5DDd6E6Da88f54dA872FA8;
    address public uniGovernance = 0x8306bec30063f00F5ffd6976f09F6b10E77B27F2;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public rootGovernance = 0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA;
    address public lStrategyHelper = 0x9Cf7dFEf7C0311C16C864e8B88bf3261F19a6DB8;
    LStrategy lstrategy;

    uint256 constant Q48 = 2**48;
    uint256 constant Q96 = 2**96;
    uint256 constant D27 = 10**27;

    function mint(
        address token,
        address addr,
        uint256 amount
    ) public {
        uint256 currentBalance = IERC20(token).balanceOf(addr);
        deal(token, addr, currentBalance + amount);
    }

    function initialMint() public payable {
        uint256 smallAmount = 10**13;
        mint(weth, deployer, smallAmount);

        IWETH wethContract = IWETH(weth);
        IWSTETH wstethContract = IWSTETH(wsteth);
        ICurvePool curvePool = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
        IERC20 steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

        wethContract.approve(address(curvePool), type(uint256).max);
        steth.approve(address(wstethContract), type(uint256).max);

        wethContract.withdraw(smallAmount / 2);
        curvePool.exchange{value: smallAmount / 2}(0, 1, smallAmount / 2, 0);
        wstethContract.wrap(((smallAmount / 2) * 99) / 100);
    }

    function execute(
        uint256 width,
        uint256 weth_amount,
        uint256 wsteth_amount
    ) public {
        console2.log("Process started");
    }

    fallback() external payable {}

    receive() external payable {}

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory
    ) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {
        IERC20RootVaultGovernance rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);
        vm.startPrank(admin);
        for (uint256 i = 0; i < nfts.length; ++i) {
            IVaultRegistry(registry).approve(rootGovernance, nfts[i]);
        }
        (, uint256 nft) = rootVaultGovernance.createVault(tokens, address(lstrategy), nfts, admin);
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
                strategyTreasury: deployer,
                strategyPerformanceTreasury: deployer,
                managementFee: 2 * 10**7,
                performanceFee: 20 * 10**7,
                privateVault: false,
                depositCallbackAddress: address(0),
                withdrawCallbackAddress: address(0)
            })
        );

        vm.warp(block.timestamp + IProtocolGovernance(governance).governanceDelay());
        rootVaultGovernance.commitDelayedStrategyParams(nft);

        vm.stopPrank();
    }

    function setupSecondPhase(IWETH wethContract, IWSTETH wstethContract) public payable {
        ICurvePool curvePool = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
        IERC20 steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

        wethContract.approve(address(curvePool), type(uint256).max);
        steth.approve(address(wstethContract), type(uint256).max);
        wethContract.withdraw(2 * 10**21);

        console2.log("Before exchange");
        curvePool.exchange{value: 2 * 10**21}(0, 1, 2 * 10**21, 0);
        console2.log("After exchange");

        wstethContract.wrap(10**18 * 1990);

        console2.log("After wrap");

        wstethContract.transfer(address(lstrategy), 3 * 10**17);
        wethContract.transfer(address(lstrategy), 3 * 10**17);

        MockOracle mockOracle = new MockOracle();
        IUniV3VaultGovernance uniV3VaultGovernance = IUniV3VaultGovernance(uniGovernance);

        vm.startPrank(admin);
        uniV3VaultGovernance.stageDelayedProtocolParams(
            IUniV3VaultGovernance.DelayedProtocolParams({
                positionManager: INonfungiblePositionManager(uniswapV3PositionManager),
                oracle: IOracle(mockOracle)
            })
        );

        vm.warp(block.timestamp + 86400);
        uniV3VaultGovernance.commitDelayedProtocolParams();

        lstrategy.updateTradingParams(
            LStrategy.TradingParams({
                maxSlippageD: 10**7,
                oracleSafetyMask: 0x20,
                orderDeadline: 86400 * 30,
                oracle: mockOracle,
                maxFee0: 10**9,
                maxFee1: 10**9
            })
        );

        lstrategy.updateRatioParams(
            LStrategy.RatioParams({
                erc20UniV3CapitalRatioD: 5 * 10**7, // 0.05 * DENOMINATOR
                erc20TokenRatioD: 5 * 10**8, // 0.5 * DENOMINATOR
                minErc20UniV3CapitalRatioDeviationD: 10**7,
                minErc20TokenRatioDeviationD: 5 * 10**7,
                minUniV3LiquidityRatioDeviationD: 2 * 10**6
            })
        );

        lstrategy.updateOtherParams(
            LStrategy.OtherParams({minToken0ForOpening: 10**6, minToken1ForOpening: 10**6, secondsBetweenRebalances: 0})
        );

        vm.stopPrank();
    }

    function setup() public payable {
        vm.deal(address(this), 0 ether);
        initialMint();
        console2.log("In setup");

        uint256 uniV3PoolFee = 500;
        ISwapRouter swapRouter = ISwapRouter(uniswapV3Router);
        INonFungiblePositionManager positionManager = INonFungiblePositionManager(uniswapV3PositionManager);

        IWETH wethContract = IWETH(weth);
        IWSTETH wstethContract = IWSTETH(wsteth);

        wethContract.approve(uniswapV3PositionManager, type(uint256).max);
        wstethContract.approve(uniswapV3PositionManager, type(uint256).max);

        IProtocolGovernance protocolGovernance = IProtocolGovernance(governance);

        {
            uint8[] memory args = new uint8[](1);
            args[0] = PermissionIdsLibrary.ERC20_VAULT_TOKEN;
            vm.prank(admin);
            protocolGovernance.stagePermissionGrants(wsteth, args);
        }

        vm.warp(block.timestamp + protocolGovernance.governanceDelay());
        vm.prank(admin);
        protocolGovernance.commitPermissionGrants(wsteth);

        address[] memory tokens = new address[](2);
        tokens[0] = wsteth;
        tokens[1] = weth;

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        uint256 uniV3LowerVaultNft = vaultRegistry.vaultsCount() + 1;
        uint256 uniV3UpperVaultNft = uniV3LowerVaultNft + 1;
        uint256 erc20VaultNft = uniV3LowerVaultNft + 2;

        vm.startPrank(admin);

        {
            IUniV3VaultGovernance uniV3VaultGovernance = IUniV3VaultGovernance(uniGovernance);
            uniV3VaultGovernance.createVault(tokens, admin, uint24(uniV3PoolFee), helper);
            uniV3VaultGovernance.createVault(tokens, admin, uint24(uniV3PoolFee), helper);
        }

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, admin);
        }

        vm.stopPrank();

        MockCowswap mockCowswap = new MockCowswap();
        IERC20Vault erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));
        IUniV3Vault uniV3LowerVault = IUniV3Vault(vaultRegistry.vaultForNft(uniV3LowerVaultNft));
        IUniV3Vault uniV3UpperVault = IUniV3Vault(vaultRegistry.vaultForNft(uniV3UpperVaultNft));

        lstrategy = new LStrategy(
            positionManager,
            address(mockCowswap),
            erc20Vault,
            uniV3LowerVault,
            uniV3UpperVault,
            ILStrategyHelper(lStrategyHelper),
            admin,
            uint16(Constants.width)
        );
        ERC20Validator wstethValidator = new ERC20Validator(IProtocolGovernance(governance));

        {
            uint256[] memory nfts = new uint256[](3);
            nfts[0] = erc20VaultNft;
            nfts[1] = uniV3LowerVaultNft;
            nfts[2] = uniV3UpperVaultNft;

            combineVaults(tokens, nfts);
        }

        IERC20RootVault erc20RootVaultContract = IERC20RootVault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        vm.startPrank(admin);
        protocolGovernance.stageValidator(wsteth, address(wstethValidator));
        vm.warp(block.timestamp + protocolGovernance.governanceDelay());
        protocolGovernance.commitValidator(wsteth);

        CowswapValidator cowswapValidator = new CowswapValidator(protocolGovernance);

        protocolGovernance.stageValidator(address(mockCowswap), address(cowswapValidator));
        vm.warp(block.timestamp + protocolGovernance.governanceDelay());
        protocolGovernance.commitValidator(address(mockCowswap));

        vm.stopPrank();

        console2.log("Minted lstrategy");
        mint(weth, deployer, 4 * 10**21);
        console2.log("Minted money");

        setupSecondPhase(wethContract, wstethContract);
    }

    function mintMockPosition() public {
        INonFungiblePositionManager positionManager = INonFungiblePositionManager(uniswapV3PositionManager);
        positionManager.mint(INonfungiblePositionManager.MintParams({
            token0: wsteth,
            token1: weth,
            fee: 500,
            tickLower: -10000,
            tickUpper: 10000,
            amount0Desired: 5*10**20,
            amount1Desired: 5*10**20,
            amount0Min: 0,
            amount1Min: 0,
            recipient: deployer,
            deadline: type(uint256).max
        }));
    }

    // rawPrice = realPrice * 10^27
    // returnPrice = sqrt(realPrice) * 2^96
    function stringToSqrtPriceX96(uint256 rawPrice) public returns (uint256 price) {
        uint256 priceX96 = FullMath.mulDiv(rawPrice, Q96, D27);
        uint256 sqrtPriceX48 = CommonLibrary.sqrt(priceX96);
        return sqrtPriceX48 * Q48;
    }

    function getTick(uint256 x) public returns (int24) {
        return TickMath.getTickAtSqrtRatio(uint160(x));
    }

    function fullPriceUpdate(int24 tick) public {
        
    }

    function execute(string memory filename, uint256 width, uint256 weth_amount, uint256 wsteth_amount) public {
        console2.log("Process started");

        mintMockPosition();
        Feed feed = new Feed();
        (uint256[] memory blocks, uint256[] memory prices, uint256[] memory stethAmounts, uint256[] memory wethAmoutns, uint256[] memory stEthPerToken) = feed.parseFile();

        console2.log("Before price update");
        fullPriceUpdate(getTick(stringToSqrtPriceX96(prices[0])));

    }

    function test() public {
        setup();
        execute(Constants.filename, Constants.width, Constants.wethAmount, Constants.wstethAmount);
    }
}
