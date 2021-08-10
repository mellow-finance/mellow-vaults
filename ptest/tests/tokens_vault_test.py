from brownie import accounts
from brownie.network.contract import Contract
import pytest

ETH = 10 ** 18


@pytest.fixture(scope="module")
def token(ERC20Mock) -> Contract:
    t = accounts[0].deploy(ERC20Mock, "Test Token", "TST")
    t.mint(accounts[0], 1000 * ETH)
    return t


def test_transfer(token):
    token.transfer(accounts[1], 100, {"from": accounts[0]})
    assert token.balanceOf(accounts[1]) == 100
