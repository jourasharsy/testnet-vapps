# Morpheus Bug Bounty — DepositPool Self-Referral Reward Manipulation

## TARGET
`DepositPool` (shared impl `0xdB10dAEF167eA2233Ba6811457dD24D676FbD670`), all 5 in-scope
mainnet proxies — PoC run against the **stETH/WSTETH pool `0x47176B2Af9885dC6C4575d4eFd63895f7Aaa4790`**
(ERC1967). Functions: `stake()` → `_stake()` → `_getUserTotalMultiplier()` / `_applyReferrerTier()`
(`sc/contracts/capital-protocol/DepositPool.sol`, `sc/contracts/libs/ReferrerLib.sol`).

## INVARIANT
Two users who stake the **same amount** with the **same lock end** must accrue the **same reward
share** (identical `virtualDeposited`). A referrer bonus must compensate a *third party* who actually
referred a new staker — it must never be payable to the staker for referring *themselves*.

## IMPACT
**Reward over-issuance to the staker / quantified loss to co-stakers.** A staker who passes
`referrer_ = msg.sender` (self-referral) receives BOTH:
1. the **+1% base `REFERRAL_MULTIPLIER`** on their own stake's virtual weight
   (`ReferrerLib.getReferralMultiplier` returns `1.01·PRECISION` for any non-zero referrer), and
2. the **referrer-tier reward** on the referred amount (`_applyReferrerTier`), where the "referrer"
   is themselves.

Measured over-earning vs a fair split (identical stakes, `claimLockEnd = 0`, `R = 1000 MOR`):

| Scenario (on-chain state)            | Attacker | Honest | Attacker over-earns |
|--------------------------------------|----------|--------|---------------------|
| **Empty tiers (CURRENT mainnet)**    | 50.2488% | 49.7512% | **24.9 bps**        |
| 5% referrer tier configured          | 51.4563% | 48.5437% | **145.6 bps**       |
| Dominant 10× stake + 5% tier         | 91.74%   | 8.26%  | captures ~all yield |

Bounded redistribution (total minted ≤ R, **no over-mint, no principal loss**). Scales with the
attacker's pool dominance and the owner-configured tier multiplier. stETH pool TVL ≈ 3,580 WSTETH.
**Current mainnet impact is Low** (tiers are empty → only the +1% base applies); it becomes material
the moment `editReferrerTiers` is used with non-trivial multipliers.

## PRECONDITIONS
- None beyond normal staking. Attacker is **any unprivileged EOA** (no owner/admin/multisig).
- Current mainnet: `referrerTiers[pool]` is empty for all 5 pools (verified via storage slot 208),
  so the +1% base bonus is the live vector. No setup, no owner action required.

## ATTACK
1. Attacker holds WSTETH, approves the `Distributor`.
2. `pool.stake(rewardPoolIndex, D, 0, attacker)` — **`referrer_ = msg.sender`** (self-referral).
3. An honest user stakes the same `D` with `referrer_ = address(0)`.
4. Rewards accrue (real WSTETH yield → MOR). Both call `pool.claim(...)`.
5. Attacker's MOR claim > honest user's MOR claim for identical stakes → loss to co-stakers.
   (With tiers configured, attacker additionally calls `pool.claimReferrerTier(...)` as themselves.)

## POC
Foundry, `forge test`. Real `DepositPool` + `ReferrerLib` source; only the external `Distributor` /
`RewardPool` are mocked (they are not where the bug lives). 4 tests, all pass:

```
[PASS] test_Control_NoReferral_FairSplit()          // 50/50 baseline
[PASS] test_SelfReferral_EmptyTiers_CurrentState()  // 24.9 bps over-earn (LIVE state)
[PASS] test_SelfReferral_OverEarning()              // 145.6 bps over-earn (5% tier)
[PASS] test_SelfReferral_DominantStake()            // 91.74% capture (10x + 5% tier)
```

The loss is **asserted** (`assertGt(attacker, R/2)`, `assertLt(honest, R/2)`), not merely printed.
Mainnet-fork repro (pinned block, one command, RPC-only) and full source in the linked repo.

## FIX
Reject self-referral at the entry point — the bonus must only apply for a genuine third party:

```solidity
// in stake() / _stake(), before applying the referrer multiplier:
require(referrer_ != msg.sender, "DS: self-referral not allowed");
```

Defense-in-depth: in `_applyReferrerTier`, skip the referrer-tier credit when
`newReferrer_ == user_`. Existing on-chain self-referrers (if any) should be migrated so their
`userData.referrer` is reset to `address(0)` on upgrade.
