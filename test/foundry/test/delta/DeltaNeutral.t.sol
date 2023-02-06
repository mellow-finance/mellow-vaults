// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";


import "../../src/strategies/DeltaNeutralStrategy.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";
import "../../src/vaults/UniV3VaultGovernance.sol";
import "../../src/vaults/AaveVaultGovernance.sol";
import "../../src/vaults/AaveVault.sol";
import "../../src/vaults/ERC20DNRootVault.sol";
import "../../src/utils/UniV3Helper.sol";
import "../../src/utils/DeltaNeutralStrategyHelper.sol";

import "../../src/interfaces/external/aave/AaveOracle.sol";
import "../../src/MockAggregator.sol";

uint256 constant width = 8000;
uint256 constant stop = 3000;

contract DeltaNeutralTest is Test {

    DeltaNeutralStrategy dstrategy;

    ERC20DNRootVault rootVault;
    IAaveVault aaveVault;
    IUniV3Vault uniV3Vault;
    IERC20Vault erc20Vault;
    IERC20RootVaultGovernance rootVaultGovernance;

    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;

    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public uniswapV3PositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public uniGovernance = 0x9c319DC47cA6c8c5e130d5aEF5B8a40Cce9e877e;
    address public mellowOracle = 0x9d992650B30C6FB7a83E7e7a430b4e015433b838;

    address oracleAdmin = 0xEE56e2B3D491590B5b31738cC34d5232F378a8D5;

    function switchPrank(address newAddress) public {
        vm.stopPrank();
        vm.startPrank(newAddress);
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

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory
    ) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {
        for (uint256 i = 0; i < nfts.length; ++i) {
            IVaultRegistry(registry).approve(address(rootVaultGovernance), nfts[i]);
        }
        (IERC20RootVault w, uint256 nft) = rootVaultGovernance.createVault(tokens, address(dstrategy), nfts, deployer);
        rootVault = ERC20DNRootVault(address(w));
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
                depositCallbackAddress: address(dstrategy),
                withdrawCallbackAddress: address(dstrategy)
            })
        );

        rootVaultGovernance.commitDelayedStrategyParams(nft);
    }

    function buildInitialPositions(
        uint256 startNft
    ) public {

        {
            uint256[] memory nfts = new uint256[](3);
            nfts[0] = startNft + 2;
            nfts[1] = startNft;
            nfts[2] = startNft + 1;

            IVaultRegistry vaultRegistry = IVaultRegistry(registry);

            address[] memory tokens = new address[](2);
            tokens[0] = usdc;
            tokens[1] = weth;

            combineVaults(tokens, nfts);
        }
    }

    function setupSecondPhase(address token0, address token1) public payable {
        deal(token0, address(dstrategy), 3 * 10**6);
        deal(token1, address(dstrategy), 3 * 10**17);

        dstrategy.updateStrategyParams(
            DeltaNeutralStrategy.StrategyParams({
                positionTickSize: 8000,
                rebalanceTickDelta: 3000,
                shiftFromLTVD: 10**9
            })
        );

        dstrategy.updateMintingParams(
            DeltaNeutralStrategy.MintingParams({
                minToken0ForOpening: 10**9,
                minToken1ForOpening: 10**9
            })
        );

        dstrategy.updateOracleParams(
            DeltaNeutralStrategy.OracleParams({
                averagePriceTimeSpan: 1800,
                maxTickDeviation: 150
            })
        );

        dstrategy.updateTradingParams(
            DeltaNeutralStrategy.TradingParams({
                swapFee: 500,
                maxSlippageD: 3 * 10**7
            })
        );
    }

    function kek() public payable returns (uint256 startNft) {

        IProtocolGovernance protocolGovernance = IProtocolGovernance(governance);

        address[] memory tokens = new address[](2);
        tokens[0] = usdc;
        tokens[1] = weth;

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        uint256 uniV3LowerVaultNft = vaultRegistry.vaultsCount() + 1;

        INonfungiblePositionManager positionManager = INonfungiblePositionManager(uniswapV3PositionManager);
        UniV3Helper helper = new UniV3Helper(positionManager);

        {
            IUniV3VaultGovernance uniV3VaultGovernance = IUniV3VaultGovernance(uniGovernance);

            IVaultGovernance.InternalParams memory internalParamsA;
            IVaultGovernance.InternalParams memory internalParamsB;

            {

                AaveVault aaveVault = new AaveVault();
                ERC20DNRootVault sampleRootVault = new ERC20DNRootVault();

                internalParamsA = IVaultGovernance.InternalParams({
                    protocolGovernance: protocolGovernance,
                    registry: vaultRegistry,
                    singleton: aaveVault
                });

                internalParamsB = IVaultGovernance.InternalParams({
                    protocolGovernance: protocolGovernance,
                    registry: vaultRegistry,
                    singleton: sampleRootVault
                });

            }

            IAaveVaultGovernance.DelayedProtocolParams memory delayedParamsA = IAaveVaultGovernance.DelayedProtocolParams({
                lendingPool: ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9),
                estimatedAaveAPY: 10**7
            });

            IERC20RootVaultGovernance.DelayedProtocolParams memory delayedParamsB = IERC20RootVaultGovernance.DelayedProtocolParams({
                managementFeeChargeDelay: 0,
                oracle: IOracle(0x9d992650B30C6FB7a83E7e7a430b4e015433b838)
            });

            IAaveVaultGovernance aaveVaultGovernance = new AaveVaultGovernance(internalParamsA, delayedParamsA);
            rootVaultGovernance = new ERC20RootVaultGovernance(internalParamsB, delayedParamsB, IERC20RootVaultHelper(0xACEE4A703f27eA1EbCd550511aAE58ad012624CC));

            {

                switchPrank(admin);

                uint8[] memory grants = new uint8[](1);

                protocolGovernance.stagePermissionGrants(address(aaveVaultGovernance), grants);
                protocolGovernance.stagePermissionGrants(address(rootVaultGovernance), grants);
                vm.warp(block.timestamp + 86400);
                protocolGovernance.commitPermissionGrants(address(aaveVaultGovernance));
                protocolGovernance.commitPermissionGrants(address(rootVaultGovernance));

                switchPrank(deployer);

            }

            uniV3VaultGovernance.createVault(tokens, deployer, 500, address(helper));
            aaveVaultGovernance.createVault(tokens, deployer);

            IUniV3VaultGovernance.DelayedStrategyParams memory delayedStrategyParamsA = IUniV3VaultGovernance.DelayedStrategyParams({
                safetyIndicesSet: 2
            });

            IAaveVaultGovernance.DelayedStrategyParams memory delayedStrategyParamsZ = IAaveVaultGovernance.DelayedStrategyParams({
                rateMode: 1
            });

            uniV3VaultGovernance.stageDelayedStrategyParams(uniV3LowerVaultNft, delayedStrategyParamsA);
            uniV3VaultGovernance.commitDelayedStrategyParams(uniV3LowerVaultNft);

            aaveVaultGovernance.stageDelayedStrategyParams(uniV3LowerVaultNft + 1, delayedStrategyParamsZ);
            aaveVaultGovernance.commitDelayedStrategyParams(uniV3LowerVaultNft + 1);
        }

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, deployer);
        }

        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(uniV3LowerVaultNft + 2));
        uniV3Vault = IUniV3Vault(vaultRegistry.vaultForNft(uniV3LowerVaultNft));
        aaveVault = IAaveVault(vaultRegistry.vaultForNft(uniV3LowerVaultNft + 1));

        DeltaNeutralStrategyHelper dHelper = new DeltaNeutralStrategyHelper();

        dstrategy = new DeltaNeutralStrategy(
            positionManager,
            ISwapRouter(uniswapV3Router),
            dHelper
        );

        dstrategy = dstrategy.createStrategy(address(erc20Vault), address(uniV3Vault), address(aaveVault), deployer);

        setupSecondPhase(usdc, weth);
        return uniV3LowerVaultNft;
    }

    function firstDeposit() public {

        deal(usdc, deployer, 10**4);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10**4;
        IERC20(usdc).approve(address(rootVault), type(uint256).max);

        rootVault.deposit(amounts, 0, "");
    }

    function deposit(uint256 amount) public {
        if (rootVault.totalSupply() == 0) {
            firstDeposit();
            dstrategy.rebalance();
        }

        deal(usdc, deployer, amount * 10**6);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount * 10**6;

        IERC20(usdc).approve(address(rootVault), type(uint256).max);
        rootVault.deposit(amounts, 0, "");
    }

    function setUp() public {
        vm.startPrank(deployer);
        uint256 startNft = kek();
        buildInitialPositions(startNft);

        switchPrank(admin);

        uint8[] memory grants = new uint8[](2);
        grants[0] = 4;
        grants[1] = 5;

        IProtocolGovernance protocolGovernance = IProtocolGovernance(governance);

        protocolGovernance.stagePermissionGrants(address(aaveVault), grants);
        vm.warp(block.timestamp + 86400);
        protocolGovernance.commitPermissionGrants(address(aaveVault));

        switchPrank(deployer);
/*
        bytes32 ADMIN_ROLE =
        bytes32(0xf23ec0bb4210edd5cba85afd05127efcd2fc6a781bfed49188da1081670b22d8); // keccak256("admin)
        bytes32 ADMIN_DELEGATE_ROLE =
            bytes32(0xc171260023d22a25a00a2789664c9334017843b831138c8ef03cc8897e5873d7); // keccak256("admin_delegate")
        bytes32 OPERATOR_ROLE =
            bytes32(0x46a52cf33029de9f84853745a87af28464c80bf0346df1b32e205fc73319f622); // keccak256("operator")

        dstrategy.grantRole(ADMIN_ROLE, sAdmin);
        dstrategy.grantRole(ADMIN_DELEGATE_ROLE, sAdmin);
        dstrategy.grantRole(ADMIN_DELEGATE_ROLE, address(this));
        dstrategy.grantRole(OPERATOR_ROLE, sAdmin);
        dstrategy.revokeRole(OPERATOR_ROLE, address(this));
        dstrategy.revokeRole(ADMIN_DELEGATE_ROLE, address(this));
        dstrategy.revokeRole(ADMIN_ROLE, address(this));
*/
        return;
    }

    function testSimpleSmallDepositAndRebalance() public {
        firstDeposit();
        dstrategy.rebalance();

        (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = INonfungiblePositionManager(uniswapV3PositionManager).positions(
                uniV3Vault.uniV3Nft()
            );

        (, int24 tick, , , , , ) = uniV3Vault.pool().slot0();

        require(liquidity > 0);
        require(tickUpper - tickLower == int24(uint24(width)));
        require(tickLower <= tick);
        require(tick <= tickUpper);

        (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();

        require(erc20Tvl[0] <= 100); // 1%
        require(erc20Tvl[1] <= 10**8);

        (uint256[] memory aaveTvl, ) = aaveVault.tvl();
        require(aaveTvl[0] >= 5000);
        require(aaveTvl[1] >= 2*10**11 && aaveTvl[0] <= 5*10**11);

        uint256[] memory totalTvl = rootVault.calcTvl();
        require(totalTvl[1] == 0);
        require(totalTvl[0] >= 9999 && totalTvl[0] <= 10001);

        vm.warp(block.timestamp + 86400 * 365); // aave debt - fees decreases tvl

        uint256[] memory finalTotalTvl = rootVault.calcTvl();
        require(finalTotalTvl[1] == 0);
        require(finalTotalTvl[0] < 9900);
    }

    function testDepositCallbackWorks() public {
        deposit(1000);

        (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();

        require(erc20Tvl[0] <= 10**6); // 0.1%
        require(erc20Tvl[1] <= 10**14);

        uint256[] memory totalTvl = rootVault.calcTvl();
        require(totalTvl[1] == 0);
        require(isClose(totalTvl[0], 1000*10**6, 1000));
    }

    function testSimpleWithdrawWorks() public {
        deposit(1000);
        uint256 lpTokens = rootVault.balanceOf(deployer);

        uint256[] memory minTokenAmounts = new uint256[](2);
        bytes[] memory vaultsOptions = new bytes[](3);

        uint256 oldBalance = IERC20(usdc).balanceOf(deployer);

        rootVault.withdraw(deployer, lpTokens/2, minTokenAmounts, vaultsOptions);

        uint256 newBalance = IERC20(usdc).balanceOf(deployer);
        require(isClose(newBalance - oldBalance, 500*10**6, 1000));

        (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();

        require(erc20Tvl[0] <= 10**6); // 0.1%
        require(erc20Tvl[1] <= 10**14);

        uint256[] memory totalTvl = rootVault.calcTvl();
        require(totalTvl[1] == 0);
        require(isClose(totalTvl[0], 500*10**6, 1000));

        rootVault.withdraw(deployer, lpTokens/4, minTokenAmounts, vaultsOptions);
        uint256 finalBalance = IERC20(usdc).balanceOf(deployer);

        require(isClose(finalBalance, 750*10**6, 1000));
    }

    function testDepositWorksProportionally() public {
        deposit(1000);
        uint256 lpTokensBefore = rootVault.balanceOf(deployer);

        uint256[] memory totalTvl = rootVault.calcTvl();
        require(totalTvl[1] == 0);
        require(isClose(totalTvl[0], 1000*10**6, 1000));

        deposit(3000);
        uint256 lpTokensAfter = rootVault.balanceOf(deployer);

        uint256[] memory totalTvlNew = rootVault.calcTvl();
        require(totalTvl[1] == 0);
        require(isClose(totalTvlNew[0], 4000*10**6, 1000));

        require(isClose(lpTokensBefore * 4, lpTokensAfter, 1000));
    }

    function changePrice(uint256 newPrice) public {
        IUniswapV3Pool pool = uniV3Vault.pool();

        int24 needTick = TickMath.getTickAtSqrtRatio(uint160(CommonLibrary.sqrtX96(FullMath.mulDiv(1<<96, 10**12, newPrice))));

        uint256 startEth = 5 * 10**22;
        uint256 startUsd = 10**14;

        uint256 pos = 0;

        uint256 t = 0;

        while (true) {
            t += 1;
            (, int24 tick, , , , , ) = uniV3Vault.pool().slot0();

            if (tick < needTick && needTick - tick < 100) {
                break;
            }

            if (tick > needTick && tick - needTick < 100) {
                break;
            }

            if (tick > needTick) {
                if (pos != 0) {
                    pos = 1 - pos;
                    startEth /= 2;
                    startUsd /= 2;
                }
                bytes memory b = "";
                deal(usdc, deployer, startUsd);

                IERC20(usdc).approve(uniswapV3Router, startUsd);

                ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
                    tokenIn: usdc,
                    tokenOut: weth,
                    fee: 500,
                    recipient: deployer,
                    deadline: block.timestamp + 1,
                    amountIn: startUsd,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                });

                ISwapRouter(uniswapV3Router).exactInputSingle(swapParams);
            }

            else {
                if (pos != 1) {
                    pos = 1 - pos;
                    startEth /= 2;
                    startUsd /= 2;
                }
                bytes memory b = "";
                deal(weth, deployer, startEth);

                IERC20(weth).approve(uniswapV3Router, startEth);

                ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
                    tokenIn: weth,
                    tokenOut: usdc,
                    fee: 500,
                    recipient: deployer,
                    deadline: block.timestamp + 1,
                    amountIn: startEth,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                });

                ISwapRouter(uniswapV3Router).exactInputSingle(swapParams);
            }
        }

        AaveOracle aaveOracle = AaveOracle(0xA50ba011c48153De246E5192C8f9258A2ba79Ca9);
        switchPrank(oracleAdmin);

        address[] memory addresses = new address[](1);
        addresses[0] = usdc;

        address[] memory oracles = new address[](1);
        MockAggregator ma = new MockAggregator();

        ma.updatePrice(10**18 / newPrice);
        oracles[0] = address(ma);

        aaveOracle.setAssetSources(addresses, oracles);

        switchPrank(deployer);
    }

    function testDepositWorksWhenPriceChanges() public {

        dstrategy.updateOracleParams(
            DeltaNeutralStrategy.OracleParams({
                averagePriceTimeSpan: 1800,
                maxTickDeviation: 15000
            })
        );

        deposit(1000);
        changePrice(1600);
        deposit(1000);

        (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();

        require(erc20Tvl[0] <= 10**6); // 0.1%
        require(erc20Tvl[1] <= 10**14);

        uint256[] memory totalTvl = rootVault.calcTvl();
        require(totalTvl[1] == 0);
        require(totalTvl[0] >= 1900*10**6 && totalTvl[0] <= 1980*10**6);
    }

    function testFailDepositWithoutRebalanceAfterPriceChange() public {
        dstrategy.updateOracleParams(
            DeltaNeutralStrategy.OracleParams({
                averagePriceTimeSpan: 1800,
                maxTickDeviation: 15000
            })
        );

        deposit(1000);
        changePrice(1800);
        deposit(1000);
    }

    function testRebalanceWorksProperlyAfterPriceRise() public {
        dstrategy.updateOracleParams(
            DeltaNeutralStrategy.OracleParams({
                averagePriceTimeSpan: 1800,
                maxTickDeviation: 15000
            })
        );

        deposit(1000);
        changePrice(1800);
        dstrategy.rebalance();

        (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();

        require(erc20Tvl[0] <= 10**6); // 0.1%
        require(erc20Tvl[1] <= 10**14);

        uint256[] memory totalTvl = rootVault.calcTvl();
        require(totalTvl[1] == 0);
        require(totalTvl[0] >= 900*10**6 && totalTvl[0] <= 960*10**6);
    }

    function testRebalanceWorksProperlyAfterPricePlummets() public {
        dstrategy.updateOracleParams(
            DeltaNeutralStrategy.OracleParams({
                averagePriceTimeSpan: 1800,
                maxTickDeviation: 15000
            })
        );

        deposit(1000);
        changePrice(900);
        dstrategy.rebalance();

        (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();

        require(erc20Tvl[0] <= 10**6); // 0.1%
        require(erc20Tvl[1] <= 10**14);

        uint256[] memory totalTvl = rootVault.calcTvl();
        require(totalTvl[1] == 0);
        require(totalTvl[0] >= 900*10**6 && totalTvl[0] <= 960*10**6);
    }

    function testWithdrawWorks() public {

        dstrategy.updateOracleParams(
            DeltaNeutralStrategy.OracleParams({
                averagePriceTimeSpan: 1800,
                maxTickDeviation: 15000
            })
        );

        deposit(1000);
        changePrice(1600);
        uint256 lpTokens = rootVault.balanceOf(deployer);

        uint256[] memory minTokenAmounts = new uint256[](2);
        bytes[] memory vaultsOptions = new bytes[](3);

        uint256 oldBalance = IERC20(usdc).balanceOf(deployer);

        rootVault.withdraw(deployer, lpTokens/2, minTokenAmounts, vaultsOptions);

        uint256 newBalance = IERC20(usdc).balanceOf(deployer);
        require(isClose(newBalance - oldBalance, 480*10**6, 10));

        (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();

        require(erc20Tvl[0] <= 10**6); // 0.1%
        require(erc20Tvl[1] <= 10**14);

        uint256[] memory totalTvl = rootVault.calcTvl();
        require(totalTvl[1] == 0);
        require(isClose(totalTvl[0], 480*10**6, 10));

        rootVault.withdraw(deployer, lpTokens/4, minTokenAmounts, vaultsOptions);
        uint256 finalBalance = IERC20(usdc).balanceOf(deployer);

        require(isClose(finalBalance, 720*10**6, 10));
    }

    function testALotOfActionsWork() public {

        deposit(1000);

        dstrategy.updateOracleParams(
            DeltaNeutralStrategy.OracleParams({
                averagePriceTimeSpan: 1800,
                maxTickDeviation: 15000
            })
        );

        changePrice(1600);
        deposit(200);

        changePrice(1400);
        deposit(100);

        changePrice(1200);

        deposit(50);

        uint256 lpTokens = rootVault.balanceOf(deployer);

        uint256[] memory minTokenAmounts = new uint256[](2);
        bytes[] memory vaultsOptions = new bytes[](3);

        uint256 oldBalance = IERC20(usdc).balanceOf(deployer);

        rootVault.withdraw(deployer, lpTokens/10, minTokenAmounts, vaultsOptions);

        changePrice(1800);
        dstrategy.rebalance();

        (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();

        require(erc20Tvl[0] <= 10**6); // 0.1%
        require(erc20Tvl[1] <= 10**14);

        uint256[] memory totalTvl = rootVault.calcTvl();
        require(totalTvl[1] == 0);
        require(isClose(totalTvl[0], 1150*10**6, 10));



    }

    
}
