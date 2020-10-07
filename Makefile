all    :; clean build test
build  :; dapp build
init   :; dapp update; npm install
fmt    :; npm run prettier
lint   :; npm run solhint
clean  :; dapp clean
test   :; dapp build; hevm dapp-test --json-file=out/dapp.sol.json --dapp-root=. --verbose 1
# right now this just deploys a fund
deploy :; dapp create Elf
