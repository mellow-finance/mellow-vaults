# Overview

Mellow permissionless vaults is a set of smart contracts that allows anyone to create a **Vault **and a **Strategy** on top of different DeFi protocols (like Uniswap, Yearn, etc.) and blockchains (like Ethereum, Optimism, etc.)

### **Users**

There are three types of actors using permissionless vaults:

* **Liquidity provider** provides liquidity into vaults to earn profits

* **Strategist** manages liquidity in the vaults by distributing it among different DeFi protocols and earns performance fee (as a percentage of earned profits). Typically strategist would create a **Strategy** smart contract that transparently manages vault liquidity. However **Strategy** can also be an offline algorithm or manual liquidity management as well.

* **Governance **manages common protocol parameters and earns protocol fee

### **Vault smart contracts**

Allowing cross-protocol liquidity management is not an easy task. So each vault is actually a set of smart contracts as shown below.

![Smart contracts architecture (per vault view)](<../.gitbook/assets/Frame 1 (4).png>)

To make things simpler the contracts could be divided into 4 layers:

* **DeFi Layer** is represented by DeFi ecosystem protocols like Uniswap, Yearn, Aave, etc. on Ethereum / Uniswap, Sushswap on Arbitrum / Aave on Polygon, etc. These contracts are not part of the Mellow Permissionless Vaults but rather used by the vaults to provide liquidity.

* **Integration layer **holds smart contracts that interface DeFi Layer protocols. These contracts has unified interface for depositing and withdrawing liquidity. The **Strategy **contract can withdraw liquidity from these contracts but only to smart contracts of the integration layer. **Gateway** vault (from Aggregation layer) can withdraw liquidity to any address. Additionally integration layer vaults has some useful features like getting current vault TVL and claiming liquidity mining rewards.&#x20;

* **Aggregation layer **has Gateway Vault contract that aggregates several integration layer vaults into one vault thus implementing a multiprotocol strategy vault. Additionally it is responsible for collecting performance fees from integration vaults.

* **User layer **is designed for interaction with end users - strategists and liquidity providers. The **Strategy** contract can manage and redistribute liquidity between integration layer contracts. There are 2 alternatives for liquidity providers (only one is used for a particular strategy): **Lp Issuer **and** Nft Issuer. ** **Lp Issuer** issues ERC-20 tokens for strategies with fungible positions. **Nft Issuer **issues ERC-721 for strategies with nonfungible positions.

The implementation of contracts in different layers is an ongoing process. To check what contracts are already deployed see [contracts-deployments.md](contracts-deployments.md "mention") section.

### Invariants

* All tokens are sorted

* Constant tokens

* Constant vault structure

* ERC721 tokens

* Claim LM earnings
