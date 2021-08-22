import pytest
from brownie import reverts

ETH = 10 ** 18


@pytest.fixture(scope="module")
def tokens(ERC20Mock, a):
    return [a[0].deploy(ERC20Mock, f"Test Token {i}", f"TST{i}") for i in range(3)]


@pytest.mark.parametrize("order", [[2, 1, 0], [0, 1]])
def test_constructor(a, tokens, order, TokensEntity):
    addresses = [str(tokens[i]).lower() for i in order]
    tokens_vault = TokensEntity.deploy(addresses, {"from": a[0]})
    assert tokens_vault.tokens() == sorted(addresses)


@pytest.mark.parametrize("order", [[2, 1, 2], [0, 0]])
def test_constructor_repeated_tokens(a, tokens, order, TokensEntity):
    addresses = [str(tokens[i]).lower() for i in order]
    with reverts("TE"):
        TokensEntity.deploy(addresses, {"from": a[0]})


def test_constructor_empty_tokens(a, TokensEntity):
    with reverts("ETL"):
        TokensEntity.deploy([], {"from": a[0]})


@pytest.mark.parametrize("order", [[2, 1, 0], [0, 1]])
def test_tokens(a, tokens, order, TokensEntity):
    addresses = [str(tokens[i]).lower() for i in order]
    tokens_vault = TokensEntity.deploy(addresses, {"from": a[0]})
    assert tokens_vault.tokens() == sorted(addresses)


@pytest.mark.parametrize("order", [[2, 1, 0], [0, 1], [1]])
def test_tokens_count(a, tokens, order, TokensEntity):
    addresses = [str(tokens[i]).lower() for i in order]
    tokens_vault = TokensEntity.deploy(addresses, {"from": a[0]})
    assert tokens_vault.tokensCount() == len(addresses)


def test_own_token_amounts(a, tokens, TokensEntity):
    tokens_vault = TokensEntity.deploy(tokens, {"from": a[0]})
    tks = sorted(tokens, key=lambda t: str(t).lower())
    for i in range(len(tks)):
        tks[i].mint(tokens_vault, i * 1000)
    assert tokens_vault.tokenAmountsBalance() == [i * 1000 for i in range(len(tokens))]


def test_has_token(a, tokens, TokensEntity):
    tokens_vault = TokensEntity.deploy(tokens, {"from": a[0]})
    for token in tokens:
        assert tokens_vault.hasToken(token)
    assert not tokens_vault.hasToken(a[0])
