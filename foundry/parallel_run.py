import multiprocessing
import os

deviationsArray = [5, 10, 20]
positionWidths = [100, 200]
tokenAmounts = [100, 500, 2000]

processesNumber = 2

def singleProcess(allInputs, remainder):
    for i in range(len(allInputs)):
        if i % processesNumber != remainder:
            continue
        currentTuple = allInputs[i]
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

    processes = []
    
    for i in range(processesNumber):
        proc = multiprocessing.Process(target=singleProcess, args=(allInputs, i, ))
        processes.append(proc)

    for p in processes:
        p.start()

    for p in processes:
        p.join()
    

    