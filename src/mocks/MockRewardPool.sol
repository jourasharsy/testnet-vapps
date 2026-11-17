// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Minimal IRewardPool surface used by DepositPool.
contract MockRewardPool {
    bool public isPublic = true;

    function isRewardPoolExist(uint256) external pure returns (bool) {
        return true;
    }

    function isRewardPoolPublic(uint256) external view returns (bool) {
        return isPublic;
    }

    function onlyExistedRewardPool(uint256) external pure {}

    function onlyPublicRewardPool(uint256) external view {
        require(isPublic, "MRP: not public");
    }

    function getPeriodRewards(uint256, uint128, uint128) external pure returns (uint256) {
        return 0;
    }
}
