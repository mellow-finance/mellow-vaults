// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../interfaces/vaults/ISqueethVaultGovernance.sol";
import "../interfaces/external/squeeth/IController.sol";
import "../interfaces/external/squeeth/IShortPowerPerp.sol";
import "../interfaces/external/squeeth/IWPowerPerp.sol";
import "../interfaces/external/squeeth/IWETH9.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/vaults/ISqueethVault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";

/// @notice Vault that interfaces Opyn Squeeth protocol in the integration layer.
contract SqueethVault is ISqueethVault, IERC721Receiver, ReentrancyGuard, IntegrationVault {
    uint256 public DUST = 10**3;

    struct ShortPositionInfo {
        uint256 vaultId;
        uint256 wPowerPerpAmount;
    }

    struct LongPositionInfo {
        uint256 wPowerPerpAmount;
    }

    bool private isShortPosition;

    ShortPositionInfo private shortPositionInfo;
    LongPositionInfo private longPositionInfo;

    IController private controller;
    ISwapRouter private router;

    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {}

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return IntegrationVault.supportsInterface(interfaceId) || interfaceId == type(ISqueethVault).interfaceId;
    }

    /// @inheritdoc ISqueethVault
    function initialize(uint256 nft_, bool isShortPosition_) external {
        controller = ISqueethVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().controller;
        router = ISqueethVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().router;
        _vaultTokens = [controller.wPowerPerp(), controller.weth()];
        _initialize(_vaultTokens, nft_);
        isShortPosition = isShortPosition_;
    }

    function takeShort(
        uint256 wPowerPerpAmountExpected,
        uint256 wethDebtAmount,
        uint256 minWethAmountOut
    ) external payable nonReentrant returns (uint256 wPowerPerpMintedAmount, uint256 wethAmountOut) {
        require(isShortPosition, ExceptionsLibrary.INVALID_STATE);
        require(wethDebtAmount > DUST, ExceptionsLibrary.VALUE_ZERO);

        uint256 shortVaultId = shortPositionInfo.vaultId;
        if (shortVaultId != 0) {
            // short position has already been taken
            require(
                IShortPowerPerp(controller.shortPowerPerp()).ownerOf(shortVaultId) == msg.sender,
                ExceptionsLibrary.FORBIDDEN
            );
        }

        (uint256 vaultId, uint256 actualWPowerPerpAmount) = controller.mintPowerPerpAmount{value: wethDebtAmount}(
            shortVaultId,
            wPowerPerpAmountExpected,
            0
        );

        wPowerPerpMintedAmount = actualWPowerPerpAmount;

        address wPowerPerp = controller.wPowerPerp();
        address weth = controller.weth();
        address shortPowerPerp = controller.shortPowerPerp();

        ISwapRouter.ExactInputSingleParams memory exactInputParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: wPowerPerp,
            tokenOut: weth,
            fee: IUniswapV3Pool(controller.ethQuoteCurrencyPool()).fee(),
            recipient: msg.sender,
            deadline: block.timestamp + 1,
            amountIn: wPowerPerpMintedAmount,
            amountOutMinimum: minWethAmountOut,
            sqrtPriceLimitX96: 0
        });

        wethAmountOut = router.exactInputSingle(exactInputParams);

        if (vaultId == 0) {
            // if a new short vault has been created
            IShortPowerPerp(payable(shortPowerPerp)).safeTransferFrom(address(this), msg.sender, vaultId);
        }
        shortPositionInfo.vaultId = vaultId;
    }

    function closeShort(uint256 wPowerPerpBurnAmount, uint256 maxWethAmountIn)
        external
        payable
        nonReentrant
        returns (uint256 wethAmountReceived)
    {
        uint256 shortVaultId = shortPositionInfo.vaultId;
        require(
            IShortPowerPerp(controller.shortPowerPerp()).ownerOf(shortVaultId) == msg.sender,
            ExceptionsLibrary.FORBIDDEN
        );

        address wPowerPerp = controller.wPowerPerp();
        address weth = controller.weth();
        address shortPowerPerp = controller.shortPowerPerp();

        ISwapRouter.ExactOutputSingleParams memory exactOutputParams = ISwapRouter.ExactOutputSingleParams({
            tokenIn: weth,
            tokenOut: wPowerPerp,
            fee: IUniswapV3Pool(controller.ethQuoteCurrencyPool()).fee(),
            recipient: msg.sender,
            deadline: block.timestamp + 1,
            amountOut: wPowerPerpBurnAmount,
            amountInMaximum: maxWethAmountIn,
            sqrtPriceLimitX96: 0
        });

        // pay weth and get wPowerPerp in return.
        uint256 actualWethAmountIn = router.exactOutputSingle(exactOutputParams);
        controller.burnWPowerPerpAmount(shortVaultId, wPowerPerpBurnAmount, actualWethAmountIn);
        uint256 wethVaultBalance = IWETH9(weth).balanceOf(address(this));
        IWETH9(weth).transfer(msg.sender, wethVaultBalance);
    }

    function takeLong(uint256 wethAmount, uint256 minWPowerPerpAmountOut) external {
        // buy wPowerPerp with swap router
    }

    function closeLong(uint256 wPowerPerpAmount, uint256 maxWethAmountIn) external {
        // buy wPowerPerp with swap router
    }

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {}

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {}

    function _isReclaimForbidden(address token) internal view override returns (bool) {
        if (token == address(controller.weth()) || token == controller.wPowerPerp()) {
            return true;
        }
        return false;
    }

    receive() external payable {
        require(msg.sender == controller.weth() || msg.sender == address(controller), ExceptionsLibrary.INVALID_TOKEN);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
