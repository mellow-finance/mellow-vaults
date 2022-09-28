import csv
import pandas as pd
import numpy as np


def prepare_dataset():
    df = pd.read_csv('price_data.csv')
    eth_amount = [int(x) for x in df['ETH_amount'].values]
    steth_amount = [int(x) for x in df['stETH_amount'].values]
    steth_eth = [float(x) for x in df['steth_eth'].values]
    eth_capital = [x + int(y * z) for x, y, z in zip(eth_amount, steth_amount, steth_eth)]
    lp = [int(x) for x in df['total_supply'].values]
    lp_eth_d9 = np.array([x * (10 ** 9) // y for x, y in zip(eth_capital, lp)])
    lp_eth_d9[lp_eth_d9 >= 2 * (10 ** 9)] = 0
    lp_eth_hw_d9 = np.maximum.accumulate(lp_eth_d9)
    ratios = lp_eth_hw_d9[1:] * (10 ** 9) // lp_eth_hw_d9[:1]
    df['ratios'] = np.hstack([np.ones(1), ratios]).astype(np.int32)
    df = df[['block_number', 'wsteth_eth', 'stETH_amount', 'ETH_amount', 'stEthPerToken', 'ratios']]
    df.to_csv('tmp.csv', index=False, float_format='%.27f')


def main():

    prepare_dataset()

    file = open('tmp.csv')
    csvreader = csv.reader(file)

    # block_number, wsteth_eth, stETH_amount, ETH_amount, stEthPerToken, ratios
    need = [0, 1, 2, 3, 4, 5]

    arr = []
    for i in range(6):
        arr.append([])

    for row in csvreader:
        for i in range(6):
            arr[i].append(row[need[i]])

    with open("randomfile.txt", "w") as external_file:
        for i in range(6):
            print("a[" + str(i) + "] = \"", end="", file=external_file)
            for j in range(1, len(arr[0])):
                print(arr[i][j] + ",", end="", file=external_file)
            print("\";", file=external_file)


main()
