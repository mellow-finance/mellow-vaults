// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/ExceptionsLibrary.sol";

import "../interfaces/vaults/IERC20RootVault.sol";
import "../interfaces/utils/ILpCallback.sol";

import "./DefaultAccessControl.sol";
import "../../src/utils/external/synthetix/StakingRewards.sol";

contract VeloDepositWrapper is DefaultAccessControl, StakingRewards {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20RootVault;

    struct StrategyInfo {
        address strategy;
        bool needToCallCallback;
    }

    StrategyInfo public strategyInfo;

    // -------------------  EXTERNAL, MUTATING  -------------------

    constructor(
        address farmOwner,
        address farmOperator,
        address wrapperAdmin
    ) StakingRewards(farmOwner, farmOperator) DefaultAccessControl(wrapperAdmin) {}

    function initialize(address _rootVault, address _rewardsToken) external onlyOwner {
        if (address(stakingToken) == address(0)) {
            rewardsToken = IERC20(_rewardsToken);
            stakingToken = IERC20(_rootVault);
        }
        IERC20(_rootVault).safeApprove(address(this), type(uint256).max);
    }

    function deposit(
        IERC20RootVault vault,
        uint256[] calldata tokenAmounts,
        uint256 minLpTokens,
        bytes calldata vaultOptions
    ) external returns (uint256[] memory actualTokenAmounts) {
        StrategyInfo memory strategyInfo_ = strategyInfo;
        require(strategyInfo_.strategy != address(0), ExceptionsLibrary.ADDRESS_ZERO);

        address[] memory tokens = vault.vaultTokens();
        require(tokens.length == tokenAmounts.length, ExceptionsLibrary.INVALID_LENGTH);
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeTransferFrom(msg.sender, address(this), tokenAmounts[i]);
            IERC20(tokens[i]).safeIncreaseAllowance(address(vault), tokenAmounts[i]);
        }

        actualTokenAmounts = vault.deposit(tokenAmounts, minLpTokens, vaultOptions);
        uint256 lpTokenMinted = vault.balanceOf(address(this));
        if (strategyInfo_.needToCallCallback) {
            ILpCallback(strategyInfo_.strategy).depositCallback();
            StakingRewards(address(this)).stake(lpTokenMinted, msg.sender);
        }

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20(tokens[i]).safeApprove(address(vault), 0);
            IERC20(tokens[i]).safeTransfer(msg.sender, IERC20(tokens[i]).balanceOf(address(this)));
        }

        emit Deposit(msg.sender, address(vault), tokens, actualTokenAmounts, lpTokenMinted);
    }

    function setStrategyInfo(address strategy, bool needToCallCallback) external {
        _requireAdmin();
        strategyInfo = StrategyInfo({strategy: strategy, needToCallCallback: needToCallCallback});
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
