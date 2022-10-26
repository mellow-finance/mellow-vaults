from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import List, Tuple

import matplotlib.pyplot as plt
import numpy as np


@dataclass
class State:
    block_number: int
    sqrt_price_x96: int
    lower_wsteth: int
    lower_weth: int
    lower_sqrt_ratio_ax96: int
    lower_sqrt_ratio_bx96: int
    upper_wsteth: int
    upper_weth: int
    upper_sqrt_ratio_ax96: int
    upper_sqrt_ratio_bx96: int
    erc20_wsteth: int
    erc20_weth: int


@dataclass
class Earnings:
    block_number: int
    weth: int
    wsteth: int


@dataclass
class Fees:
    block_number: int
    weth_swap_fees: int
    weth_slippage_fees: int
    weth_cowswap_fees: int
    wsteth_swap_fees: int
    wsteth_slippage_fees: int
    wsteth_cowswap_fees: int


def parse_state(lines: List[str]) -> List[State]:
    i = 0
    all_stats = []

    while i < len(lines):
        if lines[i] != '  STATS BEGIN:\n':
            i += 1
            continue
        block_number = int(lines[i + 1].strip().split()[-1])
        sqrt_price = int(lines[i + 2].strip().split()[-1])
        lower_tvl = lines[i + 3].strip().split(', ')
        lower_ratios = lines[i + 4].strip().split(', ')
        upper_tvl = lines[i + 5].strip().split(', ')
        upper_ratios = lines[i + 6].strip().split(', ')
        erc20 = lines[i + 7].strip().split(', ')
        all_stats.append(
            State(
                block_number=block_number,
                sqrt_price_x96=sqrt_price,
                lower_wsteth=int(lower_tvl[0]),
                lower_weth=int(lower_tvl[1]),
                lower_sqrt_ratio_ax96=int(lower_ratios[0]),
                lower_sqrt_ratio_bx96=int(lower_ratios[1]),
                upper_wsteth=int(upper_tvl[0]),
                upper_weth=int(upper_tvl[1]),
                upper_sqrt_ratio_ax96=int(upper_ratios[0]),
                upper_sqrt_ratio_bx96=int(upper_ratios[1]),
                erc20_wsteth=int(erc20[0]),
                erc20_weth=int(erc20[1]),
            )
        )
        i += 8
    return all_stats


def parse_earnings(lines: List[str]) -> List[Earnings]:
    i = 0
    all_earnings = []

    while i < len(lines):
        if lines[i] != '  EARNINGS:\n':
            i += 1
            continue
        block_number = int(lines[i + 1].strip().split()[-1])
        amounts = lines[i + 2].strip().split(', ')
        all_earnings.append(
            Earnings(
                block_number=block_number,
                wsteth=int(amounts[0]),
                weth=int(amounts[1]),
            )
        )
        i += 3
    return all_earnings


def parse_swaps(lines: List[str]) -> List[Fees]:
    i = 0
    all_fees = []
    last_block = 0
    weth_swap_fees = 0
    weth_slippage_fees = 0
    weth_cowswap_fees = 0
    wsteth_swap_fees = 0
    wsteth_slippage_fees = 0
    wsteth_cowswap_fees = 0

    while i < len(lines):
        if lines[i] != '  SWAP:\n':
            i += 1
            continue
        block_number = int(lines[i + 1].strip().split()[-1])
        token_in = lines[i + 2].strip().split()[-1]
        swap_fees = int(lines[i + 3].strip().split()[-1])
        slippage_fees = int(lines[i + 4].strip().split()[-1])
        cowswap_fees = int(lines[i + 5].strip().split()[-1])
        if token_in == 'weth':
            weth_swap_fees += swap_fees
            weth_slippage_fees += slippage_fees
            weth_cowswap_fees += cowswap_fees
        else:
            wsteth_swap_fees += swap_fees
            wsteth_slippage_fees += slippage_fees
            wsteth_cowswap_fees += cowswap_fees
        if block_number != last_block:
            all_fees.append(
                Fees(
                    block_number=block_number,
                    weth_swap_fees=weth_swap_fees,
                    weth_slippage_fees=weth_slippage_fees,
                    wsteth_swap_fees=wsteth_swap_fees,
                    wsteth_slippage_fees=wsteth_slippage_fees,
                    weth_cowswap_fees=weth_cowswap_fees,
                    wsteth_cowswap_fees=wsteth_cowswap_fees,
                )
            )
            weth_swap_fees = 0
            weth_slippage_fees = 0
            weth_cowswap_fees = 0
            wsteth_swap_fees = 0
            wsteth_slippage_fees = 0
            wsteth_cowswap_fees = 0
            last_block = block_number
        i += 6

    all_fees.append(
        Fees(
            block_number=last_block,
            weth_swap_fees=weth_swap_fees,
            weth_slippage_fees=weth_slippage_fees,
            wsteth_swap_fees=wsteth_swap_fees,
            wsteth_slippage_fees=wsteth_slippage_fees,
            weth_cowswap_fees=weth_cowswap_fees,
            wsteth_cowswap_fees=wsteth_cowswap_fees,
        )
    )
    return all_fees


