// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/external/chainlink/IAggregatorV3.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../libraries/external/FullMath.sol";

contract BobOracle is IAggregatorV3 {
    uint256 public constant version = 1;
    uint256 public constant Q96 = 2**96;
    string public constant description = "BOB / USD";
    address public constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address public constant BOB = 0xB0B195aEFA3650A6908f15CdaC7D92F8a5791B0B;

    IAggregatorV3 public immutable usdcUsdOracle;
    IUniswapV3Pool public immutable pool;
    uint8 public immutable decimals;

    constructor(IUniswapV3Pool pool_, IAggregatorV3 usdcUsdOracle_) {
        pool = pool_;
        require(pool.token0() == USDC && pool.token1() == BOB);

        usdcUsdOracle = usdcUsdOracle_;
        decimals = usdcUsdOracle.decimals();
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        )
    {}

    function latestRoundData()
        external
        view
        override
        returns (
            uint80,
            int256 answer,
            uint256,
            uint256,
            uint80
        )
    {
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);

        (, int256 usdcPrice, , , ) = usdcUsdOracle.latestRoundData();
        uint256 denominator = Q96 * 10**(IERC20Metadata(BOB).decimals() - IERC20Metadata(USDC).decimals());
        answer = int256(FullMath.mulDiv(priceX96, uint256(usdcPrice), denominator));
    }
}
