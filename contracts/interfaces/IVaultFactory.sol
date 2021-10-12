// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IProtocolGovernance.sol";
import "./IVaultManagerGovernance.sol";

interface IVaultFactory {
    function deployVault(
        address[] calldata tokens,
        address strategyTreasury,
        bytes calldata options
    ) external returns (address vault);
}
