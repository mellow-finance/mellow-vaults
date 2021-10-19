# AaveVault

🧒 Vault that interfaces Aave protocol in the integration layer.

## Functions

### constructor

```solidity

  function constructor(contract IVaultGovernance vaultGovernance) public

```

🧒 Deploy new vault

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`vaultGovernance` | contract IVaultGovernance | reference to VaultGovernance for this vault

### tvl

```solidity

  function tvl() public returns (uint256[] tokenAmounts)

```

🧒 Total value locked for this contract. This usually represents the value

this protocol has put into other protocols, i.e. total available for withdraw balance of this contract.

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`tokenAmounts`|  | total available balances (in the same order as vaultTokens)

### earnings

```solidity

  function earnings() public returns (uint256[] tokenAmounts)

```

# AaveVaultFactory

## Functions

### deployVault

```solidity

  function deployVault(contract IVaultGovernance vaultGovernance, bytes) external returns (contract IVault)

```

# AaveVaultManager

## Functions

### constructor

```solidity

  function constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory governanceFactory, bool permissionless, contract IProtocolGovernance governance, contract ILendingPool pool) public

```

### lendingPool

```solidity

  function lendingPool() external returns (contract ILendingPool)

```

# DefaultAccessControl

## Functions

### constructor

```solidity

  function constructor(address admin) public

```

### isAdmin

```solidity

  function isAdmin() public returns (bool)

```

# ERC20Vault

## Functions

### constructor

```solidity

  function constructor(contract IVaultGovernance vaultGovernance) public

```

### tvl

```solidity

  function tvl() public returns (uint256[] tokenAmounts)

```

### earnings

```solidity

  function earnings() public returns (uint256[] tokenAmounts)

```

# ERC20VaultFactory

## Functions

### deployVault

```solidity

  function deployVault(contract IVaultGovernance vaultGovernance, bytes) external returns (contract IVault)

```

# GatewayVault

## Functions

### constructor

```solidity

  function constructor(contract IVaultGovernance vaultGovernance, address[] vaults) public

```

### tvl

```solidity

  function tvl() public returns (uint256[] tokenAmounts)

```

### earnings

```solidity

  function earnings() public returns (uint256[] tokenAmounts)

```

### vaultTvl

```solidity

  function vaultTvl(uint256 vaultNum) public returns (uint256[])

```

### vaultsTvl

```solidity

  function vaultsTvl() public returns (uint256[][] tokenAmounts)

```

### vaultEarnings

```solidity

  function vaultEarnings(uint256 vaultNum) public returns (uint256[])

```

### hasVault

```solidity

  function hasVault(address vault) external returns (bool)

```

## Events

### CollectProtocolFees

```solidity

  event CollectProtocolFees(

  )

```

### CollectStrategyFees

```solidity

  event CollectStrategyFees(

  )

```

# GatewayVaultGovernance

## Functions

### constructor

```solidity

  function constructor(address[] tokens, contract IVaultManager manager, address treasury, address admin, address[] vaults, address[] redirects_, uint256[] limits_) public

```

### limits

```solidity

  function limits() external returns (uint256[])

```

### redirects

```solidity

  function redirects() external returns (address[])

```

### setLimits

```solidity

  function setLimits(uint256[] newLimits) external

```

### setRedirects

```solidity

  function setRedirects(address[] newRedirects) external

```

## Events

### SetLimits

```solidity

  event SetLimits(

  )

```

### SetRedirects

```solidity

  event SetRedirects(

  )

```

# GatewayVaultManager

## Functions

### constructor

```solidity

  function constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory goveranceFactory, bool permissionless, contract IProtocolGovernance governance) public

```

### vaultOwnerNft

```solidity

  function vaultOwnerNft(uint256 nft) public returns (uint256)

```

### vaultOwner

```solidity

  function vaultOwner(uint256 nft) external returns (address)

```

# LpIssuer

## Functions

### constructor

```solidity

  function constructor(string name_, string symbol_, contract IVault gatewayVault, contract IProtocolGovernance protocolGovernance, uint256 limitPerAddress, address admin) public

```

### setLimit

```solidity

  function setLimit(uint256 newLimitPerAddress) external

```

### deposit

```solidity

  function deposit(uint256[] tokenAmounts, bool optimized, bytes options) external

```

### withdraw

```solidity

  function withdraw(address to, uint256 lpTokenAmount, bool optimized, bytes options) external

```

## Events

### Deposit

```solidity

  event Deposit(

  )

```

### Withdraw

```solidity

  event Withdraw(

  )

```

### ExitFeeCollected

```solidity

  event ExitFeeCollected(

  )

```

# LpIssuerGovernance

## Functions

### constructor

```solidity

  function constructor(struct ILpIssuerGovernance.GovernanceParams params) public

```

### governanceParams

```solidity

  function governanceParams() public returns (struct ILpIssuerGovernance.GovernanceParams)

```

🧒 -------------------  PUBLIC, VIEW  -------------------

### pendingGovernanceParams

```solidity

  function pendingGovernanceParams() external returns (struct ILpIssuerGovernance.GovernanceParams)

```

### pendingGovernanceParamsTimestamp

```solidity

  function pendingGovernanceParamsTimestamp() external returns (uint256)

```

### setPendingGovernanceParams

```solidity

  function setPendingGovernanceParams(struct ILpIssuerGovernance.GovernanceParams newGovernanceParams) external

```

🧒 -------------------  PUBLIC, PROTOCOL ADMIN  -------------------

### commitGovernanceParams

```solidity

  function commitGovernanceParams() external

```

# ProtocolGovernance

## Functions

### constructor

```solidity

  function constructor(address admin, struct IProtocolGovernance.Params _params) public

```

### claimAllowlist

```solidity

  function claimAllowlist() external returns (address[])

```

🧒 -------------------  PUBLIC, VIEW  -------------------

### pendingClaimAllowlistAdd

```solidity

  function pendingClaimAllowlistAdd() external returns (address[])

```

### isAllowedToClaim

```solidity

  function isAllowedToClaim(address addr) external returns (bool)

```

### maxTokensPerVault

```solidity

  function maxTokensPerVault() external returns (uint256)

```

### governanceDelay

```solidity

  function governanceDelay() external returns (uint256)

```

### strategyPerformanceFee

```solidity

  function strategyPerformanceFee() external returns (uint256)

```

### protocolPerformanceFee

```solidity

  function protocolPerformanceFee() external returns (uint256)

```

### protocolExitFee

```solidity

  function protocolExitFee() external returns (uint256)

```

### protocolTreasury

```solidity

  function protocolTreasury() external returns (address)

```

### gatewayVaultManager

```solidity

  function gatewayVaultManager() external returns (contract IGatewayVaultManager)

```

### setPendingClaimAllowlistAdd

```solidity

  function setPendingClaimAllowlistAdd(address[] addresses) external

```

🧒 -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

### removeFromClaimAllowlist

```solidity

  function removeFromClaimAllowlist(address addr) external

```

### setPendingParams

```solidity

  function setPendingParams(struct IProtocolGovernance.Params newParams) external

```

### commitClaimAllowlistAdd

