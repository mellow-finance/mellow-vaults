## Mellow contracts

### Branch naming rules

Adding tests
```
tests/<ContractName>
```

Making changes to smart contracts
```
feature/<[RelatedContractName]FeatureName>
```

### Hardhat unit test

#### Pre-requisites

Install dependencies

```bash
yarn 
```


Configure mainnet forking

```bash
echo """
MAINNET_RPC=https://eth-mainnet.alchemyapi.io/v2/<your_api_key>
""" > .env
```

#### Run all hardhat tests

```bash
yarn coverage
```

#### Hardhat hacks

Get result of mutating function 

```
nft = await erc20VaultManager.callStatic.mintVaultNft(erc20Vault.address);
await erc20VaultManager.mintVaultNft(erc20Vault.address);
```

### Brownie property tests

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


### Visualize coverage report

```
open coverage/index.html
```
