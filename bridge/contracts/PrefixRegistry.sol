// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/**
 * @title PrefixRegistry
 * @notice IP prefix registry deployed on the PRIVATE network.
 * Stores IP prefix allocations with their associated RIR data.
 * The bridge relayer reads state from this contract and anchors
 * Merkle roots to the public RegistryAnchor contract.
 */
contract PrefixRegistry {
    struct Prefix {
        string  cidr;          // e.g. "192.168.1.0/24"
        string  rir;           // e.g. "AFRINIC", "APNIC"
        address holder;        // account that registered the prefix
        uint256 registeredAt;  // block.timestamp
        bool    active;
    }

    mapping(uint256 => Prefix) public prefixes;
    uint256 public totalPrefixes;

    event PrefixRegistered(uint256 indexed id, string cidr, string rir, address holder);
    event PrefixDeactivated(uint256 indexed id);

    /**
     * @notice Register a new IP prefix.
     */
    function registerPrefix(string calldata cidr, string calldata rir) external returns (uint256) {
        uint256 id = totalPrefixes++;
        prefixes[id] = Prefix({
            cidr: cidr,
            rir: rir,
            holder: msg.sender,
            registeredAt: block.timestamp,
            active: true
        });
        emit PrefixRegistered(id, cidr, rir, msg.sender);
        return id;
    }

    /**
     * @notice Deactivate a prefix (only by original holder).
     */
    function deactivatePrefix(uint256 id) external {
        require(prefixes[id].holder == msg.sender, "Not prefix holder");
        require(prefixes[id].active, "Already deactivated");
        prefixes[id].active = false;
        emit PrefixDeactivated(id);
    }

    /**
     * @notice Get prefix details by ID.
     */
    function getPrefix(uint256 id) external view returns (
        string memory cidr,
        string memory rir,
        address holder,
        uint256 registeredAt,
        bool active
    ) {
        Prefix storage p = prefixes[id];
        return (p.cidr, p.rir, p.holder, p.registeredAt, p.active);
    }
}
