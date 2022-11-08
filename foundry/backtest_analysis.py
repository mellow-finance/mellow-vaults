from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import List, Tuple

import matplotlib.pyplot as plt
import numpy as np

import il

@dataclass
class State:
    block_number: int
    sqrt_price_x96: int
    lower_wsteth: int
    lower_weth: int
    lower_sqrt_ratio_ax96: int
    lower_sqrt_ratio_bx96: int
    lower_liquidity: int
    upper_wsteth: int
    upper_weth: int
    upper_sqrt_ratio_ax96: int
    upper_sqrt_ratio_bx96: int
    upper_liquidity: int
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
        lower_liquidity = int(lines[i + 5].strip().split()[-1])
        upper_tvl = lines[i + 6].strip().split(', ')
        upper_ratios = lines[i + 7].strip().split(', ')
        upper_liquidity = int(lines[i + 8].strip().split()[-1])
        erc20 = lines[i + 9].strip().split(', ')
        all_stats.append(
            State(
                block_number=block_number,
                sqrt_price_x96=sqrt_price,
                lower_wsteth=int(lower_tvl[0]),
                lower_weth=int(lower_tvl[1]),
                lower_sqrt_ratio_ax96=int(lower_ratios[0]),
                lower_sqrt_ratio_bx96=int(lower_ratios[1]),
                lower_liquidity=lower_liquidity,
                upper_wsteth=int(upper_tvl[0]),
                upper_weth=int(upper_tvl[1]),
                upper_sqrt_ratio_ax96=int(upper_ratios[0]),
                upper_sqrt_ratio_bx96=int(upper_ratios[1]),
                upper_liquidity=upper_liquidity,
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


def plot_weth(all_stats: List[State], preview: str):
    input_ts = [
        datetime(2022, 2, 28, 11, 59, 58) +
        12 * timedelta(seconds=x.block_number - 14297758)
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
    plt.savefig(preview + '/weth.jpg', bbox_inches='tight', dpi=150)


def plot_wsteth(all_stats: List[State], preview: str):
    input_ts = [
        datetime(2022, 2, 28, 11, 59, 58) +
        12 * timedelta(seconds=x.block_number - 14297758)
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
    plt.savefig(preview + '/wsteth.jpg', bbox_inches='tight', dpi=150)


def plot_capital(all_stats: List[State], preview: str):
    input_ts = [
        datetime(2022, 2, 28, 11, 59, 58) +
        12 * timedelta(seconds=x.block_number - 14297758)
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
    plt.savefig(preview + '/capital.jpg', bbox_inches='tight', dpi=150)


def plot_weth_wsteth(all_stats: List[State], preview: str):
    input_ts = [
        datetime(2022, 2, 28, 11, 59, 58) +
        12 * timedelta(seconds=x.block_number - 14297758)
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
    plt.savefig(preview + '/wsteth_weth.jpg', bbox_inches='tight', dpi=150)


def plot_earnings(all_earnings: List[Earnings], preview: str):
    input_ts = [
        datetime(2022, 2, 28, 11, 59, 58) +
        12 * timedelta(seconds=x.block_number - 14297758)
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
    plt.savefig(preview + '/earnings.jpg', bbox_inches='tight', dpi=150)


def plot_swaps(all_swaps: List[Fees], preview: str):
    input_ts = [
        datetime(2022, 2, 28, 11, 59, 58) +
        12 * timedelta(seconds=x.block_number - 14297758)
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
    plt.savefig(preview + '/fees.jpg', bbox_inches='tight', dpi=150)
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
    plt.savefig(preview + '/slippage.jpg', bbox_inches='tight', dpi=150)


def plot_capital_distribution(all_stats: List[State], preview):
    input_ts = [
        datetime(2022, 2, 28, 11, 59, 58) +
        12 * timedelta(seconds=x.block_number - 14297758)
        for x in all_stats
    ]
    price = np.array([(x.sqrt_price_x96 / 2 ** 96) ** 2 for x in all_stats])
    wsteth_amount_univ3 = (
        np.array([x.lower_wsteth for x in all_stats]) +
        np.array([x.upper_wsteth for x in all_stats])
    ) / 10 ** 18
    weth_amount_univ3 = (
        np.array([x.lower_weth for x in all_stats]) +
        np.array([x.upper_weth for x in all_stats])
    ) / 10 ** 18
    wsteth_amount_erc20 = (
        np.array([x.erc20_wsteth for x in all_stats])
    ) / 10 ** 18
    weth_amount_erc20 = (
        np.array([x.erc20_weth for x in all_stats])
    ) / 10 ** 18
    fig = plt.figure(figsize=(8, 5))
    ax = fig.add_subplot(111)
    plt.title('Distribution of capitals')
    ax.plot(input_ts, weth_amount_univ3 + wsteth_amount_univ3 * price, label='UniV3', color='blue')
    ax.plot(input_ts, weth_amount_erc20 + wsteth_amount_erc20 * price, label='erc20', color='red')
    ax.tick_params(axis='x', rotation=25)
    ax.set_xlabel('Date')
    ax.set_ylabel('WETH')
    ax.legend()
    ax.grid()
    plt.savefig(preview + '/distribution.jpg', bbox_inches='tight', dpi=150)


def get_total_swaps(all_swaps: List[Fees]) -> Tuple[float, float]:
    weth_fees = np.array([x.weth_cowswap_fees + x.weth_swap_fees for x in all_swaps]) / 10 ** 18
    wsteth_fees = np.array([x.wsteth_cowswap_fees + x.wsteth_swap_fees for x in all_swaps]) / 10 ** 18
    return np.sum(weth_fees), np.sum(wsteth_fees)


def get_total_rebalances(lines: List[str]) -> int:
    for line in lines:
        if line.startswith('  Total rebalances: '):
            return int(line.strip().split()[-1])


def plot_il(all_stats: List[State], preview):
    result = il.calculate_il(all_stats)
    input_ts = [
        datetime(2022, 2, 28, 11, 59, 58) +
        12 * timedelta(seconds=x.block_number - 14297758)
        for x in all_stats
    ]
    price = np.array([(x.sqrt_price_x96 / 2 ** 96) ** 2 for x in all_stats])
    il_ = np.cumsum([result[x.block_number] / 10 ** 18 for x in all_stats])
    fig = plt.figure(figsize=(8, 5))
    ax = fig.add_subplot(111)
    plt.title('IL')
    ax.plot(input_ts, il_, label='amount', color='blue')
    ax2 = ax.twinx()
    ax2.plot(input_ts, price, label='price', color='orange')
    ax.tick_params(axis='x', rotation=25)
    ax.set_xlabel('Date')
    ax.set_ylabel('Amount of capital (WETH)')
    ax.legend()
    ax2.legend()
    ax2.set_ylabel('WETH / WSTETH')
    ax.grid()
    plt.savefig(preview + '/il.jpg', bbox_inches='tight', dpi=150)


def scatter_loss(all_stats: List[State], all_earnings: List[Earnings], preview):
    capital_earnings = np.zeros(len(all_stats) - 1)
    price = np.array([(x.sqrt_price_x96 / 2 ** 96) ** 2 for x in all_stats])
    j = 0
    for i in range(len(all_stats) - 1):
        while j < len(all_earnings) and all_earnings[j].block_number <= all_stats[i + 1].block_number:
            capital_earnings[i] += (all_earnings[j].weth + all_earnings[j].wsteth * price[i + 1]) / 10 ** 18
            j += 1
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
    capital = weth_amount + wsteth_amount * price
    diff = np.diff(capital)
    loss = (diff - capital_earnings)

    price_deviation = 100 * price[1:] / price[:-1] - 100
    fig = plt.figure(figsize=(8, 5))
    ax = fig.add_subplot(111)
    ax.grid()
    plt.title('Capital change / price deviation')
    ax.scatter(price_deviation, loss)
    plt.xlabel('Price deviation (%)')
    plt.ylabel('Capital change (WETH)')
    plt.savefig(preview + '/loss.jpg', bbox_inches='tight', dpi=150)


def scatter_il(all_stats: List[State], preview):
    result = il.calculate_il(all_stats)
    price = np.array([(x.sqrt_price_x96 / 2 ** 96) ** 2 for x in all_stats])
    il_ = np.array([result[x.block_number] / 10 ** 18 for x in all_stats[:-1]])
    price_deviation = np.abs(100 * price[1:] / price[:-1] - 100)
    fig = plt.figure(figsize=(8, 5))
    ax = fig.add_subplot(111)
    ax.grid()
    plt.title('Capital loss / price deviation')
    print(il_.shape)
    print(price_deviation.shape)
    ax.scatter(il_, price_deviation, alpha=0.5)
    plt.xlabel('Price deviation (%)')
    plt.ylabel('Loss (WETH)')
    plt.savefig(preview + '/il_loss.jpg', bbox_inches='tight', dpi=150)


def parse_final_stats(lines: List[str]) -> State:
    i = 0

    while i < len(lines):
        if lines[i] != '  FINAL STATS:\n':
            i += 1
            continue
        sqrt_price = int(lines[i + 1].strip().split()[-1])
        lower_tvl = lines[i + 2].strip().split(', ')
        lower_ratios = lines[i + 3].strip().split(', ')
        lower_liquidity = int(lines[i + 4].strip().split()[-1])
        upper_tvl = lines[i + 5].strip().split(', ')
        upper_ratios = lines[i + 6].strip().split(', ')
        upper_liquidity = int(lines[i + 7].strip().split()[-1])
        erc20 = lines[i + 8].strip().split(', ')
        return State(
            block_number=0,
            sqrt_price_x96=sqrt_price,
            lower_wsteth=int(lower_tvl[0]),
            lower_weth=int(lower_tvl[1]),
            lower_sqrt_ratio_ax96=int(lower_ratios[0]),
            lower_sqrt_ratio_bx96=int(lower_ratios[1]),
            lower_liquidity=lower_liquidity,
            upper_wsteth=int(upper_tvl[0]),
            upper_weth=int(upper_tvl[1]),
            upper_sqrt_ratio_ax96=int(upper_ratios[0]),
            upper_sqrt_ratio_bx96=int(upper_ratios[1]),
            upper_liquidity=upper_liquidity,
            erc20_wsteth=int(erc20[0]),
            erc20_weth=int(erc20[1]),
        )


def short_report(all_stats: List[State], final_state: State, all_swaps: List[Fees], preview):
    weth_fees = np.sum([
        x.weth_cowswap_fees / 10 ** 18 +
        x.weth_swap_fees / 10 ** 18 for x in all_swaps
    ])
    wsteth_fees = np.sum([
        x.wsteth_cowswap_fees / 10 ** 18 +
        x.wsteth_swap_fees / 10 ** 18 for x in all_swaps
    ])
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
    initial_capital = wsteth_amount[0] * price[0] + weth_amount[0]
    end_capital = wsteth_amount[-1] * price[-1] + weth_amount[-1]
    end_capital_without_strategy = wsteth_amount[0] * price[-1] + weth_amount[0]
    backtest_power = (365 * 24 * 60 * 60) / 12 / (all_stats[-1].block_number - all_stats[0].block_number)
    end_capital_modified = (final_state.lower_weth + final_state.upper_weth + final_state.erc20_weth) + \
        (final_state.lower_wsteth + final_state.upper_wsteth + final_state.erc20_wsteth) * (final_state.sqrt_price_x96 / 2 ** 96) ** 2
    end_capital_modified /= 10 ** 18

    with open(preview + '/report.txt', 'w') as file:
        file.write(f'WETH fees: {weth_fees}\n')
        file.write(f'WSTETH fees: {wsteth_fees}\n')
        file.write(f'initial capital WETH: {round(initial_capital, 2)}\n')
        file.write(f'end capital WETH: {round(end_capital, 2)}\n')
        file.write(f'apr WETH: {round(100 * (end_capital / initial_capital) ** backtest_power - 100 , 2)}\n')
        file.write(f'apr WSTETH: {round(100 * (end_capital / price[-1] / initial_capital * price[0] - 100, 2))}\n')
        file.write(f'neutral apr: {round(100 * (end_capital / end_capital_without_strategy) ** backtest_power - 100, 2)}\n')
        file.write(f'modified apr: {round(100 * (end_capital_modified / initial_capital) ** backtest_power - 100, 2)}\n')


def plot_all(lines: List[str], preview: str):
    earnings = parse_earnings(lines)
    state = parse_state(lines)
    plot_weth(state, preview)
    plot_wsteth(state, preview)
    plot_capital(state, preview)
    plot_weth_wsteth(state, preview)
    plot_earnings(earnings, preview)
    plot_swaps(parse_swaps(lines), preview)
    plot_capital_distribution(state, preview)
    plot_il(state, preview)
    scatter_loss(state, earnings, preview)
    scatter_il(state, preview)
    short_report(state, parse_final_stats(lines), parse_swaps(lines), preview)
