// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Script.sol";

import "../../src/ProtocolGovernance.sol";
import "../../src/VaultRegistry.sol";
import "../../src/ERC20RootVaultHelper.sol";
import "../../src/MockOracle.sol";

import "../../src/utils/UniV3Helper.sol";
import "../../src/utils/LStrategyHelper.sol";
import "../../src/vaults/ERC20Vault.sol";
import "../../src/vaults/ERC20RootVault.sol";

import "../../src/vaults/GearboxVaultGovernance.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";
import "../../src/vaults/UniV3VaultGovernance.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";
import "../../src/strategies/LStrategy.sol";

contract LStrategyDeployment is Script {

    IERC20RootVault public rootVault;
    IERC20Vault erc20Vault;
    IUniV3Vault uniV3LowerVault;
    IUniV3Vault uniV3UpperVault;


    uint256 nftStart;
    address sAdmin = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;
    address protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

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

    LStrategy lstrategy;

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {

        ERC20RootVault singleton = new ERC20RootVault();

        IProtocolGovernance protocolGovernance = IProtocolGovernance(governance);
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        IERC20RootVaultGovernance.DelayedProtocolParams memory paramsB = IERC20RootVaultGovernance.DelayedProtocolParams({
            managementFeeChargeDelay: 0,
            oracle: IOracle(mellowOracle)
        });

        IVaultGovernance.InternalParams memory paramsA = IVaultGovernance.InternalParams({
            protocolGovernance: protocolGovernance,
            registry: vaultRegistry,
            singleton: singleton
        });

        IERC20RootVaultHelper helper = new ERC20RootVaultHelper();

        IERC20RootVaultGovernance rootVaultGovernance = new ERC20RootVaultGovernance(paramsA, paramsB, helper);
        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(address(rootVaultGovernance), nfts[i]);
        }

        return;

        uint8[] memory grant = new uint8[](1);
        protocolGovernance.stagePermissionGrants(address(rootVaultGovernance), grant);
        protocolGovernance.commitPermissionGrants(address(rootVaultGovernance));

        return;

        (IERC20RootVault w, uint256 nft) = rootVaultGovernance.createVault(tokens, address(lstrategy), nfts, deployer);
        rootVault = w;
        rootVaultGovernance.setStrategyParams(
            nft,
            IERC20RootVaultGovernance.StrategyParams({
                tokenLimitPerAddress: type(uint256).max,
                tokenLimit: type(uint256).max,
                maxTimeOneRebalance: 0,
                minTimeBetweenRebalances: 3600
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
                depositCallbackAddress: address(lstrategy),
                withdrawCallbackAddress: address(lstrategy)
            })
        );

        rootVaultGovernance.commitDelayedStrategyParams(nft);
        vaultRegistry.transferFrom(deployer, sAdmin, nftStart);

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
                amount0Desired: 10**9,
                amount1Desired: 10**9,
                amount0Min: 0,
                amount1Min: 0,
                recipient: operator,
                deadline: type(uint256).max
            })
        );

        IVaultRegistry(registry).approve(operator, vault.nft());

        vm.stopPrank();
        vm.startPrank(operator);

        INonfungiblePositionManager(uniswapV3PositionManager).safeTransferFrom(operator, address(vault), nft);

        vm.stopPrank();
        vm.startPrank(deployer);
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

        preparePush(lowerVault, tickLeftLower, tickLeftUpper);
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

    function setupSecondPhase() public payable {

        IERC20(weth).transfer(address(lstrategy), 10**12);
        IERC20(wsteth).transfer(address(lstrategy), 10**12);

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
                minErc20UniV3CapitalRatioDeviationD: 2 * 10**7,
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
        }

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, deployer);
        }

        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(uniV3LowerVaultNft + 2));
        uniV3LowerVault = IUniV3Vault(vaultRegistry.vaultForNft(uniV3LowerVaultNft));
        uniV3UpperVault = IUniV3Vault(vaultRegistry.vaultForNft(uniV3LowerVaultNft + 1));

        IUniV3VaultGovernance.DelayedStrategyParams memory params = IUniV3VaultGovernance.DelayedStrategyParams({
            safetyIndicesSet: 2
        });

        IUniV3VaultGovernance(uniGovernance).stageDelayedStrategyParams(uniV3LowerVault.nft(), params);
        IUniV3VaultGovernance(uniGovernance).stageDelayedStrategyParams(uniV3UpperVault.nft(), params);

        IUniV3VaultGovernance(uniGovernance).commitDelayedStrategyParams(uniV3LowerVault.nft());
        IUniV3VaultGovernance(uniGovernance).commitDelayedStrategyParams(uniV3UpperVault.nft());

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

        setupSecondPhase();
        return uniV3LowerVaultNft;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory
    ) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function run() external {
        vm.startBroadcast();

        ERC20RootVault singleton = new ERC20RootVault();

        IProtocolGovernance protocolGovernance = IProtocolGovernance(governance);
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        IERC20RootVaultGovernance.DelayedProtocolParams memory paramsB = IERC20RootVaultGovernance.DelayedProtocolParams({
            managementFeeChargeDelay: 0,
            oracle: IOracle(mellowOracle)
        });

        IVaultGovernance.InternalParams memory paramsA = IVaultGovernance.InternalParams({
            protocolGovernance: protocolGovernance,
            registry: vaultRegistry,
            singleton: singleton
        });

        IERC20RootVaultHelper helper = new ERC20RootVaultHelper();

        IERC20RootVaultGovernance rootVaultGovernance = new ERC20RootVaultGovernance(paramsA, paramsB, helper);
        console2.log(address(rootVaultGovernance));
        return;

        uint256 startNft = kek();
        buildInitialPositions(width, startNft);
        bytes32 ADMIN_ROLE =
        bytes32(0xf23ec0bb4210edd5cba85afd05127efcd2fc6a781bfed49188da1081670b22d8); // keccak256("admin)
        bytes32 ADMIN_DELEGATE_ROLE =
            bytes32(0xc171260023d22a25a00a2789664c9334017843b831138c8ef03cc8897e5873d7); // keccak256("admin_delegate")
        bytes32 OPERATOR_ROLE =
            bytes32(0x46a52cf33029de9f84853745a87af28464c80bf0346df1b32e205fc73319f622); // keccak256("operator")

        lstrategy.grantRole(ADMIN_ROLE, sAdmin);
        lstrategy.grantRole(ADMIN_DELEGATE_ROLE, sAdmin);
        lstrategy.grantRole(ADMIN_DELEGATE_ROLE, address(this));
        lstrategy.grantRole(OPERATOR_ROLE, sAdmin);
        lstrategy.revokeRole(OPERATOR_ROLE, address(this));
        lstrategy.revokeRole(ADMIN_DELEGATE_ROLE, address(this));
        lstrategy.revokeRole(ADMIN_ROLE, address(this));
    }

}