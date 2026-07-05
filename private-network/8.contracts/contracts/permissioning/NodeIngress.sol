// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./NodeRules.sol";

/**
 * @title NodeIngress
 * @notice Fixed-address entrypoint for Besu node connection permissioning.
 * Delegates checks to the configured NodeRules contract.
 */
contract NodeIngress {
    address public rulesAddress;
    address public admin;

    event RulesAddressSet(address indexed rulesAddress);

    modifier onlyAdmin() {
        require(msg.sender == admin, "NodeIngress: Caller is not admin");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    function setRulesAddress(address _rulesAddress) external onlyAdmin {
        rulesAddress = _rulesAddress;
        emit RulesAddressSet(_rulesAddress);
    }

    function connectionAllowed(
        string calldata sourceEnodeId,
        string calldata sourceEnodeIp,
        uint16 sourceEnodePort,
        string calldata destinationEnodeId,
        string calldata destinationEnodeIp,
        uint16 destinationEnodePort
    ) external view returns (bool) {
        if (rulesAddress == address(0)) {
            return true; // Bypass allowlist check if contract is not initialized yet
        }
        return NodeRules(rulesAddress).connectionAllowed(
            sourceEnodeId,
            sourceEnodeIp,
            sourceEnodePort,
            destinationEnodeId,
            destinationEnodeIp,
            destinationEnodePort
        );
    }
}
