// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title MockEntropy
 * @notice Testing infrastructure for Pyth Entropy integration
 * @dev Simulates Pyth Entropy behavior with deterministic outcomes for comprehensive testing
 */
contract MockEntropy {
    struct RandomnessRequest {
        address requester;
        address provider;
        bytes32 userCommitment;
        uint256 fee;
        bool fulfilled;
        bytes32 randomNumber;
    }

    uint256 private _fee = 0.001 ether;
    uint64 private _sequenceCounter = 0;
    address private _authorizedCallback;

    mapping(uint64 => RandomnessRequest) public requests;
    mapping(address => bool) public authorizedProviders;

    event RandomnessRequested(
        uint64 indexed sequenceNumber,
        address indexed requester,
        address provider,
        bytes32 userCommitment,
        uint256 fee
    );

    event RandomnessRevealed(
        uint64 indexed sequenceNumber,
        address indexed requester,
        bytes32 randomNumber
    );

    error InsufficientFee();
    error UnauthorizedProvider();
    error RequestNotFound();
    error RequestAlreadyFulfilled();
    error UnauthorizedCallback();

    constructor() {
        authorizedProviders[address(this)] = true;
    }

    function requestRandomness(
        address provider,
        bytes32 userCommitment
    ) external payable returns (uint64 sequenceNumber) {
        if (!authorizedProviders[provider]) revert UnauthorizedProvider();
        if (msg.value < _fee) revert InsufficientFee();
        _sequenceCounter++;
        sequenceNumber = _sequenceCounter;
        requests[sequenceNumber] = RandomnessRequest({
            requester: msg.sender,
            provider: provider,
            userCommitment: userCommitment,
            fee: msg.value,
            fulfilled: false,
            randomNumber: bytes32(0)
        });
        emit RandomnessRequested(sequenceNumber, msg.sender, provider, userCommitment, msg.value);
    }

    function getFee(address) external view returns (uint256 fee) {
        return _fee;
    }

    function simulateCallback(
        address target,
        uint64 sequenceNumber,
        address provider,
        bytes32 randomNumber
    ) external {
        RandomnessRequest storage request = requests[sequenceNumber];
        if (request.requester == address(0)) revert RequestNotFound();
        if (request.fulfilled) revert RequestAlreadyFulfilled();
        if (_authorizedCallback != address(0) && target != _authorizedCallback) revert UnauthorizedCallback();
        if (randomNumber == bytes32(0)) {
            randomNumber = keccak256(abi.encodePacked(sequenceNumber, request.userCommitment, block.timestamp, block.prevrandao));
        }
        request.randomNumber = randomNumber;
        request.fulfilled = true;
        (bool success,) = target.call(abi.encodeWithSignature("entropyCallback(uint64,address,bytes32)", sequenceNumber, provider, randomNumber));
        require(success, "Callback execution failed");
        emit RandomnessRevealed(sequenceNumber, request.requester, randomNumber);
    }

    function setFee(uint256 newFee) external {
        _fee = newFee;
    }

    function setAuthorizedCallback(address callback) external {
        _authorizedCallback = callback;
    }

    function authorizeProvider(address provider, bool authorized) external {
        authorizedProviders[provider] = authorized;
    }

    function getRequest(uint64 sequenceNumber) external view returns (
        address requester,
        address provider,
        bytes32 userCommitment,
        uint256 fee,
        bool fulfilled,
        bytes32 randomNumber
    ) {
        RandomnessRequest memory request = requests[sequenceNumber];
        return (request.requester, request.provider, request.userCommitment, request.fee, request.fulfilled, request.randomNumber);
    }

    function getCurrentSequence() external view returns (uint64) {
        return _sequenceCounter;
    }

    function simulateBatchCallbacks(
        uint256 count,
        address target,
        address provider
    ) external {
        require(count <= 10, "Batch size too large");
        for (uint256 i = 0; i < count; i++) {
            uint64 sequence = _sequenceCounter - uint64(count) + uint64(i) + 1;
            if (requests[sequence].requester != address(0) && !requests[sequence].fulfilled) {
                bytes32 randomNumber = keccak256(abi.encodePacked("batch", sequence, block.timestamp, i));
                this.simulateCallback(target, sequence, provider, randomNumber);
            }
        }
    }

    function resetSequenceCounter() external {
        _sequenceCounter = 0;
    }

    function clearRequest(uint64 sequenceNumber) external {
        delete requests[sequenceNumber];
    }

    receive() external payable {}
}
