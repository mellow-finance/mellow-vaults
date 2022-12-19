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
    address public immutable usdc;
    address public immutable bob;

    IAggregatorV3 public immutable usdcUsdOracle;
    IUniswapV3Pool public immutable pool;
    uint8 public immutable decimals;

    constructor(
        address usdc_,
        address bob_,
        IUniswapV3Pool pool_,
        IAggregatorV3 usdcUsdOracle_
    ) {
        pool = pool_;
        usdc = usdc_;
        bob = bob_;

        require((pool.token0() == usdc && pool.token1() == bob) || (pool.token0() == bob && pool.token1() == usdc));
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
        if (pool.token1() == bob) {
            priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
        }

        (, int256 usdcPrice, , , ) = usdcUsdOracle.latestRoundData();
        uint256 denominator = Q96 / 10**(IERC20Metadata(bob).decimals() - IERC20Metadata(usdc).decimals());
        answer = int256(FullMath.mulDiv(priceX96, uint256(usdcPrice), denominator));
    }
}
