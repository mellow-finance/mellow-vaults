// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

import "./interfaces/ITrader.sol";
import "./libraries/Exceptions.sol";

abstract contract Trader is ERC165 {
    address public chiefTrader;

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return (interfaceId == this.supportsInterface.selector || interfaceId == type(ITrader).interfaceId);
    }

    function _requireChiefTrader() internal view {
        require(msg.sender == chiefTrader, Exceptions.CHIEF_REQUIRED_EXCEPTION);
    }

    function _safeApproveERC20TokenIfNecessary(address token, address to) internal {
        if (IERC20(token).allowance(to, address(this)) < type(uint256).max / 2)
            TransferHelper.safeApprove(token, to, type(uint256).max);
    }
}
