/// # MultiCoin - ERC-1155 Style Multi-Token Standard for Sui
///
/// This module implements a fungible multi-token system similar to Ethereum's ERC-1155 standard,
/// allowing a single collection to manage multiple token types with independent balances and supplies.
///
/// ## Core Concepts
///
/// - **Collection**: A shared object representing a token collection (similar to an ERC-1155 contract).
///   Each collection can contain (2^128)-1 token types identified by u128 token IDs.
///
/// - **Token ID**: A 128-bit identifier that can be bit-packed to encode semantic meaning.
///   By default, uses a location_id (upper 64 bits) + item_id (lower 64 bits) scheme,
///   enabling hierarchical token organization (e.g., items per location in a game). 
///   If this was to be generalized outside of this game - the id would just be _some_
///   unique u128.
///
/// - **Balance**: An owned object representing a user's balance of a specific token type.
///   Similar to Sui's Coin type, balances can be split, merged, and transferred independently.
///
/// - **CollectionCap**: Admin capability for minting tokens and managing metadata.
///   Only the holder of this capability can mint new tokens or set metadata.
///
/// ## Key Features
///
/// - **Flexible Token IDs**: Bit-packed u128 IDs support token organization
/// - **Independent Balances**: Each token type has its own supply and owned balance objects
/// - **Coin-like Operations**: Split, merge, and transfer balances with type safety
/// - **Metadata Support**: Optional on-chain metadata storage per token type
/// - **Batch Operations**: Mint and transfer multiple token types efficiently
/// - **Event Emission**: Track all mints, burns, and transfers on-chain
///
/// ## Usage Example
///
/// ```move
/// // Create collection
/// let (collection, cap) = multicoin::new_collection(ctx);
/// 
/// // Create token ID for location 1, item 5
/// let token_id = multicoin::make_token_id(1, 5);
/// 
/// // Mint 100 tokens
/// let balance = multicoin::mint_balance(&cap, &mut collection, token_id, 100, ctx);
/// 
/// // Split and transfer 30 tokens
/// let split_balance = balance.split(30, ctx);
/// transfer::transfer(split_balance, recipient);
/// ```
///
/// ## Token ID Scheme
///
/// Default bit-packing: `token_id = (location_id << 64) | item_id`
/// - Upper 64 bits: location_id (spatial/categorical grouping)
/// - Lower 64 bits: item_id (specific item within location)
///
/// This scheme enables:
/// - Querying all items at a location (using indexer)
/// - Organizing tokens by game world regions, system, or assembly (using indexer)
/// - Trading "items" via runtime assets
///
/// Things this scheme fails at:
/// - Enabling clean-up of state. This would likely rely on client-side clean up of state.
///
/// Custom schemes can use the full 128-bit space for alternative encodings.
module multicoin::multicoin;

use sui::event;
use sui::table::{Self, Table};

/*********************************
 * Errors
 *********************************/
const EWrongCollection: u64 = 0;
const EWrongTokenId: u64 = 1;
const EInsufficientBalance: u64 = 2;
const EInvalidArg: u64 = 3;
const EZeroAmount: u64 = 4;

/*********************************
 * Constants for bit packing (EveF-specific implementation of token IDs)
 *********************************/
const LOCATION_BITS: u8 = 64;
const ITEM_MASK: u128 = (1u128 << 64) - 1;

/*********************************
 * Core Objects
 *********************************/

/// Shared collection (ERC-1155 "contract")
public struct Collection has key, store {
    id: UID,
    metadata: Table<u128, vector<u8>>,
    supply: Table<u128, u64>,
}

/// Admin capability for minting / control
public struct CollectionCap has key, store {
    id: UID,
    collection: ID,
}

/// Owned balance object (Coin-like)
public struct Balance has key, store {
    id: UID,
    collection: ID,
    token_id: u128,
    amount: u64,
}

/*********************************
 * Events
 *********************************/

/// Emitted when tokens are transferred
public struct TransferEvent has copy, drop {
    collection: ID,
    token_id: u128,
    from: address,
    to: address,
    amount: u64,
}

/// Emitted when tokens are minted
public struct MintEvent has copy, drop {
    collection: ID,
    token_id: u128,
    to: address,
    amount: u64,
}

/// Emitted when tokens are burned
public struct BurnEvent has copy, drop {
    collection: ID,
    token_id: u128,
    from: address,
    amount: u64,
}

