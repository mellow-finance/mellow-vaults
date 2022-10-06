import numpy as np

sigma = 0.85
mu = 0
intervals = 365 * 8

T = 1000

x = np.random.normal(mu / intervals, sigma / np.sqrt(intervals), T)

while (True):
    S = 0
    x = sorted(x)
    for i in range(len(x)):
        S += x[i]
    if abs(S - mu) < 0.1:
        break
    x = np.random.normal(mu / intervals, sigma / np.sqrt(intervals), T)

for i in range(len(x)):
    S += x[i]
    print(int(x[i] * 10**9), end=",")