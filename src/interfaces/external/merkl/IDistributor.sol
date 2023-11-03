// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

struct MerkleTree {
    // Root of a Merkle tree which leaves are `(address user, address token, uint amount)`
    // representing an amount of tokens accumulated by `user`.
    // The Merkle tree is assumed to have only increasing amounts: that is to say if a user can claim 1,
    // then after the amount associated in the Merkle tree for this token should be x > 1
    bytes32 merkleRoot;
    // Ipfs hash of the tree data
    bytes32 ipfsHash;
}

struct Claim {
    uint208 amount;
    uint48 timestamp;
    bytes32 merkleRoot;
}

interface IDistributor {
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;
}
