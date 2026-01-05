# MultiCoin Usage Guide

This guide demonstrates common operations with the MultiCoin ERC1155-like implementation on Sui.

## Prerequisites

```bash
# Install Sui CLI
curl --proto '=https' --tlsv1.2 -sSf https://sh.sui.io | sh

# Create a new address (if needed)
sui client new-address ed25519

# Get testnet SUI assets
sui client faucet
```

## 1. Create a New Collection

### Using Sui CLI

```bash
# Create collection using entry function
sui client call \
  --package <PACKAGE_ID> \
  --module multicoin \
  --function create_collection \
  --gas-budget 10000000

# The collection will be shared automatically
# The CollectionCap will be transferred to your address
```

### Using TypeScript SDK

```typescript
import { Transaction } from '@mysten/sui/transactions';
import { SuiClient } from '@mysten/sui/client';

const client = new SuiClient({ url: 'https://fullnode.testnet.sui.io' });
const tx = new Transaction();

// Create collection
tx.moveCall({
  target: `${packageId}::multicoin::create_collection`,
});

// Execute transaction
const result = await client.signAndExecuteTransaction({
  transaction: tx,
  signer: keypair,
});

// Get the collection ID and cap ID from events/created objects
const collectionId = result.objectChanges?.find(
  obj => obj.objectType === `${packageId}::multicoin::Collection`
)?.objectId;

const capId = result.objectChanges?.find(
  obj => obj.objectType === `${packageId}::multicoin::CollectionCap`
)?.objectId;

console.log('Collection ID:', collectionId);
console.log('CollectionCap ID:', capId);
```

## 2. Mint Balance on the Collection

### Prepare Asset ID

```typescript
// Asset ID = (location_id << 64) | item_id
// Example: location=100, item=1
const locationId = 100n;
const itemId = 1n;
const assetId = (locationId << 64n) | itemId;
// Result: 1844674407370955162n
```

### Using Sui CLI

```bash
# Mint 1000 assets to recipient
sui client call \
  --package <PACKAGE_ID> \
  --module multicoin \
  --function mint \
  --args <COLLECTION_CAP_ID> <COLLECTION_ID> 1844674407370955161 1000 <RECIPIENT_ADDRESS> \
  --gas-budget 10000000
```

### Using TypeScript SDK

```typescript
const tx = new Transaction();

// Mint assets
tx.moveCall({
  target: `${packageId}::multicoin::mint`,
  arguments: [
    tx.object(collectionCapId),     // CollectionCap
    tx.object(collectionId),         // Collection (shared object)
    tx.pure.u128(assetId),          // asset_id
    tx.pure.u64(1000),              // amount
    tx.pure.address(recipientAddress), // recipient
  ],
});

const result = await client.signAndExecuteTransaction({
  transaction: tx,
  signer: keypair,
});

// Get the Balance object ID
const balanceId = result.objectChanges?.find(
  obj => obj.objectType === `${packageId}::multicoin::Balance`
)?.objectId;

console.log('Balance created:', balanceId);
```

### Batch Mint Multiple Asset Types

```typescript
const tx = new Transaction();

// Prepare asset IDs and amounts
const assetIds = [
  (100n << 64n) | 1n,  // Sword
  (100n << 64n) | 2n,  // Shield
  (100n << 64n) | 3n,  // Potion
];

const amounts = [10, 5, 20];

tx.moveCall({
  target: `${packageId}::multicoin::batch_mint`,
  arguments: [
    tx.object(collectionCapId),
    tx.object(collectionId),
    tx.pure(assetIds.map(id => ['u128', id.toString()])),
    tx.pure(amounts.map(amt => ['u64', amt])),
    tx.pure.address(recipientAddress),
  ],
});

await client.signAndExecuteTransaction({
  transaction: tx,
  signer: keypair,
});
```

## 3. Fetch Balances for an Address

### Using Sui CLI

```bash
# Get all objects owned by address
sui client objects <ADDRESS>

# Filter for Balance objects
sui client objects <ADDRESS> | grep Balance

# Get details of a specific balance
sui client object <BALANCE_OBJECT_ID>
```

