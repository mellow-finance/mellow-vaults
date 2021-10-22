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
