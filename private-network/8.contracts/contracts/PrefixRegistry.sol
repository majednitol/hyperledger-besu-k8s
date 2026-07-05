// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/**
 * @title PrefixRegistry
 * @notice Route-origin registry: associates IP prefixes with authorized Autonomous System Numbers (ASNs).
 * Handles submission, RIR validator validation/revocation workflows, and paginated queries.
 */
contract PrefixRegistry {
    enum Status { Pending, Validated, Revoked }

    struct Record {
        string prefix;       // e.g. "192.0.2.0/24"
        uint32 asn;
        address submittedBy;
        Status status;
        uint256 submittedAt;
        uint256 updatedAt;
    }

    // Storage layout
    mapping(bytes32 => Record) public records;      // key = keccak256(prefix, asn)
    bytes32[] public recordKeys;
    mapping(address => bool) public validators;      // Authorized RIR validators
    address public admin;

    // Submission cooldown configuration to prevent spamming
    uint256 public cooldownPeriod = 10 seconds;
    mapping(address => uint256) public lastSubmissionTime;

    // Events
    event RecordSubmitted(bytes32 indexed key, string prefix, uint32 indexed asn, address indexed submittedBy);
    event RecordStatusChanged(bytes32 indexed key, Status indexed newStatus, address indexed changedBy);
    event ValidatorStatusChanged(address indexed account, bool indexed isValidator);

    // Modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, "PrefixRegistry: Caller is not admin");
        _;
    }

    modifier onlyValidator() {
        require(validators[msg.sender], "PrefixRegistry: Caller is not an authorized validator");
        _;
    }

    modifier checkCooldown() {
        require(
            block.timestamp >= lastSubmissionTime[msg.sender] + cooldownPeriod,
            "PrefixRegistry: Submission cooldown period active"
        );
        _;
    }

    constructor() {
        admin = msg.sender;
        validators[msg.sender] = true;
        emit ValidatorStatusChanged(msg.sender, true);
    }

    function setValidator(address account, bool isValidator) external onlyAdmin {
        validators[account] = isValidator;
        emit ValidatorStatusChanged(account, isValidator);
    }

    function setCooldownPeriod(uint256 period) external onlyAdmin {
        cooldownPeriod = period;
    }

    /**
     * @notice Submit a new prefix-to-ASN record. Sets initial state to Pending.
     */
    function submitRecord(string calldata prefix, uint32 asn) external checkCooldown returns (bytes32 key) {
        key = keccak256(abi.encodePacked(prefix, asn));
        require(records[key].submittedAt == 0, "PrefixRegistry: Record already exists");
        
        records[key] = Record({
            prefix: prefix,
            asn: asn,
            submittedBy: msg.sender,
            status: Status.Pending,
            submittedAt: block.timestamp,
            updatedAt: block.timestamp
        });
        
        recordKeys.push(key);
        lastSubmissionTime[msg.sender] = block.timestamp;

        emit RecordSubmitted(key, prefix, asn, msg.sender);
    }

    /**
     * @notice Validate or revoke a record.
     */
    function setStatus(bytes32 key, Status newStatus) external onlyValidator {
        require(records[key].submittedAt != 0, "PrefixRegistry: Record does not exist");
        records[key].status = newStatus;
        records[key].updatedAt = block.timestamp;

        emit RecordStatusChanged(key, newStatus, msg.sender);
    }

    /**
     * @notice Get total number of records.
     */
    function recordCount() external view returns (uint256) {
        return recordKeys.length;
    }

    /**
     * @notice Fetch a paginated page of record keys and associated values.
     * Prevents out-of-gas errors when reading large array sets.
     */
    function getRecordsPage(uint256 offset, uint256 limit) 
        external 
        view 
        returns (bytes32[] memory keys, Record[] memory items) 
    {
        uint256 total = recordKeys.length;
        if (offset >= total) {
            return (new bytes32[](0), new Record[](0));
        }

        uint256 size = limit;
        if (offset + limit > total) {
            size = total - offset;
        }

        keys = new bytes32[](size);
        items = new Record[](size);

        for (uint256 i = 0; i < size; i++) {
            bytes32 key = recordKeys[offset + i];
            keys[i] = key;
            items[i] = records[key];
        }
    }
}
