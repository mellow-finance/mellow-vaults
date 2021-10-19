Some contract details. `yo` this is markdown

# Functions:

- [`constructor(contract IVaultGovernance vaultGovernance)`](#AaveVault-constructor-contract-IVaultGovernance-)

- [`tvl()`](#AaveVault-tvl--)

- [`earnings()`](#AaveVault-earnings--)

# Function `constructor(contract IVaultGovernance vaultGovernance)` {#AaveVault-constructor-contract-IVaultGovernance-}

No description

# Function `tvl() → uint256[] tokenAmounts` {#AaveVault-tvl--}

Some exceptions here

# Function `earnings() → uint256[] tokenAmounts` {#AaveVault-earnings--}

No description

# Functions:

- [`deployVault(contract IVaultGovernance vaultGovernance, bytes)`](#AaveVaultFactory-deployVault-contract-IVaultGovernance-bytes-)

# Function `deployVault(contract IVaultGovernance vaultGovernance, bytes) → contract IVault` {#AaveVaultFactory-deployVault-contract-IVaultGovernance-bytes-}

No description

# Functions:

- [`constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory governanceFactory, bool permissionless, contract IProtocolGovernance governance, contract ILendingPool pool)`](#AaveVaultManager-constructor-string-string-contract-IVaultFactory-contract-IVaultGovernanceFactory-bool-contract-IProtocolGovernance-contract-ILendingPool-)

- [`lendingPool()`](#AaveVaultManager-lendingPool--)

# Function `constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory governanceFactory, bool permissionless, contract IProtocolGovernance governance, contract ILendingPool pool)` {#AaveVaultManager-constructor-string-string-contract-IVaultFactory-contract-IVaultGovernanceFactory-bool-contract-IProtocolGovernance-contract-ILendingPool-}

No description

# Function `lendingPool() → contract ILendingPool` {#AaveVaultManager-lendingPool--}

No description

# Functions:

- [`constructor(address admin)`](#DefaultAccessControl-constructor-address-)

- [`isAdmin()`](#DefaultAccessControl-isAdmin--)

# Function `constructor(address admin)` {#DefaultAccessControl-constructor-address-}

No description

# Function `isAdmin() → bool` {#DefaultAccessControl-isAdmin--}

No description

# Functions:

- [`constructor(contract IVaultGovernance vaultGovernance)`](#ERC20Vault-constructor-contract-IVaultGovernance-)

- [`tvl()`](#ERC20Vault-tvl--)

- [`earnings()`](#ERC20Vault-earnings--)

# Function `constructor(contract IVaultGovernance vaultGovernance)` {#ERC20Vault-constructor-contract-IVaultGovernance-}

No description

# Function `tvl() → uint256[] tokenAmounts` {#ERC20Vault-tvl--}

No description

# Function `earnings() → uint256[] tokenAmounts` {#ERC20Vault-earnings--}

No description

# Functions:

- [`deployVault(contract IVaultGovernance vaultGovernance, bytes)`](#ERC20VaultFactory-deployVault-contract-IVaultGovernance-bytes-)

# Function `deployVault(contract IVaultGovernance vaultGovernance, bytes) → contract IVault` {#ERC20VaultFactory-deployVault-contract-IVaultGovernance-bytes-}

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

# Function `constructor(contract IVaultGovernance vaultGovernance, address[] vaults)` {#GatewayVault-constructor-contract-IVaultGovernance-address---}

No description

# Function `tvl() → uint256[] tokenAmounts` {#GatewayVault-tvl--}

No description

# Function `earnings() → uint256[] tokenAmounts` {#GatewayVault-earnings--}

No description

# Function `vaultTvl(uint256 vaultNum) → uint256[]` {#GatewayVault-vaultTvl-uint256-}

No description

# Function `vaultsTvl() → uint256[][] tokenAmounts` {#GatewayVault-vaultsTvl--}

No description

# Function `vaultEarnings(uint256 vaultNum) → uint256[]` {#GatewayVault-vaultEarnings-uint256-}

No description

# Function `hasVault(address vault) → bool` {#GatewayVault-hasVault-address-}

No description

# Event `CollectProtocolFees(address protocolTreasury, address[] tokens, uint256[] amounts)` {#GatewayVault-CollectProtocolFees-address-address---uint256---}

No description

# Event `CollectStrategyFees(address strategyTreasury, address[] tokens, uint256[] amounts)` {#GatewayVault-CollectStrategyFees-address-address---uint256---}

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

# Function `constructor(address[] tokens, contract IVaultManager manager, address treasury, address admin, address[] vaults, address[] redirects_, uint256[] limits_)` {#GatewayVaultGovernance-constructor-address---contract-IVaultManager-address-address-address---address---uint256---}

No description

# Function `limits() → uint256[]` {#GatewayVaultGovernance-limits--}

No description

# Function `redirects() → address[]` {#GatewayVaultGovernance-redirects--}

No description

# Function `setLimits(uint256[] newLimits)` {#GatewayVaultGovernance-setLimits-uint256---}

No description

# Function `setRedirects(address[] newRedirects)` {#GatewayVaultGovernance-setRedirects-address---}

No description

# Event `SetLimits(uint256[] limits)` {#GatewayVaultGovernance-SetLimits-uint256---}

No description

# Event `SetRedirects(address[] redirects)` {#GatewayVaultGovernance-SetRedirects-address---}

No description

# Functions:

- [`constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory goveranceFactory, bool permissionless, contract IProtocolGovernance governance)`](#GatewayVaultManager-constructor-string-string-contract-IVaultFactory-contract-IVaultGovernanceFactory-bool-contract-IProtocolGovernance-)

- [`vaultOwnerNft(uint256 nft)`](#GatewayVaultManager-vaultOwnerNft-uint256-)

- [`vaultOwner(uint256 nft)`](#GatewayVaultManager-vaultOwner-uint256-)

# Function `constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory goveranceFactory, bool permissionless, contract IProtocolGovernance governance)` {#GatewayVaultManager-constructor-string-string-contract-IVaultFactory-contract-IVaultGovernanceFactory-bool-contract-IProtocolGovernance-}

No description

# Function `vaultOwnerNft(uint256 nft) → uint256` {#GatewayVaultManager-vaultOwnerNft-uint256-}

No description

# Function `vaultOwner(uint256 nft) → address` {#GatewayVaultManager-vaultOwner-uint256-}

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

# Function `constructor(string name_, string symbol_, contract IVault gatewayVault, contract IProtocolGovernance protocolGovernance, uint256 limitPerAddress, address admin)` {#LpIssuer-constructor-string-string-contract-IVault-contract-IProtocolGovernance-uint256-address-}

No description

# Function `setLimit(uint256 newLimitPerAddress)` {#LpIssuer-setLimit-uint256-}

No description

# Function `deposit(uint256[] tokenAmounts, bool optimized, bytes options)` {#LpIssuer-deposit-uint256---bool-bytes-}

No description

# Function `withdraw(address to, uint256 lpTokenAmount, bool optimized, bytes options)` {#LpIssuer-withdraw-address-uint256-bool-bytes-}

No description

# Event `Deposit(address from, address[] tokens, uint256[] actualTokenAmounts, uint256 lpTokenMinted)` {#LpIssuer-Deposit-address-address---uint256---uint256-}

No description

# Event `Withdraw(address from, address[] tokens, uint256[] actualTokenAmounts, uint256 lpTokenBurned)` {#LpIssuer-Withdraw-address-address---uint256---uint256-}

No description

# Event `ExitFeeCollected(address from, address to, address[] tokens, uint256[] amounts)` {#LpIssuer-ExitFeeCollected-address-address-address---uint256---}

No description

# Functions:

- [`constructor(struct ILpIssuerGovernance.GovernanceParams params)`](#LpIssuerGovernance-constructor-struct-ILpIssuerGovernance-GovernanceParams-)

- [`governanceParams()`](#LpIssuerGovernance-governanceParams--)

- [`pendingGovernanceParams()`](#LpIssuerGovernance-pendingGovernanceParams--)

- [`pendingGovernanceParamsTimestamp()`](#LpIssuerGovernance-pendingGovernanceParamsTimestamp--)

- [`setPendingGovernanceParams(struct ILpIssuerGovernance.GovernanceParams newGovernanceParams)`](#LpIssuerGovernance-setPendingGovernanceParams-struct-ILpIssuerGovernance-GovernanceParams-)

- [`commitGovernanceParams()`](#LpIssuerGovernance-commitGovernanceParams--)

# Function `constructor(struct ILpIssuerGovernance.GovernanceParams params)` {#LpIssuerGovernance-constructor-struct-ILpIssuerGovernance-GovernanceParams-}

No description

# Function `governanceParams() → struct ILpIssuerGovernance.GovernanceParams` {#LpIssuerGovernance-governanceParams--}

No description

# Function `pendingGovernanceParams() → struct ILpIssuerGovernance.GovernanceParams` {#LpIssuerGovernance-pendingGovernanceParams--}

No description

# Function `pendingGovernanceParamsTimestamp() → uint256` {#LpIssuerGovernance-pendingGovernanceParamsTimestamp--}

No description

# Function `setPendingGovernanceParams(struct ILpIssuerGovernance.GovernanceParams newGovernanceParams)` {#LpIssuerGovernance-setPendingGovernanceParams-struct-ILpIssuerGovernance-GovernanceParams-}

No description

# Function `commitGovernanceParams()` {#LpIssuerGovernance-commitGovernanceParams--}

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

# Function `constructor(address admin, struct IProtocolGovernance.Params _params)` {#ProtocolGovernance-constructor-address-struct-IProtocolGovernance-Params-}

No description

# Function `claimAllowlist() → address[]` {#ProtocolGovernance-claimAllowlist--}

No description

# Function `pendingClaimAllowlistAdd() → address[]` {#ProtocolGovernance-pendingClaimAllowlistAdd--}

No description

# Function `isAllowedToClaim(address addr) → bool` {#ProtocolGovernance-isAllowedToClaim-address-}

No description

# Function `maxTokensPerVault() → uint256` {#ProtocolGovernance-maxTokensPerVault--}

No description

# Function `governanceDelay() → uint256` {#ProtocolGovernance-governanceDelay--}

No description

# Function `strategyPerformanceFee() → uint256` {#ProtocolGovernance-strategyPerformanceFee--}

No description

# Function `protocolPerformanceFee() → uint256` {#ProtocolGovernance-protocolPerformanceFee--}

No description

# Function `protocolExitFee() → uint256` {#ProtocolGovernance-protocolExitFee--}

No description

# Function `protocolTreasury() → address` {#ProtocolGovernance-protocolTreasury--}

No description

# Function `gatewayVaultManager() → contract IGatewayVaultManager` {#ProtocolGovernance-gatewayVaultManager--}

No description

# Function `setPendingClaimAllowlistAdd(address[] addresses)` {#ProtocolGovernance-setPendingClaimAllowlistAdd-address---}

No description

# Function `removeFromClaimAllowlist(address addr)` {#ProtocolGovernance-removeFromClaimAllowlist-address-}

No description

# Function `setPendingParams(struct IProtocolGovernance.Params newParams)` {#ProtocolGovernance-setPendingParams-struct-IProtocolGovernance-Params-}

No description

# Function `commitClaimAllowlistAdd()` {#ProtocolGovernance-commitClaimAllowlistAdd--}

No description

# Function `commitParams()` {#ProtocolGovernance-commitParams--}

No description

# Functions:

- [`constructor(contract IVaultGovernance vaultGovernance, uint24 fee)`](#UniV3Vault-constructor-contract-IVaultGovernance-uint24-)

- [`tvl()`](#UniV3Vault-tvl--)

- [`earnings()`](#UniV3Vault-earnings--)

- [`nftEarnings(uint256 nft)`](#UniV3Vault-nftEarnings-uint256-)

- [`nftTvl(uint256 nft)`](#UniV3Vault-nftTvl-uint256-)

- [`nftTvls()`](#UniV3Vault-nftTvls--)

# Function `constructor(contract IVaultGovernance vaultGovernance, uint24 fee)` {#UniV3Vault-constructor-contract-IVaultGovernance-uint24-}

No description

# Function `tvl() → uint256[] tokenAmounts` {#UniV3Vault-tvl--}

No description

# Function `earnings() → uint256[] tokenAmounts` {#UniV3Vault-earnings--}

No description

# Function `nftEarnings(uint256 nft) → uint256[] tokenAmounts` {#UniV3Vault-nftEarnings-uint256-}

No description

# Function `nftTvl(uint256 nft) → uint256[] tokenAmounts` {#UniV3Vault-nftTvl-uint256-}

No description

# Function `nftTvls() → uint256[][] tokenAmounts` {#UniV3Vault-nftTvls--}

No description

# Functions:

- [`deployVault(contract IVaultGovernance vaultGovernance, bytes options)`](#UniV3VaultFactory-deployVault-contract-IVaultGovernance-bytes-)

# Function `deployVault(contract IVaultGovernance vaultGovernance, bytes options) → contract IVault` {#UniV3VaultFactory-deployVault-contract-IVaultGovernance-bytes-}

No description

# Functions:

- [`constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory goveranceFactory, bool permissionless, contract IProtocolGovernance governance, contract INonfungiblePositionManager uniV3PositionManager)`](#UniV3VaultManager-constructor-string-string-contract-IVaultFactory-contract-IVaultGovernanceFactory-bool-contract-IProtocolGovernance-contract-INonfungiblePositionManager-)

- [`positionManager()`](#UniV3VaultManager-positionManager--)

# Function `constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory goveranceFactory, bool permissionless, contract IProtocolGovernance governance, contract INonfungiblePositionManager uniV3PositionManager)` {#UniV3VaultManager-constructor-string-string-contract-IVaultFactory-contract-IVaultGovernanceFactory-bool-contract-IProtocolGovernance-contract-INonfungiblePositionManager-}

No description

# Function `positionManager() → contract INonfungiblePositionManager` {#UniV3VaultManager-positionManager--}

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

# Function `vaultGovernance() → contract IVaultGovernance` {#Vault-vaultGovernance--}

No description

# Function `tvl() → uint256[] tokenAmounts` {#Vault-tvl--}

No description

# Function `earnings() → uint256[] tokenAmounts` {#Vault-earnings--}

No description

# Function `push(address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options) → uint256[] actualTokenAmounts` {#Vault-push-address---uint256---bool-bytes-}

No description

# Function `transferAndPush(address from, address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options) → uint256[] actualTokenAmounts` {#Vault-transferAndPush-address-address---uint256---bool-bytes-}

No description

# Function `pull(address to, address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options) → uint256[] actualTokenAmounts` {#Vault-pull-address-address---uint256---bool-bytes-}

No description

# Function `collectEarnings(address to, bytes options) → uint256[] collectedEarnings` {#Vault-collectEarnings-address-bytes-}

No description

# Function `reclaimTokens(address to, address[] tokens)` {#Vault-reclaimTokens-address-address---}

No description

# Function `claimRewards(address from, bytes data)` {#Vault-claimRewards-address-bytes-}

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

# Function `constructor(address[] tokens, contract IVaultManager manager, address treasury, address admin)` {#VaultGovernance-constructor-address---contract-IVaultManager-address-address-}

No description

# Function `isProtocolAdmin() → bool` {#VaultGovernance-isProtocolAdmin--}

No description

# Function `vaultTokens() → address[]` {#VaultGovernance-vaultTokens--}

No description

# Function `isVaultToken(address token) → bool` {#VaultGovernance-isVaultToken-address-}

No description

# Function `vaultManager() → contract IVaultManager` {#VaultGovernance-vaultManager--}

No description

# Function `pendingVaultManager() → contract IVaultManager` {#VaultGovernance-pendingVaultManager--}

No description

# Function `pendingVaultManagerTimestamp() → uint256` {#VaultGovernance-pendingVaultManagerTimestamp--}

No description

# Function `strategyTreasury() → address` {#VaultGovernance-strategyTreasury--}

No description

# Function `pendingStrategyTreasury() → address` {#VaultGovernance-pendingStrategyTreasury--}

No description

# Function `pendingStrategyTreasuryTimestamp() → uint256` {#VaultGovernance-pendingStrategyTreasuryTimestamp--}

No description

# Function `setPendingVaultManager(contract IVaultManager manager)` {#VaultGovernance-setPendingVaultManager-contract-IVaultManager-}

No description

# Function `commitVaultManager()` {#VaultGovernance-commitVaultManager--}

No description

# Function `setPendingStrategyTreasury(address treasury)` {#VaultGovernance-setPendingStrategyTreasury-address-}

No description

# Function `commitStrategyTreasury()` {#VaultGovernance-commitStrategyTreasury--}

No description

# Functions:

- [`constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory governanceFactory, bool permissionless, contract IProtocolGovernance protocolGovernance)`](#VaultManager-constructor-string-string-contract-IVaultFactory-contract-IVaultGovernanceFactory-bool-contract-IProtocolGovernance-)

- [`nftForVault(address vault)`](#VaultManager-nftForVault-address-)

- [`vaultForNft(uint256 nft)`](#VaultManager-vaultForNft-uint256-)

- [`createVault(address[] tokens, address strategyTreasury, address admin, bytes options)`](#VaultManager-createVault-address---address-address-bytes-)

- [`supportsInterface(bytes4 interfaceId)`](#VaultManager-supportsInterface-bytes4-)

# Function `constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory governanceFactory, bool permissionless, contract IProtocolGovernance protocolGovernance)` {#VaultManager-constructor-string-string-contract-IVaultFactory-contract-IVaultGovernanceFactory-bool-contract-IProtocolGovernance-}

No description

# Function `nftForVault(address vault) → uint256` {#VaultManager-nftForVault-address-}

No description

# Function `vaultForNft(uint256 nft) → address` {#VaultManager-vaultForNft-uint256-}

No description

# Function `createVault(address[] tokens, address strategyTreasury, address admin, bytes options) → contract IVaultGovernance vaultGovernance, contract IVault vault, uint256 nft` {#VaultManager-createVault-address---address-address-bytes-}

No description

# Function `supportsInterface(bytes4 interfaceId) → bool` {#VaultManager-supportsInterface-bytes4-}

No description

# Functions:

- [`constructor(bool permissionless, contract IProtocolGovernance protocolGovernance, contract IVaultFactory factory, contract IVaultGovernanceFactory governanceFactory)`](#VaultManagerGovernance-constructor-bool-contract-IProtocolGovernance-contract-IVaultFactory-contract-IVaultGovernanceFactory-)

- [`governanceParams()`](#VaultManagerGovernance-governanceParams--)

- [`pendingGovernanceParams()`](#VaultManagerGovernance-pendingGovernanceParams--)

- [`pendingGovernanceParamsTimestamp()`](#VaultManagerGovernance-pendingGovernanceParamsTimestamp--)

- [`setPendingGovernanceParams(struct IVaultManagerGovernance.GovernanceParams newGovernanceParams)`](#VaultManagerGovernance-setPendingGovernanceParams-struct-IVaultManagerGovernance-GovernanceParams-)

- [`commitGovernanceParams()`](#VaultManagerGovernance-commitGovernanceParams--)

# Function `constructor(bool permissionless, contract IProtocolGovernance protocolGovernance, contract IVaultFactory factory, contract IVaultGovernanceFactory governanceFactory)` {#VaultManagerGovernance-constructor-bool-contract-IProtocolGovernance-contract-IVaultFactory-contract-IVaultGovernanceFactory-}

No description

# Function `governanceParams() → struct IVaultManagerGovernance.GovernanceParams` {#VaultManagerGovernance-governanceParams--}

No description

# Function `pendingGovernanceParams() → struct IVaultManagerGovernance.GovernanceParams` {#VaultManagerGovernance-pendingGovernanceParams--}

No description

# Function `pendingGovernanceParamsTimestamp() → uint256` {#VaultManagerGovernance-pendingGovernanceParamsTimestamp--}

No description

# Function `setPendingGovernanceParams(struct IVaultManagerGovernance.GovernanceParams newGovernanceParams)` {#VaultManagerGovernance-setPendingGovernanceParams-struct-IVaultManagerGovernance-GovernanceParams-}

No description

# Function `commitGovernanceParams()` {#VaultManagerGovernance-commitGovernanceParams--}

No description

# Functions:

- [`lendingPool()`](#IAaveVaultManager-lendingPool--)

# Function `lendingPool() → contract ILendingPool` {#IAaveVaultManager-lendingPool--}

No description

# Functions:

- [`isAdmin()`](#IDefaultAccessControl-isAdmin--)

# Function `isAdmin() → bool` {#IDefaultAccessControl-isAdmin--}

No description

# Functions:

- [`hasVault(address vault)`](#IGatewayVault-hasVault-address-)

- [`vaultsTvl()`](#IGatewayVault-vaultsTvl--)

- [`vaultTvl(uint256 vaultNum)`](#IGatewayVault-vaultTvl-uint256-)

- [`vaultEarnings(uint256 vaultNum)`](#IGatewayVault-vaultEarnings-uint256-)

# Function `hasVault(address vault) → bool` {#IGatewayVault-hasVault-address-}

No description

# Function `vaultsTvl() → uint256[][] tokenAmounts` {#IGatewayVault-vaultsTvl--}

No description

# Function `vaultTvl(uint256 vaultNum) → uint256[]` {#IGatewayVault-vaultTvl-uint256-}

No description

# Function `vaultEarnings(uint256 vaultNum) → uint256[]` {#IGatewayVault-vaultEarnings-uint256-}

No description

# Functions:

- [`vaultOwnerNft(uint256 nft)`](#IGatewayVaultManager-vaultOwnerNft-uint256-)

- [`vaultOwner(uint256 nft)`](#IGatewayVaultManager-vaultOwner-uint256-)

# Function `vaultOwnerNft(uint256 nft) → uint256` {#IGatewayVaultManager-vaultOwnerNft-uint256-}

No description

# Function `vaultOwner(uint256 nft) → address` {#IGatewayVaultManager-vaultOwner-uint256-}

No description

# Functions:

- [`governanceParams()`](#ILpIssuerGovernance-governanceParams--)

- [`pendingGovernanceParams()`](#ILpIssuerGovernance-pendingGovernanceParams--)

- [`pendingGovernanceParamsTimestamp()`](#ILpIssuerGovernance-pendingGovernanceParamsTimestamp--)

- [`setPendingGovernanceParams(struct ILpIssuerGovernance.GovernanceParams newParams)`](#ILpIssuerGovernance-setPendingGovernanceParams-struct-ILpIssuerGovernance-GovernanceParams-)

- [`commitGovernanceParams()`](#ILpIssuerGovernance-commitGovernanceParams--)

# Events:

- [`SetPendingGovernanceParams(struct ILpIssuerGovernance.GovernanceParams)`](#ILpIssuerGovernance-SetPendingGovernanceParams-struct-ILpIssuerGovernance-GovernanceParams-)

- [`CommitGovernanceParams(struct ILpIssuerGovernance.GovernanceParams)`](#ILpIssuerGovernance-CommitGovernanceParams-struct-ILpIssuerGovernance-GovernanceParams-)

# Function `governanceParams() → struct ILpIssuerGovernance.GovernanceParams` {#ILpIssuerGovernance-governanceParams--}

No description

# Function `pendingGovernanceParams() → struct ILpIssuerGovernance.GovernanceParams` {#ILpIssuerGovernance-pendingGovernanceParams--}

No description

# Function `pendingGovernanceParamsTimestamp() → uint256` {#ILpIssuerGovernance-pendingGovernanceParamsTimestamp--}

No description

# Function `setPendingGovernanceParams(struct ILpIssuerGovernance.GovernanceParams newParams)` {#ILpIssuerGovernance-setPendingGovernanceParams-struct-ILpIssuerGovernance-GovernanceParams-}

No description

# Function `commitGovernanceParams()` {#ILpIssuerGovernance-commitGovernanceParams--}

No description

# Event `SetPendingGovernanceParams(struct ILpIssuerGovernance.GovernanceParams)` {#ILpIssuerGovernance-SetPendingGovernanceParams-struct-ILpIssuerGovernance-GovernanceParams-}

No description

# Event `CommitGovernanceParams(struct ILpIssuerGovernance.GovernanceParams)` {#ILpIssuerGovernance-CommitGovernanceParams-struct-ILpIssuerGovernance-GovernanceParams-}

No description

# Functions:

- [`claimAllowlist()`](#IProtocolGovernance-claimAllowlist--)

- [`pendingClaimAllowlistAdd()`](#IProtocolGovernance-pendingClaimAllowlistAdd--)

- [`isAllowedToClaim(address addr)`](#IProtocolGovernance-isAllowedToClaim-address-)

- [`maxTokensPerVault()`](#IProtocolGovernance-maxTokensPerVault--)

- [`governanceDelay()`](#IProtocolGovernance-governanceDelay--)

- [`strategyPerformanceFee()`](#IProtocolGovernance-strategyPerformanceFee--)

- [`protocolPerformanceFee()`](#IProtocolGovernance-protocolPerformanceFee--)

- [`protocolExitFee()`](#IProtocolGovernance-protocolExitFee--)

- [`protocolTreasury()`](#IProtocolGovernance-protocolTreasury--)

- [`gatewayVaultManager()`](#IProtocolGovernance-gatewayVaultManager--)

- [`setPendingParams(struct IProtocolGovernance.Params newParams)`](#IProtocolGovernance-setPendingParams-struct-IProtocolGovernance-Params-)

- [`commitParams()`](#IProtocolGovernance-commitParams--)

# Function `claimAllowlist() → address[]` {#IProtocolGovernance-claimAllowlist--}

No description

# Function `pendingClaimAllowlistAdd() → address[]` {#IProtocolGovernance-pendingClaimAllowlistAdd--}

No description

# Function `isAllowedToClaim(address addr) → bool` {#IProtocolGovernance-isAllowedToClaim-address-}

No description

# Function `maxTokensPerVault() → uint256` {#IProtocolGovernance-maxTokensPerVault--}

No description

# Function `governanceDelay() → uint256` {#IProtocolGovernance-governanceDelay--}

No description

# Function `strategyPerformanceFee() → uint256` {#IProtocolGovernance-strategyPerformanceFee--}

No description

# Function `protocolPerformanceFee() → uint256` {#IProtocolGovernance-protocolPerformanceFee--}

No description

# Function `protocolExitFee() → uint256` {#IProtocolGovernance-protocolExitFee--}

No description

# Function `protocolTreasury() → address` {#IProtocolGovernance-protocolTreasury--}

No description

# Function `gatewayVaultManager() → contract IGatewayVaultManager` {#IProtocolGovernance-gatewayVaultManager--}

No description

# Function `setPendingParams(struct IProtocolGovernance.Params newParams)` {#IProtocolGovernance-setPendingParams-struct-IProtocolGovernance-Params-}

No description

# Function `commitParams()` {#IProtocolGovernance-commitParams--}

No description

# Functions:

- [`positionManager()`](#IUniV3VaultManager-positionManager--)

# Function `positionManager() → contract INonfungiblePositionManager` {#IUniV3VaultManager-positionManager--}

No description

# Functions:

- [`vaultGovernance()`](#IVault-vaultGovernance--)

- [`tvl()`](#IVault-tvl--)

- [`earnings()`](#IVault-earnings--)

- [`push(address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options)`](#IVault-push-address---uint256---bool-bytes-)

- [`transferAndPush(address from, address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options)`](#IVault-transferAndPush-address-address---uint256---bool-bytes-)

- [`pull(address to, address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options)`](#IVault-pull-address-address---uint256---bool-bytes-)

- [`collectEarnings(address to, bytes options)`](#IVault-collectEarnings-address-bytes-)

- [`reclaimTokens(address to, address[] tokens)`](#IVault-reclaimTokens-address-address---)

# Events:

- [`Push(uint256[] tokenAmounts)`](#IVault-Push-uint256---)

- [`Pull(address to, uint256[] tokenAmounts)`](#IVault-Pull-address-uint256---)

- [`CollectEarnings(address to, uint256[] tokenAmounts)`](#IVault-CollectEarnings-address-uint256---)

- [`ReclaimTokens(address to, address[] tokens, uint256[] tokenAmounts)`](#IVault-ReclaimTokens-address-address---uint256---)

# Function `vaultGovernance() → contract IVaultGovernance` {#IVault-vaultGovernance--}

No description

# Function `tvl() → uint256[] tokenAmounts` {#IVault-tvl--}

No description

# Function `earnings() → uint256[] tokenAmounts` {#IVault-earnings--}

No description

# Function `push(address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options) → uint256[] actualTokenAmounts` {#IVault-push-address---uint256---bool-bytes-}

No description

# Function `transferAndPush(address from, address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options) → uint256[] actualTokenAmounts` {#IVault-transferAndPush-address-address---uint256---bool-bytes-}

No description

# Function `pull(address to, address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options) → uint256[] actualTokenAmounts` {#IVault-pull-address-address---uint256---bool-bytes-}

No description

# Function `collectEarnings(address to, bytes options) → uint256[] collectedEarnings` {#IVault-collectEarnings-address-bytes-}

No description

# Function `reclaimTokens(address to, address[] tokens)` {#IVault-reclaimTokens-address-address---}

No description

# Event `Push(uint256[] tokenAmounts)` {#IVault-Push-uint256---}

No description

# Event `Pull(address to, uint256[] tokenAmounts)` {#IVault-Pull-address-uint256---}

No description

# Event `CollectEarnings(address to, uint256[] tokenAmounts)` {#IVault-CollectEarnings-address-uint256---}

No description

# Event `ReclaimTokens(address to, address[] tokens, uint256[] tokenAmounts)` {#IVault-ReclaimTokens-address-address---uint256---}

No description

# Functions:

- [`deployVault(contract IVaultGovernance vaultGovernance, bytes options)`](#IVaultFactory-deployVault-contract-IVaultGovernance-bytes-)

# Function `deployVault(contract IVaultGovernance vaultGovernance, bytes options) → contract IVault vault` {#IVaultFactory-deployVault-contract-IVaultGovernance-bytes-}

No description

# Functions:

- [`isProtocolAdmin()`](#IVaultGovernance-isProtocolAdmin--)

- [`vaultTokens()`](#IVaultGovernance-vaultTokens--)

- [`isVaultToken(address token)`](#IVaultGovernance-isVaultToken-address-)

- [`vaultManager()`](#IVaultGovernance-vaultManager--)

- [`pendingVaultManager()`](#IVaultGovernance-pendingVaultManager--)

- [`pendingVaultManagerTimestamp()`](#IVaultGovernance-pendingVaultManagerTimestamp--)

- [`setPendingVaultManager(contract IVaultManager newManager)`](#IVaultGovernance-setPendingVaultManager-contract-IVaultManager-)

- [`commitVaultManager()`](#IVaultGovernance-commitVaultManager--)

- [`strategyTreasury()`](#IVaultGovernance-strategyTreasury--)

- [`pendingStrategyTreasury()`](#IVaultGovernance-pendingStrategyTreasury--)

- [`pendingStrategyTreasuryTimestamp()`](#IVaultGovernance-pendingStrategyTreasuryTimestamp--)

- [`setPendingStrategyTreasury(address newTreasury)`](#IVaultGovernance-setPendingStrategyTreasury-address-)

- [`commitStrategyTreasury()`](#IVaultGovernance-commitStrategyTreasury--)

# Events:

- [`SetPendingVaultManager(contract IVaultManager)`](#IVaultGovernance-SetPendingVaultManager-contract-IVaultManager-)

- [`CommitVaultManager(contract IVaultManager)`](#IVaultGovernance-CommitVaultManager-contract-IVaultManager-)

- [`SetPendingStrategyTreasury(address)`](#IVaultGovernance-SetPendingStrategyTreasury-address-)

- [`CommitStrategyTreasury(address)`](#IVaultGovernance-CommitStrategyTreasury-address-)

# Function `isProtocolAdmin() → bool` {#IVaultGovernance-isProtocolAdmin--}

No description

# Function `vaultTokens() → address[]` {#IVaultGovernance-vaultTokens--}

No description

# Function `isVaultToken(address token) → bool` {#IVaultGovernance-isVaultToken-address-}

No description

# Function `vaultManager() → contract IVaultManager` {#IVaultGovernance-vaultManager--}

No description

# Function `pendingVaultManager() → contract IVaultManager` {#IVaultGovernance-pendingVaultManager--}

No description

# Function `pendingVaultManagerTimestamp() → uint256` {#IVaultGovernance-pendingVaultManagerTimestamp--}

No description

# Function `setPendingVaultManager(contract IVaultManager newManager)` {#IVaultGovernance-setPendingVaultManager-contract-IVaultManager-}

No description

# Function `commitVaultManager()` {#IVaultGovernance-commitVaultManager--}

No description

# Function `strategyTreasury() → address` {#IVaultGovernance-strategyTreasury--}

No description

# Function `pendingStrategyTreasury() → address` {#IVaultGovernance-pendingStrategyTreasury--}

No description

# Function `pendingStrategyTreasuryTimestamp() → uint256` {#IVaultGovernance-pendingStrategyTreasuryTimestamp--}

No description

# Function `setPendingStrategyTreasury(address newTreasury)` {#IVaultGovernance-setPendingStrategyTreasury-address-}

No description

# Function `commitStrategyTreasury()` {#IVaultGovernance-commitStrategyTreasury--}

No description

# Event `SetPendingVaultManager(contract IVaultManager)` {#IVaultGovernance-SetPendingVaultManager-contract-IVaultManager-}

No description

# Event `CommitVaultManager(contract IVaultManager)` {#IVaultGovernance-CommitVaultManager-contract-IVaultManager-}

No description

# Event `SetPendingStrategyTreasury(address)` {#IVaultGovernance-SetPendingStrategyTreasury-address-}

No description

# Event `CommitStrategyTreasury(address)` {#IVaultGovernance-CommitStrategyTreasury-address-}

No description

# Functions:

- [`deployVaultGovernance(address[] tokens, contract IVaultManager manager, address treasury, address admin)`](#IVaultGovernanceFactory-deployVaultGovernance-address---contract-IVaultManager-address-address-)

# Function `deployVaultGovernance(address[] tokens, contract IVaultManager manager, address treasury, address admin) → contract IVaultGovernance vaultGovernance` {#IVaultGovernanceFactory-deployVaultGovernance-address---contract-IVaultManager-address-address-}

No description

# Functions:

- [`nftForVault(address vault)`](#IVaultManager-nftForVault-address-)

- [`vaultForNft(uint256 nft)`](#IVaultManager-vaultForNft-uint256-)

- [`createVault(address[] tokens, address strategyTreasury, address admin, bytes options)`](#IVaultManager-createVault-address---address-address-bytes-)

# Events:

- [`CreateVault(address vaultGovernance, address vault, uint256 nft, address[] tokens, bytes options)`](#IVaultManager-CreateVault-address-address-uint256-address---bytes-)

# Function `nftForVault(address vault) → uint256` {#IVaultManager-nftForVault-address-}

No description

# Function `vaultForNft(uint256 nft) → address` {#IVaultManager-vaultForNft-uint256-}

No description

# Function `createVault(address[] tokens, address strategyTreasury, address admin, bytes options) → contract IVaultGovernance vaultGovernance, contract IVault vault, uint256 nft` {#IVaultManager-createVault-address---address-address-bytes-}

No description

# Event `CreateVault(address vaultGovernance, address vault, uint256 nft, address[] tokens, bytes options)` {#IVaultManager-CreateVault-address-address-uint256-address---bytes-}

No description

# Functions:

- [`governanceParams()`](#IVaultManagerGovernance-governanceParams--)

- [`pendingGovernanceParams()`](#IVaultManagerGovernance-pendingGovernanceParams--)

- [`pendingGovernanceParamsTimestamp()`](#IVaultManagerGovernance-pendingGovernanceParamsTimestamp--)

- [`setPendingGovernanceParams(struct IVaultManagerGovernance.GovernanceParams newParams)`](#IVaultManagerGovernance-setPendingGovernanceParams-struct-IVaultManagerGovernance-GovernanceParams-)

- [`commitGovernanceParams()`](#IVaultManagerGovernance-commitGovernanceParams--)

# Events:

- [`SetPendingGovernanceParams(struct IVaultManagerGovernance.GovernanceParams)`](#IVaultManagerGovernance-SetPendingGovernanceParams-struct-IVaultManagerGovernance-GovernanceParams-)

- [`CommitGovernanceParams(struct IVaultManagerGovernance.GovernanceParams)`](#IVaultManagerGovernance-CommitGovernanceParams-struct-IVaultManagerGovernance-GovernanceParams-)

# Function `governanceParams() → struct IVaultManagerGovernance.GovernanceParams` {#IVaultManagerGovernance-governanceParams--}

No description

# Function `pendingGovernanceParams() → struct IVaultManagerGovernance.GovernanceParams` {#IVaultManagerGovernance-pendingGovernanceParams--}

No description

# Function `pendingGovernanceParamsTimestamp() → uint256` {#IVaultManagerGovernance-pendingGovernanceParamsTimestamp--}

No description

# Function `setPendingGovernanceParams(struct IVaultManagerGovernance.GovernanceParams newParams)` {#IVaultManagerGovernance-setPendingGovernanceParams-struct-IVaultManagerGovernance-GovernanceParams-}

No description

# Function `commitGovernanceParams()` {#IVaultManagerGovernance-commitGovernanceParams--}

No description

# Event `SetPendingGovernanceParams(struct IVaultManagerGovernance.GovernanceParams)` {#IVaultManagerGovernance-SetPendingGovernanceParams-struct-IVaultManagerGovernance-GovernanceParams-}

No description

# Event `CommitGovernanceParams(struct IVaultManagerGovernance.GovernanceParams)` {#IVaultManagerGovernance-CommitGovernanceParams-struct-IVaultManagerGovernance-GovernanceParams-}

No description

# Functions:

- [`deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)`](#ILendingPool-deposit-address-uint256-address-uint16-)

- [`withdraw(address asset, uint256 amount, address to)`](#ILendingPool-withdraw-address-uint256-address-)

- [`borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)`](#ILendingPool-borrow-address-uint256-uint256-uint16-address-)

- [`repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf)`](#ILendingPool-repay-address-uint256-uint256-address-)

- [`swapBorrowRateMode(address asset, uint256 rateMode)`](#ILendingPool-swapBorrowRateMode-address-uint256-)

- [`rebalanceStableBorrowRate(address asset, address user)`](#ILendingPool-rebalanceStableBorrowRate-address-address-)

- [`setUserUseReserveAsCollateral(address asset, bool useAsCollateral)`](#ILendingPool-setUserUseReserveAsCollateral-address-bool-)

- [`liquidationCall(address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool receiveAToken)`](#ILendingPool-liquidationCall-address-address-address-uint256-bool-)

- [`flashLoan(address receiverAddress, address[] assets, uint256[] amounts, uint256[] modes, address onBehalfOf, bytes params, uint16 referralCode)`](#ILendingPool-flashLoan-address-address---uint256---uint256---address-bytes-uint16-)

- [`getUserAccountData(address user)`](#ILendingPool-getUserAccountData-address-)

- [`initReserve(address reserve, address aTokenAddress, address stableDebtAddress, address variableDebtAddress, address interestRateStrategyAddress)`](#ILendingPool-initReserve-address-address-address-address-address-)

- [`setReserveInterestRateStrategyAddress(address reserve, address rateStrategyAddress)`](#ILendingPool-setReserveInterestRateStrategyAddress-address-address-)

- [`setConfiguration(address reserve, uint256 configuration)`](#ILendingPool-setConfiguration-address-uint256-)

- [`getConfiguration(address asset)`](#ILendingPool-getConfiguration-address-)

- [`getUserConfiguration(address user)`](#ILendingPool-getUserConfiguration-address-)

- [`getReserveNormalizedIncome(address asset)`](#ILendingPool-getReserveNormalizedIncome-address-)

- [`getReserveNormalizedVariableDebt(address asset)`](#ILendingPool-getReserveNormalizedVariableDebt-address-)

- [`getReserveData(address asset)`](#ILendingPool-getReserveData-address-)

- [`finalizeTransfer(address asset, address from, address to, uint256 amount, uint256 balanceFromAfter, uint256 balanceToBefore)`](#ILendingPool-finalizeTransfer-address-address-address-uint256-uint256-uint256-)

- [`getReservesList()`](#ILendingPool-getReservesList--)

- [`getAddressesProvider()`](#ILendingPool-getAddressesProvider--)

- [`setPause(bool val)`](#ILendingPool-setPause-bool-)

- [`paused()`](#ILendingPool-paused--)

# Events:

- [`Deposit(address reserve, address user, address onBehalfOf, uint256 amount, uint16 referral)`](#ILendingPool-Deposit-address-address-address-uint256-uint16-)

- [`Withdraw(address reserve, address user, address to, uint256 amount)`](#ILendingPool-Withdraw-address-address-address-uint256-)

- [`Borrow(address reserve, address user, address onBehalfOf, uint256 amount, uint256 borrowRateMode, uint256 borrowRate, uint16 referral)`](#ILendingPool-Borrow-address-address-address-uint256-uint256-uint256-uint16-)

- [`Repay(address reserve, address user, address repayer, uint256 amount)`](#ILendingPool-Repay-address-address-address-uint256-)

- [`Swap(address reserve, address user, uint256 rateMode)`](#ILendingPool-Swap-address-address-uint256-)

- [`ReserveUsedAsCollateralEnabled(address reserve, address user)`](#ILendingPool-ReserveUsedAsCollateralEnabled-address-address-)

- [`ReserveUsedAsCollateralDisabled(address reserve, address user)`](#ILendingPool-ReserveUsedAsCollateralDisabled-address-address-)

- [`RebalanceStableBorrowRate(address reserve, address user)`](#ILendingPool-RebalanceStableBorrowRate-address-address-)

- [`FlashLoan(address target, address initiator, address asset, uint256 amount, uint256 premium, uint16 referralCode)`](#ILendingPool-FlashLoan-address-address-address-uint256-uint256-uint16-)

- [`Paused()`](#ILendingPool-Paused--)

- [`Unpaused()`](#ILendingPool-Unpaused--)

- [`LiquidationCall(address collateralAsset, address debtAsset, address user, uint256 debtToCover, uint256 liquidatedCollateralAmount, address liquidator, bool receiveAToken)`](#ILendingPool-LiquidationCall-address-address-address-uint256-uint256-address-bool-)

- [`ReserveDataUpdated(address reserve, uint256 liquidityRate, uint256 stableBorrowRate, uint256 variableBorrowRate, uint256 liquidityIndex, uint256 variableBorrowIndex)`](#ILendingPool-ReserveDataUpdated-address-uint256-uint256-uint256-uint256-uint256-)

# Function `deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)` {#ILendingPool-deposit-address-uint256-address-uint16-}

Deposits an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.

- E.g. User deposits 100 USDC and gets in return 100 aUSDC

## Parameters:

- `asset`: The address of the underlying asset to deposit

- `amount`: The amount to be deposited

- `onBehalfOf`: The address that will receive the aTokens, same as msg.sender if the user

  wants to receive them on his own wallet, or a different address if the beneficiary of aTokens

  is a different wallet

- `referralCode`: Code used to register the integrator originating the operation, for potential rewards.

  0 if the action is executed directly by the user, without any middle-man

# Function `withdraw(address asset, uint256 amount, address to) → uint256` {#ILendingPool-withdraw-address-uint256-address-}

Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned

E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC

## Parameters:

- `asset`: The address of the underlying asset to withdraw

- `amount`: The underlying amount to be withdrawn

  - Send the value type(uint256).max in order to withdraw the whole aToken balance

- `to`: Address that will receive the underlying, same as msg.sender if the user

  wants to receive it on his own wallet, or a different address if the beneficiary is a

  different wallet

## Return Values:

- The final amount withdrawn

# Function `borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)` {#ILendingPool-borrow-address-uint256-uint256-uint16-address-}

Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower

already deposited enough collateral, or he was given enough allowance by a credit delegator on the

corresponding debt token (StableDebtToken or VariableDebtToken)

- E.g. User borrows 100 USDC passing as `onBehalfOf` his own address, receiving the 100 USDC in his wallet

  and 100 stable/variable debt tokens, depending on the `interestRateMode`

## Parameters:

- `asset`: The address of the underlying asset to borrow

- `amount`: The amount to be borrowed

- `interestRateMode`: The interest rate mode at which the user wants to borrow: 1 for Stable, 2 for Variable

- `referralCode`: Code used to register the integrator originating the operation, for potential rewards.

  0 if the action is executed directly by the user, without any middle-man

- `onBehalfOf`: Address of the user who will receive the debt. Should be the address of the borrower itself

calling the function if he wants to borrow against his own collateral, or the address of the credit delegator

if he has been given credit delegation allowance

# Function `repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) → uint256` {#ILendingPool-repay-address-uint256-uint256-address-}

No description

## Parameters:

- `asset`: The address of the borrowed underlying asset previously borrowed

- `amount`: The amount to repay

- Send the value type(uint256).max in order to repay the whole debt for `asset` on the specific `debtMode`

- `rateMode`: The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable

- `onBehalfOf`: Address of the user who will get his debt reduced/removed. Should be the address of the

user calling the function if he wants to reduce/remove his own debt, or the address of any other

other borrower whose debt should be removed

## Return Values:

- The final amount repaid

# Function `swapBorrowRateMode(address asset, uint256 rateMode)` {#ILendingPool-swapBorrowRateMode-address-uint256-}

Allows a borrower to swap his debt between stable and variable mode, or viceversa

## Parameters:

- `asset`: The address of the underlying asset borrowed

- `rateMode`: The rate mode that the user wants to swap to

# Function `rebalanceStableBorrowRate(address asset, address user)` {#ILendingPool-rebalanceStableBorrowRate-address-address-}

Rebalances the stable interest rate of a user to the current stable rate defined on the reserve.

- Users can be rebalanced if the following conditions are satisfied:

    1. Usage ratio is above 95%

    2. the current deposit APY is below REBALANCE_UP_THRESHOLD * maxVariableBorrowRate, which means that too much has been

       borrowed at a stable rate and depositors are not earning enough

## Parameters:

- `asset`: The address of the underlying asset borrowed

- `user`: The address of the user to be rebalanced

# Function `setUserUseReserveAsCollateral(address asset, bool useAsCollateral)` {#ILendingPool-setUserUseReserveAsCollateral-address-bool-}

Allows depositors to enable/disable a specific deposited asset as collateral

## Parameters:

- `asset`: The address of the underlying asset deposited

- `useAsCollateral`: `true` if the user wants to use the deposit as collateral, `false` otherwise

# Function `liquidationCall(address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool receiveAToken)` {#ILendingPool-liquidationCall-address-address-address-uint256-bool-}

Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1

- The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives

  a proportionally amount of the `collateralAsset` plus a bonus to cover market risk

## Parameters:

- `collateralAsset`: The address of the underlying asset used as collateral, to receive as result of the liquidation

- `debtAsset`: The address of the underlying borrowed asset to be repaid with the liquidation

- `user`: The address of the borrower getting liquidated

- `debtToCover`: The debt amount of borrowed `asset` the liquidator wants to cover

- `receiveAToken`: `true` if the liquidators wants to receive the collateral aTokens, `false` if he wants

to receive the underlying collateral asset directly

# Function `flashLoan(address receiverAddress, address[] assets, uint256[] amounts, uint256[] modes, address onBehalfOf, bytes params, uint16 referralCode)` {#ILendingPool-flashLoan-address-address---uint256---uint256---address-bytes-uint16-}

Allows smartcontracts to access the liquidity of the pool within one transaction,

as long as the amount taken plus a fee is returned.

IMPORTANT There are security concerns for developers of flashloan receiver contracts that must be kept into consideration.

For further details please visit https://developers.aave.com

## Parameters:

- `receiverAddress`: The address of the contract receiving the funds, implementing the IFlashLoanReceiver interface

- `assets`: The addresses of the assets being flash-borrowed

- `amounts`: The amounts amounts being flash-borrowed

- `modes`: Types of the debt to open if the flash loan is not returned:

  0 -> Don't open any debt, just revert if funds can't be transferred from the receiver

  1 -> Open debt at stable rate for the value of the amount flash-borrowed to the `onBehalfOf` address

  2 -> Open debt at variable rate for the value of the amount flash-borrowed to the `onBehalfOf` address

- `onBehalfOf`: The address  that will receive the debt in the case of using on `modes` 1 or 2

- `params`: Variadic packed params to pass to the receiver as extra information

- `referralCode`: Code used to register the integrator originating the operation, for potential rewards.

  0 if the action is executed directly by the user, without any middle-man

# Function `getUserAccountData(address user) → uint256 totalCollateralETH, uint256 totalDebtETH, uint256 availableBorrowsETH, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor` {#ILendingPool-getUserAccountData-address-}

Returns the user account data across all the reserves

## Parameters:

- `user`: The address of the user

## Return Values:

- totalCollateralETH the total collateral in ETH of the user

- totalDebtETH the total debt in ETH of the user

- availableBorrowsETH the borrowing power left of the user

- currentLiquidationThreshold the liquidation threshold of the user

- ltv the loan to value of the user

- healthFactor the current health factor of the user

# Function `initReserve(address reserve, address aTokenAddress, address stableDebtAddress, address variableDebtAddress, address interestRateStrategyAddress)` {#ILendingPool-initReserve-address-address-address-address-address-}

No description

# Function `setReserveInterestRateStrategyAddress(address reserve, address rateStrategyAddress)` {#ILendingPool-setReserveInterestRateStrategyAddress-address-address-}

No description

# Function `setConfiguration(address reserve, uint256 configuration)` {#ILendingPool-setConfiguration-address-uint256-}

No description

# Function `getConfiguration(address asset) → struct DataTypes.ReserveConfigurationMap` {#ILendingPool-getConfiguration-address-}

Returns the configuration of the reserve

## Parameters:

- `asset`: The address of the underlying asset of the reserve

## Return Values:

- The configuration of the reserve

# Function `getUserConfiguration(address user) → struct DataTypes.UserConfigurationMap` {#ILendingPool-getUserConfiguration-address-}

Returns the configuration of the user across all the reserves

## Parameters:

- `user`: The user address

## Return Values:

- The configuration of the user

# Function `getReserveNormalizedIncome(address asset) → uint256` {#ILendingPool-getReserveNormalizedIncome-address-}

Returns the normalized income normalized income of the reserve

## Parameters:

- `asset`: The address of the underlying asset of the reserve

## Return Values:

- The reserve's normalized income

# Function `getReserveNormalizedVariableDebt(address asset) → uint256` {#ILendingPool-getReserveNormalizedVariableDebt-address-}

Returns the normalized variable debt per unit of asset

## Parameters:

- `asset`: The address of the underlying asset of the reserve

## Return Values:

- The reserve normalized variable debt

# Function `getReserveData(address asset) → struct DataTypes.ReserveData` {#ILendingPool-getReserveData-address-}

Returns the state and configuration of the reserve

## Parameters:

- `asset`: The address of the underlying asset of the reserve

## Return Values:

- The state of the reserve

# Function `finalizeTransfer(address asset, address from, address to, uint256 amount, uint256 balanceFromAfter, uint256 balanceToBefore)` {#ILendingPool-finalizeTransfer-address-address-address-uint256-uint256-uint256-}

No description

# Function `getReservesList() → address[]` {#ILendingPool-getReservesList--}

No description

# Function `getAddressesProvider() → contract ILendingPoolAddressesProvider` {#ILendingPool-getAddressesProvider--}

No description

# Function `setPause(bool val)` {#ILendingPool-setPause-bool-}

No description

# Function `paused() → bool` {#ILendingPool-paused--}

No description

# Event `Deposit(address reserve, address user, address onBehalfOf, uint256 amount, uint16 referral)` {#ILendingPool-Deposit-address-address-address-uint256-uint16-}

Emitted on deposit()

## Parameters:

- `reserve`: The address of the underlying asset of the reserve

- `user`: The address initiating the deposit

- `onBehalfOf`: The beneficiary of the deposit, receiving the aTokens

- `amount`: The amount deposited

- `referral`: The referral code used

# Event `Withdraw(address reserve, address user, address to, uint256 amount)` {#ILendingPool-Withdraw-address-address-address-uint256-}

Emitted on withdraw()

## Parameters:

- `reserve`: The address of the underlyng asset being withdrawn

- `user`: The address initiating the withdrawal, owner of aTokens

- `to`: Address that will receive the underlying

- `amount`: The amount to be withdrawn

# Event `Borrow(address reserve, address user, address onBehalfOf, uint256 amount, uint256 borrowRateMode, uint256 borrowRate, uint16 referral)` {#ILendingPool-Borrow-address-address-address-uint256-uint256-uint256-uint16-}

Emitted on borrow() and flashLoan() when debt needs to be opened

## Parameters:

- `reserve`: The address of the underlying asset being borrowed

- `user`: The address of the user initiating the borrow(), receiving the funds on borrow() or just

initiator of the transaction on flashLoan()

- `onBehalfOf`: The address that will be getting the debt

- `amount`: The amount borrowed out

- `borrowRateMode`: The rate mode: 1 for Stable, 2 for Variable

- `borrowRate`: The numeric rate at which the user has borrowed

- `referral`: The referral code used

# Event `Repay(address reserve, address user, address repayer, uint256 amount)` {#ILendingPool-Repay-address-address-address-uint256-}

Emitted on repay()

## Parameters:

- `reserve`: The address of the underlying asset of the reserve

- `user`: The beneficiary of the repayment, getting his debt reduced

- `repayer`: The address of the user initiating the repay(), providing the funds

- `amount`: The amount repaid

# Event `Swap(address reserve, address user, uint256 rateMode)` {#ILendingPool-Swap-address-address-uint256-}

Emitted on swapBorrowRateMode()

## Parameters:

- `reserve`: The address of the underlying asset of the reserve

- `user`: The address of the user swapping his rate mode

- `rateMode`: The rate mode that the user wants to swap to

# Event `ReserveUsedAsCollateralEnabled(address reserve, address user)` {#ILendingPool-ReserveUsedAsCollateralEnabled-address-address-}

Emitted on setUserUseReserveAsCollateral()

## Parameters:

- `reserve`: The address of the underlying asset of the reserve

- `user`: The address of the user enabling the usage as collateral

# Event `ReserveUsedAsCollateralDisabled(address reserve, address user)` {#ILendingPool-ReserveUsedAsCollateralDisabled-address-address-}

Emitted on setUserUseReserveAsCollateral()

## Parameters:

- `reserve`: The address of the underlying asset of the reserve

- `user`: The address of the user enabling the usage as collateral

# Event `RebalanceStableBorrowRate(address reserve, address user)` {#ILendingPool-RebalanceStableBorrowRate-address-address-}

Emitted on rebalanceStableBorrowRate()

## Parameters:

- `reserve`: The address of the underlying asset of the reserve

- `user`: The address of the user for which the rebalance has been executed

# Event `FlashLoan(address target, address initiator, address asset, uint256 amount, uint256 premium, uint16 referralCode)` {#ILendingPool-FlashLoan-address-address-address-uint256-uint256-uint16-}

Emitted on flashLoan()

## Parameters:

- `target`: The address of the flash loan receiver contract

- `initiator`: The address initiating the flash loan

- `asset`: The address of the asset being flash borrowed

- `amount`: The amount flash borrowed

- `premium`: The fee flash borrowed

- `referralCode`: The referral code used

# Event `Paused()` {#ILendingPool-Paused--}

Emitted when the pause is triggered.

# Event `Unpaused()` {#ILendingPool-Unpaused--}

Emitted when the pause is lifted.

# Event `LiquidationCall(address collateralAsset, address debtAsset, address user, uint256 debtToCover, uint256 liquidatedCollateralAmount, address liquidator, bool receiveAToken)` {#ILendingPool-LiquidationCall-address-address-address-uint256-uint256-address-bool-}

Emitted when a borrower is liquidated. This event is emitted by the LendingPool via

LendingPoolCollateral manager using a DELEGATECALL

This allows to have the events in the generated ABI for LendingPool.

## Parameters:

- `collateralAsset`: The address of the underlying asset used as collateral, to receive as result of the liquidation

- `debtAsset`: The address of the underlying borrowed asset to be repaid with the liquidation

- `user`: The address of the borrower getting liquidated

- `debtToCover`: The debt amount of borrowed `asset` the liquidator wants to cover

- `liquidatedCollateralAmount`: The amount of collateral received by the liiquidator

- `liquidator`: The address of the liquidator

- `receiveAToken`: `true` if the liquidators wants to receive the collateral aTokens, `false` if he wants

to receive the underlying collateral asset directly

# Event `ReserveDataUpdated(address reserve, uint256 liquidityRate, uint256 stableBorrowRate, uint256 variableBorrowRate, uint256 liquidityIndex, uint256 variableBorrowIndex)` {#ILendingPool-ReserveDataUpdated-address-uint256-uint256-uint256-uint256-uint256-}

Emitted when the state of a reserve is updated. NOTE: This event is actually declared

in the ReserveLogic library and emitted in the updateInterestRates() function. Since the function is internal,

the event will actually be fired by the LendingPool contract. The event is therefore replicated here so it

gets added to the LendingPool ABI

## Parameters:

- `reserve`: The address of the underlying asset of the reserve

- `liquidityRate`: The new liquidity rate

- `stableBorrowRate`: The new stable borrow rate

- `variableBorrowRate`: The new variable borrow rate

- `liquidityIndex`: The new liquidity index

- `variableBorrowIndex`: The new variable borrow index

Main registry of addresses part of or connected to the protocol, including permissioned roles

- Acting also as factory of proxies and admin of those, so with right to change its implementations

- Owned by the Aave Governance

# Functions:

- [`getMarketId()`](#ILendingPoolAddressesProvider-getMarketId--)

- [`setMarketId(string marketId)`](#ILendingPoolAddressesProvider-setMarketId-string-)

- [`setAddress(bytes32 id, address newAddress)`](#ILendingPoolAddressesProvider-setAddress-bytes32-address-)

- [`setAddressAsProxy(bytes32 id, address impl)`](#ILendingPoolAddressesProvider-setAddressAsProxy-bytes32-address-)

- [`getAddress(bytes32 id)`](#ILendingPoolAddressesProvider-getAddress-bytes32-)

- [`getLendingPool()`](#ILendingPoolAddressesProvider-getLendingPool--)

- [`setLendingPoolImpl(address pool)`](#ILendingPoolAddressesProvider-setLendingPoolImpl-address-)

- [`getLendingPoolConfigurator()`](#ILendingPoolAddressesProvider-getLendingPoolConfigurator--)

- [`setLendingPoolConfiguratorImpl(address configurator)`](#ILendingPoolAddressesProvider-setLendingPoolConfiguratorImpl-address-)

- [`getLendingPoolCollateralManager()`](#ILendingPoolAddressesProvider-getLendingPoolCollateralManager--)

- [`setLendingPoolCollateralManager(address manager)`](#ILendingPoolAddressesProvider-setLendingPoolCollateralManager-address-)

- [`getPoolAdmin()`](#ILendingPoolAddressesProvider-getPoolAdmin--)

- [`setPoolAdmin(address admin)`](#ILendingPoolAddressesProvider-setPoolAdmin-address-)

- [`getEmergencyAdmin()`](#ILendingPoolAddressesProvider-getEmergencyAdmin--)

- [`setEmergencyAdmin(address admin)`](#ILendingPoolAddressesProvider-setEmergencyAdmin-address-)

- [`getPriceOracle()`](#ILendingPoolAddressesProvider-getPriceOracle--)

- [`setPriceOracle(address priceOracle)`](#ILendingPoolAddressesProvider-setPriceOracle-address-)

- [`getLendingRateOracle()`](#ILendingPoolAddressesProvider-getLendingRateOracle--)

- [`setLendingRateOracle(address lendingRateOracle)`](#ILendingPoolAddressesProvider-setLendingRateOracle-address-)

# Events:

- [`MarketIdSet(string newMarketId)`](#ILendingPoolAddressesProvider-MarketIdSet-string-)

- [`LendingPoolUpdated(address newAddress)`](#ILendingPoolAddressesProvider-LendingPoolUpdated-address-)

- [`ConfigurationAdminUpdated(address newAddress)`](#ILendingPoolAddressesProvider-ConfigurationAdminUpdated-address-)

- [`EmergencyAdminUpdated(address newAddress)`](#ILendingPoolAddressesProvider-EmergencyAdminUpdated-address-)

- [`LendingPoolConfiguratorUpdated(address newAddress)`](#ILendingPoolAddressesProvider-LendingPoolConfiguratorUpdated-address-)

- [`LendingPoolCollateralManagerUpdated(address newAddress)`](#ILendingPoolAddressesProvider-LendingPoolCollateralManagerUpdated-address-)

- [`PriceOracleUpdated(address newAddress)`](#ILendingPoolAddressesProvider-PriceOracleUpdated-address-)

- [`LendingRateOracleUpdated(address newAddress)`](#ILendingPoolAddressesProvider-LendingRateOracleUpdated-address-)

- [`ProxyCreated(bytes32 id, address newAddress)`](#ILendingPoolAddressesProvider-ProxyCreated-bytes32-address-)

- [`AddressSet(bytes32 id, address newAddress, bool hasProxy)`](#ILendingPoolAddressesProvider-AddressSet-bytes32-address-bool-)

# Function `getMarketId() → string` {#ILendingPoolAddressesProvider-getMarketId--}

No description

# Function `setMarketId(string marketId)` {#ILendingPoolAddressesProvider-setMarketId-string-}

No description

# Function `setAddress(bytes32 id, address newAddress)` {#ILendingPoolAddressesProvider-setAddress-bytes32-address-}

No description

# Function `setAddressAsProxy(bytes32 id, address impl)` {#ILendingPoolAddressesProvider-setAddressAsProxy-bytes32-address-}

No description

# Function `getAddress(bytes32 id) → address` {#ILendingPoolAddressesProvider-getAddress-bytes32-}

No description

# Function `getLendingPool() → address` {#ILendingPoolAddressesProvider-getLendingPool--}

No description

# Function `setLendingPoolImpl(address pool)` {#ILendingPoolAddressesProvider-setLendingPoolImpl-address-}

No description

# Function `getLendingPoolConfigurator() → address` {#ILendingPoolAddressesProvider-getLendingPoolConfigurator--}

No description

# Function `setLendingPoolConfiguratorImpl(address configurator)` {#ILendingPoolAddressesProvider-setLendingPoolConfiguratorImpl-address-}

No description

# Function `getLendingPoolCollateralManager() → address` {#ILendingPoolAddressesProvider-getLendingPoolCollateralManager--}

No description

# Function `setLendingPoolCollateralManager(address manager)` {#ILendingPoolAddressesProvider-setLendingPoolCollateralManager-address-}

No description

# Function `getPoolAdmin() → address` {#ILendingPoolAddressesProvider-getPoolAdmin--}

No description

# Function `setPoolAdmin(address admin)` {#ILendingPoolAddressesProvider-setPoolAdmin-address-}

No description

# Function `getEmergencyAdmin() → address` {#ILendingPoolAddressesProvider-getEmergencyAdmin--}

No description

# Function `setEmergencyAdmin(address admin)` {#ILendingPoolAddressesProvider-setEmergencyAdmin-address-}

No description

# Function `getPriceOracle() → address` {#ILendingPoolAddressesProvider-getPriceOracle--}

No description

# Function `setPriceOracle(address priceOracle)` {#ILendingPoolAddressesProvider-setPriceOracle-address-}

No description

# Function `getLendingRateOracle() → address` {#ILendingPoolAddressesProvider-getLendingRateOracle--}

No description

# Function `setLendingRateOracle(address lendingRateOracle)` {#ILendingPoolAddressesProvider-setLendingRateOracle-address-}

No description

# Event `MarketIdSet(string newMarketId)` {#ILendingPoolAddressesProvider-MarketIdSet-string-}

No description

# Event `LendingPoolUpdated(address newAddress)` {#ILendingPoolAddressesProvider-LendingPoolUpdated-address-}

No description

# Event `ConfigurationAdminUpdated(address newAddress)` {#ILendingPoolAddressesProvider-ConfigurationAdminUpdated-address-}

No description

# Event `EmergencyAdminUpdated(address newAddress)` {#ILendingPoolAddressesProvider-EmergencyAdminUpdated-address-}

No description

# Event `LendingPoolConfiguratorUpdated(address newAddress)` {#ILendingPoolAddressesProvider-LendingPoolConfiguratorUpdated-address-}

No description

# Event `LendingPoolCollateralManagerUpdated(address newAddress)` {#ILendingPoolAddressesProvider-LendingPoolCollateralManagerUpdated-address-}

No description

# Event `PriceOracleUpdated(address newAddress)` {#ILendingPoolAddressesProvider-PriceOracleUpdated-address-}

No description

# Event `LendingRateOracleUpdated(address newAddress)` {#ILendingPoolAddressesProvider-LendingRateOracleUpdated-address-}

No description

# Event `ProxyCreated(bytes32 id, address newAddress)` {#ILendingPoolAddressesProvider-ProxyCreated-bytes32-address-}

No description

# Event `AddressSet(bytes32 id, address newAddress, bool hasProxy)` {#ILendingPoolAddressesProvider-AddressSet-bytes32-address-bool-}

No description

# Functions:

- [`positions(uint256 tokenId)`](#INonfungiblePositionManager-positions-uint256-)

- [`mint(struct INonfungiblePositionManager.MintParams params)`](#INonfungiblePositionManager-mint-struct-INonfungiblePositionManager-MintParams-)

- [`increaseLiquidity(struct INonfungiblePositionManager.IncreaseLiquidityParams params)`](#INonfungiblePositionManager-increaseLiquidity-struct-INonfungiblePositionManager-IncreaseLiquidityParams-)

- [`decreaseLiquidity(struct INonfungiblePositionManager.DecreaseLiquidityParams params)`](#INonfungiblePositionManager-decreaseLiquidity-struct-INonfungiblePositionManager-DecreaseLiquidityParams-)

- [`collect(struct INonfungiblePositionManager.CollectParams params)`](#INonfungiblePositionManager-collect-struct-INonfungiblePositionManager-CollectParams-)

- [`burn(uint256 tokenId)`](#INonfungiblePositionManager-burn-uint256-)

# Events:

- [`IncreaseLiquidity(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)`](#INonfungiblePositionManager-IncreaseLiquidity-uint256-uint128-uint256-uint256-)

- [`DecreaseLiquidity(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)`](#INonfungiblePositionManager-DecreaseLiquidity-uint256-uint128-uint256-uint256-)

- [`Collect(uint256 tokenId, address recipient, uint256 amount0, uint256 amount1)`](#INonfungiblePositionManager-Collect-uint256-address-uint256-uint256-)

# Function `positions(uint256 tokenId) → uint96 nonce, address operator, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, uint128 tokensOwed0, uint128 tokensOwed1` {#INonfungiblePositionManager-positions-uint256-}

Throws if the token ID is not valid.

## Parameters:

- `tokenId`: The ID of the token that represents the position

## Return Values:

- nonce The nonce for permits

- operator The address that is approved for spending

- token0 The address of the token0 for a specific pool

- token1 The address of the token1 for a specific pool

- fee The fee associated with the pool

- tickLower The lower end of the tick range for the position

- tickUpper The higher end of the tick range for the position

- liquidity The liquidity of the position

- feeGrowthInside0LastX128 The fee growth of token0 as of the last action on the individual position

- feeGrowthInside1LastX128 The fee growth of token1 as of the last action on the individual position

- tokensOwed0 The uncollected amount of token0 owed to the position as of the last computation

- tokensOwed1 The uncollected amount of token1 owed to the position as of the last computation

# Function `mint(struct INonfungiblePositionManager.MintParams params) → uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1` {#INonfungiblePositionManager-mint-struct-INonfungiblePositionManager-MintParams-}

Call this when the pool does exist and is initialized. Note that if the pool is created but not initialized

a method does not exist, i.e. the pool is assumed to be initialized.

## Parameters:

- `params`: The params necessary to mint a position, encoded as `MintParams` in calldata

## Return Values:

- tokenId The ID of the token that represents the minted position

- liquidity The amount of liquidity for this position

- amount0 The amount of token0

- amount1 The amount of token1

# Function `increaseLiquidity(struct INonfungiblePositionManager.IncreaseLiquidityParams params) → uint128 liquidity, uint256 amount0, uint256 amount1` {#INonfungiblePositionManager-increaseLiquidity-struct-INonfungiblePositionManager-IncreaseLiquidityParams-}

No description

## Parameters:

- `params`: tokenId The ID of the token for which liquidity is being increased,

amount0Desired The desired amount of token0 to be spent,

amount1Desired The desired amount of token1 to be spent,

amount0Min The minimum amount of token0 to spend, which serves as a slippage check,

amount1Min The minimum amount of token1 to spend, which serves as a slippage check,

deadline The time by which the transaction must be included to effect the change

## Return Values:

- liquidity The new liquidity amount as a result of the increase

- amount0 The amount of token0 to acheive resulting liquidity

- amount1 The amount of token1 to acheive resulting liquidity

# Function `decreaseLiquidity(struct INonfungiblePositionManager.DecreaseLiquidityParams params) → uint256 amount0, uint256 amount1` {#INonfungiblePositionManager-decreaseLiquidity-struct-INonfungiblePositionManager-DecreaseLiquidityParams-}

No description

## Parameters:

- `params`: tokenId The ID of the token for which liquidity is being decreased,

amount The amount by which liquidity will be decreased,

amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,

amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,

deadline The time by which the transaction must be included to effect the change

## Return Values:

- amount0 The amount of token0 accounted to the position's tokens owed

- amount1 The amount of token1 accounted to the position's tokens owed

# Function `collect(struct INonfungiblePositionManager.CollectParams params) → uint256 amount0, uint256 amount1` {#INonfungiblePositionManager-collect-struct-INonfungiblePositionManager-CollectParams-}

No description

## Parameters:

- `params`: tokenId The ID of the NFT for which tokens are being collected,

recipient The account that should receive the tokens,

amount0Max The maximum amount of token0 to collect,

amount1Max The maximum amount of token1 to collect

## Return Values:

- amount0 The amount of fees collected in token0

- amount1 The amount of fees collected in token1

# Function `burn(uint256 tokenId)` {#INonfungiblePositionManager-burn-uint256-}

No description

## Parameters:

- `tokenId`: The ID of the token that is being burned

# Event `IncreaseLiquidity(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)` {#INonfungiblePositionManager-IncreaseLiquidity-uint256-uint128-uint256-uint256-}

Also emitted when a token is minted

## Parameters:

- `tokenId`: The ID of the token for which liquidity was increased

- `liquidity`: The amount by which liquidity for the NFT position was increased

- `amount0`: The amount of token0 that was paid for the increase in liquidity

- `amount1`: The amount of token1 that was paid for the increase in liquidity

# Event `DecreaseLiquidity(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)` {#INonfungiblePositionManager-DecreaseLiquidity-uint256-uint128-uint256-uint256-}

No description

## Parameters:

- `tokenId`: The ID of the token for which liquidity was decreased

- `liquidity`: The amount by which liquidity for the NFT position was decreased

- `amount0`: The amount of token0 that was accounted for the decrease in liquidity

- `amount1`: The amount of token1 that was accounted for the decrease in liquidity

# Event `Collect(uint256 tokenId, address recipient, uint256 amount0, uint256 amount1)` {#INonfungiblePositionManager-Collect-uint256-address-uint256-uint256-}

The amounts reported may not be exactly equivalent to the amounts transferred, due to rounding behavior

## Parameters:

- `tokenId`: The ID of the token for which underlying tokens were collected

- `recipient`: The address of the account that received the collected tokens

- `amount0`: The amount of token0 owed to the position that was collected

- `amount1`: The amount of token1 owed to the position that was collected

# Functions:

- [`factory()`](#IPeripheryImmutableState-factory--)

- [`WETH9()`](#IPeripheryImmutableState-WETH9--)

# Function `factory() → address` {#IPeripheryImmutableState-factory--}

No description

## Return Values:

- Returns the address of the Uniswap V3 factory

# Function `WETH9() → address` {#IPeripheryImmutableState-WETH9--}

No description

## Return Values:

- Returns the address of WETH9

# Functions:

- [`owner()`](#IUniswapV3Factory-owner--)

- [`feeAmountTickSpacing(uint24 fee)`](#IUniswapV3Factory-feeAmountTickSpacing-uint24-)

- [`getPool(address tokenA, address tokenB, uint24 fee)`](#IUniswapV3Factory-getPool-address-address-uint24-)

- [`createPool(address tokenA, address tokenB, uint24 fee)`](#IUniswapV3Factory-createPool-address-address-uint24-)

- [`setOwner(address _owner)`](#IUniswapV3Factory-setOwner-address-)

- [`enableFeeAmount(uint24 fee, int24 tickSpacing)`](#IUniswapV3Factory-enableFeeAmount-uint24-int24-)

# Events:

- [`OwnerChanged(address oldOwner, address newOwner)`](#IUniswapV3Factory-OwnerChanged-address-address-)

- [`PoolCreated(address token0, address token1, uint24 fee, int24 tickSpacing, address pool)`](#IUniswapV3Factory-PoolCreated-address-address-uint24-int24-address-)

- [`FeeAmountEnabled(uint24 fee, int24 tickSpacing)`](#IUniswapV3Factory-FeeAmountEnabled-uint24-int24-)

# Function `owner() → address` {#IUniswapV3Factory-owner--}

Can be changed by the current owner via setOwner

## Return Values:

- The address of the factory owner

# Function `feeAmountTickSpacing(uint24 fee) → int24` {#IUniswapV3Factory-feeAmountTickSpacing-uint24-}

A fee amount can never be removed, so this value should be hard coded or cached in the calling context

## Parameters:

- `fee`: The enabled fee, denominated in hundredths of a bip. Returns 0 in case of unenabled fee

## Return Values:

- The tick spacing

# Function `getPool(address tokenA, address tokenB, uint24 fee) → address pool` {#IUniswapV3Factory-getPool-address-address-uint24-}

tokenA and tokenB may be passed in either token0/token1 or token1/token0 order

## Parameters:

- `tokenA`: The contract address of either token0 or token1

- `tokenB`: The contract address of the other token

- `fee`: The fee collected upon every swap in the pool, denominated in hundredths of a bip

## Return Values:

- pool The pool address

# Function `createPool(address tokenA, address tokenB, uint24 fee) → address pool` {#IUniswapV3Factory-createPool-address-address-uint24-}

tokenA and tokenB may be passed in either order: token0/token1 or token1/token0. tickSpacing is retrieved

from the fee. The call will revert if the pool already exists, the fee is invalid, or the token arguments

are invalid.

## Parameters:

- `tokenA`: One of the two tokens in the desired pool

- `tokenB`: The other of the two tokens in the desired pool

- `fee`: The desired fee for the pool

## Return Values:

- pool The address of the newly created pool

# Function `setOwner(address _owner)` {#IUniswapV3Factory-setOwner-address-}

Must be called by the current owner

## Parameters:

- `_owner`: The new owner of the factory

# Function `enableFeeAmount(uint24 fee, int24 tickSpacing)` {#IUniswapV3Factory-enableFeeAmount-uint24-int24-}

Fee amounts may never be removed once enabled

## Parameters:

- `fee`: The fee amount to enable, denominated in hundredths of a bip (i.e. 1e-6)

- `tickSpacing`: The spacing between ticks to be enforced for all pools created with the given fee amount

# Event `OwnerChanged(address oldOwner, address newOwner)` {#IUniswapV3Factory-OwnerChanged-address-address-}

No description

## Parameters:

- `oldOwner`: The owner before the owner was changed

- `newOwner`: The owner after the owner was changed

# Event `PoolCreated(address token0, address token1, uint24 fee, int24 tickSpacing, address pool)` {#IUniswapV3Factory-PoolCreated-address-address-uint24-int24-address-}

No description

## Parameters:

- `token0`: The first token of the pool by address sort order

- `token1`: The second token of the pool by address sort order

- `fee`: The fee collected upon every swap in the pool, denominated in hundredths of a bip

- `tickSpacing`: The minimum number of ticks between initialized ticks

- `pool`: The address of the created pool

# Event `FeeAmountEnabled(uint24 fee, int24 tickSpacing)` {#IUniswapV3Factory-FeeAmountEnabled-uint24-int24-}

No description

## Parameters:

- `fee`: The enabled fee, denominated in hundredths of a bip

- `tickSpacing`: The minimum number of ticks between initialized ticks for pools created with the given fee

# Functions:

- [`slot0()`](#IUniswapV3PoolState-slot0--)

- [`feeGrowthGlobal0X128()`](#IUniswapV3PoolState-feeGrowthGlobal0X128--)

- [`feeGrowthGlobal1X128()`](#IUniswapV3PoolState-feeGrowthGlobal1X128--)

- [`protocolPerformanceFees()`](#IUniswapV3PoolState-protocolPerformanceFees--)

- [`liquidity()`](#IUniswapV3PoolState-liquidity--)

- [`ticks(int24 tick)`](#IUniswapV3PoolState-ticks-int24-)

- [`tickBitmap(int16 wordPosition)`](#IUniswapV3PoolState-tickBitmap-int16-)

- [`positions(bytes32 key)`](#IUniswapV3PoolState-positions-bytes32-)

- [`observations(uint256 index)`](#IUniswapV3PoolState-observations-uint256-)

# Function `slot0() → uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked` {#IUniswapV3PoolState-slot0--}

No description

## Return Values:

- sqrtPriceX96 The current price of the pool as a sqrt(token1/token0) Q64.96 value

tick The current tick of the pool, i.e. according to the last tick transition that was run.

This value may not always be equal to SqrtTickMath.getTickAtSqrtRatio(sqrtPriceX96) if the price is on a tick

boundary.

observationIndex The index of the last oracle observation that was written,

observationCardinality The current maximum number of observations stored in the pool,

observationCardinalityNext The next maximum number of observations, to be updated when the observation.

feeProtocol The protocol fee for both tokens of the pool.

Encoded as two 4 bit values, where the protocol fee of token1 is shifted 4 bits and the protocol fee of token0

is the lower 4 bits. Used as the denominator of a fraction of the swap fee, e.g. 4 means 1/4th of the swap fee.

unlocked Whether the pool is currently locked to reentrancy

# Function `feeGrowthGlobal0X128() → uint256` {#IUniswapV3PoolState-feeGrowthGlobal0X128--}

This value can overflow the uint256

# Function `feeGrowthGlobal1X128() → uint256` {#IUniswapV3PoolState-feeGrowthGlobal1X128--}

This value can overflow the uint256

# Function `protocolPerformanceFees() → uint128 token0, uint128 token1` {#IUniswapV3PoolState-protocolPerformanceFees--}

Protocol fees will never exceed uint128 max in either token

# Function `liquidity() → uint128` {#IUniswapV3PoolState-liquidity--}

This value has no relationship to the total liquidity across all ticks

# Function `ticks(int24 tick) → uint128 liquidityGross, int128 liquidityNet, uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128, int56 tickCumulativeOutside, uint160 secondsPerLiquidityOutsideX128, uint32 secondsOutside, bool initialized` {#IUniswapV3PoolState-ticks-int24-}

No description

## Parameters:

- `tick`: The tick to look up

## Return Values:

- liquidityGross the total amount of position liquidity that uses the pool either as tick lower or

tick upper,

liquidityNet how much liquidity changes when the pool price crosses the tick,

feeGrowthOutside0X128 the fee growth on the other side of the tick from the current tick in token0,

feeGrowthOutside1X128 the fee growth on the other side of the tick from the current tick in token1,

tickCumulativeOutside the cumulative tick value on the other side of the tick from the current tick

secondsPerLiquidityOutsideX128 the seconds spent per liquidity on the other side of the tick from the current tick,

secondsOutside the seconds spent on the other side of the tick from the current tick,

initialized Set to true if the tick is initialized, i.e. liquidityGross is greater than 0, otherwise equal to false.

Outside values can only be used if the tick is initialized, i.e. if liquidityGross is greater than 0.

In addition, these values are only relative and must be used only in comparison to previous snapshots for

a specific position.

# Function `tickBitmap(int16 wordPosition) → uint256` {#IUniswapV3PoolState-tickBitmap-int16-}

No description

# Function `positions(bytes32 key) → uint128 _liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, uint128 tokensOwed0, uint128 tokensOwed1` {#IUniswapV3PoolState-positions-bytes32-}

No description

## Parameters:

- `key`: The position's key is a hash of a preimage composed by the owner, tickLower and tickUpper

## Return Values:

- _liquidity The amount of liquidity in the position,

Returns feeGrowthInside0LastX128 fee growth of token0 inside the tick range as of the last mint/burn/poke,

Returns feeGrowthInside1LastX128 fee growth of token1 inside the tick range as of the last mint/burn/poke,

Returns tokensOwed0 the computed amount of token0 owed to the position as of the last mint/burn/poke,

Returns tokensOwed1 the computed amount of token1 owed to the position as of the last mint/burn/poke

# Function `observations(uint256 index) → uint32 blockTimestamp, int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128, bool initialized` {#IUniswapV3PoolState-observations-uint256-}

You most likely want to use #observe() instead of this method to get an observation as of some amount of time

ago, rather than at a specific index in the array.

## Parameters:

- `index`: The element of the observations array to fetch

## Return Values:

- blockTimestamp The timestamp of the observation,

Returns tickCumulative the tick multiplied by seconds elapsed for the life of the pool as of the observation timestamp,

Returns secondsPerLiquidityCumulativeX128 the seconds per in range liquidity for the life of the pool as of the observation timestamp,

Returns initialized whether the observation has been initialized and the values are safe to use

# Functions:

Used in SqrtPriceMath.sol

Handles "phantom overflow" i.e., allows multiplication and division where an intermediate value overflows 256 bits

# Functions:

# Functions:

# Functions:

# Functions:

- [`constructor(string name_, string symbol_)`](#ERC20Test-constructor-string-string-)

# Function `constructor(string name_, string symbol_)` {#ERC20Test-constructor-string-string-}

No description

# Functions:

- [`bubbleSort(address[] arr)`](#CommonTest-bubbleSort-address---)

- [`isSortedAndUnique(address[] tokens)`](#CommonTest-isSortedAndUnique-address---)

# Function `bubbleSort(address[] arr) → address[]` {#CommonTest-bubbleSort-address---}

No description

# Function `isSortedAndUnique(address[] tokens) → bool` {#CommonTest-isSortedAndUnique-address---}

No description
