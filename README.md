# MultiCoin - ERC1155-like Multi-Asset Standard for Sui

A complete implementation of an ERC1155-like multi-asset standard on Sui blockchain, providing efficient management of multiple fungible asset types within a single collection.

## Features

- **Multiple Asset Types**: Single collection can manage many different asset types
- **Batch Operations**: Mint, transfer, and burn multiple asset types in one transaction
- **Bit-Packed Asset IDs**: Efficient u128 asset IDs encoding location (64 bits) + item (64 bits)
- **On-Chain Supply Tracking**: Real-time supply tracking for each asset type
- **Metadata Support**: Optional on-chain metadata per asset type
- **Events**: Full event emission for minting, burning, and transfers
- **Move 2024 Syntax**: Modern method call syntax and proper error handling

_Note: This has only been tested in MacOS & Linux so far_
---

## Documentation

- **[API Reference](./packages/contracts/README.md)** - Complete API documentation, architecture, and usage examples
- **[Usage Guide](./packages/contracts/USAGE_GUIDE.md)** - Step-by-step guide for common operations
- **[Implementation Summary](./IMPLEMENTATION_COMPLETE.md)** - Feature overview and API summary

## Quick Start

```bash
# 1. Install dependencies
yarn

# 2. Start local network
yarn start:local

# 3. Build the Move package
yarn --cwd packages/contracts build

# 4. Run tests
yarn --cwd packages/contracts test

# 5. Deploy to localnet
yarn --cwd packages/contracts deploy:watch
```

After deployment, `.env.local` contains the `PACKAGE_ID` for interaction.

---

## Installing dependencies and requirements

1. Install the [rust tools](https://rust-lang.org/tools/install/)
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```
2. Install [node version manager](https://github.com/nvm-sh/nvm)
```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
```
### Node dependencies

Before applying the following, run `nvm install 24 && nvm use 24`

3. Install [yarn package manager](https://yarnpkg.com/getting-started/install)
```bash
npm install -g yarn
```
4. Install [mprocs](https://github.com/pvolok/mprocs)
```bash
npm install -g mprocs
```

### Rust dependencies

5. Install the [sui tools manager](https://github.com/MystenLabs/suiup)
```bash
cargo install --git https://github.com/Mystenlabs/suiup.git --locked
```
6. Install the latest [sui tools](https://docs.sui.io/guides/developer/getting-started/sui-install)
```bash
suiup install sui@testnet
```
7. Install [watchexec tool](https://github.com/watchexec/watchexec)
```bash
cargo install --locked watchexec-cli
```


## How to set up local network dev env
1. Install Packages
```bash
yarn
cd packages/contracts && yarn
```

2. Start Local network + fund address from local faucet + build contracts + deploy contracts.
```bash
yarn start:local
```

---
### Development Workflow
```bash
# 1. Install deps
yarn

# 2. Start a local network
yarn start:local

# 3. Fund / import account
yarn fund          # imports key (see .env) + faucet funding loop

# 4. Build the Move package
yarn --cwd packages/contracts build:watch

# 5. Publish to localnet (from repo root OR pass '.' if inside package)
yarn --cwd packages/contracts deploy:watch

# 6. Run `.move` tests (14 comprehensive tests)
yarn --cwd packages/contracts test
```
After publish, `.env.local` (written where you run the script) contains at least:
* `PACKAGE_ID`

---

## Core Implementation

The MultiCoin module (`packages/contracts/sources/multicoin.move`) provides:

### Key Structs
- `Collection` - Shared collection container with metadata and supply tracking
- `CollectionCap` - Admin capability for minting and metadata management
- `Balance` - Owned asset balance (similar to `Coin<T>`)

### Main Functions
- Collection creation (`create_collection`, `new_collection`)
- Asset minting (`mint`, `mint_balance`, `batch_mint`)
- Balance operations (`split`, `join`, `split_and_transfer`)
- Asset burning (`burn`, `batch_burn`) - requires collection reference for supply tracking
- Metadata management (`set_metadata`, `get_metadata`, `has_metadata`)
- Supply queries (`total_supply`)
- Transfer operations (`transfer`, `batch_transfer`)

### Asset ID System
Asset IDs are u128 values with bit-packing:
- Upper 64 bits: Location ID (e.g., game zone, dungeon level)
- Lower 64 bits: Item ID (e.g., item type within location)

Helper functions: `make_asset_id(location, item)`, `location_id(asset_id)`, `item_id(asset_id)`

### Events
- `MintEvent` - Emitted when assets are minted
- `BurnEvent` - Emitted when assets are burned
- `TransferEvent` - Emitted when assets are transferred

---
## Prerequisites
* Rust (https://rust-lang.org/tools/install/)
* Sui CLI (https://docs.sui.io) in `PATH`
* `bash`, `jq`
* nodejs (tested with `v20.19`) && `yarn` (Corepack / Node.js)
* Optional: `docker`, `mprocs`, `watchexec`

Install Node dependencies:
```bash
yarn
cd packages/contracts && yarn
```

---
## Directory Layout
```
build_scripts/                         # Root helper scripts (start, fund, deployment)
packages/contracts/                    # Move package root
packages/contracts/sources/
  └── multicoin.move                   # Core ERC1155-like implementation (420+ lines)
packages/contracts/tests/
  └── multicoin_tests.move             # Comprehensive test suite (14 tests)
packages/contracts/README.md           # Complete API documentation
packages/contracts/USAGE_GUIDE.md      # Usage guide with TypeScript examples
packages/contracts/build_scripts/      # Build & publish tooling
IMPLEMENTATION_COMPLETE.md             # Implementation summary
mprocs.yaml                            # Dev process orchestration
```

## Use Cases

- **Gaming**: In-game items, equipment, consumables across zones/levels
- **DeFi**: Multi-asset liquidity positions, tiered reward assets
- **NFT Collections**: Fungible NFTs with editions, tiered memberships
- **Inventory Systems**: Location-based storage, cross-game assets

## License

Apache-2.0 (matching Sui framework)
