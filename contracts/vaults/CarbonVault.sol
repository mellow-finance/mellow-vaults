// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/vaults/ICarbonVault.sol";
import "../interfaces/external/carbon/contracts/carbon/interfaces/ICarbonController.sol";
import "./IntegrationVault.sol";

import "../interfaces/vaults/ICarbonVaultGovernance.sol";

contract CarbonVault is ICarbonVault, IntegrationVault {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    EnumerableSet.UintSet positions;

    ICarbonController public controller;

    uint256[] public freeAmounts;

    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        minTokenAmounts = new uint256[](2);

        address[] memory vaultTokens = _vaultTokens;

        uint256 positionsCount = positions.length();
        for (uint256 i = 0; i < positionsCount; ++i) {
            uint256 position = positions.at(i);
            Strategy memory strategy = controller.strategy(position);

            for (uint256 j = 0; j < 2; ++j) {
                Order memory order = strategy.orders[j];
                address token = Token.unwrap(strategy.tokens[j]);

                for (uint256 k = 0; k < 2; ++k) {
                    if (vaultTokens[k] == token) {
                        minTokenAmounts[k] += order.y;
                    }
                }
            }
        }

        for (uint256 i = 0; i < 2; ++i) {
            minTokenAmounts[i] += IERC20(vaultTokens[i]).balanceOf(address(this));
        }

        maxTokenAmounts = minTokenAmounts;
    }

    /// @inheritdoc ICarbonVault
    function initialize(uint256 nft_, address[] memory vaultTokens_) external {
        require(vaultTokens_.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        _initialize(vaultTokens_, nft_);

        controller = ICarbonVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().controller;
    }

    function _isReclaimForbidden(address token) internal view override returns (bool) {}

    // -------------------  INTERNAL, MUTATING  -------------------

    function _push(uint256[] memory tokenAmounts, bytes memory)
        internal
        pure
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        return tokenAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](2);

        address[] memory vaultTokens = _vaultTokens;

        for (uint256 i = 0; i < 2; ++i) {
            uint256 balance = IERC20(vaultTokens[i]).balanceOf(address(this));
            actualTokenAmounts[i] = (balance < tokenAmounts[i]) ? balance : tokenAmounts[i];
            IERC20(vaultTokens[i]).safeTransfer(to, actualTokenAmounts[i]);
        }
    }

    /// @inheritdoc IntegrationVault
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(ICarbonVault).interfaceId);
    }
}
