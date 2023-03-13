// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Script.sol";

import "../ProtocolGovernance.sol";
import "../VaultRegistry.sol";
import "../ERC20RootVaultHelper.sol";
import "../MockOracle.sol";

import "../utils/UniV3Helper.sol";
import "../utils/LStrategyHelper.sol";
import "../utils/GearboxOperator.sol";
import "../vaults/GearboxVault.sol";
import "../vaults/GearboxRootVault.sol";
import "../vaults/ERC20Vault.sol";

import "../vaults/GearboxVaultGovernance.sol";
import "../vaults/ERC20VaultGovernance.sol";
import "../vaults/UniV3VaultGovernance.sol";
import "../vaults/ERC20RootVaultGovernance.sol";
import "../strategies/LStrategy.sol";

import "../interfaces/external/IWETH.sol";
import "../interfaces/external/IWSTETH.sol";


contract MainnetDeployment is Script {

    address public rootVault;
    ERC20Vault erc20Vault;
    GearboxVault gearboxVault;

    ERC20RootVaultGovernance governanceA; 
    ERC20VaultGovernance governanceB;
    GearboxVaultGovernance governanceC;

    uint256 nftStart;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address sAdmin = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;
    address protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;
    address approver = 0x974b9Ec2Bb4f90984B6AFc7b2136072186C1f471;

    address depositor = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public uniswapV3PositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public rootGovernance = 0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA;
    address public uniGovernance = 0x9c319DC47cA6c8c5e130d5aEF5B8a40Cce9e877e;
    address public mellowOracle = 0x9d992650B30C6FB7a83E7e7a430b4e015433b838;

    uint256 width = 280;

    LStrategy lstrategy = LStrategy(0x8F2aE04A0e410599Cc36A7B6dF756B5239366A69);

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {
        IERC20RootVaultGovernance rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);
        for (uint256 i = 0; i < nfts.length; ++i) {
            IVaultRegistry(registry).approve(rootGovernance, nfts[i]);
        }
        (IERC20RootVault w, uint256 nft) = rootVaultGovernance.createVault(tokens, address(lstrategy), nfts, deployer);
        rootVault = address(w);
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
                privateVault: true,
                depositCallbackAddress: address(0),
                withdrawCallbackAddress: address(0)
            })
        );

        rootVaultGovernance.commitDelayedStrategyParams(nft);
    }

    function preparePush(
        IUniV3Vault vault,
        int24 tickLower,
        int24 tickUpper
    ) public {

        (uint256 nft, , , ) = INonfungiblePositionManager(uniswapV3PositionManager).mint(
            INonfungiblePositionManager.MintParams({
                token0: wsteth,
                token1: weth,
                fee: 500,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: 10**10,
                amount1Desired: 10**10,
                amount0Min: 0,
                amount1Min: 0,
                recipient: approver,
                deadline: type(uint256).max
            })
        );

       vm.stopBroadcast();
       vm.startBroadcast(approver);

       INonfungiblePositionManager(uniswapV3PositionManager).safeTransferFrom(approver, address(vault), nft);

       //console2.log("NFT: ", address(vault), nft);

       vm.stopBroadcast();
       vm.startBroadcast(deployer);
    }

    function getPool() public returns (IUniswapV3Pool) {
        IUniV3Vault lowerVault = lstrategy.lowerVault();
        return lowerVault.pool();
    }

    function getUniV3Tick() public returns (int24) {
        IUniswapV3Pool pool = getPool();
        (, int24 tick, , , , , ) = pool.slot0();
        return tick;
    }

    function buildInitialPositions(
        uint256 width,
        uint256 startNft
    ) public {
        int24 tick = getUniV3Tick();

        int24 semiPositionRange = int24(int256(width)) / 2;
        int24 tickLeftLower = (tick / semiPositionRange) * semiPositionRange - semiPositionRange;
        int24 tickLeftUpper = tickLeftLower + 2 * semiPositionRange;

        int24 tickRightLower = tickLeftLower + semiPositionRange;
        int24 tickRightUpper = tickLeftUpper + semiPositionRange;

        IUniV3Vault lowerVault = lstrategy.lowerVault();
        IUniV3Vault upperVault = lstrategy.upperVault();

       // IVaultRegistry(registry).approve(approver, startNft);
       // IVaultRegistry(registry).approve(approver, startNft + 1);

      //  preparePush(lowerVault, tickLeftLower, tickLeftUpper);
        preparePush(upperVault, tickRightLower, tickRightUpper);

        {
            uint256[] memory nfts = new uint256[](3);
            nfts[0] = startNft + 2;
            nfts[1] = startNft;
            nfts[2] = startNft + 1;

            address[] memory tokens = new address[](2);
            tokens[0] = wsteth;
            tokens[1] = weth;

            combineVaults(tokens, nfts);
        }
    }

    function setupSecondPhase(IWETH wethContract, IWSTETH wstethContract) public payable {
        wstethContract.transfer(address(lstrategy), 10**14);
        wethContract.transfer(address(lstrategy), 10**14);

        lstrategy.updateTradingParams(
            LStrategy.TradingParams({
                maxSlippageD: 10**7,
                oracleSafetyMask: 0x20,
                orderDeadline: 86400 * 30,
                oracle: IOracle(mellowOracle),
                maxFee0: 10**9,
                maxFee1: 10**9
            })
        );

        lstrategy.updateRatioParams(
            LStrategy.RatioParams({
                erc20UniV3CapitalRatioD: 5 * 10**7, // 0.05 * DENOMINATOR
                erc20TokenRatioD: 5 * 10**8, // 0.5 * DENOMINATOR
                minErc20UniV3CapitalRatioDeviationD: 10**8,
                minErc20TokenRatioDeviationD: 5 * 10**7,
                minUniV3LiquidityRatioDeviationD: 5 * 10**7
            })
        );

        lstrategy.updateOtherParams(
            LStrategy.OtherParams({minToken0ForOpening: 10**6, minToken1ForOpening: 10**6, secondsBetweenRebalances: 0})
        );
    }

    function kek() public payable returns (uint256 startNft) {

        uint256 uniV3PoolFee = 500;

        IProtocolGovernance protocolGovernance = IProtocolGovernance(governance);

        address[] memory tokens = new address[](2);
        tokens[0] = wsteth;
        tokens[1] = weth;

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        uint256 uniV3LowerVaultNft = vaultRegistry.vaultsCount() + 1;

        INonfungiblePositionManager positionManager = INonfungiblePositionManager(uniswapV3PositionManager);
        UniV3Helper helper = new UniV3Helper(positionManager);

        {
            IUniV3VaultGovernance uniV3VaultGovernance = IUniV3VaultGovernance(uniGovernance);
            uniV3VaultGovernance.createVault(tokens, deployer, uint24(uniV3PoolFee), address(helper));
            uniV3VaultGovernance.createVault(tokens, deployer, uint24(uniV3PoolFee), address(helper));

            uniV3VaultGovernance.stageDelayedStrategyParams(
                uniV3LowerVaultNft,
                IUniV3VaultGovernance.DelayedStrategyParams({
                    safetyIndicesSet: 0x02
                })
            );
            uniV3VaultGovernance.stageDelayedStrategyParams(
                uniV3LowerVaultNft + 1,
                IUniV3VaultGovernance.DelayedStrategyParams({
                    safetyIndicesSet: 0x02
                })
            );

            uniV3VaultGovernance.commitDelayedStrategyParams(
                uniV3LowerVaultNft
            );
            uniV3VaultGovernance.commitDelayedStrategyParams(
                uniV3LowerVaultNft + 1
            );
        }

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, deployer);
        }

        IERC20Vault erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(uniV3LowerVaultNft + 2));
        IUniV3Vault uniV3LowerVault = IUniV3Vault(vaultRegistry.vaultForNft(uniV3LowerVaultNft));
        IUniV3Vault uniV3UpperVault = IUniV3Vault(vaultRegistry.vaultForNft(uniV3LowerVaultNft + 1));
        console2.log("ERC20 Vault: ", address(erc20Vault));
        console2.log("Lower Vault: ", address(uniV3LowerVault));
        console2.log("Upper Vault: ", address(uniV3UpperVault));
        address cowswap = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
        address relayer = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;
        LStrategyHelper lStrategyHelper = new LStrategyHelper(cowswap);

        lstrategy = new LStrategy(
            positionManager,
            cowswap,
            relayer,
            erc20Vault,
            uniV3LowerVault,
            uniV3UpperVault,
            ILStrategyHelper(address(lStrategyHelper)),
            deployer,
            uint16(width)
        );

        IWETH wethContract = IWETH(weth);
        IWSTETH wstethContract = IWSTETH(wsteth);

        setupSecondPhase(wethContract, wstethContract);
        return uniV3LowerVaultNft;
    }

    function run() external {
        vm.startBroadcast(deployer);

        address gearboxOperator = 0x629cd0120614ed5D2D56f36D6b3C36b43dccd7D0;

        bytes32 ADMIN_ROLE = bytes32(0xf23ec0bb4210edd5cba85afd05127efcd2fc6a781bfed49188da1081670b22d8); // keccak256("admin)
        bytes32 ADMIN_DELEGATE_ROLE =
            bytes32(0xc171260023d22a25a00a2789664c9334017843b831138c8ef03cc8897e5873d7); // keccak256("admin_delegate")
        bytes32 OPERATOR_ROLE =
            bytes32(0x46a52cf33029de9f84853745a87af28464c80bf0346df1b32e205fc73319f622); // keccak256("operator")

        /*

       // uint256 startNft = kek();
        uint256 startNft = 212;
        buildInitialPositions(width, startNft);

        address[] memory depositors = new address[](1);
        depositors[0] = depositor;

        address erc20RootVault = IVaultRegistry(registry).vaultForNft(startNft + 3);

        IERC20RootVault(erc20RootVault).addDepositorsToAllowlist(depositors);

        IVaultRegistry(registry).transferFrom(deployer, sAdmin, startNft + 3);

        bytes32 ADMIN_ROLE = bytes32(0xf23ec0bb4210edd5cba85afd05127efcd2fc6a781bfed49188da1081670b22d8); // keccak256("admin)
        bytes32 ADMIN_DELEGATE_ROLE =
            bytes32(0xc171260023d22a25a00a2789664c9334017843b831138c8ef03cc8897e5873d7); // keccak256("admin_delegate")
        bytes32 OPERATOR_ROLE =
            bytes32(0x46a52cf33029de9f84853745a87af28464c80bf0346df1b32e205fc73319f622); // keccak256("operator")

        lstrategy.grantRole(ADMIN_ROLE, sAdmin);
        lstrategy.grantRole(ADMIN_DELEGATE_ROLE, sAdmin);
        lstrategy.grantRole(ADMIN_DELEGATE_ROLE, deployer);
        lstrategy.grantRole(OPERATOR_ROLE, sAdmin);
        lstrategy.revokeRole(OPERATOR_ROLE, deployer);
        lstrategy.revokeRole(ADMIN_DELEGATE_ROLE, deployer);
        lstrategy.revokeRole(ADMIN_ROLE, deployer);
        console2.log("Root Vault: ", address(erc20RootVault));
        console2.log("Strategy: ", address(lstrategy));
        */

        GearboxOperator o = new GearboxOperator(deployer, 0xB17a8d440c4e0A206Fc1dE76F3D0531F70bF6d42);

        console.log("operator:", address(o));

        o.grantRole(ADMIN_ROLE, sAdmin);
        o.grantRole(ADMIN_DELEGATE_ROLE, sAdmin);
        o.grantRole(ADMIN_DELEGATE_ROLE, deployer);
        o.grantRole(OPERATOR_ROLE, sAdmin);
        o.grantRole(OPERATOR_ROLE, gearboxOperator);
        o.revokeRole(OPERATOR_ROLE, deployer);
        o.revokeRole(ADMIN_DELEGATE_ROLE, deployer);
        o.revokeRole(ADMIN_ROLE, deployer);
        return;

        /*

        governance = ProtocolGovernance(0xDc9C17662133fB865E7bA3198B67c53a617B2153);
        registry = VaultRegistry(0xFD23F971696576331fCF96f80a20B4D3b31ca5b2);

        rootVault = new GearboxRootVault();
        gearboxVault = new GearboxVault();

        console2.log("Mock Gearbox Root Vault: ", address(rootVault));
        console2.log("Mock Gearbox Vault: ", address(gearboxVault));
        
        IVaultGovernance.InternalParams memory internalParamsA = IVaultGovernance.InternalParams({
            protocolGovernance: governance,
            registry: registry,
            singleton: rootVault
        }); // INTERNAL PARAMS FOR NEW GEARBOXROOTVAULTGOVERNANCE WHICH IS THE SAME AS ERC20ROOTVAULTGOVERNANCE

        IVaultGovernance.InternalParams memory internalParamsB = IVaultGovernance.InternalParams({
            protocolGovernance: governance,
            registry: registry,
            singleton: gearboxVault
        }); // INTERNAL PARAMS FOR NEW GEARBOXVAULTGOVERNANCE WHICH IS THE SAME AS ERC20ROOTVAULTGOVERNANCE

        IGearboxVaultGovernance.DelayedProtocolParams memory delayedParamsB = IGearboxVaultGovernance.DelayedProtocolParams({
            crv3Pool: 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7,
            crv: 0xD533a949740bb3306d119CC777fa900bA034cd52,
            cvx: cvx,
            maxSlippageD9: 10000000,
            maxSmallPoolsSlippageD9: 40000000,
            maxCurveSlippageD9: 30000000,
            uniswapRouter: 0xE592427A0AEce92De3Edee1F18E0157C05861564
        });

        ERC20RootVaultHelper helper = ERC20RootVaultHelper(0xACEE4A703f27eA1EbCd550511aAE58ad012624CC);

        IERC20RootVaultGovernance.DelayedProtocolParams memory delayedParamsA = IERC20RootVaultGovernance.DelayedProtocolParams({
            managementFeeChargeDelay: 86400,
            oracle: IOracle(0x9d992650B30C6FB7a83E7e7a430b4e015433b838)
        });
        
        governanceA = new ERC20RootVaultGovernance(internalParamsA, delayedParamsA, helper); // => GEARBOX ROOT VAULT GOVERNANCE
        governanceB = ERC20VaultGovernance(0x0bf7B603389795E109a13140eCb07036a1534573);
        governanceC = new GearboxVaultGovernance(internalParamsB, delayedParamsB);

        console2.log("Gearbox Governance: ", address(governanceC));
        console2.log("Gearbox Root Governance: ", address(governanceA));

        vm.stopBroadcast();
        return;
 
    /////////////////////////////////////////////// UP TO SIGN IN 24H
        uint8[] memory args = new uint8[](1);
        args[0] = PermissionIdsLibrary.REGISTER_VAULT;

        governance.stagePermissionGrants(address(governanceA), args);
        governance.commitPermissionGrants(address(governanceA));
    ///////////////////////////////////////////////

    
        IERC20RootVaultGovernance.StrategyParams memory strategyParams = IERC20RootVaultGovernance.StrategyParams({
            tokenLimitPerAddress: type(uint256).max,
            tokenLimit: type(uint256).max
        });

        IERC20RootVaultGovernance.DelayedStrategyParams memory delayedStrategyParams = IERC20RootVaultGovernance.DelayedStrategyParams({
            strategyTreasury: strategyTreasury,
            strategyPerformanceTreasury: protocolTreasury,
            privateVault: true,
            managementFee: 0,
            performanceFee: 0,
            depositCallbackAddress: address(0),
            withdrawCallbackAddress: address(0)
        });

        nftStart = registry.vaultsCount() + 1;


        IGearboxVaultGovernance.DelayedProtocolPerVaultParams memory delayedVaultParams = IGearboxVaultGovernance.DelayedProtocolPerVaultParams({
            primaryToken: usdc,
            univ3Adapter: 0x3883500A0721c09DC824421B00F79ae524569E09, // find
            facade: 0x61fbb350e39cc7bF22C01A469cf03085774184aa,
            withdrawDelay: 86400 * 30,
            initialMarginalValueD9: 5000000000,
            referralCode: 0
        });

        IGearboxVaultGovernance.StrategyParams memory strategyParamsB = IGearboxVaultGovernance.StrategyParams({
            largePoolFeeUsed: 500
        });

        ////////////////////// TO BE SIGNED INSTANTLY
        governanceC.stageDelayedProtocolPerVaultParams(nftStart + 1, delayedVaultParams);
        governanceC.commitDelayedProtocolPerVaultParams(nftStart + 1);
        //////////////////////


        address[] memory tokens = new address[](1);
        tokens[0] = usdc; 

        GearboxHelper helper2 = new GearboxHelper();

        governanceB.createVault(tokens, deployer);
        governanceC.createVault(tokens, deployer, address(helper2));

        uint256[] memory nfts = new uint256[](2);

        nfts[0] = nftStart;
        nfts[1] = nftStart + 1;

        registry.approve(address(governanceA), nftStart);
        registry.approve(address(governanceA), nftStart + 1);

        governanceA.createVault(tokens, operator, nfts, deployer);

        rootVault = GearboxRootVault(registry.vaultForNft(nftStart + 2));
        erc20Vault = ERC20Vault(registry.vaultForNft(nftStart));
        gearboxVault = GearboxVault(registry.vaultForNft(nftStart + 1));

        console2.log("Root Vault: ", address(rootVault));
        console2.log("ERC20 Vault: ", address(erc20Vault));
        console2.log("Gearbox Vault: ", address(gearboxVault));
        
        governanceA.stageDelayedStrategyParams(nftStart + 2, delayedStrategyParams);
        governanceA.commitDelayedStrategyParams(nftStart + 2);
        governanceA.setStrategyParams(nftStart + 2, strategyParams);

        registry.approve(operator, nftStart + 2);
        registry.transferFrom(deployer, sAdmin, nftStart + 2);

        // DO FROM OPERATOR: governanceC.setStrategyParams(nftStart + 1, strategyParamsB);

        vm.stopBroadcast();
        */
    }
}