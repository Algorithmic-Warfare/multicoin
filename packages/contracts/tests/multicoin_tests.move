#[test_only]
module multicoin::multicoin_tests;

use sui::test_scenario;
use multicoin::multicoin::{Self, Collection, CollectionCap, Balance};

const ADMIN: address = @0xAD;
const USER1: address = @0x1;
const USER2: address = @0x2;

// Asset IDs for testing (arbitrary u128 values)
const TOKEN_SWORD: u128 = 1;
const TOKEN_SHIELD: u128 = 2;
const TOKEN_POTION: u128 = 3;

#[test]
fun test_create_collection() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    {
        multicoin::create_collection(scenario.ctx());
    };
    
    scenario.next_tx(ADMIN);
    
    {
        let cap = scenario.take_from_sender<CollectionCap>();
        scenario.return_to_sender(cap);
    };
    
    scenario.end();
}

#[test]
fun test_mint_and_balance() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let (collection, cap) = multicoin::new_collection(scenario.ctx());
    let collection_id = object::id(&collection);
    let asset_id = TOKEN_SWORD;
    
    transfer::public_share_object(collection);
    
    scenario.next_tx(ADMIN);
    
    {
        let mut collection = scenario.take_shared<Collection>();
        multicoin::mint(&cap, &mut collection, asset_id, 100, USER1, scenario.ctx());
        test_scenario::return_shared(collection);
    };
    
    scenario.next_tx(USER1);
    
    {
        let balance = scenario.take_from_sender<Balance>();
        assert!(balance.value() == 100);
        assert!(balance.asset_id() == asset_id);
        assert!(balance.collection_id() == collection_id);
        scenario.return_to_sender(balance);
    };
    
    transfer::public_transfer(cap, ADMIN);
    scenario.end();
}

#[test]
fun test_split_and_join() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let (mut collection, cap) = multicoin::new_collection(scenario.ctx());
    let asset_id = TOKEN_SWORD;
    
    let mut balance = multicoin::mint_and_keep(&cap, &mut collection, asset_id, 100, scenario.ctx());
    
    let split_balance = balance.split(30, scenario.ctx());
    
    assert!(balance.value() == 70);
    assert!(split_balance.value() == 30);
    
    balance.join(split_balance, scenario.ctx());
    assert!(balance.value() == 100);
    
    transfer::public_transfer(balance, ADMIN);
    transfer::public_share_object(collection);
    transfer::public_transfer(cap, ADMIN);
    scenario.end();
}

#[test]
fun test_batch_mint() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let (collection, cap) = multicoin::new_collection(scenario.ctx());
    transfer::public_share_object(collection);
    
    scenario.next_tx(ADMIN);
    
    {
        let mut collection = scenario.take_shared<Collection>();
        let asset_ids = vector[
            TOKEN_SWORD,
            TOKEN_SHIELD,
            TOKEN_POTION,
        ];
        let amounts = vector[10, 5, 20];
        
        multicoin::batch_mint(&cap, &mut collection, asset_ids, amounts, USER1, scenario.ctx());
        test_scenario::return_shared(collection);
    };
    
    scenario.next_tx(USER1);
    
    {
        let ids = scenario.ids_for_sender<Balance>();
        assert!(ids.length() == 3);
    };
    
    transfer::public_transfer(cap, ADMIN);
    scenario.end();
}

#[test]
fun test_zero_balance() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let (collection, cap) = multicoin::new_collection(scenario.ctx());
    let collection_id = object::id(&collection);
    let asset_id = TOKEN_SWORD;
    
    let zero_balance = multicoin::zero(collection_id, asset_id, scenario.ctx());
    assert!(zero_balance.value() == 0);
    
    zero_balance.destroy_zero();
    
    transfer::public_share_object(collection);
    transfer::public_transfer(cap, ADMIN);
    scenario.end();
}

