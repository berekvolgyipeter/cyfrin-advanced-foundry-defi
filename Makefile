-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

all: clean remove install update build

clean  :; forge clean

remove :; rm -rf dependencies/ && rm soldeer.lock

install :; forge soldeer install

update:; forge soldeer update

build:; forge build

test :; forge test -vvv

test-fork-sepolia :; @forge test --fork-url $(RPC_URL_SEPOLIA) -vvv

coverage :; forge coverage --skip InvariantsTest.t.sol

coverage-lcov :; forge coverage --report lcov

coverage-txt :; forge coverage --report debug > coverage.txt

snapshot :; forge snapshot

format-check :; forge fmt --check

slither-install :; python3 -m pip install slither-analyzer

slither :; slither . --config-file slither.config.json --checklist

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

check-etherscan-api:
	@response_mainnet=$$(curl -s "https://api.etherscan.io/api?module=account&action=balance&address=$(PUBLIC_KEY_DEV)&tag=latest&apikey=$(ETHERSCAN_API_KEY)"); \
	echo "Mainnet:" $$response_mainnet; \
	response_sepolia=$$(curl -s "https://api-sepolia.etherscan.io/api?module=account&action=balance&address=$(PUBLIC_KEY_DEV)&tag=latest&apikey=$(ETHERSCAN_API_KEY)"); \
	echo "Sepolia:" $$response_sepolia;

PRIVATE_KEY_ANVIL_0 := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

NETWORK_ARGS_ANVIL := --rpc-url http://localhost:8545 --private-key $(PRIVATE_KEY_ANVIL_0) --broadcast

NETWORK_ARGS_SEPOLIA := --rpc-url $(RPC_URL_SEPOLIA) --account $(ACCOUNT_DEV) --sender $(PUBLIC_KEY_DEV) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
