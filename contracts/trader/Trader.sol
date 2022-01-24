// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "../interfaces/trader/ITrader.sol";

/// @notice Base contract for every trader contract (a contract that can execute ERC20 swaps)
abstract contract Trader is ERC165 {
    using SafeERC20 for IERC20;

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return (interfaceId == this.supportsInterface.selector || interfaceId == type(ITrader).interfaceId);
    }

    function _increaseAllowancesByAmount(
        address token,
        address to,
        uint256 amount
    ) internal {
        IERC20(token).safeIncreaseAllowance(to, amount);
    }

    function _decreaseAllowances(address token, address to) internal {
        IERC20(token).safeDecreaseAllowance(to, IERC20(token).allowance(address(this), to));
    }

    function _validatePathLinked(ITrader.PathItem[] memory path) internal pure returns (bool result) {
        uint256 pathLength = path.length;
        if (pathLength == 0) return false;
        if (pathLength == 1) return path[0].token0 != path[0].token1;
        for (uint256 i = 0; i < pathLength - 1; ++i) {
            if (path[i].token0 == address(0) || path[i].token1 == address(0)) return false;
            if (path[i].token1 != path[i + 1].token0) return false;
            if (path[i].token0 == path[i].token1) return false;
        }
        if (path[pathLength - 1].token0 == path[pathLength - 1].token1) return false;
        return true;
    }
}
