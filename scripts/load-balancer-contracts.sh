#!/bin/bash
# Directly cloned from the script in elf frontend
rm -rf balancer-core-v2

# link/clone and build contracts
if [ ! -z "$1" ] && [ $1="local" ]; then
    ln -sf ../../balancer-core-v2 .
elif [ ! -d "./contracts/balancer-core-v2" ]; then
    echo "Downloading contracts..."
    git clone https://github.com/balancer-labs/balancer-core-v2.git
    cd balancer-core-v2 \
    && git checkout f153c38c5ee8911680363eaf52aad0d691896a75 \
    && cd ..

    # blow away old-contracts
    rm -rf contracts/balancer-core-v2

    echo "Copying latest contracts..."
    mv balancer-core-v2/contracts contracts/balancer-core-v2

    echo "Removing unused balancer code"
    rm -rf balancer-core-v2

    echo "Done!"
else
    echo "Assuming you have correctly cloned the balancer-core-v2 repo"
fi