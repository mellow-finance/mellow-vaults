// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "./trader/interfaces/ITrader.sol";
import "./interfaces/IERC20VaultGovernance.sol";
import "./Vault.sol";

/// @notice Vault that stores ERC20 tokens.
contract ERC20Vault is Vault, ITrader {
    /// @notice Creates a new contract.
    /// @param vaultGovernance_ Reference to VaultGovernance for this vault
    /// @param vaultTokens_ ERC20 tokens under Vault management
    constructor(IVaultGovernance vaultGovernance_, address[] memory vaultTokens_)
        Vault(vaultGovernance_, vaultTokens_)
    {}

    /// @inheritdoc Vault
    function tvl() public view override returns (uint256[] memory tokenAmounts) {
        address[] memory tokens = _vaultTokens;
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAmounts[i] = IERC20(tokens[i]).balanceOf(address(this));
        }
    }

    function swapExactInput(
        uint256 traderId,
        address input,
        address output,
        uint256 amount,
        address,
        PathItem[] calldata path,
        bytes calldata options
    ) external returns (uint256 amountOut) {
        require(isVaultToken(output), "VT");
        require(_isStrategy(msg.sender), "ST");
        IERC20VaultGovernance vg = IERC20VaultGovernance(address(_vaultGovernance));
        ITrader trader = ITrader(vg.delayedStrategyParams(_nft).trader);
        return trader.swapExactInput(traderId, input, output, amount, address(0), path, options);
    }

    function swapExactOutput(
        uint256 traderId,
        address input,
        address output,
        uint256 amount,
        address,
        ITrader.PathItem[] calldata path,
        bytes calldata options
    ) external returns (uint256 amountOut) {
        require(isVaultToken(output), "VT");
        require(_isStrategy(msg.sender), "ST");
        IERC20VaultGovernance vg = IERC20VaultGovernance(address(_vaultGovernance));
        ITrader trader = ITrader(vg.delayedStrategyParams(_nft).trader);
        return trader.swapExactOutput(traderId, input, output, amount, address(0), path, options);
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
        for (uint256 i = 0; i < tokenAmounts.length; i++) {
            IERC20(_vaultTokens[i]).transfer(to, tokenAmounts[i]);
        }
        actualTokenAmounts = tokenAmounts;
    }

    function _postReclaimTokens(address, address[] memory tokens) internal view override {
        for (uint256 i = 0; i < tokens.length; i++) {
            require(!isVaultToken(tokens[i]), "OWT"); // vault token is part of TVL
        }
    }

    function _isStrategy(address addr) internal view returns (bool) {
        return _vaultGovernance.internalParams().registry.getApproved(_nft) == addr;
    }
}
