// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract WETH is ERC20 {

    constructor() ERC20('Wrapped Ether', 'WETH') {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint _amount) external {
        require(balanceOf(msg.sender) >= _amount, 'insufficient balance.');
        _burn(msg.sender, _amount);
        payable(msg.sender).transfer(_amount);
    }
}