def plot_weth(all_stats: List[State]):
    input_ts = [
        datetime(2022, 2, 28, 11, 59, 58) +
        15 * timedelta(seconds=x.block_number - 14297758)
        for x in all_stats
    ]
    price = np.array([(x.sqrt_price_x96 / 2 ** 96) ** 2 for x in all_stats])
    weth_amount = (
        np.array([x.lower_weth for x in all_stats]) +
        np.array([x.upper_weth for x in all_stats]) +
        np.array([x.erc20_weth for x in all_stats])
    ) / 10 ** 18
    fig = plt.figure(figsize=(8, 5))
    ax = fig.add_subplot(111)
    plt.title('WETH amount')
    ax.plot(input_ts, weth_amount, label='amount', color='blue')
    ax2 = ax.twinx()
    ax2.plot(input_ts, price, label='price', color='orange')
    ax.tick_params(axis='x', rotation=25)
    ax.set_xlabel('Date')
    ax.set_ylabel('Amount of tokens')
    ax.legend(loc=0)
    ax2.legend(loc=0)
    ax2.set_ylabel('WETH / WSTETH')
    ax.grid()
    plt.savefig('weth.jpg', bbox_inches='tight', dpi=150)


def plot_wsteth(all_stats: List[State]):
    input_ts = [
        datetime(2022, 2, 28, 11, 59, 58) +
        15 * timedelta(seconds=x.block_number - 14297758)
        for x in all_stats
    ]
    price = np.array([(x.sqrt_price_x96 / 2 ** 96) ** 2 for x in all_stats])
    wsteth_amount = (
        np.array([x.lower_wsteth for x in all_stats]) +
        np.array([x.upper_wsteth for x in all_stats]) +
        np.array([x.erc20_wsteth for x in all_stats])
    ) / 10 ** 18
    fig = plt.figure(figsize=(8, 5))
    ax = fig.add_subplot(111)
    plt.title('WSTETH amount')
    ax.plot(input_ts, wsteth_amount, label='amount', color='blue')
    ax2 = ax.twinx()
    ax2.plot(input_ts, price, label='price', color='orange')
    ax.tick_params(axis='x', rotation=25)
    ax.set_xlabel('Date')
    ax.set_ylabel('Amount of tokens')
    ax.legend()
    ax2.legend()
    ax2.set_ylabel('WETH / WSTETH')
    ax.grid()
    plt.savefig('wsteth.jpg', bbox_inches='tight', dpi=150)


def plot_capital(all_stats: List[State]):
    input_ts = [
        datetime(2022, 2, 28, 11, 59, 58) +
        15 * timedelta(seconds=x.block_number - 14297758)
        for x in all_stats
    ]
    price = np.array([(x.sqrt_price_x96 / 2 ** 96) ** 2 for x in all_stats])
    wsteth_amount = (
        np.array([x.lower_wsteth for x in all_stats]) +
        np.array([x.upper_wsteth for x in all_stats]) +
        np.array([x.erc20_wsteth for x in all_stats])
    ) / 10 ** 18
    weth_amount = (
        np.array([x.lower_weth for x in all_stats]) +
        np.array([x.upper_weth for x in all_stats]) +
        np.array([x.erc20_weth for x in all_stats])
    ) / 10 ** 18
    fig = plt.figure(figsize=(8, 5))
    ax = fig.add_subplot(111)
    plt.title('Total capital')
    ax.plot(input_ts, wsteth_amount * price + weth_amount, label='amount', color='blue')
    ax2 = ax.twinx()
    ax2.plot(input_ts, price, label='price', color='orange')
    ax.tick_params(axis='x', rotation=25)
    ax.set_xlabel('Date')
    ax.set_ylabel('Amount of tokens (in weth)')
    ax.legend()
    ax2.legend()
    ax2.set_ylabel('WETH / WSTETH')
    ax.grid()
    plt.savefig('capital.jpg', bbox_inches='tight', dpi=150)


