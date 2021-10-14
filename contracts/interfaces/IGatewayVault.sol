// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVault.sol";

interface IGatewayVault is IVault {
    function hasVault(address vault) external returns (bool);

    function vaultsTvl() external view returns (uint256[][] memory tokenAmounts);

    function vaultTvl(uint256 vaultNum) external view returns (uint256[] memory);

    function vaultEarnings(uint256 vaultNum) external view returns (uint256[] memory);

    function setLimits(uint256[] calldata newLimits) external;

    function setRedirects(address[] calldata newRedirects) external;
}
