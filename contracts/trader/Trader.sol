// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "./interfaces/ITrader.sol";

/// @notice Base contract for every trader contract (a contract that can execute ERC20 swaps)
abstract contract Trader is ERC165 {
    using SafeERC20 for IERC20;

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return (interfaceId == this.supportsInterface.selector || interfaceId == type(ITrader).interfaceId);
    }

    function _approveERC20TokenIfNecessary(address token, address to) internal {
        if (IERC20(token).allowance(to, address(this)) == 0) {
            IERC20(token).safeIncreaseAllowance(to, type(uint256).max);
        }
    }
}
