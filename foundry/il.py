from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import List

import numpy as np


@dataclass
class DepositInfo:
    liquidity: int
    sqrt_price_x96: int

@dataclass
class PositionInfo:
    sqrt_ratio_ax96: int
    sqrt_ratio_bx96: int
    deposits: List[DepositInfo]


def getAmount0ForLiquidity(l, sqrtRatioAX96, sqrtRatioBX96):
    return l * (1<<96) * (sqrtRatioBX96 - sqrtRatioAX96) // (sqrtRatioAX96 * sqrtRatioBX96)


def getAmount1ForLiquidity(l, sqrtRatioAX96, sqrtRatioBX96):
    return l * (sqrtRatioBX96 - sqrtRatioAX96) // (1 << 96)

def getAmountsForLiquidity(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, liquidity): #предполагаем tickLower <= tick <= tickUpper
    return (
        getAmount0ForLiquidity(liquidity, sqrtRatioX96, sqrtRatioBX96),
        getAmount1ForLiquidity(liquidity, sqrtRatioAX96, sqrtRatioX96),
    )


def capital(token0, token1, sqrt_ratio_x96):
    price = (sqrt_ratio_x96 / (1 << 96)) ** 2
    return token1 + int(token0 * price)

def calculate_new_state(
    position: PositionInfo,
    sqrt_ratio_x96: int,
    total_liquidity: int,
    needed_liquidity: int,
):
    capital_loss = 0
    while total_liquidity > needed_liquidity:
        deposit = position.deposits.pop()
        liquidity_to_withdraw = min(deposit.liquidity, total_liquidity - needed_liquidity)
        total_liquidity -= liquidity_to_withdraw
        (old_amount0, old_amount1) = getAmountsForLiquidity(
            deposit.sqrt_price_x96,
            position.sqrt_ratio_ax96,
            position.sqrt_ratio_bx96,
            liquidity_to_withdraw,
        )
        (new_amount0, new_amount1) = getAmountsForLiquidity(
            sqrt_ratio_x96,
            position.sqrt_ratio_ax96,
            position.sqrt_ratio_bx96,
            liquidity_to_withdraw,
        )
        capital_delta = (
            capital(old_amount0, old_amount1, sqrt_ratio_x96) -
            capital(new_amount0, new_amount1, sqrt_ratio_x96)
        )
        assert capital_delta >= -2, str(capital_delta)
        capital_loss += capital_delta
        if liquidity_to_withdraw < deposit.liquidity:
            position.deposits.append(
                DepositInfo(
                    deposit.liquidity - liquidity_to_withdraw, 
                    deposit.sqrt_price_x96,
                )
        )
    if total_liquidity < needed_liquidity:
        position.deposits.append(
            DepositInfo(
                needed_liquidity - total_liquidity,
                sqrt_ratio_x96,
            )
        )
        total_liquidity = needed_liquidity
    return capital_loss, position, total_liquidity


