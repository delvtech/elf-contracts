#!/bin/bash

rm -rf test/simulation/analysis

echo "Downloading analysis repo..."
git clone https://github.com/element-fi/analysis.git ./test/simulation/analysis

echo "Generate sim data"
python3 ./test/simulation/analysis/scripts/TestTradesSim.py

mv testTrades.json ./test/simulation/
echo "Done!"
