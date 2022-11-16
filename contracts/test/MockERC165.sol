// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

contract MockERC165 is ERC165 {
    mapping(bytes4 => bool) private _allowedInterfaceIdsMap;

    function allowInterfaceId(bytes4 interfaceId) public {
        _allowedInterfaceIdsMap[interfaceId] = true;
    }

    function denyInterfaceId(bytes4 interfaceId) public {
        delete _allowedInterfaceIdsMap[interfaceId];
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return _allowedInterfaceIdsMap[interfaceId];
    }
}