#[test]
fun test_burn() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let (mut collection, cap) = multicoin::new_collection(scenario.ctx());
    let asset_id = TOKEN_SWORD;
    
    let balance = multicoin::mint_and_keep(&cap, &mut collection, asset_id, 100, scenario.ctx());
    
    let burned_amount = multicoin::burn(&mut collection, balance, scenario.ctx());
    assert!(burned_amount == 100);
    
    transfer::public_share_object(collection);
    transfer::public_transfer(cap, ADMIN);
    scenario.end();
}

#[test]
fun test_metadata() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let (mut collection, cap) = multicoin::new_collection(scenario.ctx());
    let asset_id = TOKEN_SWORD;
    
    assert!(!collection.has_metadata(asset_id));
    
    let metadata = b"Iron Sword: A sturdy blade";
    cap.set_metadata(&mut collection, asset_id, metadata);
    
    assert!(collection.has_metadata(asset_id));
    assert!(collection.get_metadata(asset_id) == &metadata);
    
    // Update metadata
    let new_metadata = b"Steel Sword: An upgraded blade";
    cap.set_metadata(&mut collection, asset_id, new_metadata);
    assert!(collection.get_metadata(asset_id) == &new_metadata);
    
    transfer::public_share_object(collection);
    transfer::public_transfer(cap, ADMIN);
    scenario.end();
}

#[test]
fun test_split_and_transfer() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let (collection, cap) = multicoin::new_collection(scenario.ctx());
    let asset_id = TOKEN_SWORD;
    
    transfer::public_share_object(collection);
    
    scenario.next_tx(ADMIN);
    
    {
        let mut collection = scenario.take_shared<Collection>();
        multicoin::mint(&cap, &mut collection, asset_id, 100, USER1, scenario.ctx());
        test_scenario::return_shared(collection);
    };
    
    scenario.next_tx(USER1);
    
    {
        let mut balance = scenario.take_from_sender<Balance>();
        multicoin::split_and_transfer(&mut balance, 30, USER2, scenario.ctx());
        scenario.return_to_sender(balance);
    };
    
    scenario.next_tx(USER1);
    
    {
        let balance = scenario.take_from_sender<Balance>();
        assert!(balance.value() == 70);
        scenario.return_to_sender(balance);
    };
    
    scenario.next_tx(USER2);
    
    {
        let balance = scenario.take_from_sender<Balance>();
        assert!(balance.value() == 30);
        scenario.return_to_sender(balance);
    };
    
    transfer::public_transfer(cap, ADMIN);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = 2)]
fun test_split_insufficient_balance() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let (mut collection, cap) = multicoin::new_collection(scenario.ctx());
    let asset_id = TOKEN_SWORD;
    
    let mut balance = multicoin::mint_and_keep(&cap, &mut collection, asset_id, 100, scenario.ctx());
    
    let _split = balance.split(101, scenario.ctx());
    
    abort 0
}

#[test]
#[expected_failure(abort_code = 1)]
fun test_join_wrong_asset_id() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let (mut collection, cap) = multicoin::new_collection(scenario.ctx());
    let asset_id1 = TOKEN_SWORD;
    let asset_id2 = TOKEN_SHIELD;
    
    let mut balance1 = multicoin::mint_and_keep(&cap, &mut collection, asset_id1, 100, scenario.ctx());
    let balance2 = multicoin::mint_and_keep(&cap, &mut collection, asset_id2, 50, scenario.ctx());
    
    balance1.join(balance2, scenario.ctx());
    
    abort 0
}

#[test]
#[expected_failure(abort_code = 4)]
fun test_mint_zero_amount() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let (mut collection, cap) = multicoin::new_collection(scenario.ctx());
    let asset_id = TOKEN_SWORD;
    
    let _balance = multicoin::mint_and_keep(&cap, &mut collection, asset_id, 0, scenario.ctx());
    
    abort 0
}

