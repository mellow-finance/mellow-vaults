// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "../../src/interfaces/external/gearbox/helpers/uniswap/IUniswapV3.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "forge-std/console2.sol";

contract MockSwapRouter is ISwapRouter, Test {

    function toAddress(bytes memory _bytes, uint256 _start) internal pure returns (address) {
        require(_start + 20 >= _start, 'toAddress_overflow');
        require(_bytes.length >= _start + 20, 'toAddress_outOfBounds');
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }

        return tempAddress;
    }

    function toUint24(bytes memory _bytes, uint256 _start) internal pure returns (uint24) {
        require(_start + 3 >= _start, 'toUint24_overflow');
        require(_bytes.length >= _start + 3, 'toUint24_outOfBounds');
        uint24 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x3), _start))
        }

        return tempUint;
    }

    function decodeFirstPool(bytes memory path)
        internal
        pure
        returns (
            address tokenA,
            address tokenB,
            uint24 fee
        )
    {
        tokenA = toAddress(path, 0);
        fee = toUint24(path, 20);
        tokenB = toAddress(path, 23);
    }

    function exactOutput(ExactOutputParams calldata params)
        external
        payable
        returns (uint256 amountIn) 
    {
        uint256 amountOut = params.amountOut;
        uint256 amountInMaximum = params.amountInMaximum;

        address recipient = params.recipient;

        (address tokenFrom, address tokenTo, ) = decodeFirstPool(params.path);

        uint256 balanceA = IERC20(tokenFrom).balanceOf(recipient);
        uint256 balanceB = IERC20(tokenTo).balanceOf(recipient);

        deal(tokenFrom, recipient, balanceA - amountInMaximum);
        deal(tokenTo, recipient, balanceB + amountOut);
    }

    function exactInput(ExactInputParams calldata params)
        external
        payable
        returns (uint256 amountOut) {
            uint256 amountOut = params.amountOutMinimum;
            uint256 amountInMaximum = params.amountIn;

            address recipient = params.recipient;

            (address tokenFrom, address tokenTo, ) = decodeFirstPool(params.path);

            uint256 balanceA = IERC20(tokenFrom).balanceOf(recipient);
            uint256 balanceB = IERC20(tokenTo).balanceOf(recipient);

            deal(tokenFrom, recipient, balanceA - amountInMaximum);
            deal(tokenTo, recipient, balanceB + amountOut);
        }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut) {

        }
    
    function exactOutputSingle(ExactOutputSingleParams calldata params)
        external
        payable
        returns (uint256 amountIn) {
            
        }
}