```solidity

  function commitClaimAllowlistAdd() external

```

🧒 -------------------  PUBLIC, MUTATING, GOVERNANCE, IMMEDIATE  -------------------

### commitParams

```solidity

  function commitParams() external

```

# UniV3Vault

## Functions

### constructor

```solidity

  function constructor(contract IVaultGovernance vaultGovernance, uint24 fee) public

```

### tvl

```solidity

  function tvl() public returns (uint256[] tokenAmounts)

```

### earnings

```solidity

  function earnings() public returns (uint256[] tokenAmounts)

```

### nftEarnings

```solidity

  function nftEarnings(uint256 nft) public returns (uint256[] tokenAmounts)

```

### nftTvl

```solidity

  function nftTvl(uint256 nft) public returns (uint256[] tokenAmounts)

```

### nftTvls

```solidity

  function nftTvls() public returns (uint256[][] tokenAmounts)

```

# UniV3VaultFactory

## Functions

### deployVault

```solidity

  function deployVault(contract IVaultGovernance vaultGovernance, bytes options) external returns (contract IVault)

```

# UniV3VaultManager

## Functions

### constructor

```solidity

  function constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory goveranceFactory, bool permissionless, contract IProtocolGovernance governance, contract INonfungiblePositionManager uniV3PositionManager) public

```

### positionManager

```solidity

  function positionManager() external returns (contract INonfungiblePositionManager)

```

# Vault

## Functions

### vaultGovernance

```solidity

  function vaultGovernance() external returns (contract IVaultGovernance)

```

🧒 Address of the Vault Governance for this contract

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`Address`|  | of the Vault Governance for this contract

### tvl

```solidity

  function tvl() public returns (uint256[] tokenAmounts)

```

🧒 Total value locked for this contract. This usually represents the value

this protocol has put into other protocols, i.e. total available for withdraw balance of this contract.

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`tokenAmounts`|  | total available balances (in the same order as vaultTokens)

### earnings

```solidity

  function earnings() public returns (uint256[] tokenAmounts)

```

### push

```solidity

  function push(address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options) public returns (uint256[] actualTokenAmounts)

```

🧒 tokens are used from contract balance

### transferAndPush

```solidity

  function transferAndPush(address from, address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options) external returns (uint256[] actualTokenAmounts)

```

### pull

```solidity

  function pull(address to, address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options) external returns (uint256[] actualTokenAmounts)

```

### collectEarnings

```solidity

  function collectEarnings(address to, bytes options) external returns (uint256[] collectedEarnings)

```

### reclaimTokens

```solidity

  function reclaimTokens(address to, address[] tokens) external

```

🧒 -------------------  PUBLIC, MUTATING, NFT OWNER OR APPROVED OR PROTOCOL ADMIN -------------------

### claimRewards

```solidity

  function claimRewards(address from, bytes data) external

```

# VaultGovernance

## Functions

### constructor

```solidity

  function constructor(address[] tokens, contract IVaultManager manager, address treasury, address admin) public

```

### isProtocolAdmin

```solidity

  function isProtocolAdmin() public returns (bool)

```

🧒 -------------------  PUBLIC, VIEW  -------------------

### vaultTokens

```solidity

  function vaultTokens() public returns (address[])

```

### isVaultToken

```solidity

  function isVaultToken(address token) public returns (bool)

```

### vaultManager

```solidity

  function vaultManager() public returns (contract IVaultManager)

```

### pendingVaultManager

```solidity

  function pendingVaultManager() external returns (contract IVaultManager)

```

### pendingVaultManagerTimestamp

```solidity

  function pendingVaultManagerTimestamp() external returns (uint256)

```

### strategyTreasury

```solidity

  function strategyTreasury() public returns (address)

```

### pendingStrategyTreasury

```solidity

  function pendingStrategyTreasury() external returns (address)

```

### pendingStrategyTreasuryTimestamp

```solidity

  function pendingStrategyTreasuryTimestamp() external returns (uint256)

```

### setPendingVaultManager

```solidity

  function setPendingVaultManager(contract IVaultManager manager) external

```

🧒 -------------------  PUBLIC, MUTATING, PROTOCOL ADMIN  -------------------

### commitVaultManager

```solidity

  function commitVaultManager() external

```

### setPendingStrategyTreasury

```solidity

  function setPendingStrategyTreasury(address treasury) external

```

🧒 -------------------  PUBLIC, MUTATING, ADMIN  -------------------

### commitStrategyTreasury

```solidity

  function commitStrategyTreasury() external

```

# VaultManager

## Functions

### constructor

```solidity

  function constructor(string name, string symbol, contract IVaultFactory factory, contract IVaultGovernanceFactory governanceFactory, bool permissionless, contract IProtocolGovernance protocolGovernance) public

```

### nftForVault

```solidity

  function nftForVault(address vault) external returns (uint256)

```

### vaultForNft

```solidity

  function vaultForNft(uint256 nft) public returns (address)

```

### createVault

```solidity

  function createVault(address[] tokens, address strategyTreasury, address admin, bytes options) external returns (contract IVaultGovernance vaultGovernance, contract IVault vault, uint256 nft)

```

### supportsInterface

```solidity

  function supportsInterface(bytes4 interfaceId) public returns (bool)

```

# VaultManagerGovernance

## Functions

### constructor

```solidity

  function constructor(bool permissionless, contract IProtocolGovernance protocolGovernance, contract IVaultFactory factory, contract IVaultGovernanceFactory governanceFactory) public

```

### governanceParams

```solidity

  function governanceParams() public returns (struct IVaultManagerGovernance.GovernanceParams)

```

🧒 -------------------  PUBLIC, VIEW  -------------------

### pendingGovernanceParams

```solidity

  function pendingGovernanceParams() external returns (struct IVaultManagerGovernance.GovernanceParams)

```

### pendingGovernanceParamsTimestamp

```solidity

  function pendingGovernanceParamsTimestamp() external returns (uint256)

```

### setPendingGovernanceParams

```solidity

  function setPendingGovernanceParams(struct IVaultManagerGovernance.GovernanceParams newGovernanceParams) external

```

🧒 -------------------  PUBLIC, PROTOCOL ADMIN  -------------------

### commitGovernanceParams

```solidity

  function commitGovernanceParams() external

```

# IAaveVaultManager

## Functions

### lendingPool

```solidity

  function lendingPool() external returns (contract ILendingPool)

```

# IDefaultAccessControl

## Functions

### isAdmin

```solidity

  function isAdmin() external returns (bool)

```

# IGatewayVault

## Functions

### hasVault

```solidity

  function hasVault(address vault) external returns (bool)

```

### vaultsTvl

```solidity

  function vaultsTvl() external returns (uint256[][] tokenAmounts)

```

### vaultTvl

```solidity

  function vaultTvl(uint256 vaultNum) external returns (uint256[])

```

### vaultEarnings

```solidity

  function vaultEarnings(uint256 vaultNum) external returns (uint256[])

```

# IGatewayVaultManager

## Functions

### vaultOwnerNft

```solidity

  function vaultOwnerNft(uint256 nft) external returns (uint256)

```

