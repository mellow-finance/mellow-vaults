// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../interfaces/vaults/IERC20VaultGovernance.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/trader/IChiefTrader.sol";
import "./IntegrationVault.sol";

/// @notice Vault that stores ERC20 tokens.
contract ERC20Vault is IERC20Vault, IntegrationVault {
    using SafeERC20 for IERC20;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        address[] memory tokens = _vaultTokens;
        uint256 len = tokens.length;
        minTokenAmounts = new uint256[](len);
        for (uint256 i = 0; i < len; ++i) {
            minTokenAmounts[i] = IERC20(tokens[i]).balanceOf(address(this));
        }
        maxTokenAmounts = minTokenAmounts;
    }

    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IERC20Vault).interfaceId);
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    function initialize(uint256 nft_, address[] memory vaultTokens_) external {
        _initialize(vaultTokens_, nft_);
    }

    // @inheritdoc IIntegrationVault
    function reclaimTokens(address[] memory tokens)
        external
        override(IIntegrationVault, IntegrationVault)
        nonReentrant
        returns (uint256[] memory actualTokenAmounts)
    {
        // no-op
        actualTokenAmounts = new uint256[](tokens.length);
    }

    /// @inheritdoc ITrader
    function swapExactInput(
        uint256 traderId,
        uint256 amount,
        address,
        PathItem[] memory path,
        bytes memory options
    ) external returns (uint256 amountOut) {
        require(path.length > 0 && isVaultToken(path[path.length - 1].token1), ExceptionsLibrary.INVALID_TOKEN);
        require(_isStrategy(msg.sender), ExceptionsLibrary.INVALID_TARGET);
        IERC20VaultGovernance vg = IERC20VaultGovernance(address(_vaultGovernance));
        ITrader trader = ITrader(vg.delayedProtocolParams().trader);
        IChiefTrader chiefTrader = IChiefTrader(address(trader));
        _approveERC20TokenIfNecessary(path[0].token0, chiefTrader.getTrader(traderId), amount);
        return trader.swapExactInput(traderId, amount, address(0), path, options);
    }

    /// @inheritdoc ITrader
    function swapExactOutput(
        uint256 traderId,
        uint256 amount,
        address,
        PathItem[] memory path,
        bytes calldata options
    ) external returns (uint256 amountOut) {
        require(path.length > 0 && isVaultToken(path[path.length - 1].token1), ExceptionsLibrary.INVALID_TOKEN);
        require(_isStrategy(msg.sender), ExceptionsLibrary.INVALID_TARGET);
        IERC20VaultGovernance vg = IERC20VaultGovernance(address(_vaultGovernance));
        ITrader trader = ITrader(vg.delayedProtocolParams().trader);
        IChiefTrader chiefTrader = IChiefTrader(address(trader));
        _approveERC20TokenIfNecessary(path[0].token0, chiefTrader.getTrader(traderId), amount);
        return trader.swapExactOutput(traderId, amount, address(0), path, options);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _isStrategy(address addr) internal view returns (bool) {
        return _vaultGovernance.internalParams().registry.getApproved(_nft) == addr;
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _push(uint256[] memory tokenAmounts, bytes memory)
        internal
        pure
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        // no-op, tokens are already on balance
        return tokenAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](tokenAmounts.length);
        address[] memory tokens = _vaultTokens;
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        address owner = registry.ownerOf(_nft);

        for (uint256 i = 0; i < tokenAmounts.length; ++i) {
            IERC20 vaultToken = IERC20(_vaultTokens[i]);
            uint256 balance = vaultToken.balanceOf(address(this));
            uint256 amount = tokenAmounts[i] < balance ? tokenAmounts[i] : balance;
            IERC20(_vaultTokens[i]).safeTransfer(to, amount);
            if (owner != to) {
                // this will equal to amounts pulled + any accidental prior balances on `to`;
                actualTokenAmounts[i] = IERC20(_vaultTokens[i]).balanceOf(to);
            } else {
                actualTokenAmounts[i] = amount;
            }
        }
        if (owner != to) {
            // if we pull as a strategy, make sure everything is pushed
            IIntegrationVault(to).push(tokens, tokenAmounts, options);
            // any accidental prior balances + push leftovers
            uint256[] memory reclaimed = IIntegrationVault(to).reclaimTokens(tokens);
            for (uint256 i = 0; i < tokenAmounts.length; i++) {
                // equals to exactly how much is pushed
                actualTokenAmounts[i] -= reclaimed[i];
            }
        }
    }

    function _approveERC20TokenIfNecessary(
        address token,
        address to,
        uint256 amount
    ) internal {
        if (IERC20(token).allowance(address(this), to) < type(uint256).max / 2) {
            IERC20(token).safeDecreaseAllowance(to, IERC20(token).allowance(address(this), to));
            IERC20(token).safeIncreaseAllowance(to, amount);
        }
    }
}
