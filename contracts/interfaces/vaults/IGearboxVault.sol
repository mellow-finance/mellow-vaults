// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";

interface IGearboxVault is IIntegrationVault {
    
    function initialize(uint256 nft_,
        address primaryToken_,
        address depositToken_,
        address curveAdapter_,
        address convexAdapter_,
        address facade_,
        uint256 convexPoolId_,
        uint256 targetHealthFactorD_,
        bytes memory options) external;

    function updateTargetMarginalFactor(uint256 marginalFactorD_) external;

}