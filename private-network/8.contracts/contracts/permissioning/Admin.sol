// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/**
 * @title Admin
 * @notice Central administration contract for permissioning. Manages list of admins authorized
 * to update allowlists on NodeRules and AccountRules.
 */
contract Admin {
    mapping(address => bool) public admins;

    event AdminAdded(address indexed account);
    event AdminRemoved(address indexed account);

    modifier onlyAdmin() {
        require(admins[msg.sender], "Admin: Caller is not an authorized administrator");
        _;
    }

    constructor() {
        admins[msg.sender] = true;
        emit AdminAdded(msg.sender);
    }

    function addAdmin(address account) external onlyAdmin {
        admins[account] = true;
        emit AdminAdded(account);
    }

    function removeAdmin(address account) external onlyAdmin {
        require(account != msg.sender, "Admin: Cannot remove self");
        admins[account] = false;
        emit AdminRemoved(account);
    }

    function isAdmin(address account) external view returns (bool) {
        return admins[account];
    }
}
