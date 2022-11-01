import sys
import subprocess
from io import TextIOWrapper

import backoff
import csv
import pandas as pd
import numpy as np

from backtest_analysis import plot_all

INPUT_FILE = 'price_data.csv'
WETH = 1000
WSTETH = 1000
WIDTH = 100
MIN_DEVIATION = WIDTH // 20
POOL_SCALE = 1


def prepare_dataset(fname: str, apy: float, preview: str):
    df = pd.read_csv(fname)
    hw = np.power(apy, np.arange(len(df)) / 365 / 24 / 60 / 4)
    df['hw'] = [int((10 ** 9) * x) for x in np.maximum.accumulate(hw)]
    df = df[['block_number', 'wsteth_eth', 'stETH_amount', 'ETH_amount', 'stEthPerToken', 'hw']]
    df.to_csv(preview + '/tmp.csv', index=False, float_format='%.27f')


def prepare_feed(preview: str):
    file = open(preview + '/tmp.csv')
    csvreader = csv.reader(file)

    # block_number, wsteth_eth, stETH_amount, ETH_amount, stEthPerToken, hw

    arr = []
    for i in range(6):
        arr.append([])

    for row in csvreader:
        for i in range(6):
            arr[i].append(row[i])

    with open('test/FeedContract.template', 'r') as file:
        text = ''.join(file.readlines())
    text = text.format(
        block_number=','.join(arr[0][1:]) + ',',
        wsteth_eth=','.join(arr[1][1:]) + ',',
        steth_amount=','.join(arr[2][1:]) + ',',
        eth_amount=','.join(arr[3][1:]) + ',',
        steth_per_token=','.join(arr[4][1:]) + ',',
        ratios=','.join(arr[5][1:]) + ',',
    )

    with open('test/FeedContract.sol', 'w') as file:
        file.write(text)


@backoff.on_exception(
    backoff.constant,
    subprocess.CalledProcessError,
    max_tries=5,
)
def run_backtest(
    file: TextIOWrapper,
    preview: str,
    fname: str = INPUT_FILE,
    weth_amount: int = WETH,
    wsteth_amount: int = WSTETH,
    width: int = WIDTH,
    min_deviation: int = MIN_DEVIATION,
):
    prepare_dataset(fname, 1.2, preview)
    prepare_feed(preview)

    print('BACKTEST PREPARED')
    print('STARTING BACKTEST')
    try:
        subprocess.run(
            [f'len={30048} wethAmount={weth_amount} wstethAmount={wsteth_amount} width={width} minDeviation={min_deviation} yarn test'],
            stdout=file,
            check=True,
            shell=True,
        )
    except subprocess.CalledProcessError:
        file.seek(0)
        print(file.read())
        raise


if __name__ == '__main__':

    deviation = int(sys.argv[1])
    width = int(sys.argv[2])
    amount = int(sys.argv[3])
    preview = sys.argv[4]

    with open(preview + '/backtest.log', 'w') as file:
        run_backtest(file, preview, INPUT_FILE, amount, amount, width, deviation)
    with open(preview + '/backtest.log', 'r') as file:
        plot_all(file.readlines(), preview)
