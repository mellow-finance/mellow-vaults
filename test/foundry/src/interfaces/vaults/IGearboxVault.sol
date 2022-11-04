// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";
import "../external/gearbox/ICreditFacade.sol";
import "../external/gearbox/IUniswapV3Adapter.sol";

interface IGearboxVault is IIntegrationVault {

    /// @notice Reference to the Gearbox creditFacade contract for the primary token of this vault.
    function creditFacade() external view returns (ICreditFacade);

    /// @notice Reference to the Gearbox creditManager contract for the primary token of this vault.
    function creditManager() external view returns (ICreditManagerV2);

    /// @notice Primary token of the vault, for this token a credit account is opened in Gearbox.
    function primaryToken() external view returns (address);

    /// @notice Deposit token of the vault, deposits/withdawals are made in this token (might be the same or different with primaryToken)
    function depositToken() external view returns (address);

    /// @notice The leverage factor of the vault, multiplied by 10^9
    /// For a vault with X usd of collateral and marginal factor T >= 1, total assets (collateral + debt) should be equal to X * T 
    function marginalFactorD9() external view returns (uint256);

    /// @notice Index used for claiming in Gearbox V2 Degen contract
    function merkleIndex() external view returns (uint256);

    /// @notice NFTs amount used for claiming in Gearbox V2 Degen contract
    function merkleTotalAmount() external view returns (uint256);

    /// @notice Proof used for claiming in Gearbox V2 Degen contract
    function getMerkleProof() external view returns (bytes32[] memory);

    /// @notice The index of the curve pool the vault invests into
    function poolId() external view returns (uint256);

    /// @notice The index of the primary token in the used curve pool
    function primaryIndex() external view returns (int128);

    /// @notice The address of the convex token we receive after staking Convex LPs
    function convexOutputToken() external view returns (address);
    
    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param helper_ address of helper
    function initialize(uint256 nft_, address[] memory vaultTokens_, address helper_) external;

    /// @notice Updates marginalFactorD9 (can be successfully called only by an admin or a strategist)
    /// @param marginalFactorD_ New marginalFactorD9
    function updateTargetMarginalFactor(uint256 marginalFactorD_) external;

    /// @notice Sets merkle tree parameters for claiming Gearbox V2 Degen NFT (can be successfully called only by an admin or a strategist)
    /// @param merkleIndex_ Required index
    /// @param merkleTotalAmount_ Total amount of NFTs we have in Gearbox Degen Contract
    /// @param merkleProof_ Proof in Merkle tree
    function setMerkleParameters(uint256 merkleIndex_, uint256 merkleTotalAmount_, bytes32[] memory merkleProof_) external;

    /// @notice Adjust a position (takes more debt or repays some, depending on the past performance) to achieve the required marginalFactorD9
    function adjustPosition() external;

    /// @notice Opens a new credit account on the address of the vault
    function openCreditAccount() external;

    /// @notice A helper function to be able to call Gearbox multicalls from the helper, but on behalf of the vault
    /// Can be successfully called only by the helper
    function openCreditAccountInManager(uint256 currentPrimaryTokenAmount, uint16 referralCode) external;

    /// @notice Returns an address of the credit account connected to the address of the vault
    function getCreditAccount() external view returns (address);

    /// @notice Returns value of all assets located on the vault, including taken with leverage (nominated in primary tokens)
    function getAllAssetsOnCreditAccountValue() external view returns (uint256 currentAllAssetsValue);

    /// @notice Returns value of rewards (CRV, CVX) we can obtain from Convex (nominated in primary tokens)
    function getClaimableRewardsValue() external view returns (uint256);

    /// @notice A helper function to be able to call Gearbox multicalls from the helper, but on behalf of the vault
    /// Can be successfully called only by the helper
    function multicall(MultiCall[] memory calls) external;

    /// @notice A helper function to be able to call Gearbox multicalls from the helper, but on behalf of the vault
    /// Can be successfully called only by the helper
    function swap(ISwapRouter router, ISwapRouter.ExactOutputParams memory uniParams, address token, uint256 amount) external;
}