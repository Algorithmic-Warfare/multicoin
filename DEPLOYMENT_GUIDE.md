# Deploying Multicoin with Quorum Upgrade Governance

This guide walks you through deploying the multicoin package with a 2-of-3 quorum upgrade governance system.

## Overview

The deployment process consists of:

1. **Quorum Package**: A governance system that wraps the `UpgradeCap` and requires multiple approvers to authorize upgrades
2. **Multicoin Package**: The main ERC-1155-style multi-asset contract
3. **Quorum Setup**: Connecting the multicoin's `UpgradeCap` to the quorum governance

## Prerequisites

- Node.js 18+ and yarn/npm installed
- Sui CLI installed (`sui --version`)
- A funded wallet on Sui testnet
- Private key exported as environment variable

## Configuration

The deployment is configured for a **2-of-3 multisig** with these voter addresses:

```
Voter 1: 0xc2aa8506eab3adbc54597bfefd7c7f2ed7527e6f704a888744697ba07812c92e
Voter 2: 0xf30f05a4c0d8918ce9b811e3e8a7e59513917b60326a17df65f7e40edeb1d36a
Voter 3: 0x0512b609c3adc944c9336112ecf38f442f585f09735c898e403a97aeae569776
```

To change these, edit `scripts/deploy-with-quorum.ts`:
```typescript
const VOTERS = [
    '0x...', // Your voter addresses
];
const REQUIRED_VOTES = 2; // Number of approvals needed
```

## Step-by-Step Deployment

### 1. Install Dependencies

```bash
# From multicoin-example root
yarn install

# Or if using npm
npm install
```

### 2. Set Environment Variables

```bash
export SUI_NETWORK=testnet
export SUI_RPC_URL=https://fullnode.testnet.sui.io:443
export SUI_PRIVATE_KEY=your_private_key_hex
```

**Note**: Your private key should be a 64-character hex string (without 0x prefix).

### 3. Verify Wallet is Funded

```bash
# Get your address
sui client active-address

# Check balance (need at least 0.5 SUI for deployment)
sui client gas
```

If you need testnet SUI:
```bash
sui client faucet
```

### 4. Run Deployment

```bash
yarn deploy:quorum
```

The script will:
- ✅ Build the quorum_upgrade_v2 package
- ✅ Publish quorum_upgrade_v2 to testnet
- ✅ Update multicoin Move.toml with the quorum package ID
- ✅ Build the multicoin package
- ✅ Publish multicoin and create QuorumUpgrade in single transaction
- ✅ Save deployment info to `deployments/testnet-deployment.json`

### 5. Verify Deployment

After successful deployment, you'll see output like:

```
✨ Deployment complete!

📋 Summary:
   Quorum Package: 0xABCD...
   Multicoin Package: 0x1234...
   QuorumUpgrade Object: 0x5678...
   Governance: 2-of-3 multisig
```

Check the deployment file:
```bash
cat deployments/testnet-deployment.json
```

## What Gets Created

### 1. Quorum Upgrade V2 Package
**Package ID**: Saved in deployment file  
**Purpose**: Provides the governance framework

**Key Modules**:
- `quorum_upgrade`: Core quorum management
- `proposal`: Generic proposal system
- `upgrade`: Package upgrade proposals
- `add_voter`, `remove_voter`, etc.: Governance proposals

### 2. Multicoin Package
**Package ID**: Saved in deployment file  
**Purpose**: Your main application package (ERC-1155 style multi-asset system)

### 3. QuorumUpgrade Shared Object
**Object ID**: Saved in deployment file  
**Purpose**: Wraps the multicoin package's `UpgradeCap`

**Configuration**:
- Required votes: 2
- Total voters: 3
- Voters: The 3 addresses specified above

## How Upgrades Work

Once deployed, the `UpgradeCap` for multicoin is locked inside the `QuorumUpgrade` object. To upgrade:

### Step 1: Voter Creates Upgrade Proposal

Any of the 3 voters can create an upgrade proposal:

```typescript
import { Transaction } from '@mysten/sui/transactions';

const tx = new Transaction();

// Build new version and get digest
// sui move build --dump-bytecode-as-base64
const digest = [...]; // From build output

// Create upgrade proposal
const proposal = tx.moveCall({
    target: `${QUORUM_PACKAGE}::proposal::new`,
    arguments: [
        tx.object(QUORUM_UPGRADE_OBJECT_ID),
        tx.moveCall({
            target: `${QUORUM_PACKAGE}::upgrade::new`,
            arguments: [tx.pure.vector('u8', digest)],
        }),
        tx.pure.vector('String', []), // metadata
    ],
    typeArguments: [`${QUORUM_PACKAGE}::upgrade::Upgrade`],
});

tx.transferObjects([proposal], voter1Address);
```

### Step 2: Other Voters Vote

The second voter votes to reach quorum:

```typescript
const tx = new Transaction();

tx.moveCall({
    target: `${QUORUM_PACKAGE}::proposal::vote`,
    arguments: [
        tx.object(PROPOSAL_ID),
        tx.object(QUORUM_UPGRADE_OBJECT_ID),
    ],
    typeArguments: [`${QUORUM_PACKAGE}::upgrade::Upgrade`],
});
```

