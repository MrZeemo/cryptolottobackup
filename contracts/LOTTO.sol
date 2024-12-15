// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

contract Lottery is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, VRFConsumerBaseV2 {
    using SafeERC20 for IERC20;

    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_keyHash;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    mapping(uint256 => uint256) public requestToLotteryId;

    IERC20 public tether;

    uint256 public constant FEE_PERCENT = 5;
    address public constant FEE_RECIPIENT = 0xB55948e70B8Ef500878F7E75c599CeDd01246acE;

    struct LotteryInfo {
        uint256 id;
        uint256 entryFee;
        uint256 targetPrizePool;
        uint256 totalPrizePool;
        uint256 thresholdAmount;
        bool thresholdMet;
        uint256 deadlineTime;
        bool lotteryEnded;
        bool prizeDistributed;
        uint256 totalEntries;
        address[] winners;
        address[] uniqueUsers;
    }

    mapping(uint256 => LotteryInfo) public lotteries;
    uint256 public currentLotteryId;
    mapping(uint256 => mapping(address => uint256)) public entries;
    mapping(uint256 => mapping(address => uint256)) public winningsMap;

    event LotteryCreated(uint256 indexed lotteryId, uint256 entryFee, uint256 targetPrizePool);
    event LotteryEntered(uint256 indexed lotteryId, address indexed player, uint256 amount, uint256 numEntries);
    event ThresholdMet(uint256 indexed lotteryId, uint256 thresholdAmount, uint256 deadlineTime);
    event LotteryEnded(uint256 indexed lotteryId, uint256 totalPrizePool);
    event WinnersSelected(uint256 indexed lotteryId, address[] winners);
    event PrizeClaimed(uint256 indexed lotteryId, address indexed winner, uint256 amount);
    event FeeCollected(uint256 indexed lotteryId, address indexed owner, uint256 amount);
    event PrizeDistributed(uint256 indexed lotteryId, uint256 prizePoolAfterFee);

    constructor(
        address _vrfCoordinator,
        uint64 _subscriptionId,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        address _tetherAddress
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        i_vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        i_subscriptionId = _subscriptionId;
        i_keyHash = _keyHash;
        i_callbackGasLimit = _callbackGasLimit;
        tether = IERC20(_tetherAddress);
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();
    }

    function createLottery(uint256 _entryFee, uint256 _targetPrizePool) external onlyOwner {
        require(_entryFee > 0, "Entry fee must be greater than zero");
        require(_targetPrizePool > 0, "Target prize pool must be greater than zero");

        currentLotteryId++;
        uint256 threshold = (_targetPrizePool * 33) / 100;

        lotteries[currentLotteryId] = LotteryInfo({
            id: currentLotteryId,
            entryFee: _entryFee,
            targetPrizePool: _targetPrizePool,
            totalPrizePool: 0,
            thresholdAmount: threshold,
            thresholdMet: false,
            deadlineTime: 0,
            lotteryEnded: false,
            prizeDistributed: false,
            totalEntries: 0,
            winners: new address[](0),
            uniqueUsers: new address[](0)
        });

        emit LotteryCreated(currentLotteryId, _entryFee, _targetPrizePool);
    }

    function enterLottery(uint256 _lotteryId, uint256 _numEntries) external nonReentrant whenNotPaused {
        LotteryInfo storage lottery = lotteries[_lotteryId];
        require(_lotteryId > 0 && _lotteryId <= currentLotteryId, "Invalid lottery ID");
        require(!lottery.lotteryEnded, "Lottery has ended");
        require(_numEntries > 0, "Must enter at least one entry");

        uint256 totalCost = lottery.entryFee * _numEntries;
        tether.safeTransferFrom(msg.sender, address(this), totalCost);

        if (entries[_lotteryId][msg.sender] == 0) {
            lottery.uniqueUsers.push(msg.sender);
        }

        entries[_lotteryId][msg.sender] += _numEntries;
        lottery.totalEntries += _numEntries;
        lottery.totalPrizePool += totalCost;

        if (!lottery.thresholdMet && lottery.totalPrizePool >= lottery.thresholdAmount) {
            lottery.thresholdMet = true;
            lottery.deadlineTime = block.timestamp + 24 hours;
            emit ThresholdMet(_lotteryId, lottery.thresholdAmount, lottery.deadlineTime);
        }

        emit LotteryEntered(_lotteryId, msg.sender, totalCost, _numEntries);
    }

    function requestRandomWords(uint256 _lotteryId) external onlyOwner {
        LotteryInfo storage lottery = lotteries[_lotteryId];
        require(lottery.totalEntries > 0, "No entries in the lottery");
        require(lottery.thresholdMet, "Threshold not met");
        require(block.timestamp >= lottery.deadlineTime, "Deadline not reached");
        require(!lottery.lotteryEnded, "Lottery already ended");

        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_keyHash,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );

        requestToLotteryId[requestId] = _lotteryId;
        lottery.lotteryEnded = true;

        emit LotteryEnded(_lotteryId, lottery.totalPrizePool);
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 lotteryId = requestToLotteryId[requestId];
        LotteryInfo storage lottery = lotteries[lotteryId];

        uint256 winnersCount = lottery.totalEntries / 10;
        for (uint256 i = 0; i < winnersCount; i++) {
            uint256 winningIndex = uint256(keccak256(abi.encode(randomWords[0], i))) % lottery.uniqueUsers.length;
            lottery.winners.push(lottery.uniqueUsers[winningIndex]);
        }

        emit WinnersSelected(lotteryId, lottery.winners);
        _distributePrizes(lotteryId);
    }

    function _distributePrizes(uint256 _lotteryId) internal {
        LotteryInfo storage lottery = lotteries[_lotteryId];
        uint256 totalPrizePool = lottery.totalPrizePool;

        uint256 feeAmount = (totalPrizePool * FEE_PERCENT) / 100;
        uint256 prizePoolAfterFee = totalPrizePool - feeAmount;

        tether.safeTransfer(FEE_RECIPIENT, feeAmount);
        emit FeeCollected(_lotteryId, FEE_RECIPIENT, feeAmount);

        // Distribute prizes based on off-chain calculations
        // This part should be implemented in the front-end or a separate service

        lottery.prizeDistributed = true;
        emit PrizeDistributed(_lotteryId, prizePoolAfterFee);
    }

    function distributePrizesManually(uint256 _lotteryId, address[] calldata winners, uint256[] calldata amounts) external onlyOwner {
        require(winners.length == amounts.length, "Winners and amounts length mismatch");
        LotteryInfo storage lottery = lotteries[_lotteryId];
        require(lottery.lotteryEnded, "Lottery not ended");
        require(!lottery.prizeDistributed, "Prizes already distributed");

        for (uint256 i = 0; i < winners.length; i++) {
            winningsMap[_lotteryId][winners[i]] = amounts[i];
        }

        lottery.prizeDistributed = true;
        emit PrizeDistributed(_lotteryId, lottery.totalPrizePool);
    }

    function claimPrize(uint256 _lotteryId) external nonReentrant {
        require(lotteries[_lotteryId].prizeDistributed, "Prizes not yet distributed");
        uint256 winningAmount = winningsMap[_lotteryId][msg.sender];
        require(winningAmount > 0, "No prize to claim");

        winningsMap[_lotteryId][msg.sender] = 0;
        tether.safeTransfer(msg.sender, winningAmount);

        emit PrizeClaimed(_lotteryId, msg.sender, winningAmount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}