#[test]
#[expected_failure(abort_code = 2)]
fun test_destroy_non_zero_balance() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let (mut collection, cap) = multicoin::new_collection(scenario.ctx());
    let asset_id = TOKEN_SWORD;
    
    let balance = multicoin::mint_and_keep(&cap, &mut collection, asset_id, 100, scenario.ctx());
    
    balance.destroy_zero();
    
    abort 0
}

#[test]
fun test_total_supply() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let (mut collection, cap) = multicoin::new_collection(scenario.ctx());
    let asset_id = TOKEN_SWORD;
    
    // Initially supply should be 0
    assert!(multicoin::total_supply(&collection, asset_id) == 0);
    
    // Mint 100 assets
    let mut balance1 = multicoin::mint_and_keep(&cap, &mut collection, asset_id, 100, scenario.ctx());
    assert!(multicoin::total_supply(&collection, asset_id) == 100);
    
    // Mint 50 more assets
    let balance2 = multicoin::mint_and_keep(&cap, &mut collection, asset_id, 50, scenario.ctx());
    assert!(multicoin::total_supply(&collection, asset_id) == 150);
    
    // Burn 30 assets
    let split = balance1.split(30, scenario.ctx());
    multicoin::burn(&mut collection, split, scenario.ctx());
    assert!(multicoin::total_supply(&collection, asset_id) == 120);
    
    // Clean up
    transfer::public_transfer(balance1, ADMIN);
    transfer::public_transfer(balance2, ADMIN);
    transfer::public_share_object(collection);
    transfer::public_transfer(cap, ADMIN);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = 1, location = sui::balance)]
fun test_supply_overflow_protection() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let (mut collection, cap) = multicoin::new_collection(scenario.ctx());
    let asset_id = TOKEN_SWORD;
    
    // Mint close to u64 max
    let _balance1 = multicoin::mint_and_keep(&cap, &mut collection, asset_id, 18446744073709551614u64, scenario.ctx());
    
    // Try to mint more assets (should overflow and fail)
    let _balance2 = multicoin::mint_and_keep(&cap, &mut collection, asset_id, 10, scenario.ctx());
    
    abort 0
}

#[test]
#[expected_failure(abort_code = 2, location = sui::balance)]
fun test_supply_underflow_protection() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let (mut collection, cap) = multicoin::new_collection(scenario.ctx());
    let asset_id = TOKEN_SWORD;
    
    // Mint 100 assets
    let _balance = multicoin::mint_and_keep(&cap, &mut collection, asset_id, 100, scenario.ctx());
    
    // Manually corrupt supply to test underflow protection
    // In real scenario, this tests that burning more than supply is prevented
    let fake_balance = multicoin::create_balance_for_testing(
        object::id(&collection),
        asset_id,
        200, // More than actual supply
        scenario.ctx()
    );
    
    // This should fail with EInsufficientSupply
    multicoin::burn(&mut collection, fake_balance, scenario.ctx());
    
    abort 0
}

