// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITokensEntity {
    function tokensCount() external view returns (uint256);

    function tokens() external view returns (address[] memory);

    function hasToken(address token) external view returns (bool);

    function tokenAmountsBalance() external view returns (uint256[] memory);
}
