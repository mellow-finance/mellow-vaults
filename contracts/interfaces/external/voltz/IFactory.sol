// SPDX-License-Identifier: Apache-2.0

pragma solidity =0.8.9;

import "./utils/CustomErrors.sol";
import "./rate_oracles/IRateOracle.sol";
import "./IMarginEngine.sol";
import "./IVAMM.sol";
import "./fcms/IFCM.sol";
import "./IERC20Minimal.sol";
import "./IPeriphery.sol";

/// @title The interface for the Voltz AMM Factory
/// @notice The AMM Factory facilitates creation of Voltz AMMs
interface IFactory is CustomErrors {
    event IrsInstance(
        IERC20Minimal indexed underlyingToken,
        IRateOracle indexed rateOracle,
        uint256 termStartTimestampWad,
        uint256 termEndTimestampWad,
        int24 tickSpacing,
        IMarginEngine marginEngine,
        IVAMM vamm,
        IFCM fcm,
        uint8 yieldBearingProtocolID,
        uint8 underlyingTokenDecimals
    );

    event MasterFCM(IFCM masterFCMAddress, uint8 yieldBearingProtocolID);

    event Approval(
        address indexed owner,
        address indexed intAddress,
        bool indexed isApproved
    );

    event PeripheryUpdate(IPeriphery periphery);

    // view functions

    function isApproved(address _owner, address intAddress)
        external
        view
        returns (bool);

    function masterVAMM() external view returns (IVAMM);

    function masterMarginEngine() external view returns (IMarginEngine);

    function periphery() external view returns (IPeriphery);

    // settters

    function setApproval(address intAddress, bool allowIntegration) external;

    function setMasterFCM(IFCM masterFCM, uint8 yieldBearingProtocolID)
        external;

    function setMasterVAMM(IVAMM _masterVAMM) external;

    function setMasterMarginEngine(IMarginEngine _masterMarginEngine) external;

    function setPeriphery(IPeriphery _periphery) external;

    /// @notice Deploys the contracts required for a new Interest Rate Swap instance
    function deployIrsInstance(
        IERC20Minimal _underlyingToken,
        IRateOracle _rateOracle,
        uint256 _termStartTimestampWad,
        uint256 _termEndTimestampWad,
        int24 _tickSpacing
    )
        external
        returns (
            IMarginEngine marginEngineProxy,
            IVAMM vammProxy,
            IFCM fcmProxy
        );

    function masterFCMs(uint8 yieldBearingProtocolID)
        external
        view
        returns (IFCM masterFCM);
}
