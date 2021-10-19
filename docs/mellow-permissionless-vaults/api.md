Some contract details. `yo` this is markdown

# Functions:

- [`constructor(contract IVaultGovernance vaultGovernance)`](#AaveVault-constructor-contract-IVaultGovernance-)

- [`tvl()`](#AaveVault-tvl--)

- [`earnings()`](#AaveVault-earnings--)

### `constructor(contract IVaultGovernance vaultGovernance)` {#AaveVault-constructor-contract-IVaultGovernance-}

No description

### `tvl() → uint256[] tokenAmounts` {#AaveVault-tvl--}

Some exceptions here

### `earnings() → uint256[] tokenAmounts` {#AaveVault-earnings--}

No description

# Functions:

- [`deployVault(contract IVaultGovernance vaultGovernance, bytes)`](#AaveVaultFactory-deployVault-contract-IVaultGovernance-bytes-)

### `deployVault(contract IVaultGovernance vaultGovernance, bytes) → contract IVault` {#AaveVaultFactory-deployVault-contract-IVaultGovernance-bytes-}

No description

# Functions:

- [`constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory governanceFactory, bool permissionless, contract IProtocolGovernance governance, contract ILendingPool pool)`](#AaveVaultManager-constructor-string-string-contract-IVaultFactory-contract-IVaultGovernanceFactory-bool-contract-IProtocolGovernance-contract-ILendingPool-)

- [`lendingPool()`](#AaveVaultManager-lendingPool--)

### `constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory governanceFactory, bool permissionless, contract IProtocolGovernance governance, contract ILendingPool pool)` {#AaveVaultManager-constructor-string-string-contract-IVaultFactory-contract-IVaultGovernanceFactory-bool-contract-IProtocolGovernance-contract-ILendingPool-}

No description

### `lendingPool() → contract ILendingPool` {#AaveVaultManager-lendingPool--}

No description

# Functions:

- [`constructor(address admin)`](#DefaultAccessControl-constructor-address-)

- [`isAdmin()`](#DefaultAccessControl-isAdmin--)

### `constructor(address admin)` {#DefaultAccessControl-constructor-address-}

No description

### `isAdmin() → bool` {#DefaultAccessControl-isAdmin--}

No description

# Functions:

- [`constructor(contract IVaultGovernance vaultGovernance)`](#ERC20Vault-constructor-contract-IVaultGovernance-)

- [`tvl()`](#ERC20Vault-tvl--)

- [`earnings()`](#ERC20Vault-earnings--)

### `constructor(contract IVaultGovernance vaultGovernance)` {#ERC20Vault-constructor-contract-IVaultGovernance-}

No description

### `tvl() → uint256[] tokenAmounts` {#ERC20Vault-tvl--}

No description

### `earnings() → uint256[] tokenAmounts` {#ERC20Vault-earnings--}

No description

# Functions:

- [`deployVault(contract IVaultGovernance vaultGovernance, bytes)`](#ERC20VaultFactory-deployVault-contract-IVaultGovernance-bytes-)

### `deployVault(contract IVaultGovernance vaultGovernance, bytes) → contract IVault` {#ERC20VaultFactory-deployVault-contract-IVaultGovernance-bytes-}

No description

# Functions:

- [`constructor(contract IVaultGovernance vaultGovernance, address[] vaults)`](#GatewayVault-constructor-contract-IVaultGovernance-address---)

- [`tvl()`](#GatewayVault-tvl--)

- [`earnings()`](#GatewayVault-earnings--)

- [`vaultTvl(uint256 vaultNum)`](#GatewayVault-vaultTvl-uint256-)

- [`vaultsTvl()`](#GatewayVault-vaultsTvl--)

- [`vaultEarnings(uint256 vaultNum)`](#GatewayVault-vaultEarnings-uint256-)

- [`hasVault(address vault)`](#GatewayVault-hasVault-address-)

# Events:

- [`CollectProtocolFees(address protocolTreasury, address[] tokens, uint256[] amounts)`](#GatewayVault-CollectProtocolFees-address-address---uint256---)

- [`CollectStrategyFees(address strategyTreasury, address[] tokens, uint256[] amounts)`](#GatewayVault-CollectStrategyFees-address-address---uint256---)

### `constructor(contract IVaultGovernance vaultGovernance, address[] vaults)` {#GatewayVault-constructor-contract-IVaultGovernance-address---}

No description

### `tvl() → uint256[] tokenAmounts` {#GatewayVault-tvl--}

No description

### `earnings() → uint256[] tokenAmounts` {#GatewayVault-earnings--}

No description

### `vaultTvl(uint256 vaultNum) → uint256[]` {#GatewayVault-vaultTvl-uint256-}

No description

### `vaultsTvl() → uint256[][] tokenAmounts` {#GatewayVault-vaultsTvl--}

No description

### `vaultEarnings(uint256 vaultNum) → uint256[]` {#GatewayVault-vaultEarnings-uint256-}

No description

### `hasVault(address vault) → bool` {#GatewayVault-hasVault-address-}

No description

### Event `CollectProtocolFees(address protocolTreasury, address[] tokens, uint256[] amounts)` {#GatewayVault-CollectProtocolFees-address-address---uint256---}

No description

### Event `CollectStrategyFees(address strategyTreasury, address[] tokens, uint256[] amounts)` {#GatewayVault-CollectStrategyFees-address-address---uint256---}

No description

# Functions:

- [`constructor(address[] tokens, contract IVaultManager manager, address treasury, address admin, address[] vaults, address[] redirects_, uint256[] limits_)`](#GatewayVaultGovernance-constructor-address---contract-IVaultManager-address-address-address---address---uint256---)

- [`limits()`](#GatewayVaultGovernance-limits--)

- [`redirects()`](#GatewayVaultGovernance-redirects--)

- [`setLimits(uint256[] newLimits)`](#GatewayVaultGovernance-setLimits-uint256---)

- [`setRedirects(address[] newRedirects)`](#GatewayVaultGovernance-setRedirects-address---)

# Events:

- [`SetLimits(uint256[] limits)`](#GatewayVaultGovernance-SetLimits-uint256---)

- [`SetRedirects(address[] redirects)`](#GatewayVaultGovernance-SetRedirects-address---)

### `constructor(address[] tokens, contract IVaultManager manager, address treasury, address admin, address[] vaults, address[] redirects_, uint256[] limits_)` {#GatewayVaultGovernance-constructor-address---contract-IVaultManager-address-address-address---address---uint256---}

No description

### `limits() → uint256[]` {#GatewayVaultGovernance-limits--}

No description

### `redirects() → address[]` {#GatewayVaultGovernance-redirects--}

No description

### `setLimits(uint256[] newLimits)` {#GatewayVaultGovernance-setLimits-uint256---}

No description

### `setRedirects(address[] newRedirects)` {#GatewayVaultGovernance-setRedirects-address---}

No description

### Event `SetLimits(uint256[] limits)` {#GatewayVaultGovernance-SetLimits-uint256---}

No description

### Event `SetRedirects(address[] redirects)` {#GatewayVaultGovernance-SetRedirects-address---}

No description

# Functions:

- [`constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory goveranceFactory, bool permissionless, contract IProtocolGovernance governance)`](#GatewayVaultManager-constructor-string-string-contract-IVaultFactory-contract-IVaultGovernanceFactory-bool-contract-IProtocolGovernance-)

- [`vaultOwnerNft(uint256 nft)`](#GatewayVaultManager-vaultOwnerNft-uint256-)

- [`vaultOwner(uint256 nft)`](#GatewayVaultManager-vaultOwner-uint256-)

### `constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory goveranceFactory, bool permissionless, contract IProtocolGovernance governance)` {#GatewayVaultManager-constructor-string-string-contract-IVaultFactory-contract-IVaultGovernanceFactory-bool-contract-IProtocolGovernance-}

No description

### `vaultOwnerNft(uint256 nft) → uint256` {#GatewayVaultManager-vaultOwnerNft-uint256-}

No description

### `vaultOwner(uint256 nft) → address` {#GatewayVaultManager-vaultOwner-uint256-}

No description

# Functions:

- [`constructor(string name_, string symbol_, contract IVault gatewayVault, contract IProtocolGovernance protocolGovernance, uint256 limitPerAddress, address admin)`](#LpIssuer-constructor-string-string-contract-IVault-contract-IProtocolGovernance-uint256-address-)

- [`setLimit(uint256 newLimitPerAddress)`](#LpIssuer-setLimit-uint256-)

- [`deposit(uint256[] tokenAmounts, bool optimized, bytes options)`](#LpIssuer-deposit-uint256---bool-bytes-)

- [`withdraw(address to, uint256 lpTokenAmount, bool optimized, bytes options)`](#LpIssuer-withdraw-address-uint256-bool-bytes-)

# Events:

- [`Deposit(address from, address[] tokens, uint256[] actualTokenAmounts, uint256 lpTokenMinted)`](#LpIssuer-Deposit-address-address---uint256---uint256-)

- [`Withdraw(address from, address[] tokens, uint256[] actualTokenAmounts, uint256 lpTokenBurned)`](#LpIssuer-Withdraw-address-address---uint256---uint256-)

- [`ExitFeeCollected(address from, address to, address[] tokens, uint256[] amounts)`](#LpIssuer-ExitFeeCollected-address-address-address---uint256---)

### `constructor(string name_, string symbol_, contract IVault gatewayVault, contract IProtocolGovernance protocolGovernance, uint256 limitPerAddress, address admin)` {#LpIssuer-constructor-string-string-contract-IVault-contract-IProtocolGovernance-uint256-address-}

No description

### `setLimit(uint256 newLimitPerAddress)` {#LpIssuer-setLimit-uint256-}

No description

### `deposit(uint256[] tokenAmounts, bool optimized, bytes options)` {#LpIssuer-deposit-uint256---bool-bytes-}

No description

### `withdraw(address to, uint256 lpTokenAmount, bool optimized, bytes options)` {#LpIssuer-withdraw-address-uint256-bool-bytes-}

No description

### Event `Deposit(address from, address[] tokens, uint256[] actualTokenAmounts, uint256 lpTokenMinted)` {#LpIssuer-Deposit-address-address---uint256---uint256-}

No description

### Event `Withdraw(address from, address[] tokens, uint256[] actualTokenAmounts, uint256 lpTokenBurned)` {#LpIssuer-Withdraw-address-address---uint256---uint256-}

No description

### Event `ExitFeeCollected(address from, address to, address[] tokens, uint256[] amounts)` {#LpIssuer-ExitFeeCollected-address-address-address---uint256---}

No description

# Functions:

- [`constructor(struct ILpIssuerGovernance.GovernanceParams params)`](#LpIssuerGovernance-constructor-struct-ILpIssuerGovernance-GovernanceParams-)

- [`governanceParams()`](#LpIssuerGovernance-governanceParams--)

- [`pendingGovernanceParams()`](#LpIssuerGovernance-pendingGovernanceParams--)

- [`pendingGovernanceParamsTimestamp()`](#LpIssuerGovernance-pendingGovernanceParamsTimestamp--)

- [`setPendingGovernanceParams(struct ILpIssuerGovernance.GovernanceParams newGovernanceParams)`](#LpIssuerGovernance-setPendingGovernanceParams-struct-ILpIssuerGovernance-GovernanceParams-)

- [`commitGovernanceParams()`](#LpIssuerGovernance-commitGovernanceParams--)

### `constructor(struct ILpIssuerGovernance.GovernanceParams params)` {#LpIssuerGovernance-constructor-struct-ILpIssuerGovernance-GovernanceParams-}

No description

### `governanceParams() → struct ILpIssuerGovernance.GovernanceParams` {#LpIssuerGovernance-governanceParams--}

No description

### `pendingGovernanceParams() → struct ILpIssuerGovernance.GovernanceParams` {#LpIssuerGovernance-pendingGovernanceParams--}

No description

### `pendingGovernanceParamsTimestamp() → uint256` {#LpIssuerGovernance-pendingGovernanceParamsTimestamp--}

No description

### `setPendingGovernanceParams(struct ILpIssuerGovernance.GovernanceParams newGovernanceParams)` {#LpIssuerGovernance-setPendingGovernanceParams-struct-ILpIssuerGovernance-GovernanceParams-}

No description

### `commitGovernanceParams()` {#LpIssuerGovernance-commitGovernanceParams--}

No description

# Functions:

- [`constructor(address admin, struct IProtocolGovernance.Params _params)`](#ProtocolGovernance-constructor-address-struct-IProtocolGovernance-Params-)

- [`claimAllowlist()`](#ProtocolGovernance-claimAllowlist--)

- [`pendingClaimAllowlistAdd()`](#ProtocolGovernance-pendingClaimAllowlistAdd--)

- [`isAllowedToClaim(address addr)`](#ProtocolGovernance-isAllowedToClaim-address-)

- [`maxTokensPerVault()`](#ProtocolGovernance-maxTokensPerVault--)

- [`governanceDelay()`](#ProtocolGovernance-governanceDelay--)

- [`strategyPerformanceFee()`](#ProtocolGovernance-strategyPerformanceFee--)

- [`protocolPerformanceFee()`](#ProtocolGovernance-protocolPerformanceFee--)

- [`protocolExitFee()`](#ProtocolGovernance-protocolExitFee--)

- [`protocolTreasury()`](#ProtocolGovernance-protocolTreasury--)

- [`gatewayVaultManager()`](#ProtocolGovernance-gatewayVaultManager--)

- [`setPendingClaimAllowlistAdd(address[] addresses)`](#ProtocolGovernance-setPendingClaimAllowlistAdd-address---)

- [`removeFromClaimAllowlist(address addr)`](#ProtocolGovernance-removeFromClaimAllowlist-address-)

- [`setPendingParams(struct IProtocolGovernance.Params newParams)`](#ProtocolGovernance-setPendingParams-struct-IProtocolGovernance-Params-)

- [`commitClaimAllowlistAdd()`](#ProtocolGovernance-commitClaimAllowlistAdd--)

- [`commitParams()`](#ProtocolGovernance-commitParams--)

### `constructor(address admin, struct IProtocolGovernance.Params _params)` {#ProtocolGovernance-constructor-address-struct-IProtocolGovernance-Params-}

No description

### `claimAllowlist() → address[]` {#ProtocolGovernance-claimAllowlist--}

No description

### `pendingClaimAllowlistAdd() → address[]` {#ProtocolGovernance-pendingClaimAllowlistAdd--}

No description

### `isAllowedToClaim(address addr) → bool` {#ProtocolGovernance-isAllowedToClaim-address-}

No description

### `maxTokensPerVault() → uint256` {#ProtocolGovernance-maxTokensPerVault--}

No description

### `governanceDelay() → uint256` {#ProtocolGovernance-governanceDelay--}

No description

### `strategyPerformanceFee() → uint256` {#ProtocolGovernance-strategyPerformanceFee--}

No description

### `protocolPerformanceFee() → uint256` {#ProtocolGovernance-protocolPerformanceFee--}

No description

### `protocolExitFee() → uint256` {#ProtocolGovernance-protocolExitFee--}

No description

### `protocolTreasury() → address` {#ProtocolGovernance-protocolTreasury--}

No description

### `gatewayVaultManager() → contract IGatewayVaultManager` {#ProtocolGovernance-gatewayVaultManager--}

No description

### `setPendingClaimAllowlistAdd(address[] addresses)` {#ProtocolGovernance-setPendingClaimAllowlistAdd-address---}

No description

### `removeFromClaimAllowlist(address addr)` {#ProtocolGovernance-removeFromClaimAllowlist-address-}

No description

### `setPendingParams(struct IProtocolGovernance.Params newParams)` {#ProtocolGovernance-setPendingParams-struct-IProtocolGovernance-Params-}

No description

### `commitClaimAllowlistAdd()` {#ProtocolGovernance-commitClaimAllowlistAdd--}

No description

### `commitParams()` {#ProtocolGovernance-commitParams--}

No description

# Functions:

- [`constructor(contract IVaultGovernance vaultGovernance, uint24 fee)`](#UniV3Vault-constructor-contract-IVaultGovernance-uint24-)

- [`tvl()`](#UniV3Vault-tvl--)

- [`earnings()`](#UniV3Vault-earnings--)

- [`nftEarnings(uint256 nft)`](#UniV3Vault-nftEarnings-uint256-)

- [`nftTvl(uint256 nft)`](#UniV3Vault-nftTvl-uint256-)

- [`nftTvls()`](#UniV3Vault-nftTvls--)

### `constructor(contract IVaultGovernance vaultGovernance, uint24 fee)` {#UniV3Vault-constructor-contract-IVaultGovernance-uint24-}

No description

### `tvl() → uint256[] tokenAmounts` {#UniV3Vault-tvl--}

No description

### `earnings() → uint256[] tokenAmounts` {#UniV3Vault-earnings--}

No description

### `nftEarnings(uint256 nft) → uint256[] tokenAmounts` {#UniV3Vault-nftEarnings-uint256-}

No description

### `nftTvl(uint256 nft) → uint256[] tokenAmounts` {#UniV3Vault-nftTvl-uint256-}

No description

### `nftTvls() → uint256[][] tokenAmounts` {#UniV3Vault-nftTvls--}

No description

# Functions:

- [`deployVault(contract IVaultGovernance vaultGovernance, bytes options)`](#UniV3VaultFactory-deployVault-contract-IVaultGovernance-bytes-)

### `deployVault(contract IVaultGovernance vaultGovernance, bytes options) → contract IVault` {#UniV3VaultFactory-deployVault-contract-IVaultGovernance-bytes-}

No description

# Functions:

- [`constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory goveranceFactory, bool permissionless, contract IProtocolGovernance governance, contract INonfungiblePositionManager uniV3PositionManager)`](#UniV3VaultManager-constructor-string-string-contract-IVaultFactory-contract-IVaultGovernanceFactory-bool-contract-IProtocolGovernance-contract-INonfungiblePositionManager-)

- [`positionManager()`](#UniV3VaultManager-positionManager--)

### `constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory goveranceFactory, bool permissionless, contract IProtocolGovernance governance, contract INonfungiblePositionManager uniV3PositionManager)` {#UniV3VaultManager-constructor-string-string-contract-IVaultFactory-contract-IVaultGovernanceFactory-bool-contract-IProtocolGovernance-contract-INonfungiblePositionManager-}

No description

### `positionManager() → contract INonfungiblePositionManager` {#UniV3VaultManager-positionManager--}

No description

# Functions:

- [`vaultGovernance()`](#Vault-vaultGovernance--)

- [`tvl()`](#Vault-tvl--)

- [`earnings()`](#Vault-earnings--)

- [`push(address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options)`](#Vault-push-address---uint256---bool-bytes-)

- [`transferAndPush(address from, address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options)`](#Vault-transferAndPush-address-address---uint256---bool-bytes-)

- [`pull(address to, address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options)`](#Vault-pull-address-address---uint256---bool-bytes-)

- [`collectEarnings(address to, bytes options)`](#Vault-collectEarnings-address-bytes-)

- [`reclaimTokens(address to, address[] tokens)`](#Vault-reclaimTokens-address-address---)

- [`claimRewards(address from, bytes data)`](#Vault-claimRewards-address-bytes-)

### `vaultGovernance() → contract IVaultGovernance` {#Vault-vaultGovernance--}

No description

### `tvl() → uint256[] tokenAmounts` {#Vault-tvl--}

No description

### `earnings() → uint256[] tokenAmounts` {#Vault-earnings--}

No description

### `push(address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options) → uint256[] actualTokenAmounts` {#Vault-push-address---uint256---bool-bytes-}

No description

### `transferAndPush(address from, address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options) → uint256[] actualTokenAmounts` {#Vault-transferAndPush-address-address---uint256---bool-bytes-}

No description

### `pull(address to, address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options) → uint256[] actualTokenAmounts` {#Vault-pull-address-address---uint256---bool-bytes-}

No description

### `collectEarnings(address to, bytes options) → uint256[] collectedEarnings` {#Vault-collectEarnings-address-bytes-}

No description

### `reclaimTokens(address to, address[] tokens)` {#Vault-reclaimTokens-address-address---}

No description

### `claimRewards(address from, bytes data)` {#Vault-claimRewards-address-bytes-}

No description

# Functions:

- [`constructor(address[] tokens, contract IVaultManager manager, address treasury, address admin)`](#VaultGovernance-constructor-address---contract-IVaultManager-address-address-)

- [`isProtocolAdmin()`](#VaultGovernance-isProtocolAdmin--)

- [`vaultTokens()`](#VaultGovernance-vaultTokens--)

- [`isVaultToken(address token)`](#VaultGovernance-isVaultToken-address-)

- [`vaultManager()`](#VaultGovernance-vaultManager--)

- [`pendingVaultManager()`](#VaultGovernance-pendingVaultManager--)

- [`pendingVaultManagerTimestamp()`](#VaultGovernance-pendingVaultManagerTimestamp--)

- [`strategyTreasury()`](#VaultGovernance-strategyTreasury--)

- [`pendingStrategyTreasury()`](#VaultGovernance-pendingStrategyTreasury--)

- [`pendingStrategyTreasuryTimestamp()`](#VaultGovernance-pendingStrategyTreasuryTimestamp--)

- [`setPendingVaultManager(contract IVaultManager manager)`](#VaultGovernance-setPendingVaultManager-contract-IVaultManager-)

- [`commitVaultManager()`](#VaultGovernance-commitVaultManager--)

- [`setPendingStrategyTreasury(address treasury)`](#VaultGovernance-setPendingStrategyTreasury-address-)

- [`commitStrategyTreasury()`](#VaultGovernance-commitStrategyTreasury--)

### `constructor(address[] tokens, contract IVaultManager manager, address treasury, address admin)` {#VaultGovernance-constructor-address---contract-IVaultManager-address-address-}

No description

### `isProtocolAdmin() → bool` {#VaultGovernance-isProtocolAdmin--}

No description

### `vaultTokens() → address[]` {#VaultGovernance-vaultTokens--}

No description

### `isVaultToken(address token) → bool` {#VaultGovernance-isVaultToken-address-}

No description

### `vaultManager() → contract IVaultManager` {#VaultGovernance-vaultManager--}

No description

### `pendingVaultManager() → contract IVaultManager` {#VaultGovernance-pendingVaultManager--}

No description

### `pendingVaultManagerTimestamp() → uint256` {#VaultGovernance-pendingVaultManagerTimestamp--}

No description

### `strategyTreasury() → address` {#VaultGovernance-strategyTreasury--}

No description

### `pendingStrategyTreasury() → address` {#VaultGovernance-pendingStrategyTreasury--}

No description

### `pendingStrategyTreasuryTimestamp() → uint256` {#VaultGovernance-pendingStrategyTreasuryTimestamp--}

No description

### `setPendingVaultManager(contract IVaultManager manager)` {#VaultGovernance-setPendingVaultManager-contract-IVaultManager-}

No description

### `commitVaultManager()` {#VaultGovernance-commitVaultManager--}

No description

### `setPendingStrategyTreasury(address treasury)` {#VaultGovernance-setPendingStrategyTreasury-address-}

No description

### `commitStrategyTreasury()` {#VaultGovernance-commitStrategyTreasury--}

No description

# Functions:

- [`constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory governanceFactory, bool permissionless, contract IProtocolGovernance protocolGovernance)`](#VaultManager-constructor-string-string-contract-IVaultFactory-contract-IVaultGovernanceFactory-bool-contract-IProtocolGovernance-)

- [`nftForVault(address vault)`](#VaultManager-nftForVault-address-)

- [`vaultForNft(uint256 nft)`](#VaultManager-vaultForNft-uint256-)

- [`createVault(address[] tokens, address strategyTreasury, address admin, bytes options)`](#VaultManager-createVault-address---address-address-bytes-)

- [`supportsInterface(bytes4 interfaceId)`](#VaultManager-supportsInterface-bytes4-)

### `constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory governanceFactory, bool permissionless, contract IProtocolGovernance protocolGovernance)` {#VaultManager-constructor-string-string-contract-IVaultFactory-contract-IVaultGovernanceFactory-bool-contract-IProtocolGovernance-}

No description

### `nftForVault(address vault) → uint256` {#VaultManager-nftForVault-address-}

No description

### `vaultForNft(uint256 nft) → address` {#VaultManager-vaultForNft-uint256-}
