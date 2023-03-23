// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/utils/ISwapper.sol";

contract InchSwapper is ISwapper {
    using SafeERC20 for IERC20;

    address public immutable router;
    
    constructor(
        address router_
    ) {
        router = router_;
    }

    function swap(address token0, address token1, uint256 amountIn, uint256 minAmountOut, bytes memory data) external returns (uint256) {

        IERC20(token0).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(token0).safeIncreaseAllowance(router, amountIn);

        uint256 balanceBefore = IERC20(token1).balanceOf(address(this));

        (bool res, bytes memory returndata) = router.call(data);

        if (!res) {
            assembly {
                let returndata_size := mload(returndata)
                // Bubble up revert reason
                revert(add(32, returndata), returndata_size)
            }
        }

        uint256 balanceAfter = IERC20(token1).balanceOf(address(this));
        require(balanceAfter - balanceBefore >= minAmountOut, ExceptionsLibrary.LIMIT_UNDERFLOW);

        IERC20(token0).safeApprove(router, 0);
        IERC20(token1).safeTransfer(msg.sender, balanceAfter);

        return balanceAfter;

    }

    
}
