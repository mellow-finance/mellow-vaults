// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.9;
pragma abicoder v2;

// Interfaces
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ISwapRouter} from "../univ3/ISwapRouter.sol";

import {IWPowerPerp} from "./IWPowerPerp.sol";
import {IWETH9} from "./IWETH9.sol";
import {IShortPowerPerp} from "./IShortPowerPerp.sol";
import {IController} from "./IController.sol";

interface ISqueethShortHelper is IERC721Receiver {
    /**
     * @notice mint power perp, trade with uniswap v3 and send back premium in eth
     * @param _vaultId short wPowerPerp vault id
     * @param _powerPerpAmount amount of powerPerp to mint/sell
     * @param _uniNftId uniswap v3 position token id
     */
    function openShort(
        uint256 _vaultId,
        uint256 _powerPerpAmount,
        uint256 _uniNftId,
        ISwapRouter.ExactInputSingleParams memory _exactInputParams
    ) external payable;

    /**
     * @notice buy back wPowerPerp with eth on uniswap v3 and close position
     * @param _vaultId short wPowerPerp vault id
     * @param _wPowerPerpAmount amount of wPowerPerp to burn
     * @param _withdrawAmount amount to withdraw
     */
    function closeShort(
        uint256 _vaultId,
        uint256 _wPowerPerpAmount,
        uint256 _withdrawAmount,
        ISwapRouter.ExactOutputSingleParams memory _exactOutputParams
    ) external payable;

    /**
     * @dev only receive eth from weth contract and controller.
     */
    receive() external payable;

    function controller() external view returns (IController);
    function router() external view returns (ISwapRouter);
    function weth() external view returns (IWETH9);
    function shortPowerPerp() external view returns (IShortPowerPerp);
    function wPowerPerp() external view returns (address);
}
