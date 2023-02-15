// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {UniV3Helper} from "./UniV3Helper.sol";
import {QuickSwapHelper} from "./QuickSwapHelper.sol";

import {SinglePositionQuickSwapStrategy} from "../strategies/SinglePositionQuickSwapStrategy.sol";
import {SinglePositionStrategy} from "../strategies/SinglePositionStrategy.sol";
import {HStrategy} from "../strategies/HStrategy.sol";

import {IChainlinkOracle} from "../interfaces/oracles/IChainlinkOracle.sol";

import {IERC20RootVault} from "../interfaces/vaults/IERC20RootVault.sol";
import {IUniV3Vault} from "../interfaces/vaults/IUniV3Vault.sol";
import {IQuickSwapVault} from "../interfaces/vaults/IQuickSwapVault.sol";
import {IQuickSwapVaultGovernance} from "../interfaces/vaults/IQuickSwapVaultGovernance.sol";

import {IAlgebraPool} from "../interfaces/external/quickswap/IAlgebraPool.sol";

contract ExporterDataCollector {
    error UnsupportedTokenAmounts();

    UniV3Helper public immutable uniV3Helper;
    QuickSwapHelper public immutable quickSwapHelper;
    IChainlinkOracle public immutable chainlinkOracle;
    address public immutable usdc;

    constructor(
        UniV3Helper uniV3Helper_,
        QuickSwapHelper quickSwapHelper_,
        IChainlinkOracle chainlinkOracle_,
        address usdc_
    ) {
        uniV3Helper = uniV3Helper_;
        quickSwapHelper = quickSwapHelper_;
        chainlinkOracle = chainlinkOracle_;
        usdc = usdc_;
    }

    // calculate fees + rewards
    function calculateQuickSwapFees(SinglePositionQuickSwapStrategy strategy)
        public
        view
        returns (uint256[] memory fees)
    {
        (, , IQuickSwapVault vault) = strategy.immutableParams();
        IQuickSwapVaultGovernance.DelayedStrategyParams memory strategyParams = vault.delayedStrategyParams();
        fees = quickSwapHelper.calculateTvl(
            vault.positionNft(),
            strategyParams,
            vault.farmingCenter(),
            vault.vaultTokens()[0]
        );
        (, , , , , , uint128 liquidity, , , , ) = vault.positionManager().positions(vault.positionNft());
        (uint160 sqrtRatioX96, , , , , , ) = strategyParams.key.pool.globalState();
        (uint256 amount0, uint256 amount1) = quickSwapHelper.liquidityToTokenAmounts(
            vault.positionNft(),
            sqrtRatioX96,
            liquidity
        );
        fees[0] -= amount0;
        fees[1] -= amount1;
    }

    function calculateUniFees(IUniV3Vault vault) public view returns (uint256[] memory fees) {
        uint256 uniV3Nft = vault.uniV3Nft();
        fees = new uint256[](2);
        if (uniV3Nft == 0) return fees;
        (fees[0], fees[1]) = uniV3Helper.getFeesByNft(uniV3Nft);
    }

    function calculateUniTvl(uint256 uniV3Nft) public view returns (uint256[] memory tokenAmounts) {
        if (uniV3Nft == 0) return new uint256[](2);
        (uint160 sqrtPriceX96, , , , , , ) = uniV3Helper.getPoolByNft(uniV3Nft).slot0();
        tokenAmounts = uniV3Helper.calculateTvlBySqrtPriceX96(uniV3Nft, sqrtPriceX96);
    }

    struct RootVaultData {
        uint256[] minTvl;
        uint256[] maxTvl;
        uint256 totalSupply;
        uint256 price0To1;
        uint256 price0ToUsdc;
        uint256 price1ToUsdc;
    }

    function collectRootVaultData(IERC20RootVault rootVault) public view returns (RootVaultData memory data) {
        (data.minTvl, data.maxTvl) = rootVault.tvl();
        data.totalSupply = rootVault.totalSupply();
        address[] memory tokens = rootVault.vaultTokens();
        (uint256[] memory pricesX96, ) = chainlinkOracle.priceX96(tokens[0], usdc, 1 << 5);
        data.price0ToUsdc = pricesX96[0];
        if (tokens.length == 2) {
            (pricesX96, ) = chainlinkOracle.priceX96(tokens[0], tokens[1], 1 << 5);
            data.price0To1 = pricesX96[0];
            (pricesX96, ) = chainlinkOracle.priceX96(tokens[1], usdc, 1 << 5);
            data.price1ToUsdc = pricesX96[0];
        } else if (tokens.length != 1) {
            revert UnsupportedTokenAmounts();
        }
    }

    struct HStrategyData {
        uint256[] uniV3VaultMinTvl;
        uint256[] uniV3VaultMaxTvl;
        uint256[] uniV3VaultSpotTvl;
        uint256[] uniV3TaretPositionTvl;
        RootVaultData rootVaultData;
    }

    function collectHStrategyData(
        HStrategy strategy,
        uint256 targetNft,
        IERC20RootVault rootVault
    ) public view returns (HStrategyData memory data) {
        IUniV3Vault uniV3Vault = strategy.uniV3Vault();
        (data.uniV3VaultMinTvl, data.uniV3VaultMaxTvl) = uniV3Vault.tvl();
        data.uniV3VaultSpotTvl = calculateUniTvl(uniV3Vault.uniV3Nft());
        data.uniV3TaretPositionTvl = calculateUniTvl(targetNft);
        data.rootVaultData = collectRootVaultData(rootVault);
    }

    struct PulseStrategyData {
        uint256[] fees;
        RootVaultData rootVaultData;
    }

    function collectUniPulseData(SinglePositionStrategy strategy, IERC20RootVault rootVault)
        public
        view
        returns (PulseStrategyData memory data)
    {
        (, , IUniV3Vault uniV3Vault) = strategy.immutableParams();
        data.fees = calculateUniFees(uniV3Vault);
        data.rootVaultData = collectRootVaultData(rootVault);
    }

    function collectQuickPulseData(SinglePositionQuickSwapStrategy strategy, IERC20RootVault rootVault)
        public
        view
        returns (PulseStrategyData memory data)
    {
        data.fees = calculateQuickSwapFees(strategy);
        data.rootVaultData = collectRootVaultData(rootVault);
    }

    struct Request {
        IERC20RootVault[] ordinaryRootVaults;
        IERC20RootVault[] hRootVaults;
        uint256[] targetNfts;
        HStrategy[] hStrategies;
        IERC20RootVault[] uniPulseRootVaults;
        SinglePositionStrategy[] uniPulseStrategies;
        IERC20RootVault[] quickPulseRootVaults;
        SinglePositionQuickSwapStrategy[] quickSwapStrategies;
        address[] users;
    }

    function collect(Request memory request)
        public
        view
        returns (
            RootVaultData[] memory ordinaryStrategydata,
            HStrategyData[] memory hStrategyData,
            PulseStrategyData[] memory uniPulseStrategyData,
            PulseStrategyData[] memory quickPulseStrategyData,
            uint256[] memory balances
        )
    {
        ordinaryStrategydata = new RootVaultData[](request.ordinaryRootVaults.length);
        for (uint256 i = 0; i < request.ordinaryRootVaults.length; i++) {
            ordinaryStrategydata[i] = collectRootVaultData(request.ordinaryRootVaults[i]);
        }

        hStrategyData = new HStrategyData[](request.hRootVaults.length);
        for (uint256 i = 0; i < request.hRootVaults.length; i++) {
            hStrategyData[i] = collectHStrategyData(
                request.hStrategies[i],
                request.targetNfts[i],
                request.hRootVaults[i]
            );
        }

        uniPulseStrategyData = new PulseStrategyData[](request.uniPulseRootVaults.length);
        for (uint256 i = 0; i < request.uniPulseRootVaults.length; i++) {
            uniPulseStrategyData[i] = collectUniPulseData(request.uniPulseStrategies[i], request.uniPulseRootVaults[i]);
        }

        quickPulseStrategyData = new PulseStrategyData[](request.quickPulseRootVaults.length);
        for (uint256 i = 0; i < request.quickPulseRootVaults.length; i++) {
            quickPulseStrategyData[i] = collectQuickPulseData(
                request.quickSwapStrategies[i],
                request.quickPulseRootVaults[i]
            );
        }

        balances = new uint256[](request.users.length);
        for (uint256 i = 0; i < request.users.length; i++) {
            balances[i] = request.users[i].balance;
        }
    }
}
