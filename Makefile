all    :; clean build test
build  :; dapp build --extract
init   :; dapp update; npm install
fmt    :; npm run prettier
fmt-ci :; npm run style-check
lint   :; npm run solhint
clean  :; dapp clean
test   :; dapp build; hevm dapp-test --rpc=https://mainnet.infura.io/v3/73dc63290c73465d8b659ce17028909f --json-file=out/dapp.sol.json --dapp-root=. --verbose 1
