// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../interfaces/vaults/IERC20RootVault.sol";
import "../interfaces/vaults/IERC20RootVaultGovernance.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IERC20VaultGovernance.sol";
import "../interfaces/vaults/IVeloVault.sol";
import "../interfaces/vaults/IVeloVaultGovernance.sol";
import "../interfaces/external/velo/ICLPool.sol";
import "../interfaces/external/velo/ICLFactory.sol";
import "../interfaces/external/velo/ICLGauge.sol";
import "../interfaces/external/velo/ICLGaugeFactory.sol";
import "../interfaces/external/velo/INonfungiblePositionManager.sol";
import "../interfaces/external/velo/ISwapRouter.sol";

import "../strategies/BaseAmmStrategy.sol";
import "../strategies/PulseOperatorStrategy.sol";

import "./BaseAmmStrategyHelper.sol";
import "./DefaultAccessControl.sol";
import "./VeloDepositWrapper.sol";
import "./VeloDeployFactory.sol";

contract VeloDeployFactoryHelper {
    using SafeERC20 for IERC20;

    uint256 public constant Q96 = 2**96;

    ICLFactory public immutable factory;
    ISwapRouter public immutable swapRouter;

    constructor(ICLFactory factory_, ISwapRouter swapRouter_) {
        swapRouter = swapRouter_;
        factory = factory_;
    }

    function _combineVaults(
        VeloDeployFactory.InternalParams memory params,
        VeloDeployFactory.VaultInfo memory info,
        uint256[] memory nfts
    ) private returns (VeloDeployFactory.VaultInfo memory) {
        IVaultRegistry vaultRegistry = IVaultRegistry(params.addresses.vaultRegistry);
        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(params.addresses.erc20RootVaultGovernance, nfts[i]);
        }
        uint256 nft;
        (info.rootVault, nft) = IERC20RootVaultGovernance(params.addresses.erc20RootVaultGovernance).createVault(
            info.tokens,
            info.baseStrategy,
            nfts,
            address(this)
        );
        IERC20RootVaultGovernance(params.addresses.erc20RootVaultGovernance).setStrategyParams(
            nft,
            IERC20RootVaultGovernance.StrategyParams({
                tokenLimitPerAddress: type(uint256).max,
                tokenLimit: type(uint256).max
            })
        );
        {
            address[] memory whitelist = new address[](1);
            whitelist[0] = info.depositWrapper;
            info.rootVault.addDepositorsToAllowlist(whitelist);
        }
        IERC20RootVaultGovernance(params.addresses.erc20RootVaultGovernance).stageDelayedStrategyParams(
            nft,
            IERC20RootVaultGovernance.DelayedStrategyParams({
                strategyTreasury: params.addresses.strategyTreasury,
                strategyPerformanceTreasury: params.addresses.protocolTreasury,
                managementFee: 0,
                performanceFee: 0,
                privateVault: true,
                depositCallbackAddress: address(0),
                withdrawCallbackAddress: address(0)
            })
        );
        IERC20RootVaultGovernance(params.addresses.erc20RootVaultGovernance).commitDelayedStrategyParams(nft);
        vaultRegistry.approve(params.addresses.operator, nft);
        return info;
    }

    function deployVaults(VeloDeployFactory.InternalParams memory params, VeloDeployFactory.VaultInfo memory info)
        external
        returns (VeloDeployFactory.VaultInfo memory)
    {
        IVaultRegistry vaultRegistry = IVaultRegistry(params.addresses.vaultRegistry);

        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;
        IERC20VaultGovernance(params.addresses.erc20VaultGovernance).createVault(info.tokens, address(this));
        info.erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        info.veloVaults = new IIntegrationVault[](params.positionsCount);
        int24 tickSpacing = info.pool.tickSpacing();
        for (uint256 i = 0; i < info.veloVaults.length; i++) {
            IVeloVaultGovernance(params.addresses.veloVaultGovernance).createVault(
                info.tokens,
                address(this),
                tickSpacing
            );
            uint256 nft = erc20VaultNft + 1 + i;
            info.veloVaults[i] = IIntegrationVault(vaultRegistry.vaultForNft(nft));
            IVeloVaultGovernance(params.addresses.veloVaultGovernance).setStrategyParams(
                nft,
                IVeloVaultGovernance.StrategyParams({
                    farmingPool: address(info.depositWrapper),
                    gauge: address(info.gauge),
                    protocolFeeD9: params.protocolFeeD9,
                    protocolTreasury: params.addresses.protocolTreasury
                })
            );
        }

        {
            uint256[] memory nfts = new uint256[](1 + info.veloVaults.length);
            for (uint256 i = 0; i < nfts.length; i++) {
                nfts[i] = erc20VaultNft + i;
            }
            info = _combineVaults(params, info, nfts);
        }

        VeloDepositWrapper(info.depositWrapper).initialize(
            address(info.rootVault),
            info.gauge.rewardToken(),
            address(this)
        );

        VeloDepositWrapper(info.depositWrapper).grantRole(keccak256("admin"), address(params.addresses.operator));

        return info;
    }

    function initialDeposit(VeloDeployFactory.VaultInfo memory info) external {
        uint256[] memory tokenAmounts = info.rootVault.pullExistentials();
        for (uint256 i = 0; i < info.tokens.length; i++) {
            tokenAmounts[i] *= 10;
            address token = info.tokens[i];
            IERC20(token).safeApprove(address(info.depositWrapper), type(uint256).max);
            uint256 amount = IERC20(token).balanceOf(address(this));
            if (amount < tokenAmounts[i]) {
                IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmounts[i] - amount);
            }
        }

        VeloDepositWrapper(info.depositWrapper).setStrategyInfo(address(info.baseStrategy), false);
        VeloDepositWrapper(info.depositWrapper).deposit(tokenAmounts, 0, new bytes(0));
        VeloDepositWrapper(info.depositWrapper).setStrategyInfo(address(info.baseStrategy), true);
    }

    function rebalance(VeloDeployFactory.InternalParams memory params, VeloDeployFactory.VaultInfo memory info)
        external
    {
        (uint160 sqrtPriceX96, , , , , ) = info.pool.slot0();
        BaseAmmStrategy.Position[] memory target = new BaseAmmStrategy.Position[](params.positionsCount);
        (BaseAmmStrategy.Position memory newPosition, ) = PulseOperatorStrategy(info.operatorStrategy)
            .calculateExpectedPosition();
        target[0].tickLower = newPosition.tickLower;
        target[0].tickUpper = newPosition.tickUpper;
        target[0].capitalRatioX96 = Q96;

        int24 tickSpacing = info.pool.tickSpacing();
        uint24 fee = factory.tickSpacingToFee(tickSpacing);
        (address tokenIn, address tokenOut, uint256 amountIn, uint256 expectedAmountOut) = BaseAmmStrategyHelper(
            params.addresses.baseStrategyHelper
        ).calculateSwapAmounts(sqrtPriceX96, target, info.rootVault, fee);

        uint256 amountOutMin = (expectedAmountOut * 99) / 100;
        bytes memory data = abi.encodeWithSelector(
            ISwapRouter.exactInputSingle.selector,
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                tickSpacing: tickSpacing,
                amountIn: amountIn,
                deadline: type(uint256).max,
                recipient: address(info.erc20Vault),
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            })
        );

        PulseOperatorStrategy(info.operatorStrategy).rebalance(
            BaseAmmStrategy.SwapData({
                router: address(swapRouter),
                data: data,
                tokenInIndex: tokenIn < tokenOut ? 0 : 1,
                amountIn: amountIn,
                amountOutMin: amountOutMin
            })
        );

        PulseOperatorStrategy(info.operatorStrategy).revokeRole(keccak256("admin_delegate"), address(this));
        PulseOperatorStrategy(info.operatorStrategy).revokeRole(keccak256("admin"), address(this));
    }
}
