// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../interfaces/external/chainlink/IAggregatorV3.sol";

import "../interfaces/external/pancakeswap/IPancakeV3Factory.sol";
import "../interfaces/external/pancakeswap/IPancakeV3Pool.sol";
import "../interfaces/external/pancakeswap/IPancakeNonfungiblePositionManager.sol";

import "../libraries/external/FullMath.sol";

/// @notice Contract for getting chainlink data
contract PancakeChainlinkOracle is IAggregatorV3 {
    uint256 public constant Q96 = 2 ** 96;

    address public immutable token;
    address public immutable usdc;
    IPancakeV3Pool public immutable pool;

    constructor(address src, address dst, uint24 fee, IPancakeNonfungiblePositionManager positionManager) {
        token = src;
        usdc = dst;
        pool = IPancakeV3Pool(IPancakeV3Factory(positionManager.factory()).getPool(src, dst, fee));
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function description() external view returns (string memory) {
        return string(abi.encodePacked(IERC20Metadata(token).symbol(), " / USD"));
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {}

    function latestAnswer() public view returns (int256) {
        if (usdc == token) return 1e8;
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        if (pool.token0() == usdc) {
            priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
        }

        uint8 decimals_ = IERC20Metadata(token).decimals();
        uint256 answer = FullMath.mulDiv(10 ** (decimals_ + 2), priceX96, Q96);
        return int256(answer);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        answer = latestAnswer();
    }
}
