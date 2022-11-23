// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "../interfaces/external/erc/IERC1271.sol";
import "../libraries/CommonLibrary.sol";

contract MockERC1271 is ERC165, IERC1271 {
    address public signer;

    function setSigner(address newSigner) public {
        signer = newSigner;
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return (interfaceId == type(IERC165).interfaceId) || (interfaceId == type(IERC1271).interfaceId);
    }

    function isValidSignature(bytes32 _hash, bytes memory _signature) external view returns (bytes4 magicValue) {
        if (CommonLibrary.recoverSigner(_hash, _signature) == signer) {
            return 0x1626ba7e;
        } else {
            return 0xffffffff;
        }
    }
}