### vaultOwner

```solidity

  function vaultOwner(uint256 nft) external returns (address)

```

# ILpIssuerGovernance

## Functions

### governanceParams

```solidity

  function governanceParams() external returns (struct ILpIssuerGovernance.GovernanceParams)

```

### pendingGovernanceParams

```solidity

  function pendingGovernanceParams() external returns (struct ILpIssuerGovernance.GovernanceParams)

```

### pendingGovernanceParamsTimestamp

```solidity

  function pendingGovernanceParamsTimestamp() external returns (uint256)

```

### setPendingGovernanceParams

```solidity

  function setPendingGovernanceParams(struct ILpIssuerGovernance.GovernanceParams newParams) external

```

### commitGovernanceParams

```solidity

  function commitGovernanceParams() external

```

## Events

### SetPendingGovernanceParams

```solidity

  event SetPendingGovernanceParams(

  )

```

### CommitGovernanceParams

```solidity

  event CommitGovernanceParams(

  )

```

# IProtocolGovernance

## Functions

### claimAllowlist

```solidity

  function claimAllowlist() external returns (address[])

```

### pendingClaimAllowlistAdd

```solidity

  function pendingClaimAllowlistAdd() external returns (address[])

```

### isAllowedToClaim

```solidity

  function isAllowedToClaim(address addr) external returns (bool)

```

### maxTokensPerVault

```solidity

  function maxTokensPerVault() external returns (uint256)

```

### governanceDelay

```solidity

  function governanceDelay() external returns (uint256)

```

### strategyPerformanceFee

```solidity

  function strategyPerformanceFee() external returns (uint256)

```

### protocolPerformanceFee

```solidity

  function protocolPerformanceFee() external returns (uint256)

```

### protocolExitFee

```solidity

  function protocolExitFee() external returns (uint256)

```

### protocolTreasury

```solidity

  function protocolTreasury() external returns (address)

```

### gatewayVaultManager

```solidity

  function gatewayVaultManager() external returns (contract IGatewayVaultManager)

```

### setPendingParams

```solidity

  function setPendingParams(struct IProtocolGovernance.Params newParams) external

```

🧒 -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

### commitParams

```solidity

  function commitParams() external

```

🧒 -------------------  PUBLIC, MUTATING, GOVERNANCE, IMMEDIATE  -------------------

# IUniV3VaultManager

## Functions

### positionManager

```solidity

  function positionManager() external returns (contract INonfungiblePositionManager)

```

# IVault

## Functions

### vaultGovernance

```solidity

  function vaultGovernance() external returns (contract IVaultGovernance)

```

🧒 Address of the Vault Governance for this contract

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`Address`|  | of the Vault Governance for this contract

### tvl

```solidity

  function tvl() external returns (uint256[] tokenAmounts)

```

🧒 Total value locked for this contract. This usually represents the value

this protocol has put into other protocols, i.e. total available for withdraw balance of this contract.

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`tokenAmounts`|  | total available balances (in the same order as vaultTokens)

### earnings

```solidity

  function earnings() external returns (uint256[] tokenAmounts)

```

### push

```solidity

  function push(address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options) external returns (uint256[] actualTokenAmounts)

```

### transferAndPush

```solidity

  function transferAndPush(address from, address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options) external returns (uint256[] actualTokenAmounts)

```

### pull

```solidity

  function pull(address to, address[] tokens, uint256[] tokenAmounts, bool optimized, bytes options) external returns (uint256[] actualTokenAmounts)

```

### collectEarnings

```solidity

  function collectEarnings(address to, bytes options) external returns (uint256[] collectedEarnings)

```

### reclaimTokens

```solidity

  function reclaimTokens(address to, address[] tokens) external

```

## Events

### Push

```solidity

  event Push(

  )

```

### Pull

```solidity

  event Pull(

  )

```

### CollectEarnings

```solidity

  event CollectEarnings(

  )

```

### ReclaimTokens

```solidity

  event ReclaimTokens(

  )

```

# IVaultFactory

## Functions

### deployVault

```solidity

  function deployVault(contract IVaultGovernance vaultGovernance, bytes options) external returns (contract IVault vault)

```

# IVaultGovernance

## Functions

### isProtocolAdmin

```solidity

  function isProtocolAdmin() external returns (bool)

```

### vaultTokens

```solidity

  function vaultTokens() external returns (address[])

```

### isVaultToken

```solidity

  function isVaultToken(address token) external returns (bool)

```

### vaultManager

```solidity

  function vaultManager() external returns (contract IVaultManager)

```

### pendingVaultManager

```solidity

  function pendingVaultManager() external returns (contract IVaultManager)

```

### pendingVaultManagerTimestamp

```solidity

  function pendingVaultManagerTimestamp() external returns (uint256)

```

### setPendingVaultManager

```solidity

  function setPendingVaultManager(contract IVaultManager newManager) external

```

### commitVaultManager

```solidity

  function commitVaultManager() external

```

### strategyTreasury

```solidity

  function strategyTreasury() external returns (address)

```

### pendingStrategyTreasury

```solidity

  function pendingStrategyTreasury() external returns (address)

```

### pendingStrategyTreasuryTimestamp

```solidity

  function pendingStrategyTreasuryTimestamp() external returns (uint256)

```

### setPendingStrategyTreasury

```solidity

  function setPendingStrategyTreasury(address newTreasury) external

```

### commitStrategyTreasury

```solidity

  function commitStrategyTreasury() external

```

## Events

### SetPendingVaultManager

```solidity

  event SetPendingVaultManager(

  )

```

### CommitVaultManager

```solidity

  event CommitVaultManager(

  )

```

### SetPendingStrategyTreasury

```solidity

  event SetPendingStrategyTreasury(

  )

```

### CommitStrategyTreasury

```solidity

  event CommitStrategyTreasury(

  )

```

# IVaultGovernanceFactory

## Functions

### deployVaultGovernance

```solidity

  function deployVaultGovernance(address[] tokens, contract IVaultManager manager, address treasury, address admin) external returns (contract IVaultGovernance vaultGovernance)

```

# IVaultManager

## Functions

### nftForVault

```solidity

  function nftForVault(address vault) external returns (uint256)

```

### vaultForNft

```solidity

  function vaultForNft(uint256 nft) external returns (address)

```

### createVault

```solidity

  function createVault(address[] tokens, address strategyTreasury, address admin, bytes options) external returns (contract IVaultGovernance vaultGovernance, contract IVault vault, uint256 nft)

```

## Events

### CreateVault

```solidity

  event CreateVault(

  )

```

# IVaultManagerGovernance

## Functions

### governanceParams

```solidity

  function governanceParams() external returns (struct IVaultManagerGovernance.GovernanceParams)

```

### pendingGovernanceParams

```solidity

  function pendingGovernanceParams() external returns (struct IVaultManagerGovernance.GovernanceParams)

```

### pendingGovernanceParamsTimestamp

```solidity

  function pendingGovernanceParamsTimestamp() external returns (uint256)

```

### setPendingGovernanceParams

```solidity

  function setPendingGovernanceParams(struct IVaultManagerGovernance.GovernanceParams newParams) external

```

