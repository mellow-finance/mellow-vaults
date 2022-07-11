#!/usr/bin/bash

width=60
input_name=price_data.csv
output_name=output.csv

while [ $# -gt 0 ]; do
  case "$1" in
    --width=*)
      width="${1#*=}"
      ;;
    --input_name=*)
      input_name="${1#*=}"
      ;;
    --output_name=*)
      output_name="${1#*=}"
      ;;
    *)
      printf "***************************\n"
      printf "* Error: Invalid argument.*\n"
      printf "***************************\n"
      exit 1
  esac
  shift
done

echo "Running backtest with the following parameters: width=$width, input_name=$input_name"

export HARDHAT_MAX_MEMORY=8192
export NODE_OPTIONS="--max-old-space-size=8192"

rm -rf artifacts
npx hardhat compile
npx hardhat --config hardhat.backtest.config.ts lstrategy-backtest --filename $input_name --width $width 
