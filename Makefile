all    :; clean build test
build  :; dapp build --extract
init   :; dapp update; npm install
fmt    :; npm run prettier
fmt-ci :; npm run style-check
lint   :; npm run solhint
clean  :; dapp clean
test   :; dapp build; hevm dapp-test --rpc=https://mainnet.infura.io/v3/6a2249f0a26444d7a26375321b49f608 --json-file=out/dapp.sol.json --dapp-root=. --verbose 1