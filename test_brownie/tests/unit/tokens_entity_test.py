import pytest

ETH = 10 ** 18


@pytest.fixture(scope="module")
def tokens(ERC20Mock, a):
    return [a[0].deploy(ERC20Mock, f"Test Token {i}", f"TST{i}") for i in range(3)]
