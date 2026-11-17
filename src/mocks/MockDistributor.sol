// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDistributor} from "../contracts/interfaces/capital-protocol/IDistributor.sol";

contract MockDistributor is IDistributor {
    using SafeERC20 for IERC20;

    address public rewardPool_;
    address public l1Sender_ = address(0);
    address public morToken;
    IERC20 public depositToken;

    mapping(uint256 => mapping(address => uint256)) public distributedRewards;
    uint256 public totalMinted;

    function setRewardPoolAddr(address v) external {
        rewardPool_ = v;
    }

    function setMOR(address m) external {
        morToken = m;
    }

    function setDepositTokenAddr(address t) external {
        depositToken = IERC20(t);
    }

    // Test helper: directly credit distributed rewards to a deposit pool.
    function addDistributedRewards(uint256 pool, address dp, uint256 amount) external {
        distributedRewards[pool][dp] += amount;
    }

    // ---- IDistributor view getters ----
    function rewardPool() external view override returns (address) {
        return rewardPool_;
    }

    function l1Sender() external view override returns (address) {
        return l1Sender_;
    }

    function chainLinkDataConsumer() external pure override returns (address) {
        return address(0);
    }

    function aavePoolDataProvider() external pure override returns (address) {
        return address(0);
    }

    function aavePoolAddressesProvider() external pure override returns (address) {
        return address(0);
    }

    function aaveRewardsController() external pure override returns (address) {
        return address(0);
    }

    function undistributedRewards() external pure override returns (uint256) {
        return 0;
    }

    function minRewardsDistributePeriod() external pure override returns (uint256) {
        return 0;
    }

    function getDistributedRewards(uint256 pool, address dp) external view override returns (uint256) {
        return distributedRewards[pool][dp];
    }

    // ---- setters (no-ops) ----
    function setChainLinkDataConsumer(address) external override {}

    function setAavePoolDataProvider(address) external override {}

    function setAavePoolAddressesProvider(address) external override {}

    function setAaveRewardsController(address) external override {}

    function setRewardPool(address) external override {}

    function addDepositPool(
        uint256,
        address,
        address,
        string memory,
        Strategy
    ) external override {}

    function updateDepositTokensPrices(uint256) external override {}

    // ---- core flow ----
    function supply(uint256, address user, uint256 amount) external override returns (uint256) {
        depositToken.safeTransferFrom(user, address(this), amount);
        return amount;
    }

    function withdraw(uint256, address user, uint256 amount) external override returns (uint256) {
        depositToken.safeTransfer(user, amount);
        return amount;
    }

    function distributeRewards(uint256) external override {
        // no-op: rewards are credited via addDistributedRewards in the test
    }

    function withdrawYield(uint256, address) external override {}

    function withdrawUndistributedRewards(address, address) external payable override {}

    function claimAaveRewards(
        address[] calldata,
        uint256,
        address,
        address
    ) external pure override returns (uint256) {
        return 0;
    }

    function version() external pure override returns (uint256) {
        return 2;
    }

    function sendMintMessage(uint256, address user, uint256 amount, address) external payable override {
        (bool ok, bytes memory data) = morToken.call(
            abi.encodeWithSignature("mint(address,uint256)", user, amount)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "MD: mint failed");
        totalMinted += amount;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IDistributor).interfaceId;
    }
}
