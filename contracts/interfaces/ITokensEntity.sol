// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITokensEntity {
    function tokensCount() external view returns (uint256);

    function tokens() external view returns (IERC20[] memory);

    function hasToken(IERC20 token) external view returns (bool);

    function tokenAmountsBalance() external view returns (uint256[] memory);
}
