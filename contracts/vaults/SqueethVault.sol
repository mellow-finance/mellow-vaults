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

    bool private _isShortPosition;

    ShortPositionInfo private _shortPositionInfo;
    LongPositionInfo private _longPositionInfo;

    IController private _controller;
    ISwapRouter private _router;

    address private _wPowerPerp;
    address private _weth;
    address private _shortPowerPerp;

    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {}

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return IntegrationVault.supportsInterface(interfaceId) || interfaceId == type(ISqueethVault).interfaceId;
    }

    /// @inheritdoc ISqueethVault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        bool isShortPosition_
    ) external {
        require(vaultTokens_.length == 2, ExceptionsLibrary.INVALID_LENGTH);
        _initialize(vaultTokens_, nft_);
        _controller = ISqueethVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().controller;
        _router = ISqueethVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().router;

        _wPowerPerp = _controller.wPowerPerp();
        _weth = _controller.weth();
        _shortPowerPerp = _controller.shortPowerPerp();

        require(vaultTokens_[0] == _weth || vaultTokens_[0] == _wPowerPerp, ExceptionsLibrary.INVALID_TOKEN);
        require(vaultTokens_[1] == _weth || vaultTokens_[1] == _wPowerPerp, ExceptionsLibrary.INVALID_TOKEN);
        _isShortPosition = isShortPosition_;
    }

    function takeShort(
        uint256 wPowerPerpAmountExpected,
        uint256 ethDebtAmount,
        uint256 minWethAmountOut
    ) external payable nonReentrant returns (uint256 wPowerPerpMintedAmount, uint256 wethAmountOut) {
        require(_isShortPosition, ExceptionsLibrary.INVALID_STATE);
        require(ethDebtAmount > DUST, ExceptionsLibrary.VALUE_ZERO);

        uint256 shortVaultId = _shortPositionInfo.vaultId;
        if (shortVaultId != 0) {
            // short position has already been taken
            require(
                IShortPowerPerp(_controller.shortPowerPerp()).ownerOf(shortVaultId) == msg.sender,
                ExceptionsLibrary.FORBIDDEN
            );
        }

        (uint256 vaultId, uint256 actualWPowerPerpAmount) = _controller.mintPowerPerpAmount{value: ethDebtAmount}(
            shortVaultId,
            wPowerPerpAmountExpected,
            0
        );

        wPowerPerpMintedAmount = actualWPowerPerpAmount;

        ISwapRouter.ExactInputSingleParams memory exactInputParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: _wPowerPerp,
            tokenOut: _weth,
            fee: IUniswapV3Pool(_controller.ethQuoteCurrencyPool()).fee(),
            recipient: msg.sender,
            deadline: block.timestamp + 1,
            amountIn: wPowerPerpMintedAmount,
            amountOutMinimum: minWethAmountOut,
            sqrtPriceLimitX96: 0
        });

        wethAmountOut = _router.exactInputSingle(exactInputParams);

        IWETH9(_weth).withdraw(wethAmountOut);
        payable(msg.sender).transfer(wethAmountOut);

        if (vaultId == 0) {
            // if a new short vault has been created
            IShortPowerPerp(payable(_shortPowerPerp)).safeTransferFrom(address(this), msg.sender, vaultId);
        }
        _shortPositionInfo.vaultId = vaultId;
    }

    function closeShort(
        uint256 wPowerPerpBurnAmount,
        uint256 ethAmountIn,
        uint256 maxWethAmountIn
    ) external payable nonReentrant returns (uint256 ethAmountReceived) {
        require(_isShortPosition, ExceptionsLibrary.INVALID_STATE);
        require(wPowerPerpBurnAmount > DUST, ExceptionsLibrary.VALUE_ZERO);
        uint256 shortVaultId = _shortPositionInfo.vaultId;
        require(
            IShortPowerPerp(_controller.shortPowerPerp()).ownerOf(shortVaultId) == msg.sender,
            ExceptionsLibrary.FORBIDDEN
        );

        // wrap eth to _weth
        IWETH9(_weth).deposit{value: ethAmountIn}();

        ISwapRouter.ExactOutputSingleParams memory exactOutputParams = ISwapRouter.ExactOutputSingleParams({
            tokenIn: _weth,
            tokenOut: _wPowerPerp,
            fee: IUniswapV3Pool(_controller.ethQuoteCurrencyPool()).fee(),
            recipient: msg.sender,
            deadline: block.timestamp + 1,
            amountOut: wPowerPerpBurnAmount,
            amountInMaximum: maxWethAmountIn,
            sqrtPriceLimitX96: 0
        });

        // pay _weth and get _wPowerPerp in return.
        uint256 actualWethAmountIn = _router.exactOutputSingle(exactOutputParams);

        // burn wPowerPerpBurnAmount and expect to receive actualWethAmountIn (the amount of eth, that we sent to UniV3 pool while buying _wPowerPerp back)
        _controller.burnWPowerPerpAmount(shortVaultId, wPowerPerpBurnAmount, actualWethAmountIn);

        // send back unused eth and withdrawn collateral
        IWETH9(_weth).withdraw(ethAmountIn - actualWethAmountIn);

        ethAmountReceived = address(this).balance;
        payable(msg.sender).transfer(ethAmountReceived);
    }

    function takeLong(uint256 wethAmount, uint256 minWPowerPerpAmountOut)
        external
        returns (uint256 wPowerPerpAmountOut)
    {
        require(!_isShortPosition, ExceptionsLibrary.INVALID_STATE);
        require(wethAmount > DUST, ExceptionsLibrary.VALUE_ZERO);

        ISwapRouter.ExactInputSingleParams memory exactInputParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: _weth,
            tokenOut: _wPowerPerp,
            fee: IUniswapV3Pool(_controller.ethQuoteCurrencyPool()).fee(),
            recipient: msg.sender,
            deadline: block.timestamp + 1,
            amountIn: wethAmount,
            amountOutMinimum: minWPowerPerpAmountOut,
            sqrtPriceLimitX96: 0
        });

        wPowerPerpAmountOut = _router.exactInputSingle(exactInputParams);
    }

    function closeLong(uint256 wPowerPerpAmount, uint256 maxWethAmountIn) external returns (uint256 wethAmountIn) {
        require(!_isShortPosition, ExceptionsLibrary.INVALID_STATE);
        require(wPowerPerpAmount > DUST, ExceptionsLibrary.VALUE_ZERO);

        ISwapRouter.ExactOutputSingleParams memory exactOutputParams = ISwapRouter.ExactOutputSingleParams({
            tokenIn: _weth,
            tokenOut: _wPowerPerp,
            fee: IUniswapV3Pool(_controller.ethQuoteCurrencyPool()).fee(),
            recipient: msg.sender,
            deadline: block.timestamp + 1,
            amountOut: wPowerPerpAmount,
            amountInMaximum: maxWethAmountIn,
            sqrtPriceLimitX96: 0
        });

        wethAmountIn = _router.exactOutputSingle(exactOutputParams);
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
        if (token == address(_controller.weth()) || token == _controller.wPowerPerp()) {
            return true;
        }
        return false;
    }

    receive() external payable {
        require(
            msg.sender == _controller.weth() || msg.sender == address(_controller),
            ExceptionsLibrary.INVALID_TOKEN
        );
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function controller() external view returns (IController) {
        return _controller;
    }

    function router() external view returns (ISwapRouter) {
        return _router;
    }
}
