// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./interfaces/ITokenCells.sol";
import "./libraries/Array.sol";
import "./Cells.sol";
import "./interfaces/external/INonfungiblePositionManager.sol";

contract UniV3Cells is IDelegatedCells, Cells {
    INonfungiblePositionManager public positionManager;

    constructor(
        INonfungiblePositionManager _positionManager,
        string memory name,
        string memory symbol
    ) Cells(name, symbol) {
        positionManager = _positionManager;
    }

    function delegated(uint256 nft) external view returns (address[] memory tokens, uint256[] memory tokenAmounts);

    function _mintCellNft(address[] memory tokens, bytes memory params) internal virtual override returns (uint256) {
        require(params.length == 8 * 32, "IP");
        require(tokens.length == 2, "TL");
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
        assembly {
            fee := mload(add(params, 32))
            tickLower := mload(add(params, 64))
            tickUpper := mload(add(params, 96))
            amount0Desired := mload(add(params, 128))
            amount1Desired := mload(add(params, 160))
            amount0Min := mload(add(params, 192))
            amount1Min := mload(add(params, 224))
            deadline := mload(add(params, 256))
        }

        (uint256 cellNft, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: tokens[0],
                token1: tokens[1],
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                recipient: _msgSender(),
                deadline: deadline
            })
        );
        return cellNft;
    }
}
