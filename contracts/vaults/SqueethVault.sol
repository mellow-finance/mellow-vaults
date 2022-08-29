// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/FullMath.sol";

import "../interfaces/vaults/ISqueethVaultGovernance.sol";
import "../interfaces/external/squeeth/IController.sol";
import "../interfaces/external/squeeth/IShortPowerPerp.sol";
import "../interfaces/external/squeeth/IWPowerPerp.sol";
import "../interfaces/external/squeeth/IWETH9.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/vaults/ISqueethVault.sol";
import "./IntegrationVault.sol";
import "hardhat/console.sol";

/// @notice Vault that interfaces Opyn Squeeth protocol in the integration layer.
contract SqueethVault is ISqueethVault, IERC721Receiver, ReentrancyGuard, IntegrationVault {
    using SafeERC20 for IERC20;
    uint256 public immutable DUST = 10**3;

    bool private _isShortPosition;

    ShortPositionInfo private _shortPositionInfo;
    LongPositionInfo private _longPositionInfo;

    IController private _controller;
    ISwapRouter private _router;

    address private _wPowerPerp;
    address private _weth;
    address private _shortPowerPerp;

    uint256 public immutable squeethMinCollateral = 69 * 10**17;

    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {}

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return IntegrationVault.supportsInterface(interfaceId) || interfaceId == type(ISqueethVault).interfaceId;
    }

    // // fix
    // function write() external view returns (bytes4) {
    //     return type(ISqueethVault).interfaceId;
    // }

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
        uint256 wethDebtAmount,
        uint256 minWethAmountOut
    ) external payable nonReentrant returns (uint256 wPowerPerpMintedAmount, uint256 wethAmountOut) {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        require(_isShortPosition, ExceptionsLibrary.INVALID_STATE);
        require(wethDebtAmount > DUST, ExceptionsLibrary.VALUE_ZERO);
        require(IWETH9(_weth).balanceOf(msg.sender) >= wethDebtAmount, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(IWETH9(_weth).allowance(msg.sender, address(this)) >= wethDebtAmount, ExceptionsLibrary.FORBIDDEN);
        require(wethDebtAmount >= squeethMinCollateral, ExceptionsLibrary.LIMIT_UNDERFLOW);

        IWETH9(_weth).transferFrom(msg.sender, address(this), wethDebtAmount);
        IWETH9(_weth).withdraw(wethDebtAmount);

        uint256 shortVaultId = _shortPositionInfo.vaultId;
        if (shortVaultId != 0) {
            // short position has already been taken
            require(
                IShortPowerPerp(_controller.shortPowerPerp()).ownerOf(shortVaultId) == msg.sender,
                ExceptionsLibrary.FORBIDDEN
            );
        }

        (uint256 vaultId, uint256 actualWPowerPerpAmount) = _controller.mintPowerPerpAmount{value: wethDebtAmount}(
            shortVaultId,
            wPowerPerpAmountExpected,
            0
        );

        wPowerPerpMintedAmount = actualWPowerPerpAmount;

        ISwapRouter.ExactInputSingleParams memory exactInputParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: _wPowerPerp,
            tokenOut: _weth,
            fee: IUniswapV3Pool(_controller.ethQuoteCurrencyPool()).fee(),
            recipient: address(this),
            deadline: block.timestamp + 1,
            amountIn: wPowerPerpMintedAmount,
            amountOutMinimum: minWethAmountOut,
            sqrtPriceLimitX96: 0
        });

        IERC20(_wPowerPerp).safeIncreaseAllowance(address(_router), wPowerPerpMintedAmount);
        wethAmountOut = _router.exactInputSingle(exactInputParams);
        IERC20(_wPowerPerp).safeApprove(address(_router), 0);

        // there should not be any locked ether inside the contract
        uint256 ethLockedAmount = address(this).balance;
        IWETH9(_weth).deposit{value: ethLockedAmount}();
        // transfer weth received after selling wPowerPerp back to msg.sender
        IWETH9(_weth).transfer(msg.sender, ethLockedAmount);

        _shortPositionInfo.vaultId = vaultId;
        _shortPositionInfo.wPowerPerpAmount += wPowerPerpMintedAmount;
        _shortPositionInfo.wethAmount += wethAmountOut;

        emit ShortTaken(tx.origin, msg.sender, _shortPositionInfo);
    }

    function closeShort(
        uint256 wPowerPerpBurnAmount,
        uint256 ethAmountIn,
        uint256 maxWethAmountIn
    ) external payable nonReentrant returns (uint256 ethAmountReceived) {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
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

        emit ShortClosed(tx.origin, msg.sender, _shortPositionInfo);
    }

    function takeLong(uint256 wethAmount, uint256 minWPowerPerpAmountOut)
        external
        nonReentrant
        returns (uint256 wPowerPerpAmountOut)
    {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        require(!_isShortPosition, ExceptionsLibrary.INVALID_STATE);
        require(wethAmount > DUST, ExceptionsLibrary.VALUE_ZERO);
        require(IWETH9(_weth).balanceOf(msg.sender) >= wethAmount, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(IWETH9(_weth).allowance(msg.sender, address(this)) >= wethAmount, ExceptionsLibrary.FORBIDDEN);

        IWETH9(_weth).transferFrom(msg.sender, address(this), wethAmount);

        ISwapRouter.ExactInputSingleParams memory exactInputParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: _weth,
            tokenOut: _wPowerPerp,
            fee: IUniswapV3Pool(_controller.ethQuoteCurrencyPool()).fee(),
            recipient: address(this),
            deadline: block.timestamp + 1,
            amountIn: wethAmount,
            amountOutMinimum: minWPowerPerpAmountOut,
            sqrtPriceLimitX96: 0
        });

        IERC20(_weth).safeIncreaseAllowance(address(_router), wethAmount);
        wPowerPerpAmountOut = _router.exactInputSingle(exactInputParams);
        IERC20(_weth).safeApprove(address(_router), 0);

        _longPositionInfo.wPowerPerpAmount += wPowerPerpAmountOut;
        emit LongTaken(tx.origin, msg.sender, _longPositionInfo);
    }

    function closeLong(uint256 wPowerPerpAmount, uint256 minWethAmountOut)
        external
        nonReentrant
        returns (uint256 wethAmountOut)
    {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        require(!_isShortPosition, ExceptionsLibrary.INVALID_STATE);
        require(wPowerPerpAmount > DUST, ExceptionsLibrary.VALUE_ZERO);
        require(
            IWPowerPerp(_wPowerPerp).balanceOf(address(this)) >= wPowerPerpAmount,
            ExceptionsLibrary.LIMIT_OVERFLOW
        );

        ISwapRouter.ExactInputSingleParams memory exactInputParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: _wPowerPerp,
            tokenOut: _weth,
            fee: IUniswapV3Pool(_controller.ethQuoteCurrencyPool()).fee(),
            recipient: address(this),
            deadline: block.timestamp + 1,
            amountIn: wPowerPerpAmount,
            amountOutMinimum: minWethAmountOut,
            sqrtPriceLimitX96: 0
        });

        IERC20(_wPowerPerp).safeIncreaseAllowance(address(_router), wPowerPerpAmount);
        wethAmountOut = _router.exactInputSingle(exactInputParams);
        IERC20(_wPowerPerp).safeIncreaseAllowance(address(_router), 0);

        IWETH9(_weth).transfer(msg.sender, wethAmountOut);

        _longPositionInfo.wPowerPerpAmount -= wPowerPerpAmount;
        emit LongClosed(tx.origin, msg.sender, _longPositionInfo);
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
        // require(
        //     msg.sender == _controller.weth() || msg.sender == address(_controller) || _isApprovedOrOwner(msg.sender),
        //     ExceptionsLibrary.FORBIDDEN
        // );
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

    function longPositionInfo() external view returns (LongPositionInfo memory) {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        require(!_isShortPosition, ExceptionsLibrary.INVALID_STATE);
        return _longPositionInfo;
    }

    function shortPositionInfo() external view returns (ShortPositionInfo memory) {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        require(_isShortPosition, ExceptionsLibrary.INVALID_STATE);
        return _shortPositionInfo;
    }

    function getTwapIndexPrice(uint32 twapPeriod_) external view returns (uint256 twapIndexPrice) {
        require(twapPeriod_ > 0, ExceptionsLibrary.VALUE_ZERO);
        twapIndexPrice = _controller.getUnscaledIndex(twapPeriod_);
    }

    function getTwapMarkPrice(uint32 twapPeriod_) external view returns (uint256 twapMarkPrice) {
        require(twapPeriod_ > 0, ExceptionsLibrary.VALUE_ZERO);
        twapMarkPrice = _controller.getDenormalizedMark(twapPeriod_);
    }

    function getSpotSqrtPrice() external view returns (uint256 usdcWPowerPerpPriceX96) {
        IUniswapV3Pool ethQuoteCurrencyPool = IUniswapV3Pool(_controller.ethQuoteCurrencyPool());
        IUniswapV3Pool wPowerPerpPool = IUniswapV3Pool(_controller.wPowerPerpPool());

        (uint160 usdcWethSqrtPriceX96, , , , , , ) = ethQuoteCurrencyPool.slot0();
        (uint160 wethWPowerPerpSqrtPriceX96, , , , , , ) = wPowerPerpPool.slot0();

        usdcWPowerPerpPriceX96 = FullMath.mulDiv(usdcWethSqrtPriceX96, wethWPowerPerpSqrtPriceX96, CommonLibrary.Q96);
    }

    function getSqrtIndexPrice() external view returns (uint256 usdcWethSqrtPriceX96) {
        IUniswapV3Pool ethQuoteCurrencyPool = IUniswapV3Pool(_controller.ethQuoteCurrencyPool());
        (usdcWethSqrtPriceX96, , , , , , ) = ethQuoteCurrencyPool.slot0();
    }

    // --------------------------  EVENTS  --------------------------

    event LongTaken(address indexed origin, address indexed sender, LongPositionInfo longPositionInfo);

    event LongClosed(address indexed origin, address indexed sender, LongPositionInfo longPositionInfo);

    event ShortTaken(address indexed origin, address indexed sender, ShortPositionInfo shortPositionInfo);

    event ShortClosed(address indexed origin, address indexed sender, ShortPositionInfo shortPositionInfo);
}