### commitGovernanceParams

```solidity

  function commitGovernanceParams() external

```

## Events

### SetPendingGovernanceParams

```solidity

  event SetPendingGovernanceParams(

  )

```

### CommitGovernanceParams

```solidity

  event CommitGovernanceParams(

  )

```

# DataTypes

# ILendingPool

## Functions

### deposit

```solidity

  function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external

```

🤓 Deposits an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.

- E.g. User deposits 100 USDC and gets in return 100 aUSDC

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`asset` | address | The address of the underlying asset to deposit

|`amount` | uint256 | The amount to be deposited

|`onBehalfOf` | address | The address that will receive the aTokens, same as msg.sender if the user

  wants to receive them on his own wallet, or a different address if the beneficiary of aTokens

  is a different wallet

|`referralCode` | uint16 | Code used to register the integrator originating the operation, for potential rewards.

  0 if the action is executed directly by the user, without any middle-man

### withdraw

```solidity

  function withdraw(address asset, uint256 amount, address to) external returns (uint256)

```

🤓 Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned

E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`asset` | address | The address of the underlying asset to withdraw

|`amount` | uint256 | The underlying amount to be withdrawn

  - Send the value type(uint256).max in order to withdraw the whole aToken balance

|`to` | address | Address that will receive the underlying, same as msg.sender if the user

  wants to receive it on his own wallet, or a different address if the beneficiary is a

  different wallet

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`The`| address | final amount withdrawn

### borrow

```solidity

  function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external

```

🤓 Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower

already deposited enough collateral, or he was given enough allowance by a credit delegator on the

corresponding debt token (StableDebtToken or VariableDebtToken)

- E.g. User borrows 100 USDC passing as `onBehalfOf` his own address, receiving the 100 USDC in his wallet

  and 100 stable/variable debt tokens, depending on the `interestRateMode`

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`asset` | address | The address of the underlying asset to borrow

|`amount` | uint256 | The amount to be borrowed

|`interestRateMode` | uint256 | The interest rate mode at which the user wants to borrow: 1 for Stable, 2 for Variable

|`referralCode` | uint16 | Code used to register the integrator originating the operation, for potential rewards.

  0 if the action is executed directly by the user, without any middle-man

|`onBehalfOf` | address | Address of the user who will receive the debt. Should be the address of the borrower itself

calling the function if he wants to borrow against his own collateral, or the address of the credit delegator

if he has been given credit delegation allowance

### repay

```solidity

  function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external returns (uint256)

```

🧒 Repays a borrowed `amount` on a specific reserve, burning the equivalent debt tokens owned

- E.g. User repays 100 USDC, burning 100 variable/stable debt tokens of the `onBehalfOf` address

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`asset` | address | The address of the borrowed underlying asset previously borrowed

|`amount` | uint256 | The amount to repay

- Send the value type(uint256).max in order to repay the whole debt for `asset` on the specific `debtMode`

|`rateMode` | uint256 | The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable

|`onBehalfOf` | address | Address of the user who will get his debt reduced/removed. Should be the address of the

user calling the function if he wants to reduce/remove his own debt, or the address of any other

other borrower whose debt should be removed

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`The`| address | final amount repaid

### swapBorrowRateMode

```solidity

  function swapBorrowRateMode(address asset, uint256 rateMode) external

```

🤓 Allows a borrower to swap his debt between stable and variable mode, or viceversa

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`asset` | address | The address of the underlying asset borrowed

|`rateMode` | uint256 | The rate mode that the user wants to swap to

### rebalanceStableBorrowRate

```solidity

  function rebalanceStableBorrowRate(address asset, address user) external

```

🤓 Rebalances the stable interest rate of a user to the current stable rate defined on the reserve.

- Users can be rebalanced if the following conditions are satisfied:

    1. Usage ratio is above 95%

    2. the current deposit APY is below REBALANCE_UP_THRESHOLD * maxVariableBorrowRate, which means that too much has been

       borrowed at a stable rate and depositors are not earning enough

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`asset` | address | The address of the underlying asset borrowed

|`user` | address | The address of the user to be rebalanced

### setUserUseReserveAsCollateral

```solidity

  function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external

```

🤓 Allows depositors to enable/disable a specific deposited asset as collateral

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`asset` | address | The address of the underlying asset deposited

|`useAsCollateral` | bool | `true` if the user wants to use the deposit as collateral, `false` otherwise

### liquidationCall

```solidity

  function liquidationCall(address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool receiveAToken) external

```

🤓 Function to liquidate a non-healthy position collateral-wise, with Health Factor below 1

- The caller (liquidator) covers `debtToCover` amount of debt of the user getting liquidated, and receives

  a proportionally amount of the `collateralAsset` plus a bonus to cover market risk

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`collateralAsset` | address | The address of the underlying asset used as collateral, to receive as result of the liquidation

|`debtAsset` | address | The address of the underlying borrowed asset to be repaid with the liquidation

|`user` | address | The address of the borrower getting liquidated

|`debtToCover` | uint256 | The debt amount of borrowed `asset` the liquidator wants to cover

|`receiveAToken` | bool | `true` if the liquidators wants to receive the collateral aTokens, `false` if he wants

to receive the underlying collateral asset directly

### flashLoan

```solidity

  function flashLoan(address receiverAddress, address[] assets, uint256[] amounts, uint256[] modes, address onBehalfOf, bytes params, uint16 referralCode) external

```

🤓 Allows smartcontracts to access the liquidity of the pool within one transaction,

as long as the amount taken plus a fee is returned.

IMPORTANT There are security concerns for developers of flashloan receiver contracts that must be kept into consideration.

For further details please visit https://developers.aave.com

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`receiverAddress` | address | The address of the contract receiving the funds, implementing the IFlashLoanReceiver interface

|`assets` | address[] | The addresses of the assets being flash-borrowed

|`amounts` | uint256[] | The amounts amounts being flash-borrowed

|`modes` | uint256[] | Types of the debt to open if the flash loan is not returned:

  0 -> Don't open any debt, just revert if funds can't be transferred from the receiver

  1 -> Open debt at stable rate for the value of the amount flash-borrowed to the `onBehalfOf` address

  2 -> Open debt at variable rate for the value of the amount flash-borrowed to the `onBehalfOf` address

|`onBehalfOf` | address | The address  that will receive the debt in the case of using on `modes` 1 or 2

|`params` | bytes | Variadic packed params to pass to the receiver as extra information

|`referralCode` | uint16 | Code used to register the integrator originating the operation, for potential rewards.

  0 if the action is executed directly by the user, without any middle-man

### getUserAccountData

```solidity

  function getUserAccountData(address user) external returns (uint256 totalCollateralETH, uint256 totalDebtETH, uint256 availableBorrowsETH, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor)

```

🤓 Returns the user account data across all the reserves

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`user` | address | The address of the user

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`totalCollateralETH`| address | the total collateral in ETH of the user

|`totalDebtETH`|  | the total debt in ETH of the user

|`availableBorrowsETH`|  | the borrowing power left of the user

|`currentLiquidationThreshold`|  | the liquidation threshold of the user

