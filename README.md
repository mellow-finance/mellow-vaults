## Mellow contracts

### Hardhat unit test

#### Pre-requisites
```bash
yarn 
```

#### Run tests

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
