// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.9;

import "../utils/ERC20Token.sol";

contract MockERC20Token is ERC20Token {
    function initERC20(string memory _name, string memory _symbol) external {
        _initERC20(_name, _symbol);
    }

    function mint(address to, uint256 amount) external virtual {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external virtual {
        _burn(from, amount);
    }
}
