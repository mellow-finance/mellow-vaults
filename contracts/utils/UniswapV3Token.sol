// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "../interfaces/external/univ3/INonfungiblePositionManager.sol";

import "../libraries/ExceptionsLibrary.sol";

contract UniswapV3Token is IERC20 {
    INonfungiblePositionManager public immutable positionManager;
    IUniswapV3Pool public immutable pool;

    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    int24 public immutable tickLower;
    int24 public immutable tickUpper;
    mapping(address => uint256) userNft;
    mapping(address => mapping(address => uint256)) private _allowance;

    constructor(
        INonfungiblePositionManager positionManager_,
        address token0_,
        address token1_,
        int24 tickLower_,
        int24 tickUpper_,
        uint24 fee_
    ) {
        pool = IUniswapV3Pool(IUniswapV3Factory(positionManager_.factory()).getPool(token0_, token1_, fee_));
        require(tickLower_ < tickUpper_, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(address(pool) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require((tickUpper_ - tickLower_) % pool.tickSpacing() == 0, ExceptionsLibrary.INVALID_VALUE);

        positionManager = positionManager_;
        token0 = token0_;
        token1 = token1_;
        fee = fee_;
        tickLower = tickLower_;
        tickUpper = tickUpper_;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) external view override returns (uint256) {
        uint256 uniV3Nft = userNft[account];
        if (uniV3Nft == 0) return 0;
        uint128 liquidity;
        (, , , , , , , liquidity, , , , ) = positionManager.positions(uniV3Nft);
        return uint256(liquidity);
    }

    /// @inheritdoc IERC20
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        uint256 senderNft = userNft[msg.sender];
        if (senderNft == 0) {
            return false;
        }

        uint256 recipientNft = userNft[recipient];
        (uint256 amount0, uint256 amount1) = positionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: senderNft,
                liquidity: uint128(amount),
                amount0Min: 0,
                amount1Min: 0,
                deadline: type(uint256).max
            })
        );

        if (recipientNft == 0) {
            (recipientNft, , , ) = positionManager.mint(
                INonfungiblePositionManager.MintParams({
                    token0: token0,
                    token1: token1,
                    fee: fee,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Desired: amount0,
                    amount1Desired: amount1,
                    amount0Min: amount0,
                    amount1Min: amount1,
                    recipient: address(this),
                    deadline: type(uint256).max
                })
            );
            userNft[recipient] = recipientNft;
        } else {
            positionManager.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams({
                    tokenId: recipientNft,
                    amount0Desired: amount0,
                    amount1Desired: amount1,
                    amount0Min: amount0,
                    amount1Min: amount1,
                    deadline: type(uint256).max
                })
            );
        }

        return true;
    }

    /// @inheritdoc IERC20
    uint256 public totalSupply;

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowance[owner][spender];
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowance[msg.sender][spender] = amount;
        return true;
    }

    /// @inheritdoc IERC20
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external virtual returns (bool) {
        uint256 senderNft = userNft[sender];
        if (senderNft == 0) {
            return false;
        }

        uint256 recipientNft = userNft[recipient];
        (uint256 amount0, uint256 amount1) = positionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: senderNft,
                liquidity: uint128(amount),
                amount0Min: 0,
                amount1Min: 0,
                deadline: type(uint256).max
            })
        );

        if (recipientNft == 0) {
            (recipientNft, , , ) = positionManager.mint(
                INonfungiblePositionManager.MintParams({
                    token0: token0,
                    token1: token1,
                    fee: fee,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Desired: amount0,
                    amount1Desired: amount1,
                    amount0Min: amount0,
                    amount1Min: amount1,
                    recipient: address(this),
                    deadline: type(uint256).max
                })
            );
            userNft[recipient] = recipientNft;
        } else {
            positionManager.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams({
                    tokenId: recipientNft,
                    amount0Desired: amount0,
                    amount1Desired: amount1,
                    amount0Min: amount0,
                    amount1Min: amount1,
                    deadline: type(uint256).max
                })
            );
        }

        return true;
    }
}