|`ltv`|  | the loan to value of the user

|`healthFactor`|  | the current health factor of the user

### initReserve

```solidity

  function initReserve(address reserve, address aTokenAddress, address stableDebtAddress, address variableDebtAddress, address interestRateStrategyAddress) external

```

### setReserveInterestRateStrategyAddress

```solidity

  function setReserveInterestRateStrategyAddress(address reserve, address rateStrategyAddress) external

```

### setConfiguration

```solidity

  function setConfiguration(address reserve, uint256 configuration) external

```

### getConfiguration

```solidity

  function getConfiguration(address asset) external returns (struct DataTypes.ReserveConfigurationMap)

```

🤓 Returns the configuration of the reserve

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`asset` | address | The address of the underlying asset of the reserve

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`The`| address | configuration of the reserve

### getUserConfiguration

```solidity

  function getUserConfiguration(address user) external returns (struct DataTypes.UserConfigurationMap)

```

🤓 Returns the configuration of the user across all the reserves

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`user` | address | The user address

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`The`| address | configuration of the user

### getReserveNormalizedIncome

```solidity

  function getReserveNormalizedIncome(address asset) external returns (uint256)

```

🤓 Returns the normalized income normalized income of the reserve

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`asset` | address | The address of the underlying asset of the reserve

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`The`| address | reserve's normalized income

### getReserveNormalizedVariableDebt

```solidity

  function getReserveNormalizedVariableDebt(address asset) external returns (uint256)

```

🤓 Returns the normalized variable debt per unit of asset

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`asset` | address | The address of the underlying asset of the reserve

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`The`| address | reserve normalized variable debt

### getReserveData

```solidity

  function getReserveData(address asset) external returns (struct DataTypes.ReserveData)

```

🤓 Returns the state and configuration of the reserve

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`asset` | address | The address of the underlying asset of the reserve

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`The`| address | state of the reserve

### finalizeTransfer

```solidity

  function finalizeTransfer(address asset, address from, address to, uint256 amount, uint256 balanceFromAfter, uint256 balanceToBefore) external

```

### getReservesList

```solidity

  function getReservesList() external returns (address[])

```

### getAddressesProvider

```solidity

  function getAddressesProvider() external returns (contract ILendingPoolAddressesProvider)

```

### setPause

```solidity

  function setPause(bool val) external

```

### paused

```solidity

  function paused() external returns (bool)

```

## Events

### Deposit

```solidity

  event Deposit(

    address reserve,

    address user,

    address onBehalfOf,

    uint256 amount,

    uint16 referral

  )

```

🤓 Emitted on deposit()

#### Parameters:

| Name                           | Type          | Description                                    |

| :----------------------------- | :------------ | :--------------------------------------------- |

|`reserve`| address | The address of the underlying asset of the reserve

|`user`| address | The address initiating the deposit

|`onBehalfOf`| address | The beneficiary of the deposit, receiving the aTokens

|`amount`| uint256 | The amount deposited

|`referral`| uint16 | The referral code used

### Withdraw

```solidity

  event Withdraw(

    address reserve,

    address user,

    address to,

    uint256 amount

  )

```

🤓 Emitted on withdraw()

#### Parameters:

| Name                           | Type          | Description                                    |

| :----------------------------- | :------------ | :--------------------------------------------- |

|`reserve`| address | The address of the underlyng asset being withdrawn

|`user`| address | The address initiating the withdrawal, owner of aTokens

|`to`| address | Address that will receive the underlying

|`amount`| uint256 | The amount to be withdrawn

### Borrow

```solidity

  event Borrow(

    address reserve,

    address user,

    address onBehalfOf,

    uint256 amount,

    uint256 borrowRateMode,

    uint256 borrowRate,

    uint16 referral

  )

```

🤓 Emitted on borrow() and flashLoan() when debt needs to be opened

#### Parameters:

| Name                           | Type          | Description                                    |

| :----------------------------- | :------------ | :--------------------------------------------- |

|`reserve`| address | The address of the underlying asset being borrowed

|`user`| address | The address of the user initiating the borrow(), receiving the funds on borrow() or just

initiator of the transaction on flashLoan()

|`onBehalfOf`| address | The address that will be getting the debt

|`amount`| uint256 | The amount borrowed out

|`borrowRateMode`| uint256 | The rate mode: 1 for Stable, 2 for Variable

|`borrowRate`| uint256 | The numeric rate at which the user has borrowed

|`referral`| uint16 | The referral code used

### Repay

```solidity

  event Repay(

    address reserve,

    address user,

    address repayer,

    uint256 amount

  )

```

🤓 Emitted on repay()

#### Parameters:

| Name                           | Type          | Description                                    |

| :----------------------------- | :------------ | :--------------------------------------------- |

|`reserve`| address | The address of the underlying asset of the reserve

|`user`| address | The beneficiary of the repayment, getting his debt reduced

|`repayer`| address | The address of the user initiating the repay(), providing the funds

|`amount`| uint256 | The amount repaid

### Swap

```solidity

  event Swap(

    address reserve,

    address user,

    uint256 rateMode

  )

```

🤓 Emitted on swapBorrowRateMode()

#### Parameters:

| Name                           | Type          | Description                                    |

| :----------------------------- | :------------ | :--------------------------------------------- |

|`reserve`| address | The address of the underlying asset of the reserve

|`user`| address | The address of the user swapping his rate mode

|`rateMode`| uint256 | The rate mode that the user wants to swap to

### ReserveUsedAsCollateralEnabled

```solidity

  event ReserveUsedAsCollateralEnabled(

    address reserve,

    address user

  )

```

🤓 Emitted on setUserUseReserveAsCollateral()

#### Parameters:

| Name                           | Type          | Description                                    |

| :----------------------------- | :------------ | :--------------------------------------------- |

|`reserve`| address | The address of the underlying asset of the reserve

|`user`| address | The address of the user enabling the usage as collateral

### ReserveUsedAsCollateralDisabled

```solidity

  event ReserveUsedAsCollateralDisabled(

    address reserve,

    address user

  )

```

🤓 Emitted on setUserUseReserveAsCollateral()

#### Parameters:

| Name                           | Type          | Description                                    |

| :----------------------------- | :------------ | :--------------------------------------------- |

|`reserve`| address | The address of the underlying asset of the reserve

|`user`| address | The address of the user enabling the usage as collateral

### RebalanceStableBorrowRate

```solidity

  event RebalanceStableBorrowRate(

    address reserve,

    address user

  )

```

🤓 Emitted on rebalanceStableBorrowRate()

#### Parameters:

| Name                           | Type          | Description                                    |

| :----------------------------- | :------------ | :--------------------------------------------- |

|`reserve`| address | The address of the underlying asset of the reserve

|`user`| address | The address of the user for which the rebalance has been executed

### FlashLoan

```solidity

  event FlashLoan(

    address target,

    address initiator,

    address asset,

    uint256 amount,

    uint256 premium,

    uint16 referralCode

  )

```

🤓 Emitted on flashLoan()

#### Parameters:

| Name                           | Type          | Description                                    |

| :----------------------------- | :------------ | :--------------------------------------------- |

