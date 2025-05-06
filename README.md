## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

## Regenerating or Extending Contracts with LLMs

This codebase is designed to be modular, upgradeable, and security-first. To regenerate or extend the smart contracts using an LLM (such as GPT-4), see [`docs/prompt.md`](docs/prompt.md) for a detailed, professional prompt/context. This ensures reproducibility, extensibility, and adherence to best practices.

**How to use:**

- Copy the prompt from `docs/prompt.md`.
- Paste it into your preferred LLM interface (e.g., ChatGPT, GPT-4, or a specialized codegen model).
- Follow the instructions to scaffold, extend, or audit the contracts as needed.

For more details, see the [Half-Life Smart Contract Implementation Guide](docs/smart_contract_implementation.md) and [Platform Implementation Guide](docs/IMPLEMENTATION_GUIDE.md).
