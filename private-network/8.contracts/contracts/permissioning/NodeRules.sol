// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./Admin.sol";

/**
 * @title NodeRules
 * @notice Node permissioning rules. Manages the allowlist of enode IDs permitted to peer in the private network.
 */
contract NodeRules {
    Admin public adminContract;

    // Mapping of enode public key (hex string) to allowed status
    mapping(string => bool) public allowedNodes;
    string[] public nodeList;

    event NodeAdded(string enodeId);
    event NodeRemoved(string enodeId);

    modifier onlyAdmin() {
        require(adminContract.isAdmin(msg.sender), "NodeRules: Caller is not administrator");
        _;
    }

    constructor(address _adminContract) {
        adminContract = Admin(_adminContract);
    }

    function addNode(string calldata enodeId) external onlyAdmin {
        if (!allowedNodes[enodeId]) {
            allowedNodes[enodeId] = true;
            nodeList.push(enodeId);
            emit NodeAdded(enodeId);
        }
    }

    function removeNode(string calldata enodeId) external onlyAdmin {
        if (allowedNodes[enodeId]) {
            allowedNodes[enodeId] = false;
            emit NodeRemoved(enodeId);
            // Simple array cleanup
            for (uint256 i = 0; i < nodeList.length; i++) {
                if (keccak256(abi.encodePacked(nodeList[i])) == keccak256(abi.encodePacked(enodeId))) {
                    nodeList[i] = nodeList[nodeList.length - 1];
                    nodeList.pop();
                    break;
                }
            }
        }
    }

    /**
     * @notice Checked by NodeIngress. Determines if a P2P connection between two nodes is allowed.
     */
    function connectionAllowed(
        string calldata sourceEnodeId,
        string calldata, // sourceEnodeIp (unused)
        uint16,          // sourceEnodePort (unused)
        string calldata destinationEnodeId,
        string calldata, // destinationEnodeIp (unused)
        uint16           // destinationEnodePort (unused)
    ) external view returns (bool) {
        // Both nodes must be present in our allowlist to communicate
        return allowedNodes[sourceEnodeId] && allowedNodes[destinationEnodeId];
    }
}