### Using TypeScript SDK

```typescript
// Fetch all Balance objects owned by address
async function getBalances(ownerAddress: string) {
  const balances = await client.getOwnedObjects({
    owner: ownerAddress,
    filter: {
      StructType: `${packageId}::multicoin::Balance`,
    },
    options: {
      showContent: true,
      showType: true,
    },
  });

  return balances.data.map(obj => {
    const content = obj.data?.content;
    if (content?.dataType === 'moveObject') {
      const fields = content.fields as {
        collection: string;
        asset_id: string;
        amount: string;
      };
      
      // Decode asset_id into location and item
      const assetId = BigInt(fields.asset_id);
      const locationId = assetId >> 64n;
      const itemId = assetId & ((1n << 64n) - 1n);
      
      return {
        objectId: obj.data.objectId,
        collection: fields.collection,
        assetId: fields.asset_id,
        locationId: locationId.toString(),
        itemId: itemId.toString(),
        amount: fields.amount,
      };
    }
    return null;
  }).filter(Boolean);
}

// Usage
const balances = await getBalances(myAddress);
console.log('My balances:', balances);
```

### Query Balances by Collection

```typescript
async function getBalancesByCollection(
  ownerAddress: string,
  collectionId: string
) {
  const allBalances = await getBalances(ownerAddress);
  return allBalances.filter(b => b?.collection === collectionId);
}
```

### Get Balance Amount

```typescript
async function getBalanceAmount(balanceObjectId: string): Promise<string> {
  const obj = await client.getObject({
    id: balanceObjectId,
    options: { showContent: true },
  });

  const content = obj.data?.content;
  if (content?.dataType === 'moveObject') {
    return (content.fields as { amount: string }).amount;
  }
  throw new Error('Balance not found');
}
```

### Check Total Supply for a Asset ID

The MultiCoin implementation now tracks total supply on-chain in the Collection's supply table. This provides efficient, real-time supply queries.

#### Using Sui CLI

```bash
# Query supply using devInspectTransactionBlock
sui client call \
  --package <PACKAGE_ID> \
  --module multicoin \
  --function total_supply \
  --args <COLLECTION_ID> <TOKEN_ID> \
  --gas-budget 10000000
```

#### Using TypeScript SDK

```typescript
async function getTotalSupply(
  collectionId: string,
  assetId: bigint
): Promise<bigint> {
  const tx = new Transaction();
  
  tx.moveCall({
    target: `${packageId}::multicoin::total_supply`,
    arguments: [
      tx.object(collectionId),
      tx.pure.u128(assetId),
    ],
  });

  const result = await client.devInspectTransactionBlock({
    transactionBlock: tx,
    sender: myAddress,
  });

  // Parse the return value
  const returnValues = result.results?.[0]?.returnValues;
  if (returnValues && returnValues.length > 0) {
    const [bytes] = returnValues[0];
    // Decode u64 from bytes (little-endian)
    const supply = new DataView(
      new Uint8Array(bytes).buffer
    ).getBigUint64(0, true);
    return supply;
  }

  return 0n;
}

// Usage
const assetId = (100n << 64n) | 1n; // location=100, item=1
const supply = await getTotalSupply(collectionId, assetId);
console.log('Total supply:', supply);
```

#### How Supply Tracking Works

The Collection struct now includes a `supply` table:

```move
public struct Collection has key, store {
    id: UID,
    metadata: Table<u128, vector<u8>>,
    supply: Table<u128, u64>,  // On-chain supply tracking
}
```

**Supply is automatically updated:**
- **Mint**: Increases supply when assets are minted
- **Burn**: Decreases supply when assets are burned  
- **Efficient**: O(1) lookup via table
- **Real-time**: Always accurate and up-to-date

**Note**: The `burn` function now requires a mutable Collection reference:

```typescript
// Burn now needs collection
tx.moveCall({
  target: `${packageId}::multicoin::burn`,
  arguments: [
    tx.object(collectionId),  // Collection (shared, mutable)
    tx.object(balanceId),      // Balance to burn
  ],
});
```

### Track Supply with Events (Alternative)

