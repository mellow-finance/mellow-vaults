// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "./interfaces/ITrader.sol";

/// @notice Base contract for every trader contract (a contract that can execute ERC20 swaps)
abstract contract Trader is ERC165 {
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return (interfaceId == this.supportsInterface.selector || interfaceId == type(ITrader).interfaceId);
    }

    function _approveERC20TokenIfNecessary(address token, address to) internal {
        if (IERC20(token).allowance(to, address(this)) < type(uint256).max / 2)
            IERC20(token).approve(to, type(uint256).max);
    }

    function _validatePath(ITrader.PathItem[] memory path) internal pure returns (bool result) {
        uint256 pathLength = path.length;
        if (pathLength == 0) return false;
        for (uint256 i; i < pathLength - 1; ++i) {
            if (path[i].token1 != path[i + 1].token0) return false;
            if (path[i].token0 == path[i].token1) return false;
        }
        if (path[pathLength - 1].token0 == path[pathLength - 1].token1) return false;
        return true;
    }
}
