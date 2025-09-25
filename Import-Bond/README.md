# Automated Customs Bonding Smart Contract

## Overview

The Automated Customs Bonding Smart Contract is a blockchain-based solution for managing customs bonds with automated release mechanisms upon compliance verification. This contract facilitates secure, transparent, and efficient customs bond processing by automating the verification and release process through authorized customs officials.

## Features

- **Automated Bond Management**: Create, verify, and release customs bonds programmatically
- **Compliance Verification**: Authorized customs officials can verify compliance and trigger automatic fund release
- **Secure Fund Handling**: Bonds are held securely in the contract until compliance is verified or deadline expires
- **Authorization System**: Only authorized customs officials can perform compliance verifications
- **Expiration Handling**: Automatic forfeiture of bonds that exceed compliance deadlines
- **Transparent Tracking**: Complete audit trail of all bond activities and verifications

## Contract Architecture

### Core Components

1. **Bond Management System**: Handles creation, tracking, and status updates of customs bonds
2. **Authorization Framework**: Manages authorized customs officials who can verify compliance
3. **Compliance Verification**: Processes and records compliance status with detailed documentation
4. **Automated Processing**: Automatically releases or forfeits bonds based on compliance results

### Data Structures

- **bonds**: Main mapping storing complete bond information
- **authorized-officials**: Tracking of authorized customs officials
- **compliance-verifications**: Detailed compliance verification records

## Installation and Deployment

### Prerequisites

- Stacks blockchain environment
- Clarity smart contract deployment tools
- Sufficient STX tokens for contract deployment and bond creation

### Deployment Steps

1. Deploy the contract to the Stacks blockchain
2. Initialize contract owner (automatically set to deployer address)
3. Authorize initial customs officials using `authorize-official` function

## Usage Guide

### For Importers

#### Creating a Bond

```clarity
(contract-call? .customs-bond create-bond
  u10000000  ;; Bond amount (10 STX)
  u1000      ;; Compliance deadline (block height)
  0x1234...  ;; Customs declaration hash
  "Standard import compliance required"  ;; Release conditions
)
```

**Parameters:**
- `bond-amount`: Amount in microSTX (minimum 1,000,000 microSTX = 1 STX)
- `compliance-deadline`: Block height by which compliance must be verified
- `customs-declaration-hash`: SHA-256 hash of customs declaration documents
- `release-conditions`: Text description of what compliance requires

### For Customs Officials

#### Verifying Compliance

```clarity
(contract-call? .customs-bond verify-compliance
  u1         ;; Bond ID
  u1         ;; Compliance result (1=verified, 2=failed)
  "All documentation verified and approved"  ;; Verification notes
  0x5678...  ;; Documents hash
)
```

**Compliance Results:**
- `u1` (COMPLIANCE-VERIFIED): Compliance verified, bond will be released
- `u2` (COMPLIANCE-FAILED): Compliance failed, bond will be forfeited

### For Contract Administrator

#### Authorizing Officials

```clarity
(contract-call? .customs-bond authorize-official 'SP1234...)
```

#### Processing Expired Bonds

```clarity
(contract-call? .customs-bond process-expired-bond u1)
```

#### Withdrawing Forfeited Funds

```clarity
(contract-call? .customs-bond withdraw-forfeited-funds u5000000)
```

## Bond Lifecycle

### 1. Bond Creation
- Importer calls `create-bond` with required parameters
- Bond amount is transferred from importer to contract
- Bond status set to ACTIVE with COMPLIANCE-PENDING

### 2. Compliance Period
- Bond remains active until compliance deadline
- Authorized officials can verify compliance during this period

### 3. Compliance Verification
- Authorized official calls `verify-compliance`
- Bond automatically released (if compliant) or forfeited (if non-compliant)

### 4. Expiration Handling
- Bonds exceeding compliance deadline can be processed as expired
- Expired bonds are automatically forfeited

## Bond Status Values

- **STATUS-ACTIVE** (u1): Bond is active and awaiting compliance verification
- **STATUS-RELEASED** (u2): Bond has been released back to importer after compliance verification
- **STATUS-FORFEITED** (u3): Bond has been forfeited due to non-compliance or expiration

## Compliance Status Values

