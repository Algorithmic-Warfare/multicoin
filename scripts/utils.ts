import { TransactionBlock, TransactionArgument } from '@mysten/sui.js/transactions';

/**
 * Construct a VecSet of addresses for quorum voting.
 * 
 * @param txb - The transaction block to add move calls to
 * @param voters - Array of voter addresses
 * @returns TransactionArgument representing the VecSet
 */
export const prepareAddressVecSet = (txb: TransactionBlock, voters: string[]): TransactionArgument => {
    const vecSet = txb.moveCall({
        target: `0x2::vec_set::empty`,
        typeArguments: ['address']
    });

    for (let voter of voters) {
        txb.moveCall({
            target: `0x2::vec_set::insert`,
            arguments: [
                vecSet,
                txb.pure.address(voter)
            ],
            typeArguments: ['address']
        });
    }

    return vecSet;
};

/**
 * Validate that addresses are in correct Sui format
 * 
 * @param addresses - Array of addresses to validate
 * @throws Error if any address is invalid
 */
export const validateAddresses = (addresses: string[]): void => {
    for (const addr of addresses) {
        if (!addr.startsWith('0x') || addr.length !== 66) {
            throw new Error(`Invalid Sui address format: ${addr}. Expected format: 0x followed by 64 hex characters`);
        }
    }
};

/**
 * Normalize Sui address to ensure it has proper length (0x + 64 chars)
 * 
 * @param address - Address to normalize
 * @returns Normalized address
 */
export const normalizeAddress = (address: string): string => {
    if (!address.startsWith('0x')) {
        address = '0x' + address;
    }
    // Pad with zeros if needed
    const hexPart = address.slice(2);
    return '0x' + hexPart.padStart(64, '0');
};

/**
 * Get the UpgradeCap object from publish transaction
 * 
 * @param publishTxResult - Result from package publish transaction
 * @returns UpgradeCap object ID
 */
export const getUpgradeCapFromPublish = (publishTxResult: any): string | null => {
    const upgradeCap = publishTxResult.objectChanges?.find(
        (obj: any) => obj.objectType?.endsWith('::package::UpgradeCap')
    );
    return upgradeCap?.objectId || null;
};

/**
 * Extract package ID from publish transaction
 * 
 * @param publishTxResult - Result from package publish transaction
 * @returns Package ID
 */
export const getPackageIdFromPublish = (publishTxResult: any): string | null => {
    const publishedPackage = publishTxResult.objectChanges?.find(
        (obj: any) => obj.type === 'published'
    );
    return publishedPackage?.packageId || null;
};

/**
 * Wait for transaction confirmation
 * 
 * @param digest - Transaction digest to wait for
 * @param client - Sui client instance
 * @param maxRetries - Maximum number of retries (default: 30)
 * @param delayMs - Delay between retries in milliseconds (default: 1000)
 */
export const waitForTransaction = async (
    digest: string,
    client: any,
    maxRetries: number = 30,
    delayMs: number = 1000
): Promise<any> => {
    for (let i = 0; i < maxRetries; i++) {
        try {
            const txResult = await client.getTransactionBlock({
                digest,
                options: {
                    showEffects: true,
                    showObjectChanges: true,
                    showEvents: true,
                }
            });
            
            if (txResult.effects?.status?.status === 'success') {
                return txResult;
            } else if (txResult.effects?.status?.status === 'failure') {
                throw new Error(`Transaction failed: ${txResult.effects?.status?.error}`);
            }
        } catch (error: any) {
            if (i === maxRetries - 1) {
                throw new Error(`Transaction not confirmed after ${maxRetries} retries: ${error.message}`);
            }
        }
        
        await new Promise(resolve => setTimeout(resolve, delayMs));
    }
    
    throw new Error(`Transaction ${digest} not confirmed`);
};
