all    :; clean build --use solc:0.8.0 test
build  :; dapp --use solc:0.8.0 build --extract
init   :; dapp update; npm install
fmt    :; npm run prettier
fmt-ci :; npm run style-check
lint   :; npm run solhint
clean  :; dapp --use solc:0.8.0 clean
test   :; dapp --use solc:0.8.0 build; hevm dapp-test --rpc=https://mainnet.infura.io/v3/73dc63290c73465d8b659ce17028909f --json-file=out/dapp.sol.json --dapp-root=. --verbose 1
