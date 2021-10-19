# Protocol Architecture

Previous section describes [#vault-smart-contracts](overview.md#vault-smart-contracts "mention")architecture which is essentially one strategy smart contracts.&#x20;

This section describes how the whole Mellow Permissionless Vaults system works.

### **Protocol smart contracts**

![Smart contracts architecture (protocol view)](<../.gitbook/assets/Frame 2 (1).png>)

As you can see there are two types of contracts on the diagram:

1. **Protocol contracts** (teal color) - these are the protocol contracts that are deployed in one instance
2. **User contracts **(green color) - these are the contracts deployed by users (vault owners / strategists) by means of **Protocol contract** and there are multiple copies of them. Essentially everyone can create a set of User contracts

Additionally contracts are grouped into so called **Vault systems**. **Vault system** is a set of smart contracts that allows the creation and operation of a vault with a specific type. Examples of types are UniV3, Yearn, etc.

### Vault system

To understand how **Vault system **works let's take a closer look at UniV3 vault system.

#### User contracts

For each new vault system you would need to deploy 2 user contracts:&#x20;

* UniV3 Vault is a contract that can interact with UniV3 pool (Uniswap protocol), e.g. deposit and withdraw liquidity, estimate currently provided liquidity. Deposit and withdraw operations can only be performed by Gateway vault or Strategy. Strategy has an additional limitation that withdrawals can only be made to other vaults that are in the same vault system. The set of permissions are implemented using ERC-721 ownership and approvals.
* UniV3 Vault Governance is used for managing strategy params. There are two actors that can manage vault params - the Strategist and the Governance. Some params like strategy treasury address can be managed by both and some like Vault Manager address only by the Governance.

Both of these contracts are required to have a fully functioning vault system. For each new vault you would need to deploy those using Vault Manager contract (see below).

#### Protocol contracts

The rest of the contracts in the vault To finish examining the vault system we need to understand the following contracts:

*

### Fees