You can also track supply by subscribing to mint/burn events:

```typescript
// Subscribe to mint and burn events to track supply
let totalSupply = 0n;

// Track mints
await client.subscribeEvent({
  filter: {
    MoveEventType: `${packageId}::multicoin::MintEvent`,
  },
  onMessage: (event) => {
    const { asset_id, amount } = event.parsedJson;
    if (asset_id === targetAssetId.toString()) {
      totalSupply += BigInt(amount);
    }
  },
});

// Track burns
await client.subscribeEvent({
  filter: {
    MoveEventType: `${packageId}::multicoin::BurnEvent`,
  },
  onMessage: (event) => {
    const { asset_id, amount } = event.parsedJson;
    if (asset_id === targetAssetId.toString()) {
      totalSupply -= BigInt(amount);
    }
  },
});
```

### Query Historical Supply from Events

```typescript
async function calculateSupplyFromEvents(
  collectionId: string,
  assetId: bigint
): Promise<bigint> {
  let supply = 0n;
  let cursor: string | null = null;
  let hasMore = true;

  // Query all mint events
  while (hasMore) {
    const mintEvents = await client.queryEvents({
      query: {
        MoveEventType: `${packageId}::multicoin::MintEvent`,
      },
      cursor,
    });

    for (const event of mintEvents.data) {
      const { collection, asset_id, amount } = event.parsedJson as {
        collection: string;
        asset_id: string;
        amount: string;
      };
      
      if (
        collection === collectionId &&
        asset_id === assetId.toString()
      ) {
        supply += BigInt(amount);
      }
    }

    hasMore = mintEvents.hasNextPage;
    cursor = mintEvents.nextCursor ?? null;
  }

  // Query all burn events
  cursor = null;
  hasMore = true;
  
  while (hasMore) {
    const burnEvents = await client.queryEvents({
      query: {
        MoveEventType: `${packageId}::multicoin::BurnEvent`,
      },
      cursor,
    });

    for (const event of burnEvents.data) {
      const { collection, asset_id, amount } = event.parsedJson as {
        collection: string;
        asset_id: string;
        amount: string;
      };
      
      if (
        collection === collectionId &&
        asset_id === assetId.toString()
      ) {
        supply -= BigInt(amount);
      }
    }

    hasMore = burnEvents.hasNextPage;
    cursor = burnEvents.nextCursor ?? null;
  }

  return supply;
}

// Usage
const supply = await calculateSupplyFromEvents(
  collectionId,
  (100n << 64n) | 1n // location=100, item=1
);
console.log('Total supply:', supply);
```

**When to Use Each Approach:**
- **On-Chain Query**: Real-time, always accurate, recommended for most use cases
- **Event Tracking**: Historical analysis, off-chain indexing, redundancy checks

## 4. Transfer Balance

### Split and Transfer

```typescript
const tx = new Transaction();

// Split 300 assets from balance and transfer to recipient
tx.moveCall({
  target: `${packageId}::multicoin::split_and_transfer`,
  arguments: [
    tx.object(balanceId),           // Balance to split from
    tx.pure.u64(300),               // Amount to split
    tx.pure.address(recipientAddress), // Recipient
  ],
});

await client.signAndExecuteTransaction({
  transaction: tx,
  signer: keypair,
});
```

### Direct Transfer (Entire Balance)

```typescript
const tx = new Transaction();

// Transfer entire balance
tx.moveCall({
  target: `${packageId}::multicoin::transfer`,
  arguments: [
    tx.object(balanceId),
    tx.pure.address(recipientAddress),
  ],
});

await client.signAndExecuteTransaction({
  transaction: tx,
  signer: keypair,
});
```

### Using Sui CLI

```bash
# Split and transfer
sui client call \
  --package <PACKAGE_ID> \
  --module multicoin \
  --function split_and_transfer \
  --args <BALANCE_ID> 300 <RECIPIENT_ADDRESS> \
  --gas-budget 10000000
```

### Batch Transfer

