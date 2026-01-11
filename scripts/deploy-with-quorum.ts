#!/usr/bin/env node

import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { Transaction } from '@mysten/sui/transactions';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { prepareAddressVecSet } from './utils';

// Configuration
 // Replace with your deployed package ID for quorum_upgrade_v2
const PACKAGE_ID = '0x72129fbcd97a5594bd7fea2e4b3f07cde69cdc140c22e1a77f8a857037dfdb3f';
const MODULE = 'quorum_upgrade'; // module name is `quorum_upgrade` even for v2
const FUNCTION = 'new'; // function to create new quorum
const GAS_BUDGET = '10000000';

// Arguments
// Replace with your UpgradeCap object ID from your quorum-managed package deployment
const UPGRADE_CAP_OBJECT_ID = '0x2c8782b9b49f7e1fef3c0ed2a3fd11be84201002d1cbbc2441a9da0bfad44373';
const THRESHOLD = 2;
const MEMBERS = [
    '0xe788b6ce6a6d972a6cf1fdc30f508de6ab76ccdd182c3f3de7d6663c4243aeab',
    '0xc2aa8506eab3adbc54597bfefd7c7f2ed7527e6f704a888744697ba07812c92e',
    '0xf30f05a4c0d8918ce9b811e3e8a7e59513917b60326a17df65f7e40edeb1d36a',
    '0x0512b609c3adc944c9336112ecf38f442f585f09735c898e403a97aeae569776'
];

async function executeTransaction() {
  try {
    // Get private key from environment variable
    const privateKeyB64 = process.env.SUI_PRIVATE_KEY;
    if (!privateKeyB64) {
      throw new Error('SUI_PRIVATE_KEY environment variable not set');
    }
    // Initialize keypair from private key
    const keypair = Ed25519Keypair.fromSecretKey(privateKeyB64);
    const sender = keypair.getPublicKey().toSuiAddress();

    console.log(`Sender address: ${sender}`);
    console.log('Building transaction...\n');

    // Initialize Sui client (default to mainnet, can be changed)
    const network = process.env.SUI_NETWORK || 'testnet';
    const client = new SuiClient({ url: getFullnodeUrl(network as any) });

    // Create transaction
    const tx = new Transaction();
    tx.setGasBudget(Number(GAS_BUDGET));
    const vecSet = prepareAddressVecSet(tx, MEMBERS);
    // Build the move call
    tx.moveCall({
      target: `${PACKAGE_ID}::${MODULE}::${FUNCTION}`,
      arguments: [
        tx.object(UPGRADE_CAP_OBJECT_ID),
        tx.pure.u64(THRESHOLD),
        vecSet
      ],
    });

    console.log('Transaction details:');
    console.log(`  Package: ${PACKAGE_ID}`);
    console.log(`  Module: ${MODULE}`);
    console.log(`  Function: ${FUNCTION}`);
    console.log(`  UpgradeCap Object: ${UPGRADE_CAP_OBJECT_ID}`);
    console.log(`  Threshold: ${THRESHOLD}`);
    console.log(`  Members: ${MEMBERS.length} addresses`);
    console.log(`  Gas Budget: ${GAS_BUDGET}\n`);

    // Sign and execute transaction
    console.log('Signing and executing transaction...');
    const result = await client.signAndExecuteTransaction({
      signer: keypair,
      transaction: tx,
      options: {
        showEffects: true,
        showObjectChanges: true,
      },
    });

    console.log('\n✓ Transaction completed successfully!');
    console.log(`\nDigest: ${result.digest}`);
    console.log(`Status: ${result.effects?.status?.status}`);

    if (result.objectChanges) {
      console.log('\nObject Changes:');
      result.objectChanges.forEach((change, i) => {
        console.log(`  ${i + 1}. ${change.type}: ${change.version || 'N/A'}`);
      });
    }

    return result;
  } catch (error: any) {
    console.error('\n✗ Transaction failed!');
    console.error(`Error: ${error!.message}`);

}
}

// Run the script
executeTransaction();