def calculate_il(all_stats):
    lower_position = PositionInfo(
        sqrt_ratio_ax96=all_stats[0].lower_sqrt_ratio_ax96,
        sqrt_ratio_bx96=all_stats[0].lower_sqrt_ratio_bx96,
        deposits=[
            DepositInfo(
                all_stats[0].lower_liquidity,
                all_stats[0].sqrt_price_x96,
            )
        ],
    )
    total_lower_liquidity = all_stats[0].lower_liquidity
    upper_position = PositionInfo(
        sqrt_ratio_ax96=all_stats[0].upper_sqrt_ratio_ax96,
        sqrt_ratio_bx96=all_stats[0].upper_sqrt_ratio_bx96,
        deposits=[
            DepositInfo(
                all_stats[0].upper_liquidity,
                all_stats[0].sqrt_price_x96,
            )
        ],
    )
    total_upper_liquidity = all_stats[0].upper_liquidity
    result = {}
    
    for i in range(1, len(all_stats)):
        assert sum(x.liquidity for x in lower_position.deposits) == total_lower_liquidity, i
        assert sum(x.liquidity for x in upper_position.deposits) == total_upper_liquidity, i
        current_liquidity = defaultdict(lambda: 0)
        current_liquidity[(
            all_stats[i].lower_sqrt_ratio_ax96,
            all_stats[i].lower_sqrt_ratio_bx96,
        )] = all_stats[i].lower_liquidity
        current_liquidity[(
            all_stats[i].upper_sqrt_ratio_ax96,
            all_stats[i].upper_sqrt_ratio_bx96,
        )] = all_stats[i].upper_liquidity
        lower_loss, lower_position, total_lower_liquidity = calculate_new_state(
            lower_position,
            all_stats[i].sqrt_price_x96,
            total_lower_liquidity,
            current_liquidity[(lower_position.sqrt_ratio_ax96, lower_position.sqrt_ratio_bx96)],
        )
        upper_loss, upper_position, total_upper_liquidity = calculate_new_state(
            upper_position,
            all_stats[i].sqrt_price_x96,
            total_upper_liquidity,
            current_liquidity[(upper_position.sqrt_ratio_ax96, upper_position.sqrt_ratio_bx96)],
        )
        total_loss = lower_loss + upper_loss
        result[all_stats[i - 1].block_number] = total_loss
        if lower_position.sqrt_ratio_ax96 == all_stats[i].lower_sqrt_ratio_ax96:
            continue
        if total_lower_liquidity == 0 and total_upper_liquidity == 0:
            lower_position = PositionInfo(
                sqrt_ratio_ax96=all_stats[i].lower_sqrt_ratio_ax96,
                sqrt_ratio_bx96=all_stats[i].lower_sqrt_ratio_bx96,
                deposits=[
                        DepositInfo(
                            all_stats[i].lower_liquidity,
                            all_stats[i].sqrt_price_x96,
                        )
                    ],
            )
            total_lower_liquidity = all_stats[i].lower_liquidity
            upper_position = PositionInfo(
                sqrt_ratio_ax96=all_stats[i].upper_sqrt_ratio_ax96,
                sqrt_ratio_bx96=all_stats[i].upper_sqrt_ratio_bx96,
                deposits=[
                    DepositInfo(
                        all_stats[i].upper_liquidity,
                        all_stats[i].sqrt_price_x96,
                    )
                ],
            )
            total_upper_liquidity = all_stats[i].upper_liquidity
            continue
        if total_lower_liquidity == 0:
            lower_position = upper_position
            total_lower_liquidity = total_upper_liquidity
            upper_position = PositionInfo(
                sqrt_ratio_ax96=all_stats[i].upper_sqrt_ratio_ax96,
                sqrt_ratio_bx96=all_stats[i].upper_sqrt_ratio_bx96,
                deposits=[
                    DepositInfo(
                        all_stats[i].upper_liquidity,
                        all_stats[i].sqrt_price_x96,
                    )
                ],
            )
            total_upper_liquidity = all_stats[i].upper_liquidity
        else:
            upper_position = lower_position
            total_upper_liquidity = total_lower_liquidity
            lower_position = PositionInfo(
                sqrt_ratio_ax96=all_stats[i].lower_sqrt_ratio_ax96,
                sqrt_ratio_bx96=all_stats[i].lower_sqrt_ratio_bx96,
                deposits=[
                        DepositInfo(
                            all_stats[i].lower_liquidity,
                            all_stats[i].sqrt_price_x96,
                        )
                    ],
            )
            total_lower_liquidity = all_stats[i].lower_liquidity
    lower_loss, _, _ = calculate_new_state(
        lower_position,
        all_stats[-1].sqrt_price_x96,
        total_lower_liquidity,
        0,
    )
    upper_loss, _, _ = calculate_new_state(
        upper_position,
        all_stats[-1].sqrt_price_x96,
        total_upper_liquidity,
        0,
    )
    result[all_stats[-1].block_number] = lower_loss + upper_loss
    return result


def annual_il(all_stats):
    result = calculate_il(all_stats)
    price = np.array([(x.sqrt_price_x96 / 2 ** 96) ** 2 for x in all_stats])
    il_ = np.array([result[x.block_number] / 10 ** 18 for x in all_stats])
    wsteth_amount = (
        np.array([x.lower_wsteth for x in all_stats]) +
        np.array([x.upper_wsteth for x in all_stats]) +
        np.array([x.erc20_wsteth for x in all_stats])
    ) / 10 ** 18
    weth_amount = (
        np.array([x.lower_weth for x in all_stats]) +
        np.array([x.upper_weth for x in all_stats]) +
        np.array([x.erc20_weth for x in all_stats])
    ) / 10 ** 18
    capital = wsteth_amount * price + weth_amount
    capital = capital.astype('float64')
    il_ = il_.astype('float64')
    log_loss = np.log(capital - il_) - np.log(capital)
    duration = 12 * (all_stats[-1].block_number - all_stats[0].block_number)
    backtest_power = 365 * 24 * 60 * 60 / duration
    return 100 - 100 * np.exp(np.sum(log_loss) * backtest_power)
