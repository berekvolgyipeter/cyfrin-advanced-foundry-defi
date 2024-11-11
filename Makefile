-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

all: clean remove install update build

# ---------- dependencies ----------
remove :; rm -rf dependencies/ && rm soldeer.lock
install :; forge soldeer install
update:; forge soldeer update

# ---------- build ----------
build :; forge build
clean :; forge clean && rm -rf cache/

# ---------- tests ----------
TEST := forge test -vvv
TEST_UNIT := $(TEST) --match-path "test/unit/*.t.sol"

test :; $(TEST)
test-unit :; $(TEST_UNIT)
test-unit-fork-sepolia :; $(TEST_UNIT) --fork-url $(RPC_URL_SEPOLIA)
test-unit-fork-mainnet :; $(TEST_UNIT) --fork-url $(RPC_URL_MAINNET)
test-fuzz :; $(TEST) --match-path "test/fuzz/*.t.sol"
test-invariant :; $(TEST) --match-path "test/invariant/*.t.sol"
test-fork-sepolia :; $(TEST) --fork-url $(RPC_URL_SEPOLIA)
test-fork-mainnet :; $(TEST) --fork-url $(RPC_URL_MAINNET)

# ---------- coverage ----------
coverage :; forge coverage --skip InvariantsTest.t.sol --no-match-coverage test
coverage-lcov :; make coverage EXTRA_FLAGS="--report lcov"
coverage-txt :; make coverage EXTRA_FLAGS="--report debug > coverage.txt"

# ---------- static analysis ----------
format-check :; forge fmt --check
slither-install :; python3 -m pip install slither-analyzer
slither :; slither . --config-file slither.config.json --checklist

# ---------- etherscan ----------
check-etherscan-api:
	@response_mainnet=$$(curl -s "https://api.etherscan.io/api?module=account&action=balance&address=$(PUBLIC_KEY_DEV)&tag=latest&apikey=$(ETHERSCAN_API_KEY)"); \
	echo "Mainnet:" $$response_mainnet; \
	response_sepolia=$$(curl -s "https://api-sepolia.etherscan.io/api?module=account&action=balance&address=$(PUBLIC_KEY_DEV)&tag=latest&apikey=$(ETHERSCAN_API_KEY)"); \
	echo "Sepolia:" $$response_sepolia;

# ---------- deploy & interact ----------
anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

PRIVATE_KEY_ANVIL_0 := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
NETWORK_ARGS_ANVIL := --rpc-url http://localhost:8545 --private-key $(PRIVATE_KEY_ANVIL_0) --broadcast
NETWORK_ARGS_SEPOLIA := --rpc-url $(RPC_URL_SEPOLIA) --account $(ACCOUNT_DEV) --sender $(PUBLIC_KEY_DEV) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