### Step 3: Execute Upgrade

Once 2 votes are reached, anyone can execute:

```typescript
const tx = new Transaction();

const ticket = tx.moveCall({
    target: `${QUORUM_PACKAGE}::upgrade::execute`,
    arguments: [
        tx.object(PROPOSAL_ID),
        tx.object(QUORUM_UPGRADE_OBJECT_ID),
    ],
});

const receipt = tx.upgrade({
    modules: newModules,
    dependencies: newDependencies,
    package: MULTICOIN_PACKAGE_ID,
    ticket,
});

tx.moveCall({
    target: `${QUORUM_PACKAGE}::quorum_upgrade::commit_upgrade`,
    arguments: [
        tx.object(QUORUM_UPGRADE_OBJECT_ID),
        receipt,
    ],
});
```

## Governance Operations

Voters can also propose changes to the quorum itself:

### Add a Voter (Change to 2-of-4)

```typescript
const addVoterData = tx.moveCall({
    target: `${QUORUM_PACKAGE}::add_voter::new`,
    arguments: [
        tx.object(QUORUM_UPGRADE_OBJECT_ID),
        tx.pure.address(NEW_VOTER),
        tx.pure.option('u64', 3), // Update threshold to 3-of-4
    ],
});

const proposal = tx.moveCall({
    target: `${QUORUM_PACKAGE}::proposal::new`,
    arguments: [
        tx.object(QUORUM_UPGRADE_OBJECT_ID),
        addVoterData,
        tx.pure.vector('String', []),
    ],
    typeArguments: [`${QUORUM_PACKAGE}::add_voter::AddVoter`],
});
```

### Remove a Voter

```typescript
const removeVoterData = tx.moveCall({
    target: `${QUORUM_PACKAGE}::remove_voter::new`,
    arguments: [
        tx.object(QUORUM_UPGRADE_OBJECT_ID),
        tx.pure.address(VOTER_TO_REMOVE),
        tx.pure.option('u64', 2), // Keep 2-of-2
    ],
});
```

### Replace a Voter (Key Rotation)

```typescript
const replaceVoterData = tx.moveCall({
    target: `${QUORUM_PACKAGE}::replace_voter::new`,
    arguments: [
        tx.object(QUORUM_UPGRADE_OBJECT_ID),
        tx.pure.address(NEW_VOTER),
        tx.pure.address(OLD_VOTER),
    ],
});
```

### Update Threshold Only

```typescript
const updateThresholdData = tx.moveCall({
    target: `${QUORUM_PACKAGE}::update_threshold::new`,
    arguments: [
        tx.object(QUORUM_UPGRADE_OBJECT_ID),
        tx.pure.u64(3), // Change to 3-of-3
    ],
});
```

## Self-Replacement

Any voter can replace their own address without a proposal:

```typescript
const tx = new Transaction();

tx.moveCall({
    target: `${QUORUM_PACKAGE}::quorum_upgrade::replace_self`,
    arguments: [
        tx.object(QUORUM_UPGRADE_OBJECT_ID),
        tx.pure.address(NEW_ADDRESS),
    ],
});
```

This is useful for key rotation.

## Troubleshooting

### Build Fails

```bash
# Clean build artifacts
rm -rf packages/*/build

# Try building manually
cd packages/quorum_upgrade_v2
sui move build

cd ../multicoin
sui move build
```

### Transaction Fails: "Insufficient Gas"

You need more SUI in your wallet:
```bash
sui client faucet
```

### "ModuleNotFound" Error

The quorum package ID in `multicoin/Move.toml` may be incorrect. Re-run the deployment script which will update it automatically.

### Wrong Network

Ensure your environment variables match:
```bash
sui client active-env  # Should show 'testnet'
echo $SUI_NETWORK      # Should be 'testnet'
```

## Security Considerations

1. **Voter Key Security**: The 3 voter addresses control all upgrades. Secure these private keys with hardware wallets or multi-party computation (MPC).

2. **Threshold Choice**: 2-of-3 provides redundancy (1 key can be lost) while preventing unilateral action. Consider your security vs. availability tradeoff.

3. **Voter Rotation**: Use `replace_self()` or governance proposals to rotate compromised keys.

4. **Upgrade Policy**: The system uses `COMPATIBLE` policy by default (additive changes only). For breaking changes, use `ADDITIVE` or `DEP_ONLY` policies.

## Next Steps

After deployment:

1. **Test the System**: Create a test upgrade proposal on testnet
2. **Document Procedures**: Share this guide with all 3 voters
3. **Key Ceremony**: Ensure all voters have secure access to their private keys
4. **Monitoring**: Set up alerts for proposal creation and voting events

## Support

For questions or issues:
- Review the [Quorum Upgrade Documentation](../CONTEXTS/quorum_upgrade.md)
- Check [Sui Move documentation](https://docs.sui.io/guides/developer/first-app/write-package)
- Examine transaction details on [Sui Explorer](https://suiexplorer.com/?network=testnet)

---

**Remember**: The deployment process is irreversible. The `UpgradeCap` will be permanently locked in the quorum. Ensure all voters are ready before proceeding.
