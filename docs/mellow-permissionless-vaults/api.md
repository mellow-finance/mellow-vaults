# Contracts API

### `AaveVault`

Some contract details.

#### `constructor(contract IVaultGovernance vaultGovernance)` (public)

#### `tvl() → uint256[] tokenAmounts` (public)

tvl function

Some exceptions here

#### `earnings() → uint256[] tokenAmounts` (public)

#### `_push(uint256[] tokenAmounts, bool, bytes) → uint256[] actualTokenAmounts` (internal)

#### `_pull(address to, uint256[] tokenAmounts, bool, bytes) → uint256[] actualTokenAmounts` (internal)

#### `_collectEarnings(address to, bytes) → uint256[] collectedEarnings` (internal)

#### `_getAToken(address token) → address` (internal)

#### `_allowTokenIfNecessary(address token)` (internal)

#### `_lendingPool() → contract ILendingPool` (internal)
