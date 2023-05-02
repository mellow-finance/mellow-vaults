import json
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from math import log
from web3 import Web3
from web3.middleware import geth_poa_middleware
from web3.contract import Contract
from typing import Optional
from cache import Cache
from datetime import datetime
import asyncio

w3_1 = Web3(Web3.HTTPProvider('https://polygon-mainnet.g.alchemy.com/v2/2hGHxl93BXAhw36CS-PytquxtQQNEPcS'))
AVG_BLOCK_TIME = 13

def get_contract(address: str, name: str, w3) -> Optional[Contract]:
    try:
        with open('./{}.json'.format(name), 'r') as f:
            abi = json.load(f)
            return w3.eth.contract(address=w3.toChecksumAddress(address), abi=abi)
    except Exception as e:
        print(e)
        return None
        
vault = get_contract('0xF777d4C8BBcf97c924FA4377A86ac24a88ce1126', 'C', w3_1)
oracle = get_contract('0x27AeBFEBDd0fde261Ec3E1DF395061C56EEC5836', 'D', w3_1)

def f1(block):
    res = vault.functions.calcTvl().call(block_identifier=block)
    return res

def f2(block):
    res = oracle.functions.priceX96('0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619', '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174', 32).call(block_identifier=block)
    return res

DATA = None
def subcalls(block):
    global DATA
    DATA = f1(block), f2(block)

loop = asyncio.new_event_loop()
asyncio.set_event_loop(loop)
def call_contracts(block):
    subcalls(block)
    minAmounts, eth = DATA
    return minAmounts[0], int(eth[0][0] / 2**96 * 10**12)

def main():
    index = 0
    with open('kek.logs', 'w') as f:
        for block in range(39097000, 42229000, 1000):
            while (True):
                try:
                    A, B = call_contracts(block)
                    f.write(str(A) + ' ' + str(B) + '\n')
                    f.flush()
                    break
                except:
                    continue

main()