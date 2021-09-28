// SPDX-License-Identifier: MIT
pragma solidity 0.8.8;

import "./access/GovernanceAccessControl.sol";
import "./VaultsGovernance.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// TODO: Move back to NodeCells

abstract contract PermissionedERC721Receiver is IERC721Receiver, GovernanceAccessControl, VaultsGovernance {
    /// -------------------  PUBLIC, MUTATING, NFT_ALLOW_LIST  -------------------

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external virtual override returns (bytes4) {
        // Only a handful of contracts can send nfts here
        // You have to carefully verify that contract sending callback correctly satisfies the ERC721 protocol
        // Most critically so that operator could not be forged
        // Otherwise cells could be flooded with unnecessary nfts
        // require(nftAllowListIndex[_msgSender()], "IMS");
        return _onPermissionedERC721Received(operator, from, tokenId, data);
    }

    /// -------------------  PRIVATE, MUTATING  -------------------

    function _onPermissionedERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) internal virtual returns (bytes4);
}
