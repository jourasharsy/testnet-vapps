# Morpheus DepositPool — Self-Referral Reward Manipulation (PoC)

Bug bounty PoC for the Morpheus (mor.org) Capital `DepositPool` self-referral reward
manipulation. See `report.md` (1-page report) and `POC.md` (details + mainnet-fork repro).

## Run
```bash
# install foundry if needed: curl -L https://foundry.paradigm.xyz | bash && foundryup
forge test --match-contract SelfReferralTest -vv
```
One command, no RPC needed for the isolated PoC. Expect 4/4 PASS:
```
[PASS] test_Control_NoReferral_FairSplit()          // 50/50 baseline
[PASS] test_SelfReferral_EmptyTiers_CurrentState()  // 24.9 bps over-earn (LIVE state)
[PASS] test_SelfReferral_OverEarning()              // 145.6 bps over-earn (5% tier)
[PASS] test_SelfReferral_DominantStake()            // 91.74% capture (10x + 5% tier)
```

## Layout
- `src/contracts/capital-protocol/DepositPool.sol` — **real target source** (bug site).
- `src/contracts/libs/ReferrerLib.sol` — **real target source** (bug site).
- `src/contracts/libs/LockMultiplierMath.sol`, `LogExpMath.sol` — real target source.
- `src/contracts/interfaces/...` — real target interfaces.
- `src/mocks/` — minimal `MockDistributor` / `MockRewardPool` / `MockToken` / `MockMOR`
  (external deps only; the bug is NOT in these).
- `test/SelfReferral.t.sol` — the PoC.
- `lib/` — forge-std, openzeppelin, solidity-lib (dependencies, included so it builds offline).

## Target (in scope, Appendix A)
- DepositPool stETH/WSTETH proxy: `0x47176B2Af9885dC6C4575d4eFd63895f7Aaa4790` (ERC1967)
- Shared implementation: `0xdB10dAEF167eA2233Ba6811457dD24D676FbD670`
- Distributor: `0xDf1AC1AC255d91F5f4B1E3B4Aef57c5350F64C7A`