/*********************************
 * Creation
 *********************************/

/// Create a new collection and return cap, transferring collection to sender
entry fun create_collection(ctx: &mut TxContext) {
    let collection = Collection {
        id: object::new(ctx),
        metadata: table::new(ctx),
        supply: table::new(ctx),
    };

    let cap = CollectionCap {
        id: object::new(ctx),
        collection: object::id(&collection),
    };

    transfer::share_object(collection);
    transfer::transfer(cap, ctx.sender());
}

/// Create a new collection (programmatic version)
public fun new_collection(ctx: &mut TxContext): (Collection, CollectionCap) {
    let collection = Collection {
        id: object::new(ctx),
        metadata: table::new(ctx),
        supply: table::new(ctx),
    };

    let cap = CollectionCap {
        id: object::new(ctx),
        collection: object::id(&collection),
    };

    (collection, cap)
}

/*********************************
 * Token ID helpers (bit-packed)
 *********************************/

/// Pack location_id and item_id into a single u128 token_id
public fun make_token_id(location_id: u64, item_id: u64): u128 {
    (location_id as u128 << LOCATION_BITS) | (item_id as u128)
}

/// Extract location_id from token_id
public fun location_id(token_id: u128): u64 {
    (token_id >> LOCATION_BITS) as u64
}

/// Extract item_id from token_id
public fun item_id(token_id: u128): u64 {
    (token_id & ITEM_MASK) as u64
}

/*********************************
 * Metadata (optional)
 *********************************/

/// Set metadata for a token type (requires CollectionCap)
public fun set_metadata(
    cap: &CollectionCap,
    collection: &mut Collection,
    token_id: u128,
    data: vector<u8>,
) {
    assert!(cap.collection == object::id(collection), EWrongCollection);
    if (collection.metadata.contains(token_id)) {
        *collection.metadata.borrow_mut(token_id) = data;
    } else {
        collection.metadata.add(token_id, data);
    };
}

/// Get metadata for a token type
public fun get_metadata(collection: &Collection, token_id: u128): &vector<u8> {
    collection.metadata.borrow(token_id)
}

/// Check if metadata exists for a token type
public fun has_metadata(collection: &Collection, token_id: u128): bool {
    collection.metadata.contains(token_id)
}

/*********************************
 * Minting
 *********************************/

/// Mint tokens and transfer to recipient
entry fun mint(
    cap: &CollectionCap,
    collection: &mut Collection,
    token_id: u128,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    assert!(amount > 0, EZeroAmount);
    let balance = mint_balance(cap, collection, token_id, amount, ctx);
    transfer::transfer(balance, recipient);
}

/// Mint tokens as a Balance object
public fun mint_balance(
    cap: &CollectionCap,
    collection: &mut Collection,
    token_id: u128,
    amount: u64,
    ctx: &mut TxContext,
): Balance {
    assert!(cap.collection == object::id(collection), EWrongCollection);
    assert!(amount > 0, EZeroAmount);

    // Update supply
    let current_supply = if (collection.supply.contains(token_id)) {
        *collection.supply.borrow(token_id)
    } else {
        0
    };
    
    let new_supply = current_supply + amount;
    if (collection.supply.contains(token_id)) {
        *collection.supply.borrow_mut(token_id) = new_supply;
    } else {
        collection.supply.add(token_id, new_supply);
    };

    event::emit(MintEvent {
        collection: cap.collection,
        token_id,
        to: ctx.sender(),
        amount,
    });

    Balance {
        id: object::new(ctx),
        collection: cap.collection,
        token_id,
        amount,
    }
}

/// Batch mint multiple token types to a single recipient
entry fun batch_mint(
    cap: &CollectionCap,
    collection: &mut Collection,
    token_ids: vector<u128>,
    amounts: vector<u64>,
    recipient: address,
    ctx: &mut TxContext,
) {
    assert!(token_ids.length() == amounts.length(), EInvalidArg);
    assert!(token_ids.length() > 0, EInvalidArg);

    token_ids.zip_do!(amounts, |token_id, amount| {
        mint(cap, collection, token_id, amount, recipient, ctx);
    });
}

