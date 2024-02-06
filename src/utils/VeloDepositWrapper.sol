// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/ExceptionsLibrary.sol";

import "../interfaces/vaults/IERC20RootVault.sol";
import "../interfaces/utils/ILpCallback.sol";

import "./DefaultAccessControlLateInit.sol";
import "./external/synthetix/StakingRewards.sol";

/*
    Contract serving as both a reward farm and a deposit wrapper for the corresponding strategy.
    It uses a modified implementation of the farm from Synthetix.
*/
contract VeloDepositWrapper is DefaultAccessControlLateInit, StakingRewards {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20RootVault;

    /// @dev Structure containing information about the corresponding strategy for this contract.
    /// @param strategy The address of the base strategy.
    /// @param needToCallCallback A flag determining whether calling depositCallback and staking LP tokens is necessary.
    ///         It is assumed that the flag is set to false only until the initial deposit, after which it is constantly set to true.
    struct StrategyInfo {
        address strategy;
        bool needToCallCallback;
    }

    StrategyInfo public strategyInfo;

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @dev Constructor of the farm, where its owner and operator are set.
    /// @param farmOwner The address of the farm owner.
    /// @param farmOperator The address of the farm operator.
    constructor(address farmOwner, address farmOperator) StakingRewards(farmOwner, farmOperator) {}

    /// @dev Initialization function for the farm.
    /// This function can only be called once.
    /// @param rootVault The address of the ERC20RootVault.
    /// @param rewardsToken_ The address of the rewards token.
    /// @param admin The address of the admin.
    function initialize(
        address rootVault,
        address rewardsToken_,
        address admin
    ) external {
        DefaultAccessControlLateInit(address(this)).init(admin);
        rewardsToken = IERC20(rewardsToken_);
        stakingToken = IERC20(rootVault);
        IERC20(rootVault).safeApprove(address(this), type(uint256).max);
    }

    /// @dev Deposit function into ERC20RootVault. If strategyInfo.needToCallCallback is true, after depositing into ERC20RootVault,
    /// the strategy.depositCallback will be explicitly called, and LP tokens will also be staked.
    /// @param tokenAmounts An array of token amounts to deposit.
    /// @param minLpTokens The minimum LP tokens expected to be received.
    /// @param vaultOptions Additional vault options.
    /// @return actualTokenAmounts An array of actual token amounts deposited.
    function deposit(
        uint256[] calldata tokenAmounts,
        uint256 minLpTokens,
        bytes calldata vaultOptions
    ) external returns (uint256[] memory actualTokenAmounts) {
        StrategyInfo memory strategyInfo_ = strategyInfo;
        require(strategyInfo_.strategy != address(0), ExceptionsLibrary.ADDRESS_ZERO);

        IERC20RootVault vault = IERC20RootVault(address(stakingToken));
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

    /// @dev Set the strategy address and needToCallCallback flag.
    /// This function can only be called by an address with the ADMIN_ROLE.
    /// @param strategy The address of the strategy.
    /// @param needToCallCallback The flag indicating whether the callback needs to be called.
    function setStrategyInfo(address strategy, bool needToCallCallback) external {
        _requireAdmin();
        strategyInfo = StrategyInfo({strategy: strategy, needToCallCallback: needToCallCallback});
    }

    /// @notice Emitted when liquidity is deposited.
    /// @param from The source address for the liquidity.
    /// @param to The destination address for the liquidity.
    /// @param tokens ERC20 tokens deposited.
    /// @param actualTokenAmounts Token amounts deposited.
    /// @param lpTokenMinted LP tokens received by the liquidity provider.
    event Deposit(
        address indexed from,
        address indexed to,
        address[] tokens,
        uint256[] actualTokenAmounts,
        uint256 lpTokenMinted
    );
}