```typescript
const tx = new Transaction();

// Transfer multiple balances to same recipient
const balanceIds = ['0xabc...', '0xdef...', '0x123...'];

tx.moveCall({
  target: `${packageId}::multicoin::batch_transfer`,
  arguments: [
    tx.makeMoveVec({
      elements: balanceIds.map(id => tx.object(id)),
    }),
    tx.pure.address(recipientAddress),
  ],
});

await client.signAndExecuteTransaction({
  transaction: tx,
  signer: keypair,
});
```

## 5. Delete the Collection

**Important:** Collections cannot be directly deleted in the current implementation because:
1. `Collection` is a shared object with `key` ability
2. Shared objects persist on-chain for all users to access
3. The `metadata` Table inside Collection cannot be dropped if it contains entries

### What You Can Do Instead

#### Option 1: Transfer the CollectionCap (Relinquish Control)

```typescript
// Transfer cap to a burn address or another admin
const tx = new Transaction();

tx.transferObjects(
  [tx.object(collectionCapId)],
  tx.pure.address('0x0000000000000000000000000000000000000000000000000000000000000000')
);

await client.signAndExecuteTransaction({
  transaction: tx,
  signer: keypair,
});
```

#### Option 2: Implement Collection Destruction (Code Modification)

To make collections deletable, you would need to add to the module:

```move
/// Destroy an empty collection (requires CollectionCap)
public fun destroy_collection(
    cap: CollectionCap,
    collection: Collection,
) {
    assert!(cap.collection == object::id(&collection), EWrongCollection);
    
    let Collection { id, metadata } = collection;
    metadata.destroy_empty(); // Fails if table has entries
    id.delete();
    
    let CollectionCap { id, .. } = cap;
    id.delete();
}
```

Then clear all metadata first:

```typescript
// You'd need to track all asset_ids that have metadata
const assetIdsWithMetadata = [...]; // Your tracking

for (const assetId of assetIdsWithMetadata) {
  // Add a remove_metadata function to the module
  tx.moveCall({
    target: `${packageId}::multicoin::remove_metadata`,
    arguments: [
      tx.object(collectionCapId),
      tx.object(collectionId),
      tx.pure.u128(assetId),
    ],
  });
}

// Then destroy the collection
tx.moveCall({
  target: `${packageId}::multicoin::destroy_collection`,
  arguments: [
    tx.object(collectionCapId),
    tx.object(collectionId),
  ],
});
```

### Current Best Practice

**Don't delete collections.** Instead:
- Transfer the `CollectionCap` to relinquish control
- Shared `Collection` objects remain accessible for querying
- Existing `Balance` objects continue to work normally
- This follows the Sui model of persistent shared state

## Additional Operations

### Set Asset Metadata

```typescript
const tx = new Transaction();

const metadata = new TextEncoder().encode('Iron Sword: A basic weapon');

tx.moveCall({
  target: `${packageId}::multicoin::set_metadata`,
  arguments: [
    tx.object(collectionCapId),
    tx.object(collectionId),
    tx.pure.u128(assetId),
    tx.pure(Array.from(metadata)),
  ],
});

await client.signAndExecuteTransaction({
  transaction: tx,
  signer: keypair,
});
```

### Query Metadata

```typescript
async function getMetadata(collectionId: string, assetId: bigint) {
  const collection = await client.getObject({
    id: collectionId,
    options: { showContent: true },
  });

  // Note: You'll need to call the contract to read table entries
  // Tables are not directly queryable from RPC
  const tx = new Transaction();
  
  const [result] = tx.moveCall({
    target: `${packageId}::multicoin::get_metadata`,
    arguments: [
      tx.object(collectionId),
      tx.pure.u128(assetId),
    ],
  });

  // This requires a view function or inspection transaction
  const devInspect = await client.devInspectTransactionBlock({
    transactionBlock: tx,
    sender: myAddress,
  });
  
  // Parse result from devInspect
  return devInspect.results?.[0]?.returnValues?.[0];
}
```

### Burn Assets

```typescript
const tx = new Transaction();

// Burn a balance (requires collection reference)
tx.moveCall({
  target: `${packageId}::multicoin::burn`,
  arguments: [
    tx.object(collectionId),  // Collection (shared object)
    tx.object(balanceId),      // Balance to burn
  ],
});

await client.signAndExecuteTransaction({
  transaction: tx,
  signer: keypair,
});
```

