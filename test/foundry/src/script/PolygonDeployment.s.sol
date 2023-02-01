// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Script.sol";

import "../strategies/DeltaNeutralStrategy.sol";
import "../vaults/ERC20RootVaultGovernance.sol";
import "../vaults/ERC20VaultGovernance.sol";
import "../vaults/UniV3VaultGovernance.sol";
import "../vaults/AaveVaultGovernance.sol";
import "../vaults/AaveVault.sol";
import "../vaults/ERC20DNRootVault.sol";
import "../utils/UniV3Helper.sol";
import "../utils/DeltaNeutralStrategyHelper.sol";

import "../interfaces/external/aave/AaveOracle.sol";
import "../MockAggregator.sol";

uint256 constant width = 8200;
uint256 constant stop = 2700;

contract PolygonDeployment is Script {

    DeltaNeutralStrategy dstrategy;

    ERC20DNRootVault rootVault;
    IAaveVault aaveVault;
    IUniV3Vault uniV3Vault;
    IERC20Vault erc20Vault;
    IERC20RootVaultGovernance rootVaultGovernance;

    address usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address protocolTreasury = 0x646f851A97302Eec749105b73a45d461B810977F;
    address strategyTreasury = 0x83FC42839FAd06b737E0FC37CA88E84469Dbd56B;
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;

    address public weth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address public uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public uniswapV3PositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public governance = 0x8Ff3148CE574B8e135130065B188960bA93799c6;
    address public registry = 0xd3D0e85F225348a2006270Daf624D8c46cAe4E1F;
    address public erc20Governance = 0x05164eC2c3074A4E8eA20513Fbe98790FfE930A4;
    address public uniGovernance = 0x1832A9c3a578a0E6D02Cc4C19ecBD33FA88Cb183;
    address public sAdmin = 0x36B16e173C5CDE5ef9f43944450a7227D71B4E31;

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

                AaveVault aaveVault = AaveVault(0xf5aEF1622DaaEa25bfD0672251A8Dbd74639a343);
                ERC20DNRootVault sampleRootVault = ERC20DNRootVault(0xCfA896646719d4170C4F86d762ac9ea6d84600e5);

              //  console2.log("mock aave", address(aaveVault));
              //  console2.log("mock root", address(sampleRootVault));

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

            IAaveVaultGovernance aaveVaultGovernance = AaveVaultGovernance(0xb73b54DF72eaF9d9A4b22F938214A3d92Ad38cBC);
       //     console2.log("aaveGovernance", address(aaveVaultGovernance));
            rootVaultGovernance = ERC20RootVaultGovernance(0x0467DE4D0824d57Cb1aF8680589E59048CA560Bc);
         //   console2.log("rootGovernance", address(rootVaultGovernance));
         /*
            {

                uint8[] memory grants = new uint8[](1);

                vm.stopBroadcast();
                return 1488;

                protocolGovernance.stagePermissionGrants(address(aaveVaultGovernance), grants);
                protocolGovernance.stagePermissionGrants(address(rootVaultGovernance), grants);
                protocolGovernance.commitPermissionGrants(address(aaveVaultGovernance));
                protocolGovernance.commitPermissionGrants(address(rootVaultGovernance));
            }
            */

            uniV3VaultGovernance.createVault(tokens, deployer, 500, address(helper));
            aaveVaultGovernance.createVault(tokens, deployer);

            IUniV3VaultGovernance.DelayedStrategyParams memory delayedStrategyParamsA = IUniV3VaultGovernance.DelayedStrategyParams({
                safetyIndicesSet: 2
            });

            uniV3VaultGovernance.stageDelayedStrategyParams(uniV3LowerVaultNft, delayedStrategyParamsA);
            uniV3VaultGovernance.commitDelayedStrategyParams(uniV3LowerVaultNft);
        }

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, deployer);
        }

        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(uniV3LowerVaultNft + 2));
        uniV3Vault = IUniV3Vault(vaultRegistry.vaultForNft(uniV3LowerVaultNft));
        aaveVault = IAaveVault(vaultRegistry.vaultForNft(uniV3LowerVaultNft + 1));

        console2.log("erc20Vault", address(erc20Vault));
        console2.log("uniV3Vault", address(uniV3Vault));
        console2.log("aaveVault", address(aaveVault));

        DeltaNeutralStrategyHelper dHelper = new DeltaNeutralStrategyHelper();

        dstrategy = new DeltaNeutralStrategy(
            positionManager,
            ISwapRouter(uniswapV3Router),
            dHelper
        );

        dstrategy = dstrategy.createStrategy(address(erc20Vault), address(uniV3Vault), address(aaveVault), deployer);

        console2.log("strategy", address(dstrategy));

        setupSecondPhase(usdc, weth);
        return uniV3LowerVaultNft;
    }

    function run() public {

        vm.startBroadcast();

        uint256 startNft = kek();
        return;
        buildInitialPositions(startNft);

        uint8[] memory grants = new uint8[](2);
        grants[0] = 4;
        grants[1] = 5;

        IProtocolGovernance protocolGovernance = IProtocolGovernance(governance);

        protocolGovernance.stagePermissionGrants(address(aaveVault), grants);
        protocolGovernance.commitPermissionGrants(address(aaveVault));

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
        return;
    }

    
}
