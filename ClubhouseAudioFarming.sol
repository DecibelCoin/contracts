// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "abdk-libraries-solidity/ABDKMathQuad.sol";

import "./DecibelCoin.sol";

enum RoomStates { live, finished }

enum ClubMemberRoles { member, leader, admin, owner }

struct RoomMetricsData {
  uint256 durationTime;

  uint256 avListenerTime;
  uint256 avSpeakerTime;
  uint256 avModeratorTime;

  uint256 listenersCount;
  uint256 speakersCount;
  uint256 moderatorsCount;

  uint256 stickiness;

  uint256 totalListenerTime;
  uint256 totalSpeakerTime;
  uint256 totalModeratorTime;

  uint256 roomMembersStakingAmount;
}

struct RoomMetricsDataProcessed {
  bytes16 durationTime;

  bytes16 avListenerTime;
  bytes16 avSpeakerTime;
  bytes16 avModeratorTime;

  bytes16 listenersCount;
  bytes16 speakersCount;
  bytes16 moderatorsCount;

  bytes16 stickiness;

  bytes16 roomMembersStakingAmount;
}

struct Room {
  RoomStates state;

  uint256 id;
  uint256 clubId;

  uint256 durationTime;

  uint256 avListenerTime;
  uint256 avSpeakerTime;
  uint256 avModeratorTime;

  uint256 listenersCount;
  uint256 speakersCount;
  uint256 moderatorsCount;
  uint256 stickiness;

  uint256 totalListenerTime;
  uint256 totalSpeakerTime;
  uint256 totalModeratorTime;

  uint256 roomMembersStakingAmount;

  uint256 reward;
}

struct RoomMemberMetricsData {
  uint256 listenerTime;
  uint256 speakerTime;
  uint256 moderatorTime;
  uint256 roomMemberStakingAmount;
}

struct RoomMember {
  uint256 id;
  address addr;
  uint256 listenerTime;
  uint256 speakerTime;
  uint256 moderatorTime;
  uint256 roomMemberStakingAmount;
  uint256 reward;
}

struct ClubMember {
  ClubMemberRoles role;
  address addr;
  bool isMembershipActive;
}

struct Club {
  uint256 id; 
  address adminAddress;
  uint256 stakingPoolId;
}

struct StakingPoolMember {
  uint256 stakeAmount;
  address addr;
}

struct StakingPool {
  uint256 clubId;
  uint256 totalStakeAmount;
}

struct Metric {
  uint256 minValue;
  uint256 maxValue;
  uint256 weight;
}

struct RoomMetrics {
  Metric averageListenerTime;
  Metric averageSpeakerTime;
  Metric averageModeratorTime;
  Metric listenersCount;
  Metric speakersCount;
  Metric moderatorsCount;
  Metric stickiness;
  Metric roomMembersStakingAmount;
}

struct RoomMemberMetric {
  uint256 minValue;
  uint256 maxValue;
  uint256 weight;
}

struct RoomMemberMetrics {
  RoomMemberMetric listenerTime;
  RoomMemberMetric speakerTime;
  RoomMemberMetric moderatorTime;
  RoomMemberMetric roomMemberStakingAmount;
}

