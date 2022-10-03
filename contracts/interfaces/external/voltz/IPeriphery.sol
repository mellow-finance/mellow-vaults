// SPDX-License-Identifier: Apache-2.0

pragma solidity =0.8.9;

import "./IMarginEngine.sol";
import "./IVAMM.sol";
import "./utils/CustomErrors.sol";

interface IPeriphery is CustomErrors {
    // events

    /// @dev emitted after new lp margin cap is set
    event MarginCap(IVAMM _vamm, int256 _lpMarginCapNew);

    // structs

    struct MintOrBurnParams {
        IMarginEngine marginEngine;
        int24 tickLower;
        int24 tickUpper;
        uint256 notional;
        bool isMint;
        int256 marginDelta;
    }

    struct SwapPeripheryParams {
        IMarginEngine marginEngine;
        bool isFT;
        uint256 notional;
        uint160 sqrtPriceLimitX96;
        int24 tickLower;
        int24 tickUpper;
        uint256 marginDelta;
    }

    // view functions

    function getCurrentTick(IMarginEngine marginEngine)
        external
        view
        returns (int24 currentTick);

    /// @param _vamm VAMM for which to get the lp cap in underlying tokens
    /// @return Notional Cap for liquidity providers that mint or burn via periphery (enforced in the core if isAlpha is set to true)
    function lpMarginCaps(IVAMM _vamm) external returns (int256);

    /// @param _vamm VAMM for which to get the lp notional cumulative in underlying tokens
    /// @return Total amount of notional supplied by the LPs to a given VAMM via the periphery
    function lpMarginCumulatives(IVAMM _vamm) external returns (int256);

    // non-view functions

    function mintOrBurn(MintOrBurnParams memory params)
        external
        returns (int256 positionMarginRequirement);

    function swap(SwapPeripheryParams memory params)
        external
        returns (
            int256 _fixedTokenDelta,
            int256 _variableTokenDelta,
            uint256 _cumulativeFeeIncurred,
            int256 _fixedTokenDeltaUnbalanced,
            int256 _marginRequirement,
            int24 _tickAfter
        );

    function updatePositionMargin(
        IMarginEngine _marginEngine,
        int24 _tickLower,
        int24 _tickUpper,
        int256 _marginDelta,
        bool _fullyWithdraw
    ) external;

    function setLPMarginCap(IVAMM _vamm, int256 _lpMarginCapNew) external;

    function settlePositionAndWithdrawMargin(
        IMarginEngine _marginEngine,
        address _owner,
        int24 _tickLower,
        int24 _tickUpper
    ) external;
}
