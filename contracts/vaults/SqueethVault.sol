// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IUniswapV3FlashCallback} from "../interfaces/external/univ3/IUniswapV3FlashCallback.sol";
import {PeripheryPayments} from "../utils/PeripheryPayments.sol";
import {PeripheryImmutableState} from "../utils/PeripheryImmutableState.sol";

import "../libraries/ExceptionsLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/PoolAddress.sol";
import "../libraries/external/TransferHelper.sol";
import "../libraries/external/CallbackValidation.sol";

import "../utils/SqueethHelper.sol";
import "../interfaces/external/squeeth/IController.sol";
import "../interfaces/external/squeeth/IWETH9.sol";
import "../interfaces/vaults/ISqueethVault.sol";
import "../interfaces/vaults/ISqueethVaultGovernance.sol";
import "./IntegrationVault.sol";

/// @notice Vault that interfaces Opyn Squeeth protocol in the integration layer.
contract SqueethVault is
    ISqueethVault,
    IERC721Receiver,
    ReentrancyGuard,
    IntegrationVault,
    IUniswapV3FlashCallback,
    PeripheryImmutableState
{
    using SafeERC20 for IERC20;
    uint256 public immutable D18 = 10**18;
    uint256 public immutable D9 = 10**9;
    uint256 public immutable D6 = 10**6;
    uint256 public immutable D4 = 10**4;
    uint256 public immutable X96 = 2**96;
    uint256 public immutable MINCOLLATERAL = 69 * 10**17;

    IController public controller;
    ISwapRouter public router;

    address public wPowerPerp;
    address public weth;
    address public wPowerPerpPool;
    address public wethBorrowPool;

    uint256 public shortVaultId;
    uint256 public totalCollateral;
    uint256 public wPowerPerpDebt;

    SqueethHelper public helper;

    constructor(address _factory, address WETH9) PeripheryImmutableState(_factory, WETH9) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        minTokenAmounts = new uint256[](1);
        minTokenAmounts[0] = IERC20(weth).balanceOf(address(this));
        (minTokenAmounts, maxTokenAmounts) = helper.minMaxAmounts(
            minTokenAmounts[0] + totalCollateral,
            wPowerPerpDebt,
            address(_vaultGovernance)
        );
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return IntegrationVault.supportsInterface(interfaceId) || interfaceId == type(ISqueethVault).interfaceId;
    }

    function initialize(uint256 nft_, address[] memory vaultTokens_) external {
        require(vaultTokens_.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        _initialize(vaultTokens_, nft_);
        ISqueethVaultGovernance.DelayedProtocolParams memory protocolParams = ISqueethVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();
        controller = protocolParams.controller;
        router = protocolParams.router;

        wPowerPerp = protocolParams.controller.wPowerPerp();
        weth = protocolParams.controller.weth();
        wPowerPerpPool = protocolParams.controller.wPowerPerpPool();
        wethBorrowPool = protocolParams.wethBorrowPool;
        require(vaultTokens_[0] == weth, ExceptionsLibrary.INVALID_TOKEN);
        require(
            IUniswapV3Pool(protocolParams.wethBorrowPool).token0() == protocolParams.controller.weth() ||
                IUniswapV3Pool(protocolParams.wethBorrowPool).token1() == protocolParams.controller.weth(),
            ExceptionsLibrary.INVALID_VALUE
        );

        helper = SqueethHelper(protocolParams.squeethHelper);
    }

    function takeShort(uint256 healthFactorD9, bool reusePerp) external nonReentrant {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        require(healthFactorD9 > D9, ExceptionsLibrary.INVARIANT);
        require(totalCollateral == 0, ExceptionsLibrary.INVALID_STATE);
        uint256 wethAmount = IERC20(weth).balanceOf(address(this));
        require(wethAmount >= MINCOLLATERAL, ExceptionsLibrary.LIMIT_UNDERFLOW);

        uint256 collateralFactorD9 = FullMath.mulDiv(healthFactorD9, 3, 2);
        if (!reusePerp) {
            uint256 wPowerPerpAmountExpected = helper.openAmounts(wethAmount, collateralFactorD9);
            _openPosition(wethAmount, wPowerPerpAmountExpected, 0);
        } else {
            (uint256 wethToBorrow, uint256 newWethAmount, uint256 wPowerPerpAmountExpected) = helper
                .openRecollateraizedAmounts(wethAmount, collateralFactorD9, address(_vaultGovernance));
            require(wethToBorrow > 0, ExceptionsLibrary.INVALID_STATE);
            _flashLoan(wethToBorrow, newWethAmount, wPowerPerpAmountExpected, true);
        }

        emit ShortTaken(tx.origin, msg.sender); //TODO: add data
    }

    function closeShort() external nonReentrant {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        require(totalCollateral != 0, ExceptionsLibrary.INVALID_STATE);

        uint256 wPowerPerpBalance = IERC20(wPowerPerp).balanceOf(address(this));
        bool flashLoanNeeded = false;
        uint256 wPowerPerpRemaining;
        if (wPowerPerpDebt > wPowerPerpBalance) {
            wPowerPerpRemaining = wPowerPerpDebt - wPowerPerpBalance;
            (uint256 wethToBorrow, uint256 wethAmountMax) = helper.closeAmounts(
                wPowerPerpRemaining,
                address(_vaultGovernance)
            );
            if (wethToBorrow > 0) {
                flashLoanNeeded = true;
                _flashLoan(wethToBorrow, wethAmountMax, wPowerPerpRemaining, false);
            }
        } else {
            wPowerPerpRemaining = 0;
        }
        if (!flashLoanNeeded) {
            _closePosition(0, wPowerPerpRemaining);
        }

        emit ShortClosed(tx.origin, msg.sender); //TODO: add data
    }

    receive() external payable {
        require(msg.sender == weth || msg.sender == address(controller), ExceptionsLibrary.FORBIDDEN);
    }

    function _push(uint256[] memory tokenAmounts, bytes memory)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        require(tokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH); //TODO: is it necessary
        if (totalCollateral == 0) {
            actualTokenAmounts = tokenAmounts;
        } else {
            actualTokenAmounts = new uint256[](1);
        }
    }

    struct FlashCallbackData {
        uint256 totalWeth;
        uint256 amountBorrowed;
        uint256 wPowerPerpToSwap;
        PoolAddress.PoolKey poolKey;
        bool isTake;
    }

    function uniswapV3FlashCallback(
        uint256,
        uint256,
        bytes calldata data
    ) external override {
        FlashCallbackData memory decoded = abi.decode(data, (FlashCallbackData));
        CallbackValidation.verifyCallback(factory, decoded.poolKey);

        uint256 borrowedPlusFees = FullMath.mulDivRoundingUp(
            decoded.amountBorrowed,
            D6 + IUniswapV3Pool(wethBorrowPool).fee(),
            D6
        );

        if (!decoded.isTake) {
            _closePosition(decoded.totalWeth, decoded.wPowerPerpToSwap);
        } else {
            _openPosition(decoded.totalWeth, decoded.wPowerPerpToSwap, borrowedPlusFees);
        }

        TransferHelper.safeTransfer(weth, msg.sender, borrowedPlusFees);
    }

    function _closePosition(uint256 wethToSwap, uint256 perpRemaining) internal {
        if (perpRemaining > 0) {
            ISwapRouter.ExactOutputSingleParams memory exactOutputParams = ISwapRouter.ExactOutputSingleParams({
                tokenIn: weth,
                tokenOut: wPowerPerp,
                fee: IUniswapV3Pool(wPowerPerpPool).fee(),
                recipient: address(this),
                deadline: block.timestamp + 1,
                amountOut: perpRemaining,
                amountInMaximum: wethToSwap,
                sqrtPriceLimitX96: 0
            });
            IERC20(weth).safeIncreaseAllowance(address(router), wethToSwap);
            router.exactOutputSingle(exactOutputParams);
            IERC20(weth).safeApprove(address(router), 0);
        }

        controller.burnWPowerPerpAmount(shortVaultId, wPowerPerpDebt, totalCollateral);
        IWETH9(weth).deposit{value: totalCollateral}();

        totalCollateral = 0;
        wPowerPerpDebt = 0;
    }

    function _openPosition(
        uint256 collateral,
        uint256 toMint,
        uint256 toRepay
    ) internal {
        IWETH9(weth).withdraw(collateral);
        uint256 vaultId = controller.mintWPowerPerpAmount{value: collateral}(shortVaultId, toMint, 0);
        if (shortVaultId == 0) {
            shortVaultId = vaultId;
        }
        if (toRepay > 0) {
            ISwapRouter.ExactInputSingleParams memory exactInputParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: wPowerPerp,
                tokenOut: weth,
                fee: IUniswapV3Pool(wPowerPerpPool).fee(),
                recipient: address(this),
                deadline: block.timestamp + 1,
                amountIn: toMint,
                amountOutMinimum: toRepay,
                sqrtPriceLimitX96: 0
            });
            IERC20(wPowerPerp).safeIncreaseAllowance(address(router), toMint);
            router.exactInputSingle(exactInputParams);
            IERC20(wPowerPerp).safeApprove(address(router), 0);
        }

        totalCollateral = collateral;
        wPowerPerpDebt = toMint;
    }

    function _flashLoan(
        uint256 wethToBorrow,
        uint256 totalWeth,
        uint256 wPowerPerpToSwap,
        bool isTake
    ) internal {
        IUniswapV3Pool pool = IUniswapV3Pool(wethBorrowPool);
        PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({
            token0: pool.token0(),
            token1: pool.token1(),
            fee: pool.fee()
        });
        bool wethIsFirst = pool.token0() == weth;

        pool.flash(
            address(this),
            wethIsFirst ? wethToBorrow : 0,
            wethIsFirst ? 0 : wethToBorrow,
            abi.encode(
                FlashCallbackData({
                    totalWeth: totalWeth,
                    amountBorrowed: wethToBorrow,
                    wPowerPerpToSwap: wPowerPerpToSwap,
                    poolKey: poolKey,
                    isTake: isTake
                })
            )
        );
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](1);
        if (totalCollateral == 0) {
            uint256 balance = IERC20(weth).balanceOf(address(this));
            actualTokenAmounts[0] = tokenAmounts[0] > balance ? balance : tokenAmounts[0];
            IERC20(weth).safeTransfer(to, actualTokenAmounts[0]);
        }
    }

    function _isReclaimForbidden(address token) internal view override returns (bool) {
        return token == weth || token == wPowerPerp;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function twapIndexPrice() public view returns (uint256) {
        return helper.twapIndexPrice();
    }

    // --------------------------  EVENTS  --------------------------

    event ShortTaken(address indexed origin, address indexed sender);

    event ShortClosed(address indexed origin, address indexed sender);
}
