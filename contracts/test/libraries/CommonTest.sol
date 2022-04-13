// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../../libraries/CommonLibrary.sol";

contract CommonTest {
    function isSortedAndUnique(address[] memory tokens) external pure returns (bool) {
        return CommonLibrary.isSortedAndUnique(tokens);
    }

    function projectTokenAmountsTest(
        address[] memory tokens,
        address[] memory tokensToProject,
        uint256[] memory tokenAmountsToProject
    ) external pure returns (uint256[] memory) {
        return CommonLibrary.projectTokenAmounts(tokens, tokensToProject, tokenAmountsToProject);
    }

    function splitSignature(bytes memory sig)
        external
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        return CommonLibrary.splitSignature(sig);
    }

    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature) external pure returns (address) {
        return CommonLibrary.recoverSigner(_ethSignedMessageHash, _signature);
    }
}
