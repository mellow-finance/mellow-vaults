// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";
import "../external/squeeth/IController.sol";
import "../external/univ3/ISwapRouter.sol";

interface ISqueethVault is IIntegrationVault {
    struct ShortPositionInfo {
        uint256 vaultId;
        uint256 wPowerPerpAmount;
    }

    struct LongPositionInfo {
        uint256 wPowerPerpAmount;
    }

    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    function initialize(uint256 nft_, address[] memory vaultTokens_, bool isShortPosition_) external;

    function takeShort(
        uint256 wPowerPerpAmountExpected,
        uint256 ethDebtAmount,
        uint256 minWethAmountOut
    ) external payable returns (uint256 wPowerPerpMintedAmount, uint256 wethAmountOut);

    function closeShort(
        uint256 wPowerPerpBurnAmount,
        uint256 ethAmountIn,
        uint256 maxWethAmountIn
    ) external payable returns (uint256 ethAmountReceived);

    function takeLong(uint256 wethAmount, uint256 minWPowerPerpAmountOut)
        external
        returns (uint256 wPowerPerpAmountOut);

    function closeLong(uint256 wPowerPerpAmount, uint256 minWethAmountOut) external returns (uint256 wethAmountOut);

    receive() external payable;

    function controller() external view returns (IController);

    function router() external view returns (ISwapRouter);

    function longPositionInfo() external view returns(LongPositionInfo memory);

    function shortPositionInfo() external view returns(ShortPositionInfo memory);
}