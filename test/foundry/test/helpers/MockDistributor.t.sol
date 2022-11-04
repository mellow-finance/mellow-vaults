// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "../../src/interfaces/IDegenDistributor.sol";
import "./Constants.t.sol";
import "forge-std/Test.sol";

contract MockDegenDistributor is IDegenDistributor, Test {

    IDegenNFT nft = IDegenNFT(0xB829a5b349b01fc71aFE46E50dD6Ec0222A6E599);

    mapping(address => uint256) public claimed;

    function degenNFT() external view returns (IDegenNFT) {

    }

    // Returns the merkle root of the merkle tree containing account balances available to claim.
    function merkleRoot() external view returns (bytes32) {

    }

    // Claim the given amount of the token to the given address. Reverts if the inputs are invalid.
    /// @dev Claims the remaining unclaimed amount of the token for the account. Reverts if the inputs are not a leaf in the tree
    ///      or the total claimed amount for the account is more than the leaf amount.
    function claim(
        uint256 index,
        address account,
        uint256 totalAmount,
        bytes32[] calldata merkleProof
    ) external {
        require(
            claimed[account] < totalAmount,
            "MerkleDistributor: Nothing to claim"
        );
        require(merkleProof[0] == DegenConstants.DEGEN);
        nft.mint(account, totalAmount - claimed[account]);
        claimed[account] = totalAmount;
    }
}
