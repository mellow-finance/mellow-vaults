// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultGovernance.sol";

interface IVault {
    /// @notice Address of the Vault Governance for this contract
    /// @return Address of the Vault Governance for this contract
    function vaultGovernance() external view returns (IVaultGovernance);

    /// @notice Total value locked for this contract. Generally it is the underlying token value of this contract in some
    /// other DeFi protocol. For example, for USDC Yearn Vault this would be total USDC balance that could be withdrawn for Yearn to this contract.
    /// @return tokenAmounts Total available balances for multiple tokens (nth tokenAmount corresponds to nth token in vaultTokens)
    function tvl() external view returns (uint256[] memory tokenAmounts);

    /// @notice Total earnings available now. Earnings is only needed as the base for performance fees calculation.
    /// Generally it would be DeFi yields like Yearn interest or Uniswap trading fees.
    /// @return tokenAmounts Total earnings for multiple tokens (nth tokenAmount corresponds to nth token in vaultTokens)
    function earnings() external view returns (uint256[] memory tokenAmounts);

    /// @notice Pushes tokens on the vault balance to the underlying protocol. For example, for Yearn this operation will take USDC from
    /// the contract balance and convert it to yUSDC.
    /// @dev Can only be called but Vault Owner or Strategy. Vault owner is the owner of nft for this vault in VaultManager.
    /// Strategy is approved address for the vault nft.
    ///
    /// Tokens **must** be a subset of Vault Tokens. However, the convention is that if tokenAmount == 0 it is the same as token is missing.
    /// Also notice that this operation doesn't guarantee that tokenAmounts will be invested in full.
    /// @param tokens Tokens to push
    /// @param tokenAmounts Amounts of tokens to push
    /// @param optimized Whether to use gas optimization or not. When `true` the call can have some gas cost reduction
    /// but the operation is not guaranteed to succeed. When `false` the gas cost could be higher but the operation is guaranteed to succeed.
    /// @param options Additional options that could be needed for some vaults. E.g. for Uniswap this could be `deadline` param.
    /// For the exact bytes structure see concrete vault descriptions.
    /// @return actualTokenAmounts The amounts actually invested. It could be less than tokenAmounts (but not higher).
    function push(
        address[] calldata tokens,
        uint256[] calldata tokenAmounts,
        bool optimized,
        bytes memory options
    ) external returns (uint256[] memory actualTokenAmounts);

    /// @notice The same as `push` method above but transfers tokens to vault balance prior to calling push.
    /// After the `push` it returns all the leftover tokens back (`push` method doesn't guarantee that tokenAmounts will be invested in full).
    /// @param tokens Tokens to push
    /// @param tokenAmounts Amounts of tokens to push
    /// @param optimized Whether to use gas optimization or not. When `true` the call can have some gas cost reduction but the operation is not guaranteed to succeed. When `false` the gas cost could be higher but the operation is guaranteed to succeed.
    /// @param options Additional options that could be needed for some vaults. E.g. for Uniswap this could be `deadline` param.
    /// For the exact bytes structure see concrete vault descriptions.
    /// @return actualTokenAmounts The amounts actually invested. It could be less than tokenAmounts (but not higher).
    function transferAndPush(
        address from,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts,
        bool optimized,
        bytes memory options
    ) external returns (uint256[] memory actualTokenAmounts);

    /// @notice Pulls tokens from the underlying protocol to the `to` address.
    /// For example, for Yearn this operation will take yUSDC from
    /// the Yearn protocol, convert it to USDC and send to `to` address.
    /// @dev Can only be called but Vault Owner or Strategy. Vault owner is the owner of nft for this vault in VaultManager.
    /// Strategy is approved address for the vault nft. There's a subtle difference however - while vault owner
    /// can pull the tokens to any address, Strategy can only pull to other vault in the Vault System (a set of vaults united by the Gateway Vault)
    ///
    /// Tokens **must** be a subset of Vault Tokens. However, the convention is that if tokenAmount == 0 it is the same as token is missing.
    /// Also notice that this operation doesn't guarantee that tokenAmounts will be invested in full.
    /// @param to Address to receive the tokens
    /// @param tokens Tokens to pull
    /// @param tokenAmounts Amounts of tokens to pull
    /// @param optimized Whether to use gas optimization or not. When `true` the call can have some gas cost reduction but the operation is not guaranteed to succeed. When `false` the gas cost could be higher but the operation is guaranteed to succeed.
    /// @param options Additional options that could be needed for some vaults. E.g. for Uniswap this could be `deadline` param.
    /// For the exact bytes structure see concrete vault descriptions.
    /// @return actualTokenAmounts The amounts actually withdrawn. It could be less than tokenAmounts (but not higher).
    function pull(
        address to,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts,
        bool optimized,
        bytes memory options
    ) external returns (uint256[] memory actualTokenAmounts);

    function collectEarnings(address to, bytes memory options) external returns (uint256[] memory collectedEarnings);

    function reclaimTokens(address to, address[] calldata tokens) external;

    function claimRewards(address from, bytes calldata data) external;

    event Push(uint256[] tokenAmounts);
    event Pull(address to, uint256[] tokenAmounts);
    event CollectEarnings(address to, uint256[] tokenAmounts);
    event ReclaimTokens(address to, address[] tokens, uint256[] tokenAmounts);
}