|`target`| address | The address of the flash loan receiver contract

|`initiator`| address | The address initiating the flash loan

|`asset`| address | The address of the asset being flash borrowed

|`amount`| uint256 | The amount flash borrowed

|`premium`| uint256 | The fee flash borrowed

|`referralCode`| uint16 | The referral code used

### Paused

```solidity

  event Paused(

  )

```

🤓 Emitted when the pause is triggered.

### Unpaused

```solidity

  event Unpaused(

  )

```

🤓 Emitted when the pause is lifted.

### LiquidationCall

```solidity

  event LiquidationCall(

    address collateralAsset,

    address debtAsset,

    address user,

    uint256 debtToCover,

    uint256 liquidatedCollateralAmount,

    address liquidator,

    bool receiveAToken

  )

```

🤓 Emitted when a borrower is liquidated. This event is emitted by the LendingPool via

LendingPoolCollateral manager using a DELEGATECALL

This allows to have the events in the generated ABI for LendingPool.

#### Parameters:

| Name                           | Type          | Description                                    |

| :----------------------------- | :------------ | :--------------------------------------------- |

|`collateralAsset`| address | The address of the underlying asset used as collateral, to receive as result of the liquidation

|`debtAsset`| address | The address of the underlying borrowed asset to be repaid with the liquidation

|`user`| address | The address of the borrower getting liquidated

|`debtToCover`| uint256 | The debt amount of borrowed `asset` the liquidator wants to cover

|`liquidatedCollateralAmount`| uint256 | The amount of collateral received by the liiquidator

|`liquidator`| address | The address of the liquidator

|`receiveAToken`| bool | `true` if the liquidators wants to receive the collateral aTokens, `false` if he wants

to receive the underlying collateral asset directly

### ReserveDataUpdated

```solidity

  event ReserveDataUpdated(

    address reserve,

    uint256 liquidityRate,

    uint256 stableBorrowRate,

    uint256 variableBorrowRate,

    uint256 liquidityIndex,

    uint256 variableBorrowIndex

  )

```

🤓 Emitted when the state of a reserve is updated. NOTE: This event is actually declared

in the ReserveLogic library and emitted in the updateInterestRates() function. Since the function is internal,

the event will actually be fired by the LendingPool contract. The event is therefore replicated here so it

gets added to the LendingPool ABI

#### Parameters:

| Name                           | Type          | Description                                    |

| :----------------------------- | :------------ | :--------------------------------------------- |

|`reserve`| address | The address of the underlying asset of the reserve

|`liquidityRate`| uint256 | The new liquidity rate

|`stableBorrowRate`| uint256 | The new stable borrow rate

|`variableBorrowRate`| uint256 | The new variable borrow rate

|`liquidityIndex`| uint256 | The new liquidity index

|`variableBorrowIndex`| uint256 | The new variable borrow index

# ILendingPoolAddressesProvider

🤓 Main registry of addresses part of or connected to the protocol, including permissioned roles

- Acting also as factory of proxies and admin of those, so with right to change its implementations

- Owned by the Aave Governance

## Functions

### getMarketId

```solidity

  function getMarketId() external returns (string)

```

### setMarketId

```solidity

  function setMarketId(string marketId) external

```

### setAddress

```solidity

  function setAddress(bytes32 id, address newAddress) external

```

### setAddressAsProxy

```solidity

  function setAddressAsProxy(bytes32 id, address impl) external

```

### getAddress

```solidity

  function getAddress(bytes32 id) external returns (address)

```

### getLendingPool

```solidity

  function getLendingPool() external returns (address)

```

### setLendingPoolImpl

```solidity

  function setLendingPoolImpl(address pool) external

```

### getLendingPoolConfigurator

```solidity

  function getLendingPoolConfigurator() external returns (address)

```

### setLendingPoolConfiguratorImpl

```solidity

  function setLendingPoolConfiguratorImpl(address configurator) external

```

### getLendingPoolCollateralManager

```solidity

  function getLendingPoolCollateralManager() external returns (address)

```

### setLendingPoolCollateralManager

```solidity

  function setLendingPoolCollateralManager(address manager) external

```

### getPoolAdmin

```solidity

  function getPoolAdmin() external returns (address)

```

### setPoolAdmin

```solidity

  function setPoolAdmin(address admin) external

```

### getEmergencyAdmin

```solidity

  function getEmergencyAdmin() external returns (address)

```

### setEmergencyAdmin

```solidity

  function setEmergencyAdmin(address admin) external

```

### getPriceOracle

```solidity

  function getPriceOracle() external returns (address)

```

### setPriceOracle

```solidity

  function setPriceOracle(address priceOracle) external

```

### getLendingRateOracle

```solidity

  function getLendingRateOracle() external returns (address)

```

### setLendingRateOracle

```solidity

  function setLendingRateOracle(address lendingRateOracle) external

```

## Events

### MarketIdSet

```solidity

  event MarketIdSet(

  )

```

### LendingPoolUpdated

```solidity

  event LendingPoolUpdated(

  )

```

### ConfigurationAdminUpdated

```solidity

  event ConfigurationAdminUpdated(

  )

```

### EmergencyAdminUpdated

```solidity

  event EmergencyAdminUpdated(

  )

```

### LendingPoolConfiguratorUpdated

```solidity

  event LendingPoolConfiguratorUpdated(

  )

```

### LendingPoolCollateralManagerUpdated

```solidity

  event LendingPoolCollateralManagerUpdated(

  )

```

### PriceOracleUpdated

```solidity

  event PriceOracleUpdated(

  )

```

### LendingRateOracleUpdated

```solidity

  event LendingRateOracleUpdated(

  )

```

### ProxyCreated

```solidity

  event ProxyCreated(

  )

```

### AddressSet

```solidity

  event AddressSet(

  )

```

# INonfungiblePositionManager

🧒 Wraps Uniswap V3 positions in a non-fungible token interface which allows for them to be transferred

and authorized.

## Functions

### positions

```solidity

  function positions(uint256 tokenId) external returns (uint96 nonce, address operator, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, uint128 tokensOwed0, uint128 tokensOwed1)

```

🧒 Returns the position information associated with a given token ID.

🤓 Throws if the token ID is not valid.

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`tokenId` | uint256 | The ID of the token that represents the position

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`nonce`| uint256 | The nonce for permits

|`operator`|  | The address that is approved for spending

|`token0`|  | The address of the token0 for a specific pool

|`token1`|  | The address of the token1 for a specific pool

|`fee`|  | The fee associated with the pool

|`tickLower`|  | The lower end of the tick range for the position

|`tickUpper`|  | The higher end of the tick range for the position

|`liquidity`|  | The liquidity of the position

|`feeGrowthInside0LastX128`|  | The fee growth of token0 as of the last action on the individual position

|`feeGrowthInside1LastX128`|  | The fee growth of token1 as of the last action on the individual position

|`tokensOwed0`|  | The uncollected amount of token0 owed to the position as of the last computation

|`tokensOwed1`|  | The uncollected amount of token1 owed to the position as of the last computation

### mint

```solidity

  function mint(struct INonfungiblePositionManager.MintParams params) external returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)

```

