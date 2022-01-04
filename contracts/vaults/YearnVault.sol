// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/external/yearn/IYearnProtocolVault.sol";
import "../interfaces/vaults/IYearnVaultGovernance.sol";
import "../interfaces/vaults/IYearnVault.sol";
import "./IntegrationVault.sol";

/// @notice Vault that interfaces Yearn protocol in the integration layer.
/// @dev Notes:
/// **TVL**
///
/// The TVL of the vault is cached and updated after each deposit withdraw.
/// So essentially `tvl` call doesn't take into account accrued interest / donations to Yearn since the
/// last `deposit` / `withdraw`
///
/// **yTokens**
/// yTokens are fixed at the token creation and addresses are taken from YearnVault governance and if missing there
/// - in YearnVaultRegistry.
/// So essentially each yToken is fixed for life of the YearnVault. If the yToken is missing for some vaultToken,
/// the YearnVault cannot be created.
///
/// **Push / Pull**
/// There are some deposit limits imposed by Yearn vaults.
/// The contract's vaultTokens are fully allowed to corresponding yTokens.

contract YearnVault is IYearnVault, IntegrationVault {
    address[] private _yTokens;
    uint256 public constant DEFAULT_MAX_LOSS = 10000; // 10000%%

    /// @notice Yearn protocol vaults used by this contract
    function yTokens() external view returns (address[] memory) {
        return _yTokens;
    }

    /// @inheritdoc IVault
    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        address[] memory tokens = _vaultTokens;
        minTokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < _yTokens.length; ++i) {
            IYearnProtocolVault yToken = IYearnProtocolVault(_yTokens[i]);
            minTokenAmounts[i] = (yToken.balanceOf(address(this)) * yToken.pricePerShare()) / (10**yToken.decimals());
        }
        maxTokenAmounts = minTokenAmounts;
    }

    function initialize(uint256 nft_, address[] memory vaultTokens_) external {
        _yTokens = new address[](vaultTokens_.length);
        for (uint256 i = 0; i < vaultTokens_.length; ++i) {
            _yTokens[i] = IYearnVaultGovernance(address(msg.sender)).yTokenForToken(vaultTokens_[i]);
            require(_yTokens[i] != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        }
        _initialize(vaultTokens_, nft_);
    }

    function _push(uint256[] memory tokenAmounts, bytes memory)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        address[] memory tokens = _vaultTokens;
        for (uint256 i = 0; i < _yTokens.length; ++i) {
            if (tokenAmounts[i] == 0) {
                continue;
            }

            address token = tokens[i];
            IYearnProtocolVault yToken = IYearnProtocolVault(_yTokens[i]);
            _allowTokenIfNecessary(token, address(yToken));
            yToken.deposit(tokenAmounts[i], address(this));
        }
        actualTokenAmounts = tokenAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](tokenAmounts.length);
        uint256 maxLoss = options.length > 0 ? abi.decode(options, (uint256)) : DEFAULT_MAX_LOSS;
        for (uint256 i = 0; i < _yTokens.length; ++i) {
            if (tokenAmounts[i] == 0) continue;

            IYearnProtocolVault yToken = IYearnProtocolVault(_yTokens[i]);
            uint256 yTokenAmount = ((tokenAmounts[i] * (10**yToken.decimals())) / yToken.pricePerShare());
            uint256 balance = yToken.balanceOf(address(this));
            if (yTokenAmount > balance) {
                yTokenAmount = balance;
            }

            if (yTokenAmount == 0) continue;

            actualTokenAmounts[i] = yToken.withdraw(yTokenAmount, to, maxLoss);
        }
    }
}
