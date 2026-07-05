// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./Admin.sol";

/**
 * @title AccountRules
 * @notice Account permissioning rules. Manages the allowlist of accounts allowed to transact in the private network.
 */
contract AccountRules {
    Admin public adminContract;

    mapping(address => bool) public allowedAccounts;
    address[] public accountList;

    event AccountAdded(address account);
    event AccountRemoved(address account);

    modifier onlyAdmin() {
        require(adminContract.isAdmin(msg.sender), "AccountRules: Caller is not administrator");
        _;
    }

    constructor(address _adminContract) {
        adminContract = Admin(_adminContract);
    }

    function addAccount(address account) external onlyAdmin {
        if (!allowedAccounts[account]) {
            allowedAccounts[account] = true;
            accountList.push(account);
            emit AccountAdded(account);
        }
    }

    function removeAccount(address account) external onlyAdmin {
        if (allowedAccounts[account]) {
            allowedAccounts[account] = false;
            emit AccountRemoved(account);
            // Array cleanup
            for (uint256 i = 0; i < accountList.length; i++) {
                if (accountList[i] == account) {
                    accountList[i] = accountList[accountList.length - 1];
                    accountList.pop();
                    break;
                }
            }
        }
    }

    /**
     * @notice Checked by AccountIngress. Determines if a transaction is allowed from sender.
     */
    function transactionAllowed(
        address sender,
        address, // target (unused)
        uint256, // value (unused)
        uint256, // gasPrice (unused)
        uint256, // gasLimit (unused)
        bytes calldata // payload (unused)
    ) external view returns (bool) {
        return allowedAccounts[sender];
    }
}
