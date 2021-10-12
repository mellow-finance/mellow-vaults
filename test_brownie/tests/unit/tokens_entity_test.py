import pytest

ETH = 10 ** 18


@pytest.fixture(scope="module")
def tokens(ERC20Test, a):
    return [a[0].deploy(ERC20Test, f"Test Token {i}", f"TST{i}") for i in range(3)]
