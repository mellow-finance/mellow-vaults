import os

for i in range(1000):
    block_number = 16240000 - i * 1000
    s = "yarn test:mainnet --fork-block-number " + str(block_number) + " --match-contract=\"ZTest\""
    os.system(s)  