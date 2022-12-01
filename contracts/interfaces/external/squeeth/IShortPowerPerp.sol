// SPDX-License-Identifier: MIT

pragma solidity =0.8.9;
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IShortPowerPerp is IERC721 {
    function nextId() external view returns (uint256);

    function mintNFT(address recipient) external returns (uint256 _newId);
}
