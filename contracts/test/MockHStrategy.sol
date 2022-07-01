// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../strategies/HStrategy.sol";

contract MockHStrategy is HStrategy {
    constructor(INonfungiblePositionManager positionManager_, ISwapRouter router_)
        HStrategy(positionManager_, router_)
    {}

    function calculateExpectedRatios(DomainPositionParams memory domainPositionParams)
        external
        view
        returns (ExpectedRatios memory ratios)
    {
        ratios = _calculateExpectedRatios(domainPositionParams);
    }

    function calculateDomainPositionParams(
        int24 averageTick,
        uint160 sqrtSpotPriceX96,
        StrategyParams memory strategyParams_,
        uint256 uniV3Nft,
        INonfungiblePositionManager _positionManager
    ) external view returns (DomainPositionParams memory domainPositionParams) {
        domainPositionParams = _calculateDomainPositionParams(
            averageTick,
            sqrtSpotPriceX96,
            strategyParams_,
            uniV3Nft,
            _positionManager
        );
    }

    function calculateExpectedTokenAmountsInToken0(
        TokenAmountsInToken0 memory currentTokenAmounts,
        ExpectedRatios memory expectedRatios,
        StrategyParams memory strategyParams_
    ) external pure returns (TokenAmountsInToken0 memory amounts) {
        amounts = _calculateExpectedTokenAmountsInToken0(currentTokenAmounts, expectedRatios, strategyParams_);
    }

    function calculateCurrentTokenAmountsInToken0(
        DomainPositionParams memory params,
        TokenAmounts memory currentTokenAmounts
    ) external pure returns (TokenAmountsInToken0 memory amounts) {
        amounts = _calculateCurrentTokenAmountsInToken0(params, currentTokenAmounts);
    }

    function calculateCurrentTokenAmounts(DomainPositionParams memory domainPositionParams)
        external
        view
        returns (TokenAmounts memory amounts)
    {
        amounts = _calculateCurrentTokenAmounts(domainPositionParams);
    }

    function calculateExpectedTokenAmounts(
        TokenAmounts memory currentTokenAmounts,
        StrategyParams memory strategyParams_,
        DomainPositionParams memory domainPositionParams
    ) external view returns (TokenAmounts memory amounts) {
        amounts = _calculateExpectedTokenAmounts(currentTokenAmounts, strategyParams_, domainPositionParams);
    }

    function calculateExtraTokenAmountsForMoneyVault(TokenAmounts memory expectedTokenAmounts)
        external
        view
        returns (uint256 token0Amount, uint256 token1Amount)
    {
        (token0Amount, token1Amount) = _calculateExtraTokenAmountsForMoneyVault(expectedTokenAmounts);
    }

    function calculateMissingTokenAmounts(
        TokenAmounts memory expectedTokenAmounts,
        DomainPositionParams memory domainPositionParams
    ) external view returns (TokenAmounts memory missingTokenAmounts) {
        missingTokenAmounts = _calculateMissingTokenAmounts(expectedTokenAmounts, domainPositionParams);
    }

    function swapTokens(
        TokenAmounts memory expectedTokenAmounts,
        TokenAmounts memory currentTokenAmounts,
        RebalanceRestrictions memory restrictions
    ) external returns (uint256[] memory swappedAmounts) {
        swappedAmounts = _swapTokens(expectedTokenAmounts, currentTokenAmounts, restrictions);
    }
}
