from io import TextIOWrapper
import subprocess
import tempfile

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


def prepare_dataset(fname: str, apy: float):
    df = pd.read_csv(fname)
    hw = np.power(apy, np.arange(len(df)) / 365 / 24 / 60 / 4)
    df['hw'] = [int((10 ** 9) * x) for x in np.maximum.accumulate(hw)]
    df = df[['block_number', 'wsteth_eth', 'stETH_amount', 'ETH_amount', 'stEthPerToken', 'hw']]
    df.to_csv('tmp.csv', index=False, float_format='%.27f')


def prepare_feed():
    file = open('tmp.csv')
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


def prepare_constants(
    weth_amount: int,
    wsteth_amount: int,
    width: int,
    min_deviation: int,
    pool_scale: int,
):
    length = len(pd.read_csv('tmp.csv'))
    with open('test/Constants.template', 'r') as file:
        text = ''.join(file.readlines())
    text = text.format(
        length=length,
        weth_amount=weth_amount,
        wsteth_amount=wsteth_amount,
        width=width,
        pool_scale=pool_scale,
        min_deviation=min_deviation,
    )
    with open('test/Constants.sol', 'w') as file:
        file.write(text)


@backoff.on_exception(
    backoff.constant,
    subprocess.CalledProcessError,
    max_tries=5,
)
def run_backtest(
    file: TextIOWrapper,
    fname: str = INPUT_FILE,
    weth_amount: int = WETH,
    wsteth_amount: int = WSTETH,
    width: int = WIDTH,
    min_deviation: int = MIN_DEVIATION,
    pool_scale: int = POOL_SCALE,
):
    prepare_dataset(fname, 1.032)
    prepare_feed()
    prepare_constants(
        weth_amount,
        wsteth_amount,
        width,
        min_deviation,
        pool_scale,
    )
    print('BACKTEST PREPARED')
    print('STARTING BACKTEST')
    try:
        subprocess.run(
            ['yarn', 'test'],
            stdout=file,
            check=True,
        )
    except subprocess.CalledProcessError:
        file.seek(0)
        print(file.read())
        raise


if __name__ == '__main__':
    with open('backtest.log', 'w') as file:
        run_backtest(file)
    with open('backtest.log', 'r') as file:
        plot_all(file.readlines())
