// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";
import "../external/squeeth/IController.sol";
import "../external/univ3/ISwapRouter.sol";
import "../../utils/SqueethHelper.sol";

interface ISqueethVault is IIntegrationVault {

    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    function initialize(uint256 nft_, address[] memory vaultTokens_) external;

    function takeShort(
        uint256 healthFactor, bool reusePerp
    ) external ;

    function closeShort() external;
    
    function shortVaultId() external view returns (uint256);
    
    function totalCollateral() external view returns (uint256);
    
    function wPowerPerpDebt() external view returns (uint256);

    function wPowerPerp() external view returns (address);
    
    function weth() external view returns (address);
    
    function wPowerPerpPool() external view returns (address);

    function controller() external view returns (IController);

    function router() external view returns (ISwapRouter);

    function twapIndexPrice() external view returns (uint256 indexPrice);

    function helper() external view returns (SqueethHelper);
}