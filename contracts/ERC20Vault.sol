// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./trader/interfaces/IChiefTrader.sol";
import "./trader/interfaces/ITrader.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IERC20VaultGovernance.sol";
import "./Vault.sol";
import "./libraries/ExceptionsLibrary.sol";

/// @notice Vault that stores ERC20 tokens.
contract ERC20Vault is Vault, ITrader {
    using SafeERC20 for IERC20;

    /// @notice Creates a new contract.
    /// @param vaultGovernance_ Reference to VaultGovernance for this vault
    /// @param vaultTokens_ ERC20 tokens under Vault management
    constructor(IVaultGovernance vaultGovernance_, address[] memory vaultTokens_)
        Vault(vaultGovernance_, vaultTokens_)
    {}

    /// @inheritdoc Vault
    function tvl() public view override returns (uint256[] memory tokenAmounts) {
        address[] memory tokens = _vaultTokens;
        uint256 len = tokens.length;
        tokenAmounts = new uint256[](len);
        for (uint256 i = 0; i < len; ++i) tokenAmounts[i] = IERC20(tokens[i]).balanceOf(address(this));
    }

    /// @inheritdoc ITrader
    function swapExactInput(
        uint256 traderId,
        address,
        address token0,
        address token1,
        uint256 amount,
        bytes memory options
    ) external returns (uint256 amountOut) {
        require(isVaultToken(token0) && isVaultToken(token1), ExceptionsLibrary.NOT_VAULT_TOKEN);
        require(_isStrategy(msg.sender), ExceptionsLibrary.REQUIRE_STRATEGY);
        IERC20VaultGovernance vg = IERC20VaultGovernance(address(_vaultGovernance));
        ITrader trader = ITrader(vg.delayedProtocolParams().trader);
        IChiefTrader chiefTrader = IChiefTrader(address(trader));
        _approveERC20TokenIfNecessary(token0, chiefTrader.getTrader(traderId));
        amountOut = trader.swapExactInput(traderId, address(this), token0, token1, amount, options);
        emit Swapped(token0 == _vaultTokens[0], traderId, amount, amountOut);
    }

    /// @inheritdoc ITrader
    function swapExactOutput(
        uint256 traderId,
        address,
        address token0, 
        address token1,
        uint256 amount,
        bytes memory options
    ) external returns (uint256 amountIn) {
        require(isVaultToken(token0) && isVaultToken(token1), ExceptionsLibrary.NOT_VAULT_TOKEN);
        require(_isStrategy(msg.sender), ExceptionsLibrary.REQUIRE_STRATEGY);
        IERC20VaultGovernance vg = IERC20VaultGovernance(address(_vaultGovernance));
        ITrader trader = ITrader(vg.delayedProtocolParams().trader);
        IChiefTrader chiefTrader = IChiefTrader(address(trader));
        _approveERC20TokenIfNecessary(token0, chiefTrader.getTrader(traderId));
        amountIn = trader.swapExactOutput(traderId, address(this), token0, token1, amount, options);
        emit Swapped(token0 == _vaultTokens[0], traderId, amountIn, amount);
    }

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
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        for (uint256 i = 0; i < tokenAmounts.length; ++i) IERC20(_vaultTokens[i]).safeTransfer(to, tokenAmounts[i]);

        actualTokenAmounts = tokenAmounts;
    }

    function _postReclaimTokens(address, address[] memory tokens) internal view override {
        for (uint256 i = 0; i < tokens.length; ++i)
            require(!isVaultToken(tokens[i]), ExceptionsLibrary.OTHER_VAULT_TOKENS); // vault token is part of TVL
    }

    function _isStrategy(address addr) internal view returns (bool) {
        return _vaultGovernance.internalParams().registry.getApproved(_nft) == addr;
    }

    function _approveERC20TokenIfNecessary(address token, address to) internal {
        if (IERC20(token).allowance(address(this), to) == 0) {
            IERC20(token).safeIncreaseAllowance(to, type(uint256).max);
        }
    }

    event Swapped(bool zeroForOne, uint256 traderId, uint256 amount0, uint256 amount1);
}
