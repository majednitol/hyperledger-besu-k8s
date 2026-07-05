// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/**
 * @title RegistryAnchor
 * @notice State bridge contract deployed on the public network.
 * Allows an authorized relayer to periodically write cryptographic Merkle roots
 * representing snapshots of the private PrefixRegistry contract state.
 */
contract RegistryAnchor {
    address public relayer;

    struct Anchor {
        bytes32 merkleRoot;
        uint256 privateBlockNumber;
        uint256 timestamp;
    }

    Anchor[] public anchors;

    event Anchored(uint256 indexed index, bytes32 merkleRoot, uint256 privateBlockNumber);
    event RelayerRotated(address indexed oldRelayer, address indexed newRelayer);

    modifier onlyRelayer() {
        require(msg.sender == relayer, "RegistryAnchor: Caller is not the authorized relayer");
        _;
    }

    constructor(address _relayer) {
        require(_relayer != address(0), "RegistryAnchor: Relayer address cannot be zero");
        relayer = _relayer;
        emit RelayerRotated(address(0), _relayer);
    }

    /**
     * @notice Submits a new state snapshot root.
     */
    function submitAnchor(bytes32 merkleRoot, uint256 privateBlockNumber) external onlyRelayer {
        anchors.push(Anchor({
            merkleRoot: merkleRoot,
            privateBlockNumber: privateBlockNumber,
            timestamp: block.timestamp
        }));
        
        emit Anchored(anchors.length - 1, merkleRoot, privateBlockNumber);
    }

    /**
     * @notice Fetches the most recently recorded anchor state.
     */
    function latest() external view returns (Anchor memory) {
        require(anchors.length > 0, "RegistryAnchor: No anchors submitted yet");
        return anchors[anchors.length - 1];
    }

    /**
     * @notice Get total number of submitted anchors.
     */
    function totalAnchors() external view returns (uint256) {
        return anchors.length;
    }
}
