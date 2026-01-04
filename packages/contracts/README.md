# MultiCoin - ERC1155-like Multi-Asset Standard for Sui

A complete implementation of an ERC1155-like multi-asset standard on Sui blockchain, providing efficient management of multiple fungible asset types within a single collection.

## Features

### Core Capabilities
- **Multiple Asset Types**: Single collection can manage many different asset types
- **Batch Operations**: Mint, transfer, and burn multiple asset types in one transaction
- **Bit-Packed Asset IDs**: Efficient u128 asset IDs encoding assembly (64 bits) + item (64 bits)
- **Metadata Support**: Optional on-chain metadata per asset type
- **Events**: Full event emission for minting, burning, and transfers
- **Zero Balance Handling**: Create and destroy zero-value balances safely

### ERC1155 Alignment
- Multi-asset collection management
- Batch minting and transfers
- Per-asset-type metadata
- Safe transfer patterns
- Event emission

### Sui-Specific Enhancements
- **Object-based Balances**: Each balance is a Sui object (owned or transferable)
- **Coin-like API**: Familiar `split()`, `join()`, `value()` methods
- **Move 2024 Syntax**: Method call syntax, proper error naming
- **Capability-Based Security**: CollectionCap required for minting/admin operations

## Architecture

### Core Types

```move
/// Shared collection container
public struct Collection has key, store {
    id: UID,
    metadata: Table<u128, vector<u8>>,
    supply: Table<u128, u64>,
}

/// Admin capability for minting
public struct CollectionCap has key, store {
    id: UID,
    collection: ID,
}

/// Owned balance (like Coin<T>)
public struct Balance has key, store {
    id: UID,
    collection: ID,
    asset_id: u128,
    amount: u64,
}
```

### Asset ID Format

Asset IDs are u128 values with bit-packing:
- **Upper 64 bits**: Location ID (e.g., game zone, dungeon level)
- **Lower 64 bits**: Item ID (e.g., item type within assembly)

```move
// Create asset ID
let asset_id = make_asset_id(100, 42); // assembly=100, item=42

// Extract components
let assembly = assembly_id(asset_id); // 100
let item = item_id(asset_id);         // 42
```

## Usage Examples

### 1. Create a Collection

```move
// Entry function (collection becomes shared, cap sent to sender)
multicoin::create_collection(ctx);

// Or programmatic version
let (collection, cap) = multicoin::new_collection(ctx);
transfer::share_object(collection);
```

### 2. Mint Assets

```move
// Single mint
let asset_id = make_asset_id(100, 1); // Location 100, Item 1
multicoin::mint(&cap, &collection, asset_id, 100, recipient, ctx);

// Batch mint
let asset_ids = vector[
    make_asset_id(100, 1),
    make_asset_id(100, 2),
    make_asset_id(100, 3),
];
let amounts = vector[10, 20, 30];
multicoin::batch_mint(&cap, &collection, asset_ids, amounts, recipient, ctx);

// Mint and keep for composability
let balance = multicoin::mint_and_keep(&cap, &collection, asset_id, 100, ctx);
```

### 3. Split and Join Balances

```move
// Split a balance
let split_balance = balance.split(30, ctx);

// Join balances of same asset type
balance.join(split_balance);

// Split and transfer in one call
balance.split_and_transfer(30, recipient, ctx);
```

### 4. Transfer Balances

```move
// Single transfer
multicoin::transfer(balance, recipient, ctx);

// Batch transfer
multicoin::batch_transfer(balances_vector, recipient, ctx);
```

### 5. Burn Assets

```move
// Burn single balance
let burned_amount = multicoin::burn(&mut collection, balance, ctx);

// Batch burn
multicoin::batch_burn(&mut collection, balances_vector, ctx);
```

### 6. Metadata Management

```move
// Set metadata (requires CollectionCap)
let metadata = b"Iron Sword: A basic weapon";
cap.set_metadata(&mut collection, asset_id, metadata);

// Read metadata
if (collection.has_metadata(asset_id)) {
    let metadata = collection.get_metadata(asset_id);
};
```

### 7. Zero Balances

