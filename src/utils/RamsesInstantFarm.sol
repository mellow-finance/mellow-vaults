// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../interfaces/external/ramses/IGaugeV2.sol";
import "../interfaces/external/ramses/IXRam.sol";
import "../interfaces/external/ramses/ISwapRouter.sol";

import "../interfaces/external/ramses/callback/IRamsesV2FlashCallback.sol";
import "../interfaces/external/ramses/libraries/OracleLibrary.sol";

import "../interfaces/vaults/IRamsesV2VaultGovernance.sol";
import "../interfaces/vaults/IRamsesV2Vault.sol";
import "../interfaces/vaults/IERC20RootVault.sol";

import "./InstantFarm.sol";

contract RamsesInstantFarm is InstantFarm, IRamsesV2FlashCallback {
    using SafeERC20 for IERC20;

    address public immutable xram;
    address public immutable ram;
    address public immutable weth;
    ISwapRouter public immutable router;
    IRamsesV2Pool public immutable wethRamPool;
    IRamsesV2Pool public immutable wethPool;

    uint32 public immutable timespan;
    int24 public immutable maxTickDeviation;

    struct InitParams {
        address lpToken;
        address admin;
        address[] rewardTokens;
        address xram;
        address ram;
        address weth;
        address router;
        address wethRamPool;
        address wethPool;
        uint32 timespan;
        int24 maxTickDeviation;
    }

    constructor(InitParams memory initParams)
        InstantFarm(initParams.lpToken, initParams.admin, initParams.rewardTokens)
    {
        xram = initParams.xram;
        ram = initParams.ram;
        weth = initParams.weth;
        router = ISwapRouter(initParams.router);
        wethRamPool = IRamsesV2Pool(initParams.wethRamPool);
        wethPool = IRamsesV2Pool(initParams.wethPool);
        timespan = initParams.timespan;
        maxTickDeviation = initParams.maxTickDeviation;
    }

    function ensureNoMEV(IRamsesV2Pool pool) public view {
        (int24 averageTick, , ) = OracleLibrary.consult(address(pool), timespan);
        (, int24 spotTick, , , , , ) = pool.slot0();
        int24 delta = averageTick - spotTick;
        if (delta < 0) delta = -delta;
        if (delta > maxTickDeviation) revert(ExceptionsLibrary.LIMIT_OVERFLOW);
    }

    function rewardsCallback(IRamsesV2VaultGovernance.StrategyParams memory params) public {
        uint256 subvaultNft = IERC20RootVault(lpToken).vaultGovernance().internalParams().registry.nftForVault(
            msg.sender
        );
        require(IERC20RootVault(lpToken).hasSubvault(subvaultNft), ExceptionsLibrary.FORBIDDEN);

        IRamsesV2Vault vault = IRamsesV2Vault(msg.sender);
        uint256 positionId = vault.positionId();

        IRamsesV2NonfungiblePositionManager positionManager = vault.positionManager();
        positionManager.transferFrom(msg.sender, address(this), positionId);
        IGaugeV2(params.gaugeV2).getReward(positionId, params.rewards);
        positionManager.transferFrom(address(this), msg.sender, positionId);

        if (!params.instantExitFlag) return;
        uint256 xramBalance = IERC20(xram).balanceOf(address(this));
        if (xramBalance == 0) return;
        ensureNoMEV(wethRamPool);
        uint256 requiredWethAmount = IXRam(xram).quotePayment(xramBalance);
        bytes memory data = abi.encode(requiredWethAmount, xramBalance);
        if (weth == wethPool.token0()) {
            wethPool.flash(address(this), requiredWethAmount, 0, data);
        } else {
            wethPool.flash(address(this), 0, requiredWethAmount, data);
        }
    }

    function ramsesV2FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external {
        require((fee0 == 0) != (fee1 == 0), ExceptionsLibrary.INVALID_VALUE);
        (uint256 wethPayment, uint256 xramBalance) = abi.decode(data, (uint256, uint256));
        IERC20(weth).safeIncreaseAllowance(address(xram), wethPayment);
        IXRam(xram).instantExit(xramBalance, wethPayment);
        IERC20(ram).safeIncreaseAllowance(address(router), type(uint256).max);
        router.exactOutputSingle(
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: ram,
                tokenOut: weth,
                fee: wethRamPool.fee(),
                recipient: address(wethPool),
                deadline: type(uint256).max,
                amountOut: wethPayment + fee1,
                amountInMaximum: IERC20(ram).balanceOf(address(this)),
                sqrtPriceLimitX96: 0
            })
        );
        IERC20(ram).safeApprove(address(router), 0);
    }
}
