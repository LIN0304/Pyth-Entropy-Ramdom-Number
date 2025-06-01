// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IEntropy
 * @notice Interface for Pyth Network Entropy contract
 */
interface IEntropy {
    function requestRandomness(address provider, bytes32 userCommitment) external payable returns (uint64 sequenceNumber);
    function getFee(address provider) external view returns (uint256 fee);
    function revealRandomness(address provider, uint64 sequenceNumber, bytes32 userRandomness, bytes32 providerRevelation) external;
    function getRandomNumber(address provider, uint64 sequenceNumber) external view returns (bytes32 randomNumber);
}

interface IEntropyConsumer {
    function entropyCallback(uint64 sequenceNumber, address provider, bytes32 randomNumber) external;
}