#[test]
fun test_asset_id_supply_isolation() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let (mut collection, cap) = multicoin::new_collection(scenario.ctx());
    let asset_id_sword = TOKEN_SWORD;
    let asset_id_shield = TOKEN_SHIELD;
    let asset_id_potion = TOKEN_POTION;
    
    // Initially all supplies should be 0
    assert!(multicoin::total_supply(&collection, asset_id_sword) == 0);
    assert!(multicoin::total_supply(&collection, asset_id_shield) == 0);
    assert!(multicoin::total_supply(&collection, asset_id_potion) == 0);
    
    // Mint different amounts for each asset_id
    let balance_sword = multicoin::mint_and_keep(&cap, &mut collection, asset_id_sword, 100, scenario.ctx());
    assert!(multicoin::total_supply(&collection, asset_id_sword) == 100);
    assert!(multicoin::total_supply(&collection, asset_id_shield) == 0); // Unchanged
    assert!(multicoin::total_supply(&collection, asset_id_potion) == 0); // Unchanged
    
    let balance_shield = multicoin::mint_and_keep(&cap, &mut collection, asset_id_shield, 50, scenario.ctx());
    assert!(multicoin::total_supply(&collection, asset_id_sword) == 100); // Unchanged
    assert!(multicoin::total_supply(&collection, asset_id_shield) == 50);
    assert!(multicoin::total_supply(&collection, asset_id_potion) == 0); // Unchanged
    
    let balance_potion = multicoin::mint_and_keep(&cap, &mut collection, asset_id_potion, 200, scenario.ctx());
    assert!(multicoin::total_supply(&collection, asset_id_sword) == 100); // Unchanged
    assert!(multicoin::total_supply(&collection, asset_id_shield) == 50); // Unchanged
    assert!(multicoin::total_supply(&collection, asset_id_potion) == 200);
    
    // Mint more of one asset_id - should only affect that asset_id
    let balance_sword2 = multicoin::mint_and_keep(&cap, &mut collection, asset_id_sword, 25, scenario.ctx());
    assert!(multicoin::total_supply(&collection, asset_id_sword) == 125);
    assert!(multicoin::total_supply(&collection, asset_id_shield) == 50); // Unchanged
    assert!(multicoin::total_supply(&collection, asset_id_potion) == 200); // Unchanged
    
    // Burn from one asset_id - should only affect that asset_id
    multicoin::burn(&mut collection, balance_shield, scenario.ctx());
    assert!(multicoin::total_supply(&collection, asset_id_sword) == 125); // Unchanged
    assert!(multicoin::total_supply(&collection, asset_id_shield) == 0);
    assert!(multicoin::total_supply(&collection, asset_id_potion) == 200); // Unchanged
    
    // Clean up
    transfer::public_transfer(balance_sword, ADMIN);
    transfer::public_transfer(balance_sword2, ADMIN);
    transfer::public_transfer(balance_potion, ADMIN);
    transfer::public_share_object(collection);
    transfer::public_transfer(cap, ADMIN);
    scenario.end();
}

#[test]
fun test_asset_id_balance_operations_isolated() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let (mut collection, cap) = multicoin::new_collection(scenario.ctx());
    let asset_id1 = TOKEN_SWORD;
    let asset_id2 = TOKEN_SHIELD;
    
    // Mint same amount for different asset_ids
    let mut balance1 = multicoin::mint_and_keep(&cap, &mut collection, asset_id1, 100, scenario.ctx());
    let mut balance2 = multicoin::mint_and_keep(&cap, &mut collection, asset_id2, 100, scenario.ctx());
    
    // Verify they have correct asset_ids
    assert!(balance1.asset_id() == asset_id1);
    assert!(balance2.asset_id() == asset_id2);
    
    // Split from balance1 - should not affect balance2
    let split1 = balance1.split(30, scenario.ctx());
    assert!(balance1.value() == 70);
    assert!(balance2.value() == 100); // Unchanged
    assert!(split1.asset_id() == asset_id1);
    
    // Split from balance2 - should not affect balance1
    let split2 = balance2.split(40, scenario.ctx());
    assert!(balance1.value() == 70); // Unchanged
    assert!(balance2.value() == 60);
    assert!(split2.asset_id() == asset_id2);
    
    // Join back to original balances
    balance1.join(split1, scenario.ctx());
    balance2.join(split2, scenario.ctx());
    assert!(balance1.value() == 100);
    assert!(balance2.value() == 100);
    
    // Verify supplies are still independent
    assert!(multicoin::total_supply(&collection, asset_id1) == 100);
    assert!(multicoin::total_supply(&collection, asset_id2) == 100);
    
    // Clean up
    transfer::public_transfer(balance1, ADMIN);
    transfer::public_transfer(balance2, ADMIN);
    transfer::public_share_object(collection);
    transfer::public_transfer(cap, ADMIN);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = 1)]