contract ClubhouseAudioFarming is Ownable {
  using SafeMath for uint256;
  using ECDSA for bytes32;

  mapping (uint256 => Room) private rooms;
  mapping (uint256 => mapping (address => RoomMember)) public roomMembers;

  mapping (uint256 => Club) private clubs;
  mapping (uint256 => mapping (address => ClubMember)) public clubMembers;

  uint stakingPoolsCount;
  mapping (uint256 => StakingPool) public stakingPools;
  mapping (uint256 => mapping (address => StakingPoolMember)) public stakingPoolMembers;

  RoomMetrics public roomMetrics = RoomMetrics({
    // the code is hidden for now.....
  });

  RoomMemberMetrics public roomMemberMetrics = RoomMemberMetrics({
    listenerTime:            RoomMemberMetric({ minValue: 0 seconds, maxValue: 0 seconds, weight: 5 }),
    speakerTime:             RoomMemberMetric({ minValue: 0 seconds, maxValue: 0 seconds, weight: 20 }),
    moderatorTime:           RoomMemberMetric({ minValue: 0 seconds, maxValue: 0 seconds, weight: 25 }),
    roomMemberStakingAmount: RoomMemberMetric({ minValue: 0, maxValue: 0, weight: 50 })
  });

  DecibelCoin public decibelcoin;
  address public devaddr;

  uint256 public rewardCoefficientGrowthRate = 5000;// in basis points, 100% === 10000, 50% === 5000
  uint256 public rewardPerMinute = 1 ether;
  uint256 public clubConnectionPrice = 100 ether;
  uint256 public clubMembershipPrice = 10 ether;

  mapping(uint256 => bool) usedNonces;

  event Deposit(address indexed user, uint256 indexed clubId, uint256 amount);
  event Withdraw(address indexed user, uint256 indexed clubId, uint256 amount);
  event ConnectClub(uint256 indexed clubId);
  event StartClubMembership(uint256 indexed clubId, address indexed memberAddress);
  event StopClubMembership(uint256 indexed clubId, address indexed memberAddress);
  event FarmRoom(uint256 roomId, uint256 reward);
  event GetRoomMemberReward(address addr, uint256 reward);

  constructor (
    DecibelCoin _decibelcoin,
    address _devaddr
  ) {
    decibelcoin = _decibelcoin;
    devaddr = _devaddr;
  }

  function isAuthorizedMessage(bytes memory encodedArgs, bytes memory signature) internal view {
    bytes32 messageHash = keccak256(abi.encodePacked(encodedArgs))
      .toEthSignedMessageHash();

    address signer = messageHash.recover(signature);
    require(signer == owner(), "permission denied");
  }

  function connectClub(
    uint256 nonce, bytes memory signature,
    uint256 clubId
  ) external {
    isAuthorizedMessage(
      abi.encodePacked(
        msg.sender, this, nonce,
        clubId
      ),
      signature
    );

    require(!usedNonces[nonce], 'nonce is already used');
    usedNonces[nonce] = true;

    Club storage club = clubs[clubId];
    require(club.id == 0, 'club is already connected');

    club.id = clubId;
    club.adminAddress = msg.sender;

    ClubMember storage clubMember = clubMembers[clubId][msg.sender]; 
    clubMember.role = ClubMemberRoles.owner;
    clubMember.isMembershipActive = true;
    clubMember.addr = msg.sender;

    StakingPool storage clubStakingPool = stakingPools[clubId];
    clubStakingPool.clubId = clubId;
    clubStakingPool.totalStakeAmount = clubStakingPool.totalStakeAmount.add(clubConnectionPrice);

    StakingPoolMember storage poolMember = stakingPoolMembers[clubId][msg.sender];
    poolMember.stakeAmount = poolMember.stakeAmount.add(clubConnectionPrice);
    poolMember.addr = msg.sender;

    decibelcoin.transferFrom(address(msg.sender), address(this), clubConnectionPrice);

    emit ConnectClub(clubId);
    emit StartClubMembership(clubId, msg.sender);
  }

  function startClubMembership(
    uint256 nonce, bytes memory signature,
    uint256 clubId, ClubMemberRoles role
  ) external {
    require(!usedNonces[nonce], 'nonce is already used');
    usedNonces[nonce] = true;

    require(decibelcoin.balanceOf(msg.sender) >= clubMembershipPrice, 'club membership price exceeds balance');

    Club storage club = clubs[clubId];
    require(club.id == clubId, 'club is not exist');

    StakingPool storage clubStakingPool = stakingPools[clubId];
    require(clubStakingPool.clubId == clubId, 'club staking pool is not exist');

    ClubMember storage clubMember = clubMembers[clubId][msg.sender];
    require(clubMember.isMembershipActive == false, 'club membership is already active');

    clubMember.role = role;
    clubMember.addr = msg.sender;
    clubMember.isMembershipActive = true;

    StakingPoolMember storage poolMember = stakingPoolMembers[clubId][msg.sender];
    poolMember.stakeAmount = clubMembershipPrice;
    poolMember.addr = msg.sender;

    clubStakingPool.totalStakeAmount = clubStakingPool.totalStakeAmount.add(clubMembershipPrice);

    decibelcoin.transferFrom(address(msg.sender), address(this), clubMembershipPrice);

    emit StartClubMembership(clubId, msg.sender);
  }

  function stopClubMembership(uint256 clubId) external {
    // the code is hidden for now.....
  }

  function deposit(
    uint256 clubId,
    uint256 amount
  ) external {
    require(amount > 0, 'deposit amount must be greater than zero');
    require(amount <= decibelcoin.balanceOf(msg.sender), 'deposit amount exceeds balance');

    Club storage club = clubs[clubId];
    require(club.id == clubId, 'club is not exist');

    StakingPool storage clubStakingPool = stakingPools[clubId];
    require(clubStakingPool.clubId == clubId, 'club staking pool is not exist');

    ClubMember storage clubMember = clubMembers[clubId][msg.sender];
    require(clubMember.addr == msg.sender, 'club member is not exist');
    
    StakingPoolMember storage poolMember = stakingPoolMembers[clubId][msg.sender];
    require(poolMember.addr == msg.sender, 'pool member is not exist');

    poolMember.stakeAmount = poolMember.stakeAmount.add(amount);
    clubStakingPool.totalStakeAmount = clubStakingPool.totalStakeAmount.add(amount);

    decibelcoin.transferFrom(address(msg.sender), address(this), amount);

    emit Deposit(msg.sender, clubId, amount);
  }

  function withdraw(
    uint256 clubId,
    uint256 amount
  ) external {
    require(amount > 0, 'deposit amount must be greater than zero');

    Club storage club = clubs[clubId];
    require(club.id == clubId, 'club is not exist');

    StakingPool storage clubStakingPool = stakingPools[clubId];
    require(clubStakingPool.clubId == clubId, 'club staking pool is not exist');

    ClubMember storage clubMember = clubMembers[clubId][msg.sender];
    require(clubMember.addr == msg.sender, 'club member is not exist');

    StakingPoolMember storage poolMember = stakingPoolMembers[clubId][msg.sender];
    require(poolMember.addr == msg.sender, 'pool member is not exist');

    require(poolMember.stakeAmount.sub(amount) >= clubMembershipPrice, 'stake amount is less than clubMembershipPrice, first stop club membership');
    require(amount <= poolMember.stakeAmount, 'withdraw amount exceeds stake balance');

    poolMember.stakeAmount = poolMember.stakeAmount.sub(amount);
    clubStakingPool.totalStakeAmount = clubStakingPool.totalStakeAmount.sub(amount);

    decibelcoin.transfer(address(msg.sender), amount);

    emit Withdraw(msg.sender, clubId, amount);
  }

  function farmRoom(
    uint256 roomId,
    uint256 clubId,
    RoomMetricsData memory roomMetricsData
  ) public onlyOwner {
    Club storage club = clubs[clubId];
    require(club.id == clubId, 'club is not exist');

    Room storage room = rooms[roomId];
    require(room.id == 0, 'room is already exist');

    require(
      roomMetricsData.roomMembersStakingAmount >= clubConnectionPrice,
      'room members staking amount must be greater than club min staking amount'
    );

    room.id = roomId;
    room.clubId = clubId;
    room.durationTime = roomMetricsData.durationTime;

    room.avListenerTime = roomMetricsData.avListenerTime;
    room.avSpeakerTime = roomMetricsData.avSpeakerTime;
    room.avModeratorTime = roomMetricsData.avModeratorTime;

    room.listenersCount = roomMetricsData.listenersCount;
    room.speakersCount = roomMetricsData.speakersCount;
    room.moderatorsCount = roomMetricsData.moderatorsCount;

    room.stickiness = roomMetricsData.stickiness;
    room.roomMembersStakingAmount = roomMetricsData.roomMembersStakingAmount;

    room.totalModeratorTime = roomMetricsData.totalModeratorTime;
    room.totalListenerTime = roomMetricsData.totalListenerTime;
    room.totalSpeakerTime = roomMetricsData.totalSpeakerTime;

    uint reward = computeRoomReward(
      room
    );

    room.reward = reward;

    decibelcoin.mint(address(this), reward);

    emit FarmRoom(roomId, reward);
  }

  function getRoomMemberReward(
    uint256 nonce,
    bytes memory signature,
    uint256 roomId,
    uint256 clubId,
    RoomMemberMetricsData memory roomMemberMetricsData
  ) external {
    isAuthorizedGetRoomMemberRewardMessage(
      nonce,
      signature,
      roomId,
      clubId,
      roomMemberMetricsData
    );

    Room storage room = rooms[roomId];
    require(room.id == roomId, 'room is not exist');

    Club storage club = clubs[clubId];
    require(club.id == clubId, 'club is not exist');

    ClubMember storage clubMember = clubMembers[clubId][msg.sender];
    require(clubMember.addr == msg.sender, 'club member is not exist');

    StakingPoolMember storage poolMember = stakingPoolMembers[clubId][msg.sender];
    require(poolMember.addr == msg.sender, 'pool member is not exist');

    RoomMember storage roomMember = roomMembers[roomId][msg.sender]; 
    require(roomMember.addr == address(0), 'room member is already exist');

    require(
      roomMemberMetricsData.roomMemberStakingAmount >= clubMembershipPrice,
      'room member staking amount must be greater than club member min staking amount'
    );

    roomMember.addr = msg.sender;
    roomMember.moderatorTime = roomMemberMetricsData.moderatorTime;
    roomMember.listenerTime = roomMemberMetricsData.listenerTime;
    roomMember.speakerTime = roomMemberMetricsData.speakerTime;
    roomMember.roomMemberStakingAmount = roomMemberMetricsData.roomMemberStakingAmount;

    uint reward = computeRoomMemberReward(
      room,
      roomMember
    );

    roomMember.reward = reward;

    decibelcoin.transfer(address(msg.sender), reward);

    emit GetRoomMemberReward(msg.sender, reward);
  }

  function isAuthorizedGetRoomMemberRewardMessage(
    uint256 nonce,
    bytes memory signature,
    uint256 roomId,
    uint256 clubId,
    RoomMemberMetricsData memory roomMemberMetricsData
  ) internal {
    bytes memory argsPart1;

    {
      argsPart1 = abi.encodePacked(
        msg.sender, this, nonce,

        roomId,
        clubId,
        
        roomMemberMetricsData.moderatorTime,
        roomMemberMetricsData.listenerTime,
        roomMemberMetricsData.speakerTime,
        roomMemberMetricsData.roomMemberStakingAmount
      );
    }

    isAuthorizedMessage(
      argsPart1,
      signature
    );

    require(!usedNonces[nonce], 'nonce is already used');
    usedNonces[nonce] = true;
  }

  function getRoomMetricsSum(
    RoomMetricsDataProcessed memory roomMetricsDataProcessed
  ) internal view returns (bytes16) {
    // the code is hidden for now.....
  }

  function calculateRoomReward(
    RoomMetricsDataProcessed memory roomMetricsDataProcessed
  ) internal view returns (uint256) {
    // the code is hidden for now.....
  }

  function prepareRoomMetrics(
    Room memory room
  ) internal view returns (RoomMetricsDataProcessed memory) {
    // the code is hidden for now.....
  }

  function computeRoomReward(
    Room memory room
  ) public view returns (uint256) {
    // the code is hidden for now.....
  }

  function prepareRoomMemberMetrics(
    Room memory room,
    RoomMember memory roomMember
  ) internal view returns (bytes16, bytes16, bytes16, bytes16) {
    // the code is hidden for now.....
  }

  function computeRoomMemberReward(
    Room memory room,
    RoomMember memory roomMember
  ) public view returns (uint256) {
    // the code is hidden for now.....
  }

  function calculateRoomMemberReward(
    uint256 roomReward,
    bytes16 moderatorTimeProcessed,
    bytes16 listenerTimeProcessed,
    bytes16 speakerTimeProcessed,
    bytes16 roomMemberStakingAmountProcessed
  ) internal view returns (uint256) {
    // the code is hidden for now.....
  }
  
  function getRoomMemberMetricsSum(
    bytes16 moderatorTimeProcessed,
    bytes16 listenerTimeProcessed,
    bytes16 speakerTimeProcessed,
    bytes16 roomMemberStakingAmountProcessed
  ) internal view returns (bytes16) {
    // the code is hidden for now.....
  }

  function getNormalizedMetricValue(
    uint256 value,
    uint256 minValue,
    uint256 maxValue
  ) internal view returns (bytes16) {
    uint256 numerator = value - minValue;
    uint256 denominator = maxValue - minValue;

    return ABDKMathQuad.div (
      ABDKMathQuad.fromUInt(numerator),
      ABDKMathQuad.fromUInt(denominator)
    );
  }

  function getNormalizedAndWeightedRoomMetric(
    uint256 value,
    Metric memory metric
  ) internal view returns (bytes16) {
    if (value == 0 || value == metric.minValue) {
      return ABDKMathQuad.fromUInt(0);
    }

    bytes16 metricNormalizedValue = getNormalizedMetricValue(
      value,
      metric.minValue,
      metric.maxValue
    );

    return getShareOf(
      metricNormalizedValue,
      ABDKMathQuad.fromUInt(metric.weight),
      ABDKMathQuad.fromUInt(100)
    );
  }  

  function getNormalizedAndWeightedRoomMemberMetric(
    uint256 value,
    uint256 totalValue,
    uint256 weight
  ) internal view returns (bytes16) {

    if (value == 0 || totalValue == 0) {
      return ABDKMathQuad.fromUInt(0);
    }

    bytes16 metricNormalizedValue = ABDKMathQuad.div(
      ABDKMathQuad.fromUInt(value),
      ABDKMathQuad.fromUInt(totalValue)
    );

    return getShareOf(
      metricNormalizedValue,
      ABDKMathQuad.fromUInt(weight),
      ABDKMathQuad.fromUInt(100)
    );
  } 

  function getRoom(
    uint256 roomId
  ) public view returns (Room memory) {
    Room storage room = rooms[roomId];

    require (room.id != 0, 'room is not exist');

    return room;
  }

  // the code is hidden for now.....
}
