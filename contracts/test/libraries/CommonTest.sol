// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../../libraries/CommonLibrary.sol";

contract CommonTest {
    function sortUint(uint256[] memory arr) external pure returns (uint256[] memory) {
        CommonLibrary.sortUint(arr);
        return arr;
    }

    function isSortedAndUnique(address[] memory tokens) external pure returns (bool) {
        return CommonLibrary.isSortedAndUnique(tokens);
    }

    function projectTokenAmounts(
        address[] memory tokens,
        address[] memory tokensToProject,
        uint256[] memory tokenAmountsToProject
    ) external pure returns (uint256[] memory) {
        return CommonLibrary.projectTokenAmounts(tokens, tokensToProject, tokenAmountsToProject);
    }

    function sqrtX96(uint256 xX96) external pure returns (uint256) {
        return CommonLibrary.sqrtX96(xX96);
    }

    function sqrt(uint256 x) external pure returns (uint256) {
        return CommonLibrary.sqrt(x);
    }

    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature) external pure returns (address) {
        return CommonLibrary.recoverSigner(_ethSignedMessageHash, _signature);
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
}
