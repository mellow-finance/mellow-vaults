import itertools
import os
import subprocess
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass
from enum import Enum
from typing import List, Tuple


@dataclass
class RunInfo:
    initial_attacker_capital: float
    final_attacker_capital: float
    attacker_minted_capital: float
    initial_lp_price: int
    final_lp_price: int


class Coin(Enum):
    weth = 'WETH'
    wsteth = 'WSTETH'


@dataclass
class MintInfo:
    coin: Coin
    amount: float


def parse_mints(lines: List[str]) -> List[MintInfo]:
    result: List[MintInfo] = []
    for i in range(len(lines)):
        if lines[i].strip() == 'ATTACKER_MINTED':
            result.append(
                MintInfo(
                    Coin(lines[i + 1].strip()),
                    int(lines[i + 2].strip()) / 10 ** 18,
                )
            )
    return result


def parse_price(lines: List[str]) -> float:
    for line in lines:
        if line.strip().startswith('PRICE:'):
            _, price = line.strip().split()
            return int(price) / 2 ** 96


def parse_attacker_capitals(lines: List[str]) -> Tuple[float, float]:
    starting_capital_idx = 0
    end_capital_idx = 0
    for i in range(len(lines)):
        if lines[i].strip() == 'CAPITAL:':
            starting_capital_idx = i
            break
    for i in range(starting_capital_idx + 1, len(lines)):
        if lines[i].strip() == 'CAPITAL:':
            end_capital_idx = i
            break
    starting_capital = int(lines[starting_capital_idx + 2].strip())
    final_capital = int(lines[end_capital_idx + 2].strip())
    return starting_capital / 10 ** 18, final_capital / 10 ** 18


def parse_initial_lp_price(lines: List[str]) -> int:
    for line in lines:
        if line.strip().startswith('INITIAL_LP_PRICE:'):
            _, res = line.strip().split()
            return int(res)


def parse_final_lp_price(lines: List[str]) -> int:
    for line in lines:
        if line.strip().startswith('FINAL_LP_PRICE:'):
            _, res = line.strip().split()
            return int(res)


def parse_lines(lines: List[str]) -> RunInfo:
    starting_capital, final_capital = parse_attacker_capitals(lines)
    price = parse_price(lines)
    mints = parse_mints(lines)
    initial_lp_price = parse_initial_lp_price(lines)
    final_lp_price = parse_final_lp_price(lines)
    return RunInfo(
        initial_attacker_capital=starting_capital,
        final_attacker_capital=final_capital,
        attacker_minted_capital=sum(x.amount if x.coin is Coin.weth else x.amount * price for x in mints),
        initial_lp_price=initial_lp_price,
        final_lp_price=final_lp_price,
    )


def split_lines(lines: List[str]) -> List[List[str]]:
    result: List[List[str]] = []
    indices = []

    for i in range(len(lines)):
        if lines[i].strip() == 'NEW ROUND':
            indices.append(i)

    indices.append(len(lines))

    result = []

    for i in range(len(indices) - 1):
        l = indices[i]
        r = indices[i + 1]
        result.append(lines[l:r])

    return result


def process_results(lines: List[str]) -> List[str]:
    result: List[str] = []
    for elem in split_lines(lines):
        info = parse_lines(elem)
        flag1 = info.final_lp_price >= info.initial_lp_price
        flag2 = info.initial_attacker_capital + info.attacker_minted_capital < info.final_attacker_capital
        if flag1 and flag2:
            result.append('INVARIANT IS WRONG')
        if not flag1 and flag2:
            result.append('SOMETHING WAS STOLEN')
        if not flag1 and not flag2:
            result.append('LP PRICE WENT DOWN')
    return result


def full_pipeline(args: Tuple[str, int, int, int]):
    preview, width, deviation, deposit_capital = args
    fname = preview + f'/width{width}deviation{deviation}deposit{deposit_capital}.log'
    with open(fname, 'w') as file:
        subprocess.run(
            f'width={width} deviation={deviation} deposit={deposit_capital} yarn advanced-attack-test',
            shell=True,
            stdout=file,
        )
    with open(fname, 'r') as file:
        result = process_results(file.readlines())
    with open(preview + f'/result_width{width}deviation{deviation}deposit{deposit_capital}.log', 'w') as file:
        for line in result:
            file.write(line)


def run_in_parallel(width_grid: List[int], deviation_grid: List[int], capital_amount: List[int]):
    args = itertools.product(['advanced_results'], width_grid, deviation_grid, capital_amount)
    os.system('rm -rf advanced_results')
    os.system('mkdir advanced_results')
    with ProcessPoolExecutor(2) as pool:
        pool.map(full_pipeline, args)


if __name__ == '__main__':
    run_in_parallel([80, 100], [-20, -15, -10, -5, 0, 5, 10, 15, 20], [100, 1000, 5000, 10000])