```move
// Create zero balance placeholder
let zero = multicoin::zero(collection_id, asset_id, ctx);

// Destroy zero balance
zero.destroy_zero();
```

## API Reference

### Collection Management
- `create_collection(ctx)` - Entry function to create collection
- `new_collection(ctx)` - Returns (Collection, CollectionCap)

### Asset ID Utilities
- `make_asset_id(assembly_id, item_id)` - Pack into u128
- `assembly_id(asset_id)` - Extract assembly
- `item_id(asset_id)` - Extract item

### Metadata
- `set_metadata(cap, collection, asset_id, data)` - Set/update metadata
- `get_metadata(collection, asset_id)` - Read metadata
- `has_metadata(collection, asset_id)` - Check existence

### Minting
- `mint(cap, collection, asset_id, amount, recipient, ctx)` - Mint and transfer
- `mint_balance(cap, collection, asset_id, amount, ctx)` - Mint as Balance
- `batch_mint(cap, collection, asset_ids, amounts, recipient, ctx)` - Batch mint
- `mint_and_keep(cap, collection, asset_id, amount, ctx)` - Mint and return

### Balance Operations
- `split(balance, amount, ctx)` - Split into two
- `split_and_transfer(balance, amount, recipient, ctx)` - Split and send
- `join(self, other)` - Merge same asset type
- `zero(collection_id, asset_id, ctx)` - Create zero balance
- `destroy_zero(balance)` - Destroy zero balance

### Transfer
- `transfer(balance, recipient, ctx)` - Transfer single
- `batch_transfer(balances, recipient, ctx)` - Batch transfer

### Burning
- `burn(collection, balance, ctx)` - Burn and return amount
- `batch_burn(collection, balances, ctx)` - Batch burn

### Accessors
- `value(balance)` - Get amount
- `asset_id(balance)` - Get asset ID
- `collection_id(balance)` - Get collection ID
- `cap_collection_id(cap)` - Get cap's collection ID
- `total_supply(collection, asset_id)` - Get total supply for asset type

## Events

```move
public struct TransferEvent has copy, drop {
    collection: ID,
    asset_id: u128,
    from: address,
    to: address,
    amount: u64,
}

public struct MintEvent has copy, drop {
    collection: ID,
    asset_id: u128,
    to: address,
    amount: u64,
}

public struct BurnEvent has copy, drop {
    collection: ID,
    asset_id: u128,
    from: address,
    amount: u64,
}
```

## Error Codes

- `EWrongCollection (0)` - Balance doesn't belong to this collection
- `EWrongAssetId (1)` - Asset IDs don't match
- `EInsufficientBalance (2)` - Not enough balance to split/spend
- `EInvalidArg (3)` - Invalid function arguments
- `EZeroAmount (4)` - Amount must be greater than zero

## Testing

```bash
cd packages/contracts
sui move test
```

## Use Cases

### Gaming
- In-game items across different zones/levels
- Equipment, consumables, currencies
- Trade and craft systems

### DeFi
- Multi-asset liquidity positions
- Synthetic assets with variants
- Tiered reward assets

### NFT Collections
- Fungible NFTs with editions
- Tiered membership assets
- Fractional ownership

### Inventory Systems
- Location-based item storage
- Cross-game asset management
- Supply chain tracking

## Comparison with ERC1155

| Feature | ERC1155 | MultiCoin |
|---------|---------|-----------||
| Multi-asset support | Yes | Yes |
| Batch operations | Yes | Yes |
| Metadata | Yes | Yes |
| Balance tracking | Contract storage | Individual objects |
| Transfer model | Call contract | Transfer objects |
| Approval system | setApprovalForAll | Not needed (object-based) |
| Safe transfers | Receiver check | Native Sui safety |

## Security Considerations

1. **CollectionCap**: Only holders can mint assets - protect this capability
2. **Shared Collection**: Collection is shared object, metadata can be read by anyone
3. **Balance Objects**: Each balance is an owned object - standard Sui security model
4. **Zero Amounts**: Prevented at mint/split level to avoid spam
5. **Integer Overflow**: Move has built-in overflow protection

## License

Apache-2.0 (matching Sui framework)
