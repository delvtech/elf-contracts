#!/bin/bash
# Directly cloned from the script in elf frontend
#!/bin/bash
rm -rf balancer-core-v2

echo "Downloading contracts..."
# link/clone and build contracts
if [ ! -z "$1" ] && [ $1="local" ]; then
    ln -sf ../../balancer-core-v2 .
else
    git clone https://github.com/balancer-labs/balancer-core-v2.git
fi

# blow away old-contracts
rm -rf contracts/balancer-core-v2

echo "Copying latest contracts..."
cp -R balancer-core-v2/contracts contracts
mv contracts/contracts contracts/balancer-core-v2

echo "Removing unused balancer code"
rm -r balancer-core-v2

echo "Done!"