**Note**: Burning now requires the Collection as an argument to update supply tracking.
```

## Listening to Events

```typescript
// Subscribe to mint events
const unsubscribe = await client.subscribeEvent({
  filter: {
    MoveEventType: `${packageId}::multicoin::MintEvent`,
  },
  onMessage: (event) => {
    console.log('Asset minted:', {
      collection: event.parsedJson.collection,
      assetId: event.parsedJson.asset_id,
      to: event.parsedJson.to,
      amount: event.parsedJson.amount,
    });
  },
});

// Query past events
const events = await client.queryEvents({
  query: {
    MoveEventType: `${packageId}::multicoin::TransferEvent`,
  },
});
```

## Complete Example: Full Workflow

```typescript
import { Transaction } from '@mysten/sui/transactions';
import { SuiClient } from '@mysten/sui/client';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';

const client = new SuiClient({ url: 'https://fullnode.testnet.sui.io' });
const keypair = Ed25519Keypair.fromSecretKey(secretKey);
const packageId = '0x...';

async function fullWorkflow() {
  // 1. Create collection
  const createTx = new Transaction();
  createTx.moveCall({
    target: `${packageId}::multicoin::create_collection`,
  });
  
  const createResult = await client.signAndExecuteTransaction({
    transaction: createTx,
    signer: keypair,
  });
  
  const collectionId = createResult.objectChanges?.find(
    obj => obj.objectType?.includes('Collection')
  )?.objectId;
  
  const capId = createResult.objectChanges?.find(
    obj => obj.objectType?.includes('CollectionCap')
  )?.objectId;

  // 2. Mint assets
  const mintTx = new Transaction();
  const assetId = (100n << 64n) | 1n; // location=100, item=1
  
  mintTx.moveCall({
    target: `${packageId}::multicoin::mint`,
    arguments: [
      mintTx.object(capId!),
      mintTx.object(collectionId!),
      mintTx.pure.u128(assetId),
      mintTx.pure.u64(1000),
      mintTx.pure.address(keypair.toSuiAddress()),
    ],
  });
  
  const mintResult = await client.signAndExecuteTransaction({
    transaction: mintTx,
    signer: keypair,
  });

  // 3. Fetch balances
  const balances = await getBalances(keypair.toSuiAddress());
  console.log('My balances:', balances);

  // 4. Transfer
  const balanceId = balances[0]?.objectId;
  if (balanceId) {
    const transferTx = new Transaction();
    transferTx.moveCall({
      target: `${packageId}::multicoin::split_and_transfer`,
      arguments: [
        transferTx.object(balanceId),
        transferTx.pure.u64(100),
        transferTx.pure.address(recipientAddress),
      ],
    });
    
    await client.signAndExecuteTransaction({
      transaction: transferTx,
      signer: keypair,
    });
  }
}

fullWorkflow().catch(console.error);
```

## Troubleshooting

### Error: EWrongCollection
- Ensure the `CollectionCap` matches the `Collection` ID
- Verify you're using the correct cap for the collection

### Error: EInsufficientBalance
- Check the balance amount before splitting
- Ensure you're not trying to split more than available

### Error: EZeroAmount
- Minting and splitting require amount > 0
- Use `zero()` function explicitly for zero balances

### Can't query Table metadata
- Tables are not directly readable via RPC
- Use `devInspectTransactionBlock` or maintain off-chain index
- Consider emitting events when metadata changes

## Best Practices

1. **Index Events**: Subscribe to events and maintain an off-chain index for efficient queries
2. **Batch Operations**: Use `batch_mint` and `batch_transfer` for gas efficiency
3. **Asset ID Convention**: Document your bit-packing scheme (location + item)
4. **Metadata**: Keep metadata small or store off-chain (IPFS) with on-chain reference
5. **Cap Security**: Protect the `CollectionCap` - it's admin control
6. **Shared Collections**: Collections are shared objects; design for concurrent access