🧒 Creates a new position wrapped in a NFT

🤓 Call this when the pool does exist and is initialized. Note that if the pool is created but not initialized

a method does not exist, i.e. the pool is assumed to be initialized.

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`params` | struct INonfungiblePositionManager.MintParams | The params necessary to mint a position, encoded as `MintParams` in calldata

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`tokenId`| struct INonfungiblePositionManager.MintParams | The ID of the token that represents the minted position

|`liquidity`|  | The amount of liquidity for this position

|`amount0`|  | The amount of token0

|`amount1`|  | The amount of token1

### increaseLiquidity

```solidity

  function increaseLiquidity(struct INonfungiblePositionManager.IncreaseLiquidityParams params) external returns (uint128 liquidity, uint256 amount0, uint256 amount1)

```

🧒 Increases the amount of liquidity in a position, with tokens paid by the `msg.sender`

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`params` | struct INonfungiblePositionManager.IncreaseLiquidityParams | tokenId The ID of the token for which liquidity is being increased,

amount0Desired The desired amount of token0 to be spent,

amount1Desired The desired amount of token1 to be spent,

amount0Min The minimum amount of token0 to spend, which serves as a slippage check,

amount1Min The minimum amount of token1 to spend, which serves as a slippage check,

deadline The time by which the transaction must be included to effect the change

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`liquidity`| struct INonfungiblePositionManager.IncreaseLiquidityParams | The new liquidity amount as a result of the increase

|`amount0`|  | The amount of token0 to acheive resulting liquidity

|`amount1`|  | The amount of token1 to acheive resulting liquidity

### decreaseLiquidity

```solidity

  function decreaseLiquidity(struct INonfungiblePositionManager.DecreaseLiquidityParams params) external returns (uint256 amount0, uint256 amount1)

```

🧒 Decreases the amount of liquidity in a position and accounts it to the position

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`params` | struct INonfungiblePositionManager.DecreaseLiquidityParams | tokenId The ID of the token for which liquidity is being decreased,

amount The amount by which liquidity will be decreased,

amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,

amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,

deadline The time by which the transaction must be included to effect the change

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`amount0`| struct INonfungiblePositionManager.DecreaseLiquidityParams | The amount of token0 accounted to the position's tokens owed

|`amount1`|  | The amount of token1 accounted to the position's tokens owed

### collect

```solidity

  function collect(struct INonfungiblePositionManager.CollectParams params) external returns (uint256 amount0, uint256 amount1)

```

🧒 Collects up to a maximum amount of fees owed to a specific position to the recipient

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`params` | struct INonfungiblePositionManager.CollectParams | tokenId The ID of the NFT for which tokens are being collected,

recipient The account that should receive the tokens,

amount0Max The maximum amount of token0 to collect,

amount1Max The maximum amount of token1 to collect

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`amount0`| struct INonfungiblePositionManager.CollectParams | The amount of fees collected in token0

|`amount1`|  | The amount of fees collected in token1

### burn

```solidity

  function burn(uint256 tokenId) external

```

🧒 Burns a token ID, which deletes it from the NFT contract. The token must have 0 liquidity and all tokens

must be collected first.

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`tokenId` | uint256 | The ID of the token that is being burned

## Events

### IncreaseLiquidity

```solidity

  event IncreaseLiquidity(

    uint256 tokenId,

    uint128 liquidity,

    uint256 amount0,

    uint256 amount1

  )

```

🧒 Emitted when liquidity is increased for a position NFT

🤓 Also emitted when a token is minted

#### Parameters:

| Name                           | Type          | Description                                    |

| :----------------------------- | :------------ | :--------------------------------------------- |

|`tokenId`| uint256 | The ID of the token for which liquidity was increased

|`liquidity`| uint128 | The amount by which liquidity for the NFT position was increased

|`amount0`| uint256 | The amount of token0 that was paid for the increase in liquidity

|`amount1`| uint256 | The amount of token1 that was paid for the increase in liquidity

### DecreaseLiquidity

```solidity

  event DecreaseLiquidity(

    uint256 tokenId,

    uint128 liquidity,

    uint256 amount0,

    uint256 amount1

  )

```

🧒 Emitted when liquidity is decreased for a position NFT

#### Parameters:

| Name                           | Type          | Description                                    |

| :----------------------------- | :------------ | :--------------------------------------------- |

|`tokenId`| uint256 | The ID of the token for which liquidity was decreased

|`liquidity`| uint128 | The amount by which liquidity for the NFT position was decreased

|`amount0`| uint256 | The amount of token0 that was accounted for the decrease in liquidity

|`amount1`| uint256 | The amount of token1 that was accounted for the decrease in liquidity

### Collect

```solidity

  event Collect(

    uint256 tokenId,

    address recipient,

    uint256 amount0,

    uint256 amount1

  )

```

🧒 Emitted when tokens are collected for a position NFT

🤓 The amounts reported may not be exactly equivalent to the amounts transferred, due to rounding behavior

#### Parameters:

| Name                           | Type          | Description                                    |

| :----------------------------- | :------------ | :--------------------------------------------- |

|`tokenId`| uint256 | The ID of the token for which underlying tokens were collected

|`recipient`| address | The address of the account that received the collected tokens

|`amount0`| uint256 | The amount of token0 owed to the position that was collected

|`amount1`| uint256 | The amount of token1 owed to the position that was collected

# IPeripheryImmutableState

🧒 Functions that return immutable state of the router

## Functions

### factory

```solidity

  function factory() external returns (address)

```

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`Returns`|  | the address of the Uniswap V3 factory

### WETH9

```solidity

  function WETH9() external returns (address)

```

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`Returns`|  | the address of WETH9

# IUniswapV3Factory

🧒 The Uniswap V3 Factory facilitates creation of Uniswap V3 pools and control over the protocol fees

## Functions

### owner

```solidity

  function owner() external returns (address)

```

🧒 Returns the current owner of the factory

🤓 Can be changed by the current owner via setOwner

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`The`|  | address of the factory owner

### feeAmountTickSpacing

```solidity

  function feeAmountTickSpacing(uint24 fee) external returns (int24)

```

🧒 Returns the tick spacing for a given fee amount, if enabled, or 0 if not enabled

🤓 A fee amount can never be removed, so this value should be hard coded or cached in the calling context

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`fee` | uint24 | The enabled fee, denominated in hundredths of a bip. Returns 0 in case of unenabled fee

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`The`| uint24 | tick spacing

### getPool

```solidity

  function getPool(address tokenA, address tokenB, uint24 fee) external returns (address pool)

```

🧒 Returns the pool address for a given pair of tokens and a fee, or address 0 if it does not exist

🤓 tokenA and tokenB may be passed in either token0/token1 or token1/token0 order

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`tokenA` | address | The contract address of either token0 or token1

|`tokenB` | address | The contract address of the other token

|`fee` | uint24 | The fee collected upon every swap in the pool, denominated in hundredths of a bip

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`pool`| address | The pool address

### createPool

```solidity

  function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool)

```

🧒 Creates a pool for the given two tokens and fee

