// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";
import "../external/gearbox/ICreditFacade.sol";
import "../external/gearbox/IUniswapV3Adapter.sol";

interface IGearboxVault is IIntegrationVault {
    
    function initialize(uint256 nft_, address[] memory vaultTokens_, address helper_) external;

    function updateTargetMarginalFactor(uint256 marginalFactorD_) external;

    function adjustPosition() external;

    function openCreditAccount() external;

    function multicall(MultiCall[] memory calls) external;

    function swap(ISwapRouter router, ISwapRouter.ExactOutputParams memory uniParams) external;

}