fun test_cannot_join_different_asset_ids_same_collection() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    let (mut collection, cap) = multicoin::new_collection(scenario.ctx());
    let asset_id1 = TOKEN_SWORD;
    let asset_id2 = TOKEN_SHIELD;
    
    // Mint balances for different asset_ids in the same collection
    let mut balance1 = multicoin::mint_and_keep(&cap, &mut collection, asset_id1, 100, scenario.ctx());
    let balance2 = multicoin::mint_and_keep(&cap, &mut collection, asset_id2, 50, scenario.ctx());
    
    // Verify they're from the same collection but different asset_ids
    assert!(balance1.collection_id() == balance2.collection_id());
    assert!(balance1.asset_id() != balance2.asset_id());
    
    // Try to join - should fail with EWrongAssetId
    balance1.join(balance2, scenario.ctx());
    
    abort 0
}

#[test]
fun test_collection_isolation() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Create two separate collections
    let (mut collection1, cap1) = multicoin::new_collection(scenario.ctx());
    let (mut collection2, cap2) = multicoin::new_collection(scenario.ctx());
    
    let collection1_id = object::id(&collection1);
    let collection2_id = object::id(&collection2);
    let asset_id = TOKEN_SWORD;
    
    // Verify collections have different IDs
    assert!(collection1_id != collection2_id);
    
    // Mint 100 assets in collection1
    let balance1 = multicoin::mint_and_keep(&cap1, &mut collection1, asset_id, 100, scenario.ctx());
    assert!(multicoin::total_supply(&collection1, asset_id) == 100);
    assert!(multicoin::total_supply(&collection2, asset_id) == 0);
    assert!(balance1.collection_id() == collection1_id);
    
    // Mint 50 assets in collection2 (same asset_id but different collection)
    let balance2 = multicoin::mint_and_keep(&cap2, &mut collection2, asset_id, 50, scenario.ctx());
    assert!(multicoin::total_supply(&collection1, asset_id) == 100); // Unchanged
    assert!(multicoin::total_supply(&collection2, asset_id) == 50);
    assert!(balance2.collection_id() == collection2_id);
    
    // Burn from collection1
    multicoin::burn(&mut collection1, balance1, scenario.ctx());
    assert!(multicoin::total_supply(&collection1, asset_id) == 0);
    assert!(multicoin::total_supply(&collection2, asset_id) == 50); // Unchanged
    
    // Burn from collection2
    multicoin::burn(&mut collection2, balance2, scenario.ctx());
    assert!(multicoin::total_supply(&collection2, asset_id) == 0);
    
    // Clean up
    transfer::public_share_object(collection1);
    transfer::public_share_object(collection2);
    transfer::public_transfer(cap1, ADMIN);
    transfer::public_transfer(cap2, ADMIN);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = 0)]
fun test_cannot_join_balances_from_different_collections() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Create two separate collections
    let (mut collection1, cap1) = multicoin::new_collection(scenario.ctx());
    let (mut collection2, cap2) = multicoin::new_collection(scenario.ctx());
    
    let asset_id = TOKEN_SWORD;
    
    // Mint from both collections
    let mut balance1 = multicoin::mint_and_keep(&cap1, &mut collection1, asset_id, 100, scenario.ctx());
    let balance2 = multicoin::mint_and_keep(&cap2, &mut collection2, asset_id, 50, scenario.ctx());
    
    // Try to join balances from different collections - should fail
    balance1.join(balance2, scenario.ctx());
    
    abort 0
}

#[test]
#[expected_failure(abort_code = 0)]
fun test_cannot_burn_balance_with_wrong_collection() {
    let mut scenario = test_scenario::begin(ADMIN);
    
    // Create two separate collections
    let (mut collection1, cap1) = multicoin::new_collection(scenario.ctx());
    let (mut collection2, _cap2) = multicoin::new_collection(scenario.ctx());
    
    let asset_id = TOKEN_SWORD;
    
    // Mint from collection1
    let balance = multicoin::mint_and_keep(&cap1, &mut collection1, asset_id, 100, scenario.ctx());
    
    // Try to burn using collection2 - should fail
    multicoin::burn(&mut collection2, balance, scenario.ctx());
    
    abort 0
}

