all    :; clean build test deploy
build  :; dapp build
clean  :; dapp clean
test   :; dapp build; hevm dapp-test --json-file=out/dapp.sol.json --dapp-root=. --verbose 1
# right now this just deploys a fund
deploy :; dapp create Elf
