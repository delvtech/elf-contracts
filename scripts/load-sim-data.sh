#!/bin/bash

version=$(python -V 2>&1 | grep -Po '(?<=Python )\d')
if [[ "$version" = 3 ]]
then
    echo "calling python"
    alias py="python"
else
    echo "calling python3"
    alias py="python3"
fi

rm -rf test/simulation/analysis

echo "Downloading analysis repo..."
git clone https://github.com/element-fi/analysis.git ./test/simulation/analysis

echo "Generate sim data"
py ./test/simulation/analysis/scripts/TestTradesSim.py

mv testTrades.json ./test/simulation/
echo "Done!"