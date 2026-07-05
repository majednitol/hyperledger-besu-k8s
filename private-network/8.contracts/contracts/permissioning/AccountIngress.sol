// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./AccountRules.sol";

/**
 * @title AccountIngress
 * @notice Fixed-address entrypoint for Besu transaction sending permissioning.
 * Delegates checks to the configured AccountRules contract.
 */
contract AccountIngress {
    address public rulesAddress;
    address public admin;

    event RulesAddressSet(address indexed rulesAddress);

    modifier onlyAdmin() {
        require(msg.sender == admin, "AccountIngress: Caller is not admin");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    function setRulesAddress(address _rulesAddress) external onlyAdmin {
        rulesAddress = _rulesAddress;
        emit RulesAddressSet(_rulesAddress);
    }

    function transactionAllowed(
        address sender,
        address target,
        uint256 value,
        uint256 gasPrice,
        uint256 gasLimit,
        bytes calldata payload
    ) external view returns (bool) {
        if (rulesAddress == address(0)) {
            return true; // Bypass allowlist check if contract is not initialized yet
        }
        return AccountRules(rulesAddress).transactionAllowed(
            sender,
            target,
            value,
            gasPrice,
            gasLimit,
            payload
        );
    }
}