- **COMPLIANCE-PENDING** (u0): Awaiting compliance verification
- **COMPLIANCE-VERIFIED** (u1): Compliance has been verified and approved
- **COMPLIANCE-FAILED** (u2): Compliance verification failed

## Error Codes

- **ERR-UNAUTHORIZED-ACCESS** (u100): Caller not authorized for this operation
- **ERR-BOND-NOT-FOUND** (u101): Specified bond ID does not exist
- **ERR-BOND-ALREADY-EXISTS** (u102): Bond with this ID already exists
- **ERR-INSUFFICIENT-BOND-AMOUNT** (u103): Bond amount below minimum requirement
- **ERR-BOND-NOT-ACTIVE** (u104): Bond is not in active status
- **ERR-BOND-ALREADY-RELEASED** (u105): Bond has already been released
- **ERR-BOND-ALREADY-FORFEITED** (u106): Bond has already been forfeited
- **ERR-INVALID-COMPLIANCE-STATUS** (u107): Invalid compliance status provided
- **ERR-COMPLIANCE-PERIOD-EXPIRED** (u108): Compliance deadline has passed
- **ERR-INVALID-BOND-AMOUNT** (u109): Invalid bond amount specified
- **ERR-TRANSFER-FAILED** (u110): STX transfer operation failed

## Read-Only Functions

### Query Bond Information

```clarity
(contract-call? .customs-bond get-bond-info u1)
```

### Check Compliance Verification Details

```clarity
(contract-call? .customs-bond get-compliance-verification u1)
```

### Verify Official Authorization

```clarity
(contract-call? .customs-bond is-authorized-official 'SP1234...)
```

### Get Contract Statistics

```clarity
(contract-call? .customs-bond get-total-active-bonds)
(contract-call? .customs-bond get-next-bond-id)
(contract-call? .customs-bond get-contract-balance)
```

### Check Bond Expiration Status

```clarity
(contract-call? .customs-bond is-bond-expired u1)
```

## Security Considerations

### Access Control
- Only contract owner can authorize/revoke customs officials
- Only authorized officials can verify compliance
- Only contract owner can withdraw forfeited funds

### Fund Security
- Bond funds are held securely in the contract until release or forfeiture
- Automatic processing prevents manual interference with fund distribution
- Clear audit trail for all fund movements

### Validation
- Minimum bond amount enforced (1 STX)
- Compliance deadline must be in the future
- Comprehensive input validation on all functions

## Best Practices

### For Importers
- Ensure sufficient STX balance before creating bonds
- Set realistic compliance deadlines
- Maintain secure copies of customs declaration documents
- Monitor bond status regularly

### For Customs Officials
- Verify all documentation thoroughly before marking compliance
- Include detailed verification notes
- Process compliance verifications promptly
- Maintain secure document hashes

### For Administrators
- Regularly review and audit authorized officials list
- Monitor expired bonds and process them appropriately
- Keep track of contract balance and forfeited funds
- Implement additional access controls as needed

## Integration Examples

### Web3 Integration

```javascript
// Example using Stacks.js
import { makeContractCall, broadcastTransaction } from '@stacks/transactions';

const createBond = async (bondAmount, deadline, declarationHash, conditions) => {
  const txOptions = {
    contractAddress: 'SP...',
    contractName: 'customs-bond',
    functionName: 'create-bond',
    functionArgs: [
      uintCV(bondAmount),
      uintCV(deadline),
      bufferCV(declarationHash),
      stringUtf8CV(conditions)
    ],
    senderKey: privateKey,
    network
  };
  
  const transaction = await makeContractCall(txOptions);
  const result = await broadcastTransaction(transaction, network);
  return result;
};
```

## Monitoring and Analytics

The contract provides several read-only functions for monitoring:

- Track total active bonds over time
- Monitor compliance verification rates
- Analyze bond forfeiture patterns
- Audit official authorization changes

## Support and Maintenance

### Regular Maintenance Tasks
- Monitor contract balance and active bonds
- Review expired bonds for processing
- Audit authorized officials list
- Check for any stuck or problematic bonds

### Upgrading Considerations
- Contract is immutable once deployed
- New versions require new contract deployment
- Data migration strategies should be planned in advance
- Maintain backward compatibility for existing bonds