// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./access/GovernanceAccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract PermissionedERC721Receiver is IERC721Receiver, GovernanceAccessControl {
    address[] public nftAllowList;
    mapping(address => bool) public nftAllowListIndex;

    function addNftAllowedTokens(address[] calldata tokens) external {
        require(_isGovernanceOrDelegate(), "GD");
        for (uint256 i = 0; i < tokens.length; i++) {
            if (nftAllowListIndex[tokens[i]]) {
                continue;
            }
            nftAllowList.push(tokens[i]);
            nftAllowListIndex[tokens[i]] = true;
        }
    }

    function removeNftAllowedToken(address token) external {
        require(_isGovernanceOrDelegate(), "GD");
        nftAllowListIndex[token] = false;
    }

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
        require(nftAllowListIndex[_msgSender()], "IMS");
        return _onPermissionedERC721Received(operator, from, tokenId, data);
    }

    function _onPermissionedERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) internal virtual returns (bytes4) {}
}
