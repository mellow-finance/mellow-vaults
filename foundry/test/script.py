import subprocess

def readNumber(s):
    s = s[::-1]
    t = ""
    ptr = 0
    for x in s:
        if x == '%':
            ptr += 2
            continue
        if x == ' ' or x == 'S':
            ptr -= 1
            if ptr < 0:
                break
            else:
                continue
        t += x
    
    return int(t[::-1])

res = []
for i in range(5):
    res.append([])

outs = ["MIN PRICE = ", "MAX PRICE = ", "FINAL PRICE = ", "% PROFIT = ", "% PN PROFIT = "]
outs_avg = ["AVG FINAL PRICE = ", "AVG % PROFIT = ", "AVG % PN PROFIT = "]

NONCE = 3

for i in range(10000):
    nonce = 1488 * (i + 1) + (i+NONCE) * (i+1)
    command = "// SPDX-License-Identifier: UNLICENSED\npragma solidity ^0.8.9;\ncontract MockFeed {\nfunction nonce() public pure returns (uint256) {\nreturn " + str(nonce) + ";\n}\n}"
    with open('test/MockFeed.sol', 'w') as f:
        f.write(command)
        f.close()
    bash_command = "yarn test --match-contract=HBacktest"
    with open('test/output.txt', 'w') as f:
        process = subprocess.Popen(bash_command.split(), stdout=f)
        process.communicate()
        f.close()

    with open('test/output.txt') as f:
        print("=========================================================")
        lines = f.readlines()
        lines = [line.rstrip() for line in lines][-8:-3]
        assert(lines[0][:5] == '  MIN')
        numbers = []
        for i in range(len(lines)):
            res[i].append(readNumber(lines[i]))
            print(outs[i] + str(readNumber(lines[i])))
        print("=========================================================")
        for i in range(3):
            print(outs_avg[i] + str(sum(res[i + 2]) / len(res[i + 2])))
        #f.close()

