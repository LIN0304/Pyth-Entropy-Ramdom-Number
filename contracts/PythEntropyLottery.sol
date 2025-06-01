// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./interfaces/IEntropy.sol";

/**
 * @title PythEntropyLottery
 * @notice Decentralized lottery system using Pyth Entropy for verifiable randomness
 */
contract PythEntropyLottery is Ownable, ReentrancyGuard, ERC721 {
    using Counters for Counters.Counter;

    IEntropy public immutable entropy;
    address public immutable entropyProvider;

    uint256 public constant MIN_PARTICIPANTS = 3;
    uint256 public constant PROTOCOL_FEE_BPS = 250; // 2.5%
    uint256 public constant REFERRAL_BONUS_BPS = 100; // 1%

    enum PoolTier { BRONZE, SILVER, GOLD, PLATINUM }

    struct LotteryPool {
        uint256 entryFee;
        uint256 maxParticipants;
        uint256 currentParticipants;
        uint256 totalPrize;
        address[] participants;
        mapping(address => uint256) entries;
        bool isActive;
        uint64 entropySequence;
    }

    struct Winner {
        address winner;
        uint256 prize;
        uint256 timestamp;
        PoolTier tier;
        uint256 randomSeed;
    }

    struct NFTAttributes {
        uint8 rarity;
        uint8 luck;
        uint8 multiplier;
        string element;
    }

    mapping(PoolTier => LotteryPool) public lotteryPools;
    mapping(uint256 => Winner) public winners;
    mapping(uint256 => NFTAttributes) public nftAttributes;
    mapping(address => uint256) public referralRewards;
    mapping(address => address) public referrers;

    Counters.Counter private _tokenIdCounter;
    Counters.Counter private _winnerCounter;

    event LotteryEntry(address indexed participant, PoolTier tier, uint256 amount);
    event LotteryDrawInitiated(PoolTier tier, uint64 sequenceNumber);
    event WinnerSelected(address indexed winner, PoolTier tier, uint256 prize, uint256 tokenId);
    event ReferralRewarded(address indexed referrer, address indexed referee, uint256 amount);

    error InvalidEntryFee();
    error PoolNotActive();
    error PoolFull();
    error AlreadyEntered();
    error InsufficientParticipants();
    error DrawAlreadyInProgress();
    error UnauthorizedCaller();
    error InvalidPool();

    constructor(address _entropy, address _entropyProvider)
        ERC721("Pyth Entropy Lottery NFT", "PELN")
    {
        entropy = IEntropy(_entropy);
        entropyProvider = _entropyProvider;
        _initializePools();
    }

    function _initializePools() private {
        lotteryPools[PoolTier.BRONZE].entryFee = 0.01 ether;
        lotteryPools[PoolTier.BRONZE].maxParticipants = 50;
        lotteryPools[PoolTier.BRONZE].isActive = true;

        lotteryPools[PoolTier.SILVER].entryFee = 0.1 ether;
        lotteryPools[PoolTier.SILVER].maxParticipants = 30;
        lotteryPools[PoolTier.SILVER].isActive = true;

        lotteryPools[PoolTier.GOLD].entryFee = 1 ether;
        lotteryPools[PoolTier.GOLD].maxParticipants = 20;
        lotteryPools[PoolTier.GOLD].isActive = true;

        lotteryPools[PoolTier.PLATINUM].entryFee = 10 ether;
        lotteryPools[PoolTier.PLATINUM].maxParticipants = 10;
        lotteryPools[PoolTier.PLATINUM].isActive = true;
    }

    function enterLottery(PoolTier tier, address referrer) external payable nonReentrant {
        LotteryPool storage pool = lotteryPools[tier];
        if (!pool.isActive) revert PoolNotActive();
        if (msg.value != pool.entryFee) revert InvalidEntryFee();
        if (pool.currentParticipants >= pool.maxParticipants) revert PoolFull();
        if (pool.entries[msg.sender] > 0) revert AlreadyEntered();

        pool.participants.push(msg.sender);
        pool.entries[msg.sender] = msg.value;
        pool.currentParticipants++;
        pool.totalPrize += msg.value;

        if (referrer != address(0) && referrer != msg.sender && referrers[msg.sender] == address(0)) {
            referrers[msg.sender] = referrer;
            uint256 referralBonus = (msg.value * REFERRAL_BONUS_BPS) / 10000;
            referralRewards[referrer] += referralBonus;
            emit ReferralRewarded(referrer, msg.sender, referralBonus);
        }

        emit LotteryEntry(msg.sender, tier, msg.value);

        if (pool.currentParticipants == pool.maxParticipants) {
            _initiateDraw(tier);
        }
    }

    function initiateDraw(PoolTier tier) external {
        LotteryPool storage pool = lotteryPools[tier];
        if (pool.currentParticipants < MIN_PARTICIPANTS) revert InsufficientParticipants();
        if (pool.entropySequence != 0) revert DrawAlreadyInProgress();
        _initiateDraw(tier);
    }

    function _initiateDraw(PoolTier tier) private {
        LotteryPool storage pool = lotteryPools[tier];
        bytes32 userCommitment = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, tier, pool.currentParticipants));
        uint256 fee = entropy.getFee(entropyProvider);
        uint64 sequenceNumber = entropy.requestRandomness{value: fee}(entropyProvider, userCommitment);
        pool.entropySequence = sequenceNumber;
        emit LotteryDrawInitiated(tier, sequenceNumber);
    }

    function entropyCallback(uint64 sequenceNumber, address provider, bytes32 randomNumber) external {
        if (msg.sender != address(entropy)) revert UnauthorizedCaller();
        PoolTier tier = _findPoolBySequence(sequenceNumber);
        LotteryPool storage pool = lotteryPools[tier];
        if (pool.entropySequence != sequenceNumber) revert InvalidPool();
        uint256 winnerIndex = uint256(randomNumber) % pool.currentParticipants;
        address winner = pool.participants[winnerIndex];
        uint256 protocolFee = (pool.totalPrize * PROTOCOL_FEE_BPS) / 10000;
        uint256 winnerPrize = pool.totalPrize - protocolFee;
        uint256 tokenId = _mintWinnerNFT(winner, randomNumber, tier);
        _winnerCounter.increment();
        uint256 winnerId = _winnerCounter.current();
        winners[winnerId] = Winner({winner: winner, prize: winnerPrize, timestamp: block.timestamp, tier: tier, randomSeed: uint256(randomNumber)});
        payable(winner).transfer(winnerPrize);
        emit WinnerSelected(winner, tier, winnerPrize, tokenId);
        _resetPool(tier);
    }

    function _mintWinnerNFT(address winner, bytes32 randomSeed, PoolTier tier) private returns (uint256) {
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();
        NFTAttributes memory attrs = _generateNFTAttributes(randomSeed, tier);
        nftAttributes[tokenId] = attrs;
        _safeMint(winner, tokenId);
        return tokenId;
    }

    function _generateNFTAttributes(bytes32 randomSeed, PoolTier tier) private pure returns (NFTAttributes memory) {
        uint256 seed = uint256(randomSeed);
        uint8 baseRarity = uint8(tier) * 20 + 20;
        uint8 rarity = baseRarity + uint8(seed % 20);
        uint8 luck = uint8((seed >> 8) % 100) + 1;
        uint8 multiplier = uint8((seed >> 16) % 10) + 1;
        string[4] memory elements = ["Fire", "Water", "Earth", "Air"];
        uint256 elementIndex = (seed >> 24) % 4;
        return NFTAttributes({rarity: rarity, luck: luck, multiplier: multiplier, element: elements[elementIndex]});
    }

    function _findPoolBySequence(uint64 sequenceNumber) private view returns (PoolTier) {
        if (lotteryPools[PoolTier.BRONZE].entropySequence == sequenceNumber) return PoolTier.BRONZE;
        if (lotteryPools[PoolTier.SILVER].entropySequence == sequenceNumber) return PoolTier.SILVER;
        if (lotteryPools[PoolTier.GOLD].entropySequence == sequenceNumber) return PoolTier.GOLD;
        if (lotteryPools[PoolTier.PLATINUM].entropySequence == sequenceNumber) return PoolTier.PLATINUM;
        revert InvalidPool();
    }

    function _resetPool(PoolTier tier) private {
        LotteryPool storage pool = lotteryPools[tier];
        for (uint256 i = 0; i < pool.participants.length; i++) {
            delete pool.entries[pool.participants[i]];
        }
        delete pool.participants;
        pool.currentParticipants = 0;
        pool.totalPrize = 0;
        pool.entropySequence = 0;
    }

    function claimReferralRewards() external nonReentrant {
        uint256 rewards = referralRewards[msg.sender];
        require(rewards > 0, "No rewards");
        referralRewards[msg.sender] = 0;
        payable(msg.sender).transfer(rewards);
    }

    function getPoolInfo(PoolTier tier) external view returns (
        uint256 entryFee,
        uint256 currentParticipants,
        uint256 maxParticipants,
        uint256 totalPrize,
        bool isActive,
        address[] memory participants
    ) {
        LotteryPool storage pool = lotteryPools[tier];
        return (pool.entryFee, pool.currentParticipants, pool.maxParticipants, pool.totalPrize, pool.isActive, pool.participants);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        NFTAttributes memory attrs = nftAttributes[tokenId];
        string memory json = string(abi.encodePacked(
            '{"name":"Pyth Entropy Lottery #', _toString(tokenId),'",',
            '"description":"Winner NFT from Pyth Entropy Lottery",',
            '"attributes":[',
            '{"trait_type":"Rarity","value":', _toString(attrs.rarity),'},',
            '{"trait_type":"Luck","value":', _toString(attrs.luck),'},',
            '{"trait_type":"Multiplier","value":', _toString(attrs.multiplier),'},',
            '{"trait_type":"Element","value":"', attrs.element, '"}',
            ']}'
        ));
        return string(abi.encodePacked("data:application/json;base64,", _base64Encode(bytes(json))));
    }

    function emergencyWithdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _base64Encode(bytes memory data) internal pure returns (string memory) {
        string memory base64Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        uint256 len = data.length;
        if (len == 0) return "";
        uint256 encodedLen = 4 * ((len + 2) / 3);
        bytes memory result = new bytes(encodedLen);
        bytes memory alphabet = bytes(base64Alphabet);
        uint256 i = 0;
        uint256 j = 0;
        for (; i + 3 <= len; i += 3) {
            (result[j], result[j+1], result[j+2], result[j+3]) = _encode3(
                uint8(data[i]),
                uint8(data[i+1]),
                uint8(data[i+2]),
                alphabet
            );
            j += 4;
        }
        if ((len - i) == 2) {
            (result[j], result[j+1], result[j+2], result[j+3]) = _encode2(uint8(data[i]), uint8(data[i+1]), alphabet);
        } else if ((len - i) == 1) {
            (result[j], result[j+1], result[j+2], result[j+3]) = _encode1(uint8(data[i]), alphabet);
        }
        return string(result);
    }

    function _encode3(uint8 a0, uint8 a1, uint8 a2, bytes memory alphabet) private pure returns (bytes1, bytes1, bytes1, bytes1) {
        uint24 input = (uint24(a0) << 16) | (uint24(a1) << 8) | a2;
        uint8 b0 = uint8(input >> 18);
        uint8 b1 = uint8((input >> 12) & 0x3F);
        uint8 b2 = uint8((input >> 6) & 0x3F);
        uint8 b3 = uint8(input & 0x3F);
        return (alphabet[b0], alphabet[b1], alphabet[b2], alphabet[b3]);
    }

    function _encode2(uint8 a0, uint8 a1, bytes memory alphabet) private pure returns (bytes1, bytes1, bytes1, bytes1) {
        uint24 input = (uint24(a0) << 16) | (uint24(a1) << 8);
        uint8 b0 = uint8(input >> 18);
        uint8 b1 = uint8((input >> 12) & 0x3F);
        uint8 b2 = uint8((input >> 6) & 0x3F);
        return (alphabet[b0], alphabet[b1], alphabet[b2], '=');
    }

    function _encode1(uint8 a0, bytes memory alphabet) private pure returns (bytes1, bytes1, bytes1, bytes1) {
        uint24 input = uint24(a0) << 16;
        uint8 b0 = uint8(input >> 18);
        uint8 b1 = uint8((input >> 12) & 0x3F);
        return (alphabet[b0], alphabet[b1], '=', '=');
    }

    receive() external payable {}
}
