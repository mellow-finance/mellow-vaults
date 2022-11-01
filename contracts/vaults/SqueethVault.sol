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
import {IUniswapV3Pool as IUniV3Pool} from "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/vaults/ISqueethVault.sol";
import "./IntegrationVault.sol";

/// @notice Vault that interfaces Opyn Squeeth protocol in the integration layer.
contract SqueethVault is ISqueethVault, IERC721Receiver, ReentrancyGuard, IntegrationVault, IUniswapV3FlashCallback, PeripheryImmutableState, PeripheryPayments {
    using SafeERC20 for IERC20;
    uint256 public immutable DUST = 10**3;
    uint256 public immutable D18 = 10**18;
    uint256 public immutable D9 = 10**9;
    uint256 public immutable D6 = 10**6;
    uint256 public immutable D4 = 10**4;
    uint256 public immutable MINCOLLATERAL = 69 * 10**17;


    IController public controller;
    ISwapRouter public router;

    address public wPowerPerp;
    address public weth;
    address public shortPowerPerp;
    address public wPowerPerpPool;
    address public wethBorrowPool;

    uint256 public shortVaultId;
    uint256 public totalCollateral;
    uint256 public wPowerPerpDebt;
    
    constructor(
        address _factory,
        address WETH9
    ) PeripheryImmutableState(_factory, WETH9) {

    }

    // -------------------  EXTERNAL, VIEW  -------------------

    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        minTokenAmounts = new uint256[](1);
        maxTokenAmounts = new uint256[](1);
        minTokenAmounts[0] = IERC20(weth).balanceOf(address(this));
        if (shortVaultId != 0) {
            minTokenAmounts[0] += totalCollateral;
            maxTokenAmounts[0] = minTokenAmounts[0];
            uint256 normalizationFactorD18 = controller.getExpectedNormalizationFactor();
            uint256 wPowerPerpBalance = IERC20(wPowerPerp).balanceOf(address(this)); 
            ISqueethVaultGovernance.DelayedProtocolParams memory protocolParams = ISqueethVaultGovernance(address(_vaultGovernance)).delayedProtocolParams();
            (uint256 minPriceX96, uint256 maxPriceX96) = _getMinMaxPrice(protocolParams.oracle);
            if (wPowerPerpDebt > wPowerPerpBalance) {
                minTokenAmounts[0] -= FullMath.mulDiv(wPowerPerpDebt - wPowerPerpBalance, maxPriceX96, CommonLibrary.Q96);
                maxTokenAmounts[0] -= FullMath.mulDiv(wPowerPerpDebt - wPowerPerpBalance, minPriceX96, CommonLibrary.Q96);
            } else {
                minTokenAmounts[0] += FullMath.mulDiv(wPowerPerpBalance - wPowerPerpDebt, minPriceX96, CommonLibrary.Q96);
                maxTokenAmounts[0] += FullMath.mulDiv(wPowerPerpBalance - wPowerPerpDebt, maxPriceX96, CommonLibrary.Q96);
            }
        } else {
            maxTokenAmounts[0] = minTokenAmounts[0];
        }
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
        wPowerPerpPool = protocolParams.controller.wPowerPerpPool();
        wethBorrowPool = protocolParams.wethBorrowPool;

        shortVaultId = 0; // maybe delete later
        require(vaultTokens_[0] == weth, ExceptionsLibrary.INVALID_TOKEN);
    }

    function takeShort(
        uint256 healthFactorD9, bool reusePerp
    ) external nonReentrant {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN); 
        require(healthFactorD9 > CommonLibrary.DENOMINATOR, ExceptionsLibrary.INVARIANT);
        require(shortVaultId == 0, ExceptionsLibrary.INVALID_STATE);
        uint256 wethAmount = IERC20(weth).balanceOf(address(this));
        require(wethAmount >= MINCOLLATERAL, ExceptionsLibrary.LIMIT_UNDERFLOW);

        uint256 ethPrice = twapIndexPrice(); 
        uint256 collateralFactorD9 = FullMath.mulDiv(healthFactorD9, 3, 2);
        uint256 ethPriceNormalized = FullMath.mulDiv(ethPrice, controller.getExpectedNormalizationFactor(), CommonLibrary.D18);
        uint256 wPowerPerpAmountExpected;
        if (!reusePerp) {
            IWETH9(weth).withdraw(wethAmount);
            wPowerPerpAmountExpected = FullMath.mulDiv(wethAmount, collateralFactorD9, ethPriceNormalized);
            shortVaultId = controller.mintWPowerPerpAmount{value: wethAmount}(
                0,
                wPowerPerpAmountExpected,
                0
            );
        } else {
            ISqueethVaultGovernance.DelayedProtocolParams memory protocolParams = ISqueethVaultGovernance(address(_vaultGovernance)).delayedProtocolParams();
            uint256 tempD9 = FullMath.mulDiv(D9 - protocolParams.slippageD9, D9, collateralFactorD9);
            uint256 temp2D9 = D9 + FullMath.mulDiv(IUniV3Pool(wPowerPerpPool).fee(), D9, D6) - tempD9;

            uint256 wethToBorrow = FullMath.mulDiv(wethAmount, tempD9, temp2D9);
        
            uint256 mintedETHAmount = FullMath.mulDiv(wethAmount + wethToBorrow, tempD9, CommonLibrary.DENOMINATOR);
            wPowerPerpAmountExpected = FullMath.mulDiv(mintedETHAmount, D4 * D18, ethPriceNormalized);
            wethAmount += wethToBorrow;
            _flashLoan(wethToBorrow, wPowerPerpAmountExpected, true);
        }

        totalCollateral = wethAmount;
        wPowerPerpDebt = wPowerPerpAmountExpected;

        emit ShortTaken(tx.origin, msg.sender); //TODO: add data
    }

    function healthFactor() view external returns (uint256 ratioD9) {
        uint256 ethPriceNormalized = FullMath.mulDiv(twapIndexPrice(), controller.getExpectedNormalizationFactor(), CommonLibrary.D18);
        ratioD9 = FullMath.mulDiv(totalCollateral * D4, D18, ethPriceNormalized);
        ratioD9 = FullMath.mulDiv(ratioD9, D9 * 2, wPowerPerpDebt * 3); 
    }

    function closeShort() external nonReentrant {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        require(shortVaultId != 0, ExceptionsLibrary.INVALID_STATE);

        uint256 wPowerPerpBalance = IERC20(wPowerPerp).balanceOf(address(this)); 
        bool flashLoanNeeded = false;
        uint256 wPowerPerpRemaining;
        if (wPowerPerpDebt > wPowerPerpBalance) {
            wPowerPerpRemaining = wPowerPerpDebt - wPowerPerpBalance;
            uint256 wethNeeded = FullMath.mulDiv(wPowerPerpRemaining, _spotPriceX96(wPowerPerp, wPowerPerpPool), CommonLibrary.Q96);
            ISqueethVaultGovernance.DelayedProtocolParams memory protocolParams = ISqueethVaultGovernance(address(_vaultGovernance)).delayedProtocolParams();
            uint256 wethMax = FullMath.mulDiv(wethNeeded, CommonLibrary.DENOMINATOR, CommonLibrary.DENOMINATOR - protocolParams.slippageD9); //TODO: add fees
            if (IERC20(weth).balanceOf(address(this)) < wethMax) {
                flashLoanNeeded = true;
                _flashLoan(wethMax - IERC20(weth).balanceOf(address(this)), wPowerPerpRemaining, false) ;
            }
        } else {
            wPowerPerpRemaining = 0;
        }
        if (!flashLoanNeeded) {
            _repayDebt(wPowerPerpRemaining);
        }
        
        shortVaultId = 0;
        totalCollateral = 0;
        wPowerPerpDebt = 0;
        emit ShortClosed(tx.origin, msg.sender); //TODO: add data
    }
    
    receive() override external payable {
        // require(
        //     msg.sender == controller.weth() || msg.sender == address(controller),
        //     ExceptionsLibrary.FORBIDDEN
        // );
    }

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        require(tokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH); //TODO: is it necessary 
        if (shortVaultId != 0) {
            uint256 wPowerPerpToMint = FullMath.mulDiv(tokenAmounts[0], wPowerPerpDebt, totalCollateral);
            
            IWETH9(weth).withdraw(tokenAmounts[0]);
            uint256 vaultId = controller.mintWPowerPerpAmount{value: tokenAmounts[0]}(
                shortVaultId,
                wPowerPerpToMint,
                0
            );
            totalCollateral += tokenAmounts[0];
            wPowerPerpDebt += FullMath.mulDiv(wPowerPerpToMint, D18, controller.getExpectedNormalizationFactor());
        }
        actualTokenAmounts = tokenAmounts;
    }

    struct FlashCallbackData {
        uint256 amountBorrowed;
        uint256 amountToSwap;
        PoolAddress.PoolKey poolKey;
        bool isTake;
    }

    function _flashLoan(uint256 wethToBorrow, uint256 wPowerPerpToSwap, bool isTake) internal {
        IUniV3Pool pool = IUniV3Pool(wethBorrowPool);
        PoolAddress.PoolKey memory poolKey =
            PoolAddress.PoolKey({token0: pool.token0(), token1: pool.token1(), fee: pool.fee()});
        bool wethIsFirst = pool.token0() == weth;
        pool.flash(
            address(this),
            wethIsFirst ? wethToBorrow : 0,
            wethIsFirst ? 0 : wethToBorrow,
            abi.encode(
                FlashCallbackData({
                    amountBorrowed: wethToBorrow,
                    amountToSwap: wPowerPerpToSwap,
                    poolKey: poolKey,
                    isTake: isTake
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

        uint256 borrowedPlusFees = FullMath.mulDivRoundingUp(decoded.amountBorrowed, D6 + IUniV3Pool(wethBorrowPool).fee(), D6);
        
        if (!decoded.isTake) {
            _repayDebt(decoded.amountToSwap);
        } else {
            uint256 wethAmount = IERC20(weth).balanceOf(address(this)); 
            IWETH9(weth).withdraw(wethAmount);
        
            shortVaultId = controller.mintWPowerPerpAmount{value: wethAmount}(
                0,
                decoded.amountToSwap,
                0
            );

            ISwapRouter.ExactInputSingleParams memory exactInputParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: wPowerPerp,
                tokenOut: weth,
                fee: IUniV3Pool(wPowerPerpPool).fee(),
                recipient: address(this),
                deadline: block.timestamp + 1,
                amountIn: decoded.amountToSwap,
                amountOutMinimum: borrowedPlusFees,
                sqrtPriceLimitX96: 0
            });
            IERC20(wPowerPerp).safeIncreaseAllowance(address(router), decoded.amountToSwap);
            router.exactInputSingle(exactInputParams);
            IERC20(wPowerPerp).safeApprove(address(router), 0);
        }

        pay(weth, address(this), msg.sender, borrowedPlusFees);
    }

    function _repayDebt(uint256 wPowerPerpRemaining) internal {
        if (wPowerPerpRemaining > 0) {
            uint256 wethNeeded = FullMath.mulDiv(wPowerPerpRemaining, _spotPriceX96(wPowerPerp, wPowerPerpPool), CommonLibrary.Q96);
            ISqueethVaultGovernance.DelayedProtocolParams memory protocolParams = ISqueethVaultGovernance(address(_vaultGovernance)).delayedProtocolParams();
            uint256 wethMax = FullMath.mulDiv(wethNeeded, CommonLibrary.DENOMINATOR, CommonLibrary.DENOMINATOR - protocolParams.slippageD9); //TODO: add fees
            
            ISwapRouter.ExactOutputSingleParams memory exactOutputParams = ISwapRouter.ExactOutputSingleParams({
                tokenIn: weth,
                tokenOut: wPowerPerp,
                fee: IUniV3Pool(wPowerPerpPool).fee(),
                recipient: address(this),
                deadline: block.timestamp + 1,
                amountOut: wPowerPerpRemaining,
                amountInMaximum: wethMax,
                sqrtPriceLimitX96: 0
            });

            IERC20(weth).safeIncreaseAllowance(address(router), wethMax);
            router.exactOutputSingle(exactOutputParams);
            IERC20(weth).safeApprove(address(router), 0);
        }

        controller.burnWPowerPerpAmount(shortVaultId, wPowerPerpDebt, totalCollateral);
        IWETH9(weth).deposit{value: totalCollateral}();
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](1);
        if (shortVaultId == 0) {
            uint256 balance = IERC20(weth).balanceOf(address(this));
            actualTokenAmounts[0] = tokenAmounts[0] > balance ? balance : tokenAmounts[0];
            IERC20(weth).safeTransfer(to, actualTokenAmounts[0]);
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
        indexPrice = CommonLibrary.sqrt(controller.getUnscaledIndex(protocolParams.twapPeriod)) * D9;
    }

    function twapMarkPrice() public view returns (uint256 markPrice) {
        ISqueethVaultGovernance.DelayedProtocolParams memory protocolParams = ISqueethVaultGovernance(address(_vaultGovernance)).delayedProtocolParams();
        markPrice = controller.getDenormalizedMark(protocolParams.twapPeriod);
    }

    function _spotPriceX96(address tokenIn, address pool) internal view returns (uint256 priceX96) {
        (uint160 poolSqrtPriceX96, , , , , ,) = IUniV3Pool(pool).slot0();
        priceX96 = FullMath.mulDiv(poolSqrtPriceX96, poolSqrtPriceX96, CommonLibrary.Q96); //TODO: check type convertion
        if (tokenIn == IUniV3Pool(pool).token1()) {
            priceX96 = FullMath.mulDiv(CommonLibrary.Q96, CommonLibrary.Q96, priceX96);
        }
    }


    function _getMinMaxPrice(IOracle oracle) internal view returns (uint256 minPriceX96, uint256 maxPriceX96) {
        (uint256[] memory prices, ) = oracle.priceX96(wPowerPerp, weth, 0x2A);
        require(prices.length > 1, ExceptionsLibrary.INVARIANT);
        minPriceX96 = prices[0];
        maxPriceX96 = prices[0];
        for (uint32 i = 1; i < prices.length; ++i) {
            if (prices[i] < minPriceX96) {
                minPriceX96 = prices[i];
            } else if (prices[i] > maxPriceX96) {
                maxPriceX96 = prices[i];
            }
        }
    }

    // --------------------------  EVENTS  --------------------------

    event ShortTaken(address indexed origin, address indexed sender);

    event ShortClosed(address indexed origin, address indexed sender);
}
