from brownie import accounts
from brownie.test import given, strategy
from brownie.typing import AccountsType


def _addresses_to_int(addresses: list[AccountsType]) -> list[int]:
    return [(address.address.lower(), 16) for address in addresses]


def _is_unique(seq: list) -> bool:
    return len(seq) == len(set(seq))


@given(addresses=strategy("address[]", min_length=0, max_length=15, unique=False))
def test_sorted_and_unique(addresses, a, CommonTest):
    common_test = CommonTest.deploy({"from": a[0]})
    print(common_test.isSortedAndUnique(addresses))
    int_addresses = _addresses_to_int(addresses)
    int_addresses_sorted = [_ for _ in sorted(int_addresses)]
    assert common_test.isSortedAndUnique(addresses) == (
        int_addresses == int_addresses_sorted and
        _is_unique(int_addresses)
    )
