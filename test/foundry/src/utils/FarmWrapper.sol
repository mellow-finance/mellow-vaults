// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/ExceptionsLibrary.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../interfaces/vaults/IERC20RootVault.sol";
import "../interfaces/utils/ILpCallback.sol";
import "../interfaces/external/synthetix/IFarmingPool.sol";
import "./BatchCall.sol";
import "./FarmingPool.sol";

import "./DefaultAccessControl.sol";
import "forge-std/console2.sol";

contract FarmWrapper is FarmingPool, DefaultAccessControl {

    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20RootVault;

    struct StrategyInfo {
        address strategy;
        bool needToCallCallback;
        IFarmingPool farm;
    }

    BatchCall batchCall;

    mapping(address => StrategyInfo) public depositInfo;

    constructor(address owner, address rewardsDistribution, address rewardsToken, address stakingToken, address admin, address batchCall_) FarmingPool(owner, rewardsDistribution, rewardsToken, stakingToken) DefaultAccessControl(admin) {
        require(batchCall_ != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        batchCall = BatchCall(batchCall_);
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    function depositAndStake(
        IERC20RootVault vault,
        uint256[] calldata tokenAmounts,
        uint256 minLpTokens,
        bytes calldata vaultOptions
    ) external returns (uint256[] memory actualTokenAmounts) {
        StrategyInfo memory strategyInfo = depositInfo[address(vault)];
        require(strategyInfo.strategy != address(0), ExceptionsLibrary.ADDRESS_ZERO);

        address[] memory tokens = vault.vaultTokens();
        require(tokens.length == tokenAmounts.length, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeTransferFrom(msg.sender, address(this), tokenAmounts[i]);
            IERC20(tokens[i]).safeIncreaseAllowance(address(vault), tokenAmounts[i]);
        }

        uint256 oldBalance = vault.balanceOf(address(this));
        actualTokenAmounts = vault.deposit(tokenAmounts, minLpTokens, vaultOptions);
        uint256 lpReceived = vault.balanceOf(address(this)) - oldBalance;

        vault.safeTransfer(msg.sender, lpReceived);

        {

            bytes memory data = abi.encodePacked(IFarmingPool.stake.selector, abi.encode(lpReceived));
            Address.functionDelegateCall(address(strategyInfo.farm), data);

        }

        if (strategyInfo.needToCallCallback) {
            bytes memory info = bytes("");
            ILpCallback(strategyInfo.strategy).depositCallback(info);
        }

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeApprove(address(vault), 0);
            IERC20(tokens[i]).safeTransfer(msg.sender, tokenAmounts[i] - actualTokenAmounts[i]);
        }

        emit Deposit(msg.sender, address(vault), tokens, actualTokenAmounts, lpReceived);
    }

    function addNewStrategy(
        address vault,
        address strategy,
        bool needToCallCallback,
        IFarmingPool farm
    ) external {
        _requireAdmin();
        depositInfo[vault] = StrategyInfo({strategy: strategy, needToCallCallback: needToCallCallback, farm: farm});
    }

    /// @notice Emitted when liquidity is deposited
    /// @param from The source address for the liquidity
    /// @param tokens ERC20 tokens deposited
    /// @param actualTokenAmounts Token amounts deposited
    /// @param lpTokenMinted LP tokens received by the liquidity provider
    event Deposit(
        address indexed from,
        address indexed to,
        address[] tokens,
        uint256[] actualTokenAmounts,
        uint256 lpTokenMinted
    );
}