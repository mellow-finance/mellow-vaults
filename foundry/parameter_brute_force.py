import subprocess
import tempfile
from concurrent.futures import ProcessPoolExecutor
from itertools import product
from typing import Dict, List, Tuple

import numpy as np
from tqdm.notebook import tqdm

from backtest import INPUT_FILE, run_backtest
from backtest_analysis import parse_state, parse_swaps


def get_stats(lines: List[str]):
    all_stats = parse_state(lines)
    all_swaps = parse_swaps(lines)
    starting_price = (all_stats[0].sqrt_price_x96 / 2 ** 96) ** 2
    end_price = (all_stats[-1].sqrt_price_x96 / 2 ** 96) ** 2
    starting_capital = int(all_stats[0].erc20_wsteth * starting_price) + all_stats[0].erc20_weth
    end_capital = int(all_stats[0].erc20_wsteth * end_price) + all_stats[0].erc20_weth
    strategy_end_capital = int(all_stats[-1].erc20_wsteth * end_price) + all_stats[-1].erc20_weth
    num_days = (all_stats[-1].block_number - all_stats[0].block_number) * 15 // 60 // 60 // 24
    erc20_rebalances = 0
    for line in lines:
        if line.startswith('  ERC20Rebalances:'):
            erc20_rebalances = int(line.strip().split()[-1])
    uni_v3_rebalances = 0
    for line in lines:
        if line.startswith('  UniV3 rebalances:'):
            uni_v3_rebalances = int(line.strip().split()[-1])
    return {
        'starting_price': starting_price,
        'end_price': end_price,
        'num_days': num_days,
        'starting_tokens': [
            all_stats[0].erc20_weth / 10 ** 18 + all_stats[0].lower_weth / 10 ** 18 + all_stats[0].upper_weth / 10 ** 18,
            all_stats[0].erc20_wsteth / 10 ** 18 + all_stats[0].lower_wsteth / 10 ** 18 + all_stats[0].upper_wsteth / 10 ** 18,
        ],
        'end_tokens': [
            all_stats[-1].erc20_weth / 10 ** 18 + all_stats[-1].lower_weth / 10 ** 18 + all_stats[-1].upper_weth / 10 ** 18,
            all_stats[-1].erc20_wsteth / 10 ** 18 + all_stats[-1].lower_wsteth / 10 ** 18 + all_stats[-1].upper_wsteth / 10 ** 18,
        ],
        'erc20_rebalances': erc20_rebalances,
        'uni_v3_rebalances': uni_v3_rebalances,
        'cowswap_weth': np.sum([x.weth_cowswap_fees / 10 ** 18 for x in all_swaps]),
        'cowswap_wsteth': np.sum([x.wsteth_cowswap_fees / 10 ** 18 for x in all_swaps]),
    }


def process_one(x: Tuple[int, int, int]):
    with tempfile.TemporaryFile() as file:
        try:
            run_backtest(file, INPUT_FILE, x[0], x[0], x[1], x[2], 1)
        except subprocess.CalledProcessError:
            print("Error: ", x)
        print("Finished one")
        file.seek(0)
        lines = [line.decode('utf-8') for line in file.readlines()]
        return x, get_stats(lines)


def brute_force(
    tvl_grid: List[int],
    width_grid: List[int],
    min_deviation_grid: List[int],
    was: List[Tuple[int, int, int]] = [],
) -> List[Tuple[Tuple[int, int, int], Dict[str, int]]]:
    args = product(tvl_grid, width_grid, min_deviation_grid)
    result = []
    for elem in tqdm(args):
        if elem in was:
            continue
        result.append(process_one(elem))
        print(elem)
        print(result[-1])
    return result
    with ProcessPoolExecutor(3) as pool:
        return list(pool.map(process_one, args))
