from brownie import accounts
from brownie.test import given, strategy


@given(addresses=strategy("address[]", min_length=1, max_length=10, unique=True))
def test_sorted_tokens(addresses, a, TokensVault):
    tokens_vault = TokensVault.deploy(addresses, {"from": a[0]})
    assert tokens_vault.tokens() == sorted(addresses, key=lambda a: str(a).lower())


@given(addresses=strategy("address[]", min_length=1, max_length=10, unique=True))
def test_tokens_count(addresses, a, TokensVault):
    tokens_vault = TokensVault.deploy(addresses, {"from": a[0]})
    assert tokens_vault.tokensCount() == len(addresses)


@given(addresses=strategy("address[]", min_length=1, max_length=10, unique=True))
def test_has_token(addresses, a, TokensVault):
    tokens_vault = TokensVault.deploy(addresses, {"from": a[0]})
    for addr in addresses:
        assert tokens_vault.hasToken(addr)


@given(num_tokens=strategy("uint8", min_value=1, max_value=10))
def test_own_token_amounts(num_tokens, a, TokensVault, ERC20Mock):
    tokens = [
        ERC20Mock.deploy(f"T{i}", f"T{i}", {"from": a[0]}) for i in range(num_tokens)
    ]
    tokens.sort(key=lambda t: str(t).lower())
    tokens_vault = TokensVault.deploy(tokens, {"from": a[0]})
    for i in range(num_tokens):
        tokens[i].mint(tokens_vault, i * 1000)
    tokens_vault.ownTokenAmounts() == [i * 1000 for i in range(num_tokens)]
