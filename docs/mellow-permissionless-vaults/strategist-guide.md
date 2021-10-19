# Strategist guide

## Create vault

To create a new vault use wizard at [https://mellow.finance](https://mellow.finance)

## Create vault using contracts

To setup a new Vault and Strategy you first need to pick protocols you want to use in your strategy. Let's assume you want to create a Strategy on top of UniV3 and Aave for WETH and USDC ERC-20 tokens. Then you need to follow these steps:

#### 1) Create vault in the AaveVaults contract

Call `createVault` method with the arguments:&#x20;

| Argument | Value                                                                                    |
| -------- | ---------------------------------------------------------------------------------------- |
| tokens   | \[0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48,0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2] |
| options  | 0x0                                                                                      |

Note that tokens must be always used in the ascending order.

#### 2) Create vault in the[ ](univ3-cells.md#aavevaults)[UniV3Vaults](univ3-cells.md#univ-3-vaults) contract&#x20;

Call `createVault` method with the arguments:&#x20;

| Argument | Value                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| tokens   | \[0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48,0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2]                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| options  | 0x0000000000000000000000000000000000000000000000000000000000000bb8000000000000000000000000000000000000000000000000000000000002fcc4000000000000000000000000000000000000000000000000000000000002fd3c000000000000000000000000000000000000000000000000000000000000271000000000000000000000000000000000000000000000000000000000000027100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000614a44ee |

Notice that `createVault` for [UniV3Vaults](univ3-cells.md#univ-3-vaults) has additional options unlike [AaveVaults](univ3-cells.md#aavevaults). If you breakdown the options bytestring by 32-byte slices you'll get the following table:

| Bytes                                                            | Argument     |
| ---------------------------------------------------------------- | ------------ |
| 0000000000000000000000000000000000000000000000000000000000000bb8 | Pool fee     |
| 000000000000000000000000000000000000000000000000000000000002fcc4 | Lower tick   |
| 000000000000000000000000000000000000000000000000000000000002fd3c | Upper tick   |
| 0000000000000000000000000000000000000000000000000000000000002710 | Amount 0     |
| 0000000000000000000000000000000000000000000000000000000000002710 | Amount 1     |
| 0000000000000000000000000000000000000000000000000000000000000000 | Min Amount 0 |
| 0000000000000000000000000000000000000000000000000000000000000000 | Min Amount 1 |
| 00000000000000000000000000000000000000000000000000000000614a44ee | Deadline     |

You'll recognize that these options are from UniV3 `mint` method:

* **Pool fee** - the fee of the pool you want to build the strategy over. The most common value is 3000 (0xbb8), meaning 0.3% - fee pool.
* **Lower tick **- lower tick of the position. The formula for tick is $$t = \lfloor \frac{\log{p}}{\log{1.0001}} \rfloor$$ where p is price in basic currency units (like wei and satoshi). Note that for 0.3% pool t must be divisible by 60.
* **Upper tick** - upper tick of the position
* **Amount 0** - initial investment of the token 0 (USDC)
* **Amount 1** - initial investment of the token 1 (WETH)
* **Min Amount 0 **- minimal acceptable investment of token 0 (USDC). The actual investment of tokens can deviate from amount 0 and amount 1 since the tokens must be in correct proportion that depends on lower tick, upper tick and price
* **Min Amount 1 **- minimal acceptable investment of token 1 (WETH).
* **Deadline - **the timestamp in secs. If the block time is greater than deadline, the transaction is reverted.

#### 3) Create vault in the[ ](univ3-cells.md#aavevaults)[RouterVaults](univ3-cells.md#routervaults) contract

Call `createVault` method with the arguments:

| Argument | Value                                                                                    |
| -------- | ---------------------------------------------------------------------------------------- |
| tokens   | \[0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48,0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2] |
| options  | 0x0                                                                                      |

#### 4) Create vault in the [LpVaults](univ3-cells.md#lpvaults) contract

Call `createVault` method with the arguments:

| Argument | Value                                                                                    |
| -------- | ---------------------------------------------------------------------------------------- |
| tokens   | \[0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48,0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2] |
| options  | 0x0                                                                                      |

#### 4) Link Aave Vault and Uni Vault to Router Vault&#x20;

Call `safeTransfer` method for NFT tokens minted at step 1 and 2

#### 5) Link Router Vault to Lp Vault
