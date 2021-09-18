## Mellow contracts

### Task examples

#### Mint UniV3Cells token

```
npx hardhat --network localhost create-uni-v3-cell --token0 usdc --token1 weth --lower-tick -120 --upper-tick 120 --amount0 100 --amount1 100
```

#### Mint TokenCells (or other cells contract) token

```
npx hardhat --network localhost create-cell --cells 'TokenCells' --tokens '["usdc", "weth"]'
```