def plot_weth_wsteth(all_stats: List[State]):
    input_ts = [
        datetime(2022, 2, 28, 11, 59, 58) +
        15 * timedelta(seconds=x.block_number - 14297758)
        for x in all_stats
    ]
    price = np.array([(x.sqrt_price_x96 / 2 ** 96) ** 2 for x in all_stats])
    wsteth_amount = (
        np.array([x.lower_wsteth for x in all_stats]) +
        np.array([x.upper_wsteth for x in all_stats]) +
        np.array([x.erc20_wsteth for x in all_stats])
    ) / 10 ** 18
    weth_amount = (
        np.array([x.lower_weth for x in all_stats]) +
        np.array([x.upper_weth for x in all_stats]) +
        np.array([x.erc20_weth for x in all_stats])
    ) / 10 ** 18
    fig = plt.figure(figsize=(8, 5))
    ax = fig.add_subplot(111)
    plt.title('WSTETH+WETH amount')
    ax.plot(input_ts, weth_amount + wsteth_amount, label='amount', color='blue')
    ax2 = ax.twinx()
    ax2.plot(input_ts, price, label='price', color='orange')
    ax.tick_params(axis='x', rotation=25)
    ax.set_xlabel('Date')
    ax.set_ylabel('Amount of tokens')
    ax.legend()
    ax2.legend()
    ax2.set_ylabel('WETH / WSTETH')
    ax.grid()
    plt.savefig('wsteth_weth.jpg', bbox_inches='tight', dpi=150)


def plot_earnings(all_earnings: List[Earnings]):
    input_ts = [
        datetime(2022, 2, 28, 11, 59, 58) +
        15 * timedelta(seconds=x.block_number - 14297758)
        for x in all_earnings
    ]
    weth_earnings = np.array([x.weth for x in all_earnings]) / 10 ** 18
    wsteth_earnings = np.array([x.wsteth for x in all_earnings]) / 10 ** 18
    fig = plt.figure(figsize=(8, 5))
    ax = fig.add_subplot(111)
    plt.title('Earnings')
    ax.plot(input_ts, weth_earnings.cumsum(), label='WETH', color='blue')
    ax.plot(input_ts, wsteth_earnings.cumsum(), label='WSTETH', color='orange')
    ax.tick_params(axis='x', rotation=25)
    ax.set_xlabel('Date')
    ax.set_ylabel('Amount of tokens')
    ax.legend(loc=0)
    ax.grid()
    plt.savefig('earnings.jpg', bbox_inches='tight', dpi=150)


def plot_swaps(all_swaps: List[Fees]):
    input_ts = [
        datetime(2022, 2, 28, 11, 59, 58) +
        15 * timedelta(seconds=x.block_number - 14297758)
        for x in all_swaps
    ]
    weth_fees = np.array([x.weth_cowswap_fees + x.weth_swap_fees for x in all_swaps]) / 10 ** 18
    wsteth_fees = np.array([x.wsteth_cowswap_fees + x.wsteth_swap_fees for x in all_swaps]) / 10 ** 18
    weth_slippage = np.array([x.weth_slippage_fees for x in all_swaps]) / 10 ** 18
    wsteth_slippage = np.array([x.wsteth_slippage_fees for x in all_swaps]) / 10 ** 18
    fig = plt.figure(figsize=(8, 5))
    ax = fig.add_subplot(111)
    plt.title('Swap fees')
    ax.plot(input_ts, weth_fees.cumsum(), label='WETH', color='blue')
    ax.plot(input_ts, wsteth_fees.cumsum(), label='WSTETH', color='orange')
    ax.tick_params(axis='x', rotation=25)
    ax.set_xlabel('Date')
    ax.set_ylabel('Amount of tokens')
    ax.legend(loc=0)
    ax.grid()
    plt.savefig('fees.jpg', bbox_inches='tight', dpi=150)
    fig = plt.figure(figsize=(8, 5))
    ax = fig.add_subplot(111)
    plt.title('Slippage loss')
    ax.plot(input_ts, weth_slippage.cumsum(), label='WETH', color='blue')
    ax.plot(input_ts, wsteth_slippage.cumsum(), label='WSTETH', color='orange')
    ax.tick_params(axis='x', rotation=25)
    ax.set_xlabel('Date')
    ax.set_ylabel('Amount of tokens')
    ax.legend(loc=0)
    ax.grid()
    plt.savefig('slippage.jpg', bbox_inches='tight', dpi=150)


def get_total_swaps(all_swaps: List[Fees]) -> Tuple[float, float]:
    weth_fees = np.array([x.weth_cowswap_fees + x.weth_swap_fees for x in all_swaps]) / 10 ** 18
    wsteth_fees = np.array([x.wsteth_cowswap_fees + x.wsteth_swap_fees for x in all_swaps]) / 10 ** 18
    return np.sum(weth_fees), np.sum(wsteth_fees)


def get_total_rebalances(lines: List[str]) -> int:
    for line in lines:
        if line.startswith('  Total rebalances: '):
            return int(line.strip().split()[-1])


def plot_all(lines: List[str]):
    earnings = parse_earnings(lines)
    state = parse_state(lines)
    plot_weth(state)
    plot_wsteth(state)
    plot_capital(state)
    plot_weth_wsteth(state)
    plot_earnings(earnings)
    plot_swaps(parse_swaps(lines))
