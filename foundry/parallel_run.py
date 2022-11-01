from cmath import sin
from concurrent.futures import ProcessPoolExecutor

import os

deviationsArray = [10, 20]
positionWidths = [100, 120, 140]
tokenAmounts = [1000]

processesNumber = 3


def singleProcess(currentTuple):
    folderName = 'deviation' + str(currentTuple[0]) + 'width' + str(currentTuple[1]) + 'amount' + str(currentTuple[2])
    preview = "backtest_results/" + folderName
    os.system("rm -rf " + preview)
    os.system("mkdir " + preview)
    os.system("python3 backtest.py " + str(currentTuple[0]) + " " + str(currentTuple[1]) + " " + str(currentTuple[2]) + " " + preview)


if __name__ == '__main__':

    os.system("rm -rf backtest_results")
    os.system("mkdir backtest_results")

    allInputs = []

    for deviation in deviationsArray:
        for positionWidth in positionWidths:
            for amount in tokenAmounts:
                allInputs.append((deviation, positionWidth, amount))

    with ProcessPoolExecutor(2) as pool:
        pool.map(singleProcess, allInputs)
