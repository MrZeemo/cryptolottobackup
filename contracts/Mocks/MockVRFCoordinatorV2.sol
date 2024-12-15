// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

contract MockVRFCoordinatorV2 is VRFCoordinatorV2Interface {
    function requestRandomWords(
        bytes32 /* keyHash */,
        uint64 /* subId */,
        uint16 /* minimumRequestConfirmations */,
        uint32 /* callbackGasLimit */,
        uint32 /* numWords */
    ) external pure override returns (uint256 requestId) {
        // Mock implementation
        return 0;
    }

    function getRequestConfig() external pure override returns (uint16, uint32, bytes32[] memory) {
        bytes32[] memory keyhashes = new bytes32[](0);
        return (0, 0, keyhashes);
    }

    function requestSubscriptionOwnerTransfer(uint64 /* subId */, address /* newOwner */) external pure override {}

    function acceptSubscriptionOwnerTransfer(uint64 /* subId */) external pure override {}

    function addConsumer(uint64 /* subId */, address /* consumer */) external pure override {}

    function removeConsumer(uint64 /* subId */, address /* consumer */) external pure override {}

    function cancelSubscription(uint64 /* subId */, address /* to */) external pure override {}

    function pendingRequestExists(uint64 /* subId */) external pure override returns (bool) {
        return false;
    }

    function createSubscription() external pure override returns (uint64 subId) {
        return 0;
    }

    function getSubscription(uint64 /* subId */) external pure override returns (
        uint96 balance,
        uint64 reqCount,
        address owner,
        address[] memory consumers
    ) {
        address[] memory _consumers = new address[](0);
        return (0, 0, address(0), _consumers);
    }

    // This function is not in the VRFCoordinatorV2Interface, so we remove the override keyword
    function fundSubscription(uint64 /* subId */, uint256 /* amount */) external pure {}
}
