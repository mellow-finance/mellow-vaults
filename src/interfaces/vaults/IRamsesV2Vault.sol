// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./IIntegrationVault.sol";
import "../external/ramses/IRamsesV2NonfungiblePositionManager.sol";
import "../external/ramses/IRamsesV2Pool.sol";

interface IRamsesV2Vault is IERC721Receiver, IIntegrationVault {
    struct Options {
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    function positionManager() external view returns (IRamsesV2NonfungiblePositionManager);

    function pool() external view returns (IRamsesV2Pool);

    function erc20Vault() external view returns (address);

    function positionId() external view returns (uint256);

    function liquidityToTokenAmounts(uint128 liquidity) external view returns (uint256[] memory tokenAmounts);

    function tokenAmountsToLiquidity(uint256[] memory tokenAmounts) external view returns (uint128 liquidity);

    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        uint24 fee_,
        address helper_,
        address erc20Vault_
    ) external;

    function collectEarnings() external returns (uint256[] memory collectedEarnings);

    function collectRewards() external returns (uint256[] memory collectedRewards);
}
