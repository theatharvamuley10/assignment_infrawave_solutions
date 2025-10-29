MOCK TOKEN ON ETHEREUM = 0xe0cBafc8Ba24e1A7929883E146fF5E0f26249d12
STAKE CONTRACT ON ETHEREUM = 0x085881d1A2a676646aB36623C79C9786C13A57a1

Will deploy on BNB testnet as soon as I get my hands on some tBnB

---

# StakingNFT – Simplified Staking System on BSC Testnet

A lightweight staking system built for Binance Smart Chain (BSC) Testnet. Each stake is represented by an ERC‑721 NFT position. Holders of these NFTs can claim daily ROI or unstake their tokens directly, ensuring transparent ownership and security through NFT-based positions.

---

### Features

- **NFT-based positions:** Each user stake mints an ERC‑721 token representing ownership of that position.
- **Daily ROI:** 1% return on investment every 24 hours, based on staked principal.
- **Referral rewards:** 0.5% of the referred user’s stake paid instantly from their deposit.
- **Claim interval:** Only one ROI claim is allowed per 24 hours per user.
- **Permit-enabled deposits:** Supports EIP‑2612 `permit` for gasless approval (if token supports it).
- **Emergency safety:** Includes `pause()`, `emergencyWithdraw()`, and token recovery mechanisms for safety.

---

### Contract Overview

| Contract                       | Description                                                          |
| ------------------------------ | -------------------------------------------------------------------- |
| **StakingNFT.sol**             | Core staking logic, NFT position management, ROI and reward handling |
| **TestToken.sol** _(optional)_ | A simple BEP‑20 token for testing deposits and claims                |

---

### Key Parameters

| Parameter         | Default Value                    | Description                                |
| ----------------- | -------------------------------- | ------------------------------------------ |
| Daily ROI         | 1% (`DAILY = 100`)               | 1% reward per 24h                          |
| Referral Reward   | 0.5% (`REFERRAL = 50`)           | Paid instantly from referee’s deposit      |
| Claim Interval    | 24 hours                         | Minimum gap between consecutive ROI claims |
| Max Daily ROI     | 5% (`MAX_DAILY_ROI = 500`)       | Safety cap                                 |
| Max Referral Rate | 10% (`MAX_REFERRAL_RATE = 1000`) | Safety cap                                 |

---

### Core Functions

| Function                                  | Purpose                                        |
| ----------------------------------------- | ---------------------------------------------- |
| `stake(amount, referrer)`                 | Stake BEP‑20 tokens and mint NFT position      |
| `stakeWithPermit(...)`                    | Stake using EIP‑2612 permit (gasless approval) |
| `claim(stakeId, beneficiary)`             | Claim 1% ROI (only once every 24h)             |
| `unstake(stakeId, beneficiary)`           | Withdraw principal and accrued ROI             |
| `emergencyWithdraw(stakeId, beneficiary)` | Withdraw only principal (no ROI) when paused   |

---

### Deployment Instructions

1. **Deploy your test token (if not using an existing one):**

   ```bash
   npx hardhat run scripts/deploy_token.js --network bsctest
   ```

2. **Deploy the staking contract:**

   ```bash
   npx hardhat run scripts/deploy_staking.js --network bsctest
   ```

3. **Verify deployment:**

   - `stakingToken` = address of BEP‑20 token
   - `stakingContract` = address returned after deployment

4. **Fund the contract for ROI payouts:**
   ```solidity
   stakingContract.fundContract(amount);
   ```

---

### Example Workflow (Deposit → Claim → Unstake)

1. **Approve tokens and stake:**
   ```solidity
   stake(amount, referrer);
   ```
2. **Wait 24 hours and claim ROI:**
   ```solidity
   claim(stakeId, msg.sender);
   ```
3. **Unstake principal and any pending rewards:**
   ```solidity
   unstake(stakeId, msg.sender);
   ```

---

### Tests

Basic test coverage includes:

- Deposit flow with optional referral
- ROI claiming with 24h interval enforcement
- Unstaking with principal and accrued ROI retrieval

Run tests:

```bash
npx hardhat test
```

---

### Deliverables

- **GitHub Repository:** Full contracts, deployment scripts, and tests
- **BSC Testnet Deployments:**
  - Staking Contract: `<YOUR_STAKING_CONTRACT_ADDRESS>`
  - Test Token (if deployed): `<YOUR_TEST_TOKEN_ADDRESS>`
