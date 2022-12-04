// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.9;

import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../interfaces/external/univ3/INonfungiblePositionManager.sol";

contract UniswapV3Token is IERC721Receiver {
    INonfungiblePositionManager public immutable positionManager;
    uint256 public uniV3Nft;
    IUniswapV3Pool public immutable pool;
    bool public isPrivate;
    address[] public approvedList;

    constructor (INonfungiblePositionManager positionManager_, IUniswapV3Pool pool_, bool isPrivate_) {
        positionManager = positionManager_;
        pool = pool_;
        isPrivate = isPrivate_;
    }

    function isApproved(address sender) public view returns (bool) {
        if (!isPrivate) return true;
        for (uint256 i = 0; i < approvedList.length; i++) {
            if (approvedList[i] == sender) {
                return true;
            }
        }
        return false;
    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes memory
    ) external returns (bytes4) {
        require(msg.sender == address(positionManager), ExceptionsLibrary.FORBIDDEN);
        require(isApproved(operator), ExceptionsLibrary.FORBIDDEN);
        (, , address token0, address token1, uint24 fee, , , , , , , ) = positionManager.positions(tokenId);

        require(
            token0 == pool.token0() && token1 == pool.token1() && fee == pool.fee(),
            ExceptionsLibrary.INVALID_TOKEN
        );

        require(
            uniV3Nft == 0,
            ExceptionsLibrary.INVALID_VALUE
        );
        
        uniV3Nft = tokenId;
        
        return this.onERC721Received.selector;
    }


    function totalSupply() public view returns (uint128 supply) {
        if (uniV3Nft == 0) return 0;
        (,,,,,,, supply,,,,) = positionManager.positions(uniV3Nft);
    }

}