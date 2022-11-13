// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import { IDegenNFT } from "./IDegenNFT.sol";

interface IDegenDistributorEvents {
    /// @dev Emits when a user claims tokens
    event Claimed(
        address indexed account,
        uint256 amount
    );

    /// @dev Emits when the owner replaces the merkle root
    event RootUpdated(bytes32 oldRoot, bytes32 indexed newRoot);
}

interface IDegenDistributor is IDegenDistributorEvents {
    // Returns the address of the token distributed by this contract.
    function degenNFT() external view returns (IDegenNFT);

    // Returns the merkle root of the merkle tree containing account balances available to claim.
    function merkleRoot() external view returns (bytes32);

    /// @dev Returns the total amount of token claimed by the user
    function claimed(address user) external view returns (uint256);

    // Claim the given amount of the token to the given address. Reverts if the inputs are invalid.
    /// @dev Claims the remaining unclaimed amount of the token for the account. Reverts if the inputs are not a leaf in the tree
    ///      or the total claimed amount for the account is more than the leaf amount.
    function claim(
        uint256 index,
        address account,
        uint256 totalAmount,
        bytes32[] calldata merkleProof
    ) external;
}

