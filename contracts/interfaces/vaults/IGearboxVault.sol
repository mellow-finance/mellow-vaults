// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";
import "../external/gearbox/ICreditFacade.sol";
import "../external/gearbox/IUniswapV3Adapter.sol";
import "../external/gearbox/helpers/ICreditManagerV2.sol";

interface IGearboxVault is IIntegrationVault {

    function creditFacade() external view returns (ICreditFacade);

    function creditManager() external view returns (ICreditManagerV2);

    function primaryToken() external view returns (address);

    function depositToken() external view returns (address);

    function marginalFactorD9() external view returns (uint256);

    function primaryIndex() external view returns (int128);

    function poolId() external view returns (uint256);

    function convexOutputToken() external view returns (address);
    
    function initialize(uint256 nft_, address[] memory vaultTokens_, address helper_) external;

    function updateTargetMarginalFactor(uint256 marginalFactorD_) external;

    function adjustPosition() external;

    function openCreditAccount() external;

    function getCreditAccount() external view returns (address);

    function multicall(MultiCall[] memory calls) external;

    function swap(ISwapRouter router, ISwapRouter.ExactOutputParams memory uniParams, address token, uint256 amount) external;
}