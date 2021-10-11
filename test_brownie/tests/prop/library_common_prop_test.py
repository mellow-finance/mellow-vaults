from typing import List

from brownie import accounts
from brownie.test import given, strategy
from brownie.typing import AccountsType


def _addresses_to_int(addresses: List[AccountsType]) -> List[int]:
    return [(address.address.lower(), 16) for address in addresses]


def _is_unique(seq: list) -> bool:
    return len(seq) == len(set(seq))


@given(addresses=strategy("address[]", min_length=0, max_length=15, unique=False))
def test_sorted_and_unique(addresses, a, CommonTest):
    common_test = CommonTest.deploy({"from": a[0]})
    int_addresses = _addresses_to_int(addresses)
    int_addresses_sorted = [_ for _ in sorted(int_addresses)]
    assert common_test.isSortedAndUnique(addresses) == (
        int_addresses == int_addresses_sorted and
        _is_unique(int_addresses)
    )
