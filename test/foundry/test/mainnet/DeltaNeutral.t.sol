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
import "../../src/utils/UniV3Helper.sol";

uint256 constant width = 8000;
uint256 constant stop = 3000;

contract DeltaNeutralTest is Test {

    DeltaNeutralStrategy dstrategy;

    address public rootVault;

    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public uniswapV3PositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public rootGovernance = 0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA;
    address public uniGovernance = 0x9c319DC47cA6c8c5e130d5aEF5B8a40Cce9e877e;
    address public mellowOracle = 0x9d992650B30C6FB7a83E7e7a430b4e015433b838;

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {
        IERC20RootVaultGovernance rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);
        for (uint256 i = 0; i < nfts.length; ++i) {
            IVaultRegistry(registry).approve(rootGovernance, nfts[i]);
        }
        (IERC20RootVault w, uint256 nft) = rootVaultGovernance.createVault(tokens, address(dstrategy), nfts, address(this));
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

    function buildInitialPositions(
        uint256 startNft
    ) public {

        {
            uint256[] memory nfts = new uint256[](3);
            nfts[0] = startNft + 2;
            nfts[1] = startNft;
            nfts[2] = startNft + 1;

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
                rebalanceTickDelta: 3000
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

        uint256 uniV3PoolFee = 500;

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

            AaveVault aaveVault = new AaveVault();

            IVaultGovernance.InternalParams memory internalParamsA = IVaultGovernance.InternalParams({
                protocolGovernance: protocolGovernance,
                registry: vaultRegistry,
                singleton: aaveVault
            });

            IAaveVaultGovernance.DelayedProtocolParams memory delayedParamsA = IAaveVaultGovernance.DelayedProtocolParams({
                lendingPool: ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9),
                estimatedAaveAPY: 10**7
            });

            IAaveVaultGovernance aaveVaultGovernance = new AaveVaultGovernance(internalParamsA, delayedParamsA);

            uniV3VaultGovernance.createVault(tokens, address(this), uint24(uniV3PoolFee), address(helper));
            aaveVaultGovernance.createVault(tokens, address(this));
        }

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, address(this));
        }

        IERC20Vault erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(uniV3LowerVaultNft + 2));
        IUniV3Vault uniV3Vault = IUniV3Vault(vaultRegistry.vaultForNft(uniV3LowerVaultNft));
        IAaveVault aaveVault = IAaveVault(vaultRegistry.vaultForNft(uniV3LowerVaultNft + 1));

        dstrategy = new DeltaNeutralStrategy(
            positionManager,
            ISwapRouter(uniswapV3Router)
        );

        dstrategy.initialize(address(erc20Vault), address(uniV3Vault), address(aaveVault), address(this));

        setupSecondPhase(usdc, weth);
        return uniV3LowerVaultNft;
    }

    function setUp() public {
        uint256 startNft = kek();
        buildInitialPositions(startNft);
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

    function test() public {

    }

    
}
