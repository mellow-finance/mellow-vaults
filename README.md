## Mellow contracts

### Task examples

#### Mint UniV3Vaults token

```
npx hardhat --network localhost create-uni-v3-cell --token0 usdc --token1 weth --lower-tick -120 --upper-tick 120 --amount0 100 --amount1 100
```

#### Mint TokenVaults (or other cells contract) token

```
npx hardhat --network localhost create-cell --cells 'TokenVaults' --tokens '["usdc", "weth"]'
```

#### Create strategy-1 vault

```
npx hardhat --network localhost create-vault-1 --lower-tick 195780 --upper-tick 195900 --token0 usdc --token1 weth --strategist 0x638F16FB633747d140e1Ed6219dB783e52a2207B
```
