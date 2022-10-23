// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IUniswapV3FlashCallback} from '../interfaces/external/univ3/IUniswapV3FlashCallback.sol';
import {PeripheryPayments} from '../utils/PeripheryPayments.sol';
import {PeripheryImmutableState} from '../utils/PeripheryImmutableState.sol';

import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/PoolAddress.sol";
import "../libraries/external/CallbackValidation.sol";

import "../interfaces/vaults/ISqueethVaultGovernance.sol";
import "../interfaces/external/squeeth/IController.sol";
import "../interfaces/external/squeeth/IShortPowerPerp.sol";
import "../interfaces/external/squeeth/IWPowerPerp.sol";
import "../interfaces/external/squeeth/IWETH9.sol";
import "../interfaces/vaults/ISqueethVault.sol";
import "./IntegrationVault.sol";

/// @notice Vault that interfaces Opyn Squeeth protocol in the integration layer.
contract SqueethVault is ISqueethVault, IERC721Receiver, ReentrancyGuard, IntegrationVault, IUniswapV3FlashCallback, PeripheryImmutableState, PeripheryPayments {
    using SafeERC20 for IERC20;
    uint256 public immutable DUST = 10**3;


    IController public controller;
    ISwapRouter public router;

    address public wPowerPerp;
    address public weth;
    address public shortPowerPerp;
    address public wPowerPerpPool;

    uint256 public immutable squeethMinCollateral = 69 * 10**17;
    uint256 public shortVaultId;
    uint256 private _totalCollateral;
    uint256 private _wPowerPerpDebt;
    
    constructor(
        address _factory,
        address WETH9
    ) PeripheryImmutableState(_factory, WETH9) {

    }

    // -------------------  EXTERNAL, VIEW  -------------------

    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        minTokenAmounts[0] = IERC20(weth).balanceOf(address(this));
        if (shortVaultId != 0) {
            minTokenAmounts[0] += _totalCollateral;
            uint256 currentDebt = _wPowerPerpDebt - IERC20(wPowerPerp).balanceOf(address(this));
            minTokenAmounts[0] -= FullMath.mulDiv(currentDebt, _grabPriceX96(wPowerPerp, wPowerPerpPool), CommonLibrary.Q96);
        }
        maxTokenAmounts = minTokenAmounts; //TODO: unvi3 logic
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return IntegrationVault.supportsInterface(interfaceId) || interfaceId == type(ISqueethVault).interfaceId;
    }


    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_
    ) external {
        require(vaultTokens_.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        _initialize(vaultTokens_, nft_);
        ISqueethVaultGovernance.DelayedProtocolParams memory protocolParams = ISqueethVaultGovernance(address(_vaultGovernance)).delayedProtocolParams();
        controller = protocolParams.controller;
        router = protocolParams.router;

        wPowerPerp = protocolParams.controller.wPowerPerp();
        weth = protocolParams.controller.weth();
        shortPowerPerp = protocolParams.controller.shortPowerPerp();

        shortVaultId = 0; // maybe delete later
        require(vaultTokens_[0] == weth, ExceptionsLibrary.INVALID_TOKEN);
    }

    function takeShort(
        uint256 healthFactor
    ) external nonReentrant {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN); 
        require(healthFactor > CommonLibrary.DENOMINATOR, ExceptionsLibrary.INVARIANT);
        require(shortVaultId == 0, ExceptionsLibrary.INVALID_STATE);
        uint256 wethAmount = IWETH9(weth).balanceOf(address(this));
        require(wethAmount >= squeethMinCollateral, ExceptionsLibrary.LIMIT_UNDERFLOW); //TODO: doublecheck

        IWETH9(weth).withdraw(wethAmount);
        uint256 ethPrice = twapIndexPrice(); 
        uint256 collateralFactor = FullMath.mulDiv(healthFactor, 3, 2);
        uint256 ethPriceNormalized = FullMath.mulDiv(ethPrice, controller.getExpectedNormalizationFactor(), CommonLibrary.D18);
        uint256 wPowerPerpAmountExpected = FullMath.mulDiv(wethAmount, collateralFactor, ethPriceNormalized);
        (uint256 vaultId, uint256 actualWPowerPerpAmount) = controller.mintPowerPerpAmount{value: wethAmount}(
            0,
            wPowerPerpAmountExpected,
            0
        );

        shortVaultId = vaultId;
        _totalCollateral += wethAmount;
        _wPowerPerpDebt += actualWPowerPerpAmount;

        emit ShortTaken(tx.origin, msg.sender); //TODO: add data
    }

    function closeShort() external nonReentrant {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        require(
            IShortPowerPerp(shortPowerPerp).ownerOf(shortVaultId) == msg.sender,
            ExceptionsLibrary.FORBIDDEN
        );

        uint256 wPowerPerpRemaining = _wPowerPerpDebt - IWETH9(wPowerPerp).balanceOf(address(this));
        if (wPowerPerpRemaining > 0) {
            uint256 wethNeeded = FullMath.mulDiv(wPowerPerpRemaining, _grabPriceX96(wPowerPerp, wPowerPerpPool), CommonLibrary.Q96);
            ISqueethVaultGovernance.DelayedProtocolParams memory protocolParams = ISqueethVaultGovernance(address(_vaultGovernance)).delayedProtocolParams();
            uint256 wethRemaining = FullMath.mulDiv(wethNeeded  - IWETH9(weth).balanceOf(address(this)), CommonLibrary.DENOMINATOR, CommonLibrary.DENOMINATOR - protocolParams.slippageD9); //TODO: add fees
            _flashRepayDebt(wethRemaining, wPowerPerpRemaining);
        } else {
            _repayDebt(0);
        }
        emit ShortClosed(tx.origin, msg.sender); //TODO: add data
    }

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        require(tokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH); //TODO: is it necessary 
        if (shortVaultId != 0) {
            uint256 wPowerPerpToMint = FullMath.mulDiv(tokenAmounts[0], _wPowerPerpDebt, _totalCollateral);
            
            IWETH9(weth).withdraw(tokenAmounts[0]);
            uint256 vaultId = controller.mintWPowerPerpAmount{value: tokenAmounts[0]}(
                shortVaultId,
                wPowerPerpToMint,
                0
            );
            _totalCollateral += tokenAmounts[0];
            _wPowerPerpDebt += wPowerPerpToMint;
        }
        actualTokenAmounts = tokenAmounts;
    }

    struct FlashCallbackData {
        uint256 amountBorrowed;
        uint256 amountToSwapTo;
        PoolAddress.PoolKey poolKey;
    }

    function _flashRepayDebt(uint256 wethToBorrow, uint256 wPowerPerpToSwapTo) internal {
        IUniswapV3Pool pool = IUniswapV3Pool(wPowerPerpPool);
        PoolAddress.PoolKey memory poolKey =
            PoolAddress.PoolKey({token0: weth, token1: wPowerPerp, fee: pool.fee()});
        bool wethIsFirst = pool.token0() == weth;
        uint256 amount0 = wethIsFirst ? wethToBorrow : 0;
        uint256 amount1 = wethIsFirst ? 0 : wethToBorrow;
        pool.flash(
            address(this),
            amount0,
            amount1,
            abi.encode(
                FlashCallbackData({
                    amountBorrowed: wethToBorrow,
                    amountToSwapTo: wPowerPerpToSwapTo,
                    poolKey: poolKey
                })
            )
        );
    }

    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external override {
        FlashCallbackData memory decoded = abi.decode(data, (FlashCallbackData));
        CallbackValidation.verifyCallback(factory, decoded.poolKey);

        ISwapRouter.ExactOutputSingleParams memory exactOutputParams = ISwapRouter.ExactOutputSingleParams({
            tokenIn: weth,
            tokenOut: wPowerPerp,
            fee: IUniswapV3Pool(wPowerPerpPool).fee(),
            recipient: address(this),
            deadline: block.timestamp + 1,
            amountOut: decoded.amountToSwapTo,
            amountInMaximum: decoded.amountBorrowed,
            sqrtPriceLimitX96: 0
        });

        IERC20(weth).safeIncreaseAllowance(address(router), decoded.amountBorrowed);
        router.exactOutputSingle(exactOutputParams);
        IERC20(weth).safeApprove(address(router), 0);
        _repayDebt(decoded.amountBorrowed);
    }

    function _repayDebt(uint256 amountBorrowed) internal {
        // burn wPowerPerpBurnAmount and expect to receive actualWethAmountIn (the amount of eth, that we sent to UniV3 pool while buying wPowerPerp back)
        controller.burnWPowerPerpAmount(shortVaultId, _wPowerPerpDebt, _totalCollateral);

        // send back unused eth and withdrawn collateral
        IWETH9(weth).deposit{value: _totalCollateral}();

        if (amountBorrowed != 0) {
            pay(weth, address(this), msg.sender, amountBorrowed);
        }
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        if (shortVaultId == 0) {
            actualTokenAmounts = tokenAmounts;
        }
    }

    function _isReclaimForbidden(address token) internal view override returns (bool) {
        if (token == weth || token == wPowerPerp) {
            return true;
        }
        return false;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function twapIndexPrice() public view returns (uint256 indexPrice) {
        ISqueethVaultGovernance.DelayedProtocolParams memory protocolParams = ISqueethVaultGovernance(address(_vaultGovernance)).delayedProtocolParams();
        indexPrice = CommonLibrary.sqrt(controller.getUnscaledIndex(protocolParams.twapPeriod));
    }

    function twapMarkPrice() public view returns (uint256 markPrice) {
        ISqueethVaultGovernance.DelayedProtocolParams memory protocolParams = ISqueethVaultGovernance(address(_vaultGovernance)).delayedProtocolParams();
        markPrice = controller.getDenormalizedMark(protocolParams.twapPeriod);
    }

    function _grabPriceX96(address tokenIn, address pool) internal view returns (uint256 priceX96) {
        (uint160 poolSqrtPriceX96, , , , , ,) = IUniswapV3Pool(pool).slot0();
        priceX96 = FullMath.mulDiv(poolSqrtPriceX96, poolSqrtPriceX96, CommonLibrary.Q96); //TODO: check type convertion
        if (tokenIn == IUniswapV3Pool(pool).token1()) {
            priceX96 = FullMath.mulDiv(CommonLibrary.Q96, CommonLibrary.Q96, priceX96);
        }
    }

    // --------------------------  EVENTS  --------------------------

    event ShortTaken(address indexed origin, address indexed sender);

    event ShortClosed(address indexed origin, address indexed sender);
}
