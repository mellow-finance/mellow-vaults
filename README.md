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


### Brownie tests

#### Pre-requisites

Install ganache-cli
```bash
npm i -g ganache-cli
```

Create virtualenv & install requirements
```bash
cd test_brownie
python3 -m virtualenv venv
source venv/bin/activate
pip install -r requirements.txt
```

#### Run tests

```bash
brownie test
```
