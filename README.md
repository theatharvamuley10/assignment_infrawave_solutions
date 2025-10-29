MOCK TOKEN ON ETHEREUM = 0xe0cBafc8Ba24e1A7929883E146fF5E0f26249d12

STAKING CONTRACT ON ETHEREUM = 0x085881d1A2a676646aB36623C79C9786C13A57a1

Will deploy on BNB testnet as soon as I get my hands on some tBnB

---

# StakingNFT

A simple staking system. Each stake is represented by an ERC‑721 NFT position. Holders of these NFTs can claim daily or accumulated ROI or unstake their tokens directly, ensuring transparent ownership and security through NFT-based positions.

---

### Features

- NFT-based positions: Each user stake mints an ERC‑721 token representing ownership of that position.
- Daily ROI: 1% return on investment every 24 hours, based on staked principal.
- Referral rewards: 0.5% of the referred user’s stake paid instantly from their deposit.
- Claim interval: Only one ROI claim is allowed per 24 hours per user.
- Permit-enabled deposits: Supports EIP‑2612 `permit` for gasless approval (if token supports it).
- Emergency safety: Includes `pause()`, `emergencyWithdraw()`, and token recovery mechanisms for safety in case a hack occurs.

---

### Contract Overview

| Contract                       | Description                                                          |
| ------------------------------ | -------------------------------------------------------------------- |
| StakingNFT.sol                 | Core staking logic, NFT position management, ROI and reward handling |
| mockBEP20.sol                  | A simple BEP‑20 token for testing deposits and claims                |

---

### Key Parameters

| Parameter         | Default Value                    | Description                                |
| ----------------- | -------------------------------- | ------------------------------------------ |
| Daily ROI         | 1% (`DAILY = 100`)               | 1% reward per 24h                          |
| Referral Reward   | 0.5% (`REFERRAL = 50`)           | Paid instantly from referee’s deposit      |
| Claim Interval    | 24 hours                         | Minimum gap between consecutive ROI claims |
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