/// Mint tokens and keep them (for composability)
public fun mint_and_keep(
    cap: &CollectionCap,
    collection: &mut Collection,
    token_id: u128,
    amount: u64,
    ctx: &mut TxContext,
): Balance {
    mint_balance(cap, collection, token_id, amount, ctx)
}

/*********************************
 * Balance operations (Coin-like)
 *********************************/

/// Split a balance into two
public fun split(balance: &mut Balance, amount: u64, ctx: &mut TxContext): Balance {
    assert!(balance.amount >= amount, EInsufficientBalance);
    assert!(amount > 0, EZeroAmount);

    balance.amount = balance.amount - amount;

    Balance {
        id: object::new(ctx),
        collection: balance.collection,
        token_id: balance.token_id,
        amount,
    }
}

/// Split and transfer to recipient
entry fun split_and_transfer(
    balance: &mut Balance,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let split_balance = balance.split(amount, ctx);
    transfer::transfer(split_balance, recipient);
}

/// Merge two balances of the same token type
public fun join(self: &mut Balance, other: Balance) {
    assert!(self.collection == other.collection, EWrongCollection);
    assert!(self.token_id == other.token_id, EWrongTokenId);

    self.amount = self.amount + other.amount;
    let Balance { id, .. } = other;
    id.delete();
}

/// Create a zero balance
public fun zero(collection_id: ID, token_id: u128, ctx: &mut TxContext): Balance {
    Balance {
        id: object::new(ctx),
        collection: collection_id,
        token_id,
        amount: 0,
    }
}

/// Destroy a zero balance
public fun destroy_zero(balance: Balance) {
    assert!(balance.amount == 0, EInsufficientBalance);
    let Balance { id, .. } = balance;
    id.delete();
}

/*********************************
 * Burning
 *********************************/

/// Burn tokens
public fun burn(
    collection: &mut Collection,
    balance: Balance,
    ctx: &TxContext,
): u64 {
    let Balance { id, collection: balance_collection, token_id, amount } = balance;
    
    // Verify balance belongs to this collection
    assert!(object::id(collection) == balance_collection, EWrongCollection);
    
    // Update supply
    if (collection.supply.contains(token_id)) {
        let current_supply = *collection.supply.borrow(token_id);
        *collection.supply.borrow_mut(token_id) = current_supply - amount;
    };
    
    event::emit(BurnEvent {
        collection: balance_collection,
        token_id,
        from: ctx.sender(),
        amount,
    });
    
    id.delete();
    amount
}

/// Batch burn multiple balances
entry fun batch_burn(
    collection: &mut Collection,
    balances: vector<Balance>,
    ctx: &TxContext,
) {
    balances.do!(|balance| {
        burn(collection, balance, ctx);
    });
}

/*********************************
 * Accessors
 *********************************/

/// Get balance amount
public fun value(balance: &Balance): u64 {
    balance.amount
}

/// Get token ID
public fun token_id(balance: &Balance): u128 {
    balance.token_id
}

/// Get collection ID
public fun collection_id(balance: &Balance): ID {
    balance.collection
}

/// Get collection ID from cap
public fun cap_collection_id(cap: &CollectionCap): ID {
    cap.collection
}

/// Get total supply for a token type
public fun total_supply(collection: &Collection, token_id: u128): u64 {
    if (collection.supply.contains(token_id)) {
        *collection.supply.borrow(token_id)
    } else {
        0
    }
}

/*********************************
 * Transfer functions
 *********************************/

/// Transfer balance to recipient
#[allow(lint(custom_state_change))]
entry fun transfer(balance: Balance, recipient: address, ctx: &TxContext) {
    event::emit(TransferEvent {
        collection: balance.collection,
        token_id: balance.token_id,
        from: ctx.sender(),
        to: recipient,
        amount: balance.amount,
    });
    transfer::transfer(balance, recipient);
}

/// Batch transfer multiple balances to a single recipient
entry fun batch_transfer(balances: vector<Balance>, recipient: address, ctx: &TxContext) {
    balances.do!(|balance| {
        transfer(balance, recipient, ctx);
    });
}

/*********************************
 * Test-only functions
 *********************************/

#[test_only]
/// Create a balance for testing
public fun create_balance_for_testing(
    collection_id: ID,
    token_id: u128,
    amount: u64,
    ctx: &mut TxContext,
): Balance {
    Balance {
        id: object::new(ctx),
        collection: collection_id,
        token_id,
        amount,
    }
}