🤓 tokenA and tokenB may be passed in either order: token0/token1 or token1/token0. tickSpacing is retrieved

from the fee. The call will revert if the pool already exists, the fee is invalid, or the token arguments

are invalid.

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`tokenA` | address | One of the two tokens in the desired pool

|`tokenB` | address | The other of the two tokens in the desired pool

|`fee` | uint24 | The desired fee for the pool

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`pool`| address | The address of the newly created pool

### setOwner

```solidity

  function setOwner(address _owner) external

```

🧒 Updates the owner of the factory

🤓 Must be called by the current owner

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`_owner` | address | The new owner of the factory

### enableFeeAmount

```solidity

  function enableFeeAmount(uint24 fee, int24 tickSpacing) external

```

🧒 Enables a fee amount with the given tickSpacing

🤓 Fee amounts may never be removed once enabled

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`fee` | uint24 | The fee amount to enable, denominated in hundredths of a bip (i.e. 1e-6)

|`tickSpacing` | int24 | The spacing between ticks to be enforced for all pools created with the given fee amount

## Events

### OwnerChanged

```solidity

  event OwnerChanged(

    address oldOwner,

    address newOwner

  )

```

🧒 Emitted when the owner of the factory is changed

#### Parameters:

| Name                           | Type          | Description                                    |

| :----------------------------- | :------------ | :--------------------------------------------- |

|`oldOwner`| address | The owner before the owner was changed

|`newOwner`| address | The owner after the owner was changed

### PoolCreated

```solidity

  event PoolCreated(

    address token0,

    address token1,

    uint24 fee,

    int24 tickSpacing,

    address pool

  )

```

🧒 Emitted when a pool is created

#### Parameters:

| Name                           | Type          | Description                                    |

| :----------------------------- | :------------ | :--------------------------------------------- |

|`token0`| address | The first token of the pool by address sort order

|`token1`| address | The second token of the pool by address sort order

|`fee`| uint24 | The fee collected upon every swap in the pool, denominated in hundredths of a bip

|`tickSpacing`| int24 | The minimum number of ticks between initialized ticks

|`pool`| address | The address of the created pool

### FeeAmountEnabled

```solidity

  event FeeAmountEnabled(

    uint24 fee,

    int24 tickSpacing

  )

```

🧒 Emitted when a new fee amount is enabled for pool creation via the factory

#### Parameters:

| Name                           | Type          | Description                                    |

| :----------------------------- | :------------ | :--------------------------------------------- |

|`fee`| uint24 | The enabled fee, denominated in hundredths of a bip

|`tickSpacing`| int24 | The minimum number of ticks between initialized ticks for pools created with the given fee

# IUniswapV3PoolState

🧒 These methods compose the pool's state, and can change with any frequency including multiple times

per transaction

## Functions

### slot0

```solidity

  function slot0() external returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked)

```

🧒 The 0th storage slot in the pool stores many values, and is exposed as a single method to save gas

when accessed externally.

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`sqrtPriceX96`|  | The current price of the pool as a sqrt(token1/token0) Q64.96 value

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

### feeGrowthGlobal0X128

```solidity

  function feeGrowthGlobal0X128() external returns (uint256)

```

🧒 The fee growth as a Q128.128 fees of token0 collected per unit of liquidity for the entire life of the pool

🤓 This value can overflow the uint256

### feeGrowthGlobal1X128

```solidity

  function feeGrowthGlobal1X128() external returns (uint256)

```

🧒 The fee growth as a Q128.128 fees of token1 collected per unit of liquidity for the entire life of the pool

🤓 This value can overflow the uint256

### protocolPerformanceFees

```solidity

  function protocolPerformanceFees() external returns (uint128 token0, uint128 token1)

```

🧒 The amounts of token0 and token1 that are owed to the protocol

🤓 Protocol fees will never exceed uint128 max in either token

### liquidity

```solidity

  function liquidity() external returns (uint128)

```

🧒 The currently in range liquidity available to the pool

🤓 This value has no relationship to the total liquidity across all ticks

### ticks

```solidity

  function ticks(int24 tick) external returns (uint128 liquidityGross, int128 liquidityNet, uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128, int56 tickCumulativeOutside, uint160 secondsPerLiquidityOutsideX128, uint32 secondsOutside, bool initialized)

```

🧒 Look up information about a specific tick in the pool

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`tick` | int24 | The tick to look up

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`liquidityGross`| int24 | the total amount of position liquidity that uses the pool either as tick lower or

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

### tickBitmap

```solidity

  function tickBitmap(int16 wordPosition) external returns (uint256)

```

🧒 Returns 256 packed tick initialized boolean values. See TickBitmap for more information

### positions

```solidity

  function positions(bytes32 key) external returns (uint128 _liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, uint128 tokensOwed0, uint128 tokensOwed1)

```

🧒 Returns the information about a position by the position's key

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`key` | bytes32 | The position's key is a hash of a preimage composed by the owner, tickLower and tickUpper

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`_liquidity`| bytes32 | The amount of liquidity in the position,

Returns feeGrowthInside0LastX128 fee growth of token0 inside the tick range as of the last mint/burn/poke,

Returns feeGrowthInside1LastX128 fee growth of token1 inside the tick range as of the last mint/burn/poke,

Returns tokensOwed0 the computed amount of token0 owed to the position as of the last mint/burn/poke,

Returns tokensOwed1 the computed amount of token1 owed to the position as of the last mint/burn/poke

### observations

```solidity

  function observations(uint256 index) external returns (uint32 blockTimestamp, int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128, bool initialized)

```

🧒 Returns data about a specific observation index

🤓 You most likely want to use #observe() instead of this method to get an observation as of some amount of time

ago, rather than at a specific index in the array.

#### Parameters:

| Name | Type | Description                                                          |

| :--- | :--- | :------------------------------------------------------------------- |

|`index` | uint256 | The element of the observations array to fetch

#### Return Values:

| Name                           | Type          | Description                                                                  |

| :----------------------------- | :------------ | :--------------------------------------------------------------------------- |

|`blockTimestamp`| uint256 | The timestamp of the observation,

Returns tickCumulative the tick multiplied by seconds elapsed for the life of the pool as of the observation timestamp,

Returns secondsPerLiquidityCumulativeX128 the seconds per in range liquidity for the life of the pool as of the observation timestamp,

Returns initialized whether the observation has been initialized and the values are safe to use

# Common

## Functions

# FixedPoint96

🧒 A library for handling binary fixed point numbers, see https://en.wikipedia.org/wiki/Q_(number_format)

🤓 Used in SqrtPriceMath.sol

# FullMath

🧒 Facilitates multiplication and division that can have overflow of an intermediate value without any loss of precision

🤓 Handles "phantom overflow" i.e., allows multiplication and division where an intermediate value overflows 256 bits

## Functions

# LiquidityAmounts

🧒 Provides functions for computing liquidity amounts from token amounts and prices

## Functions

# TickMath

🧒 Computes sqrt price for ticks of size 1.0001, i.e. sqrt(1.0001^tick) as fixed point Q64.96 numbers. Supports

prices between 2**-128 and 2**128

## Functions
