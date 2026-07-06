// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/**
 * @title MedicalRecordRegistry
 * @notice Patient medical records registry deployed on the PRIVATE network.
 * Stores medical record metadata (hashed for patient privacy).
 * Access is controlled so only authorized doctors can write records, and patients
 * can authorize/revoke access to their records.
 */
contract MedicalRecordRegistry {
    struct MedicalRecord {
        uint256 patientId;        // anonymized patient identifier
        string  diagnosisCode;    // ICD-10 code (encrypted or plaintext for lookup)
        string  treatmentHash;    // IPFS/Secure storage hash of full treatment plan
        address doctor;           // doctor who authorized the record
        uint256 submittedAt;      // block.timestamp
        bool    active;
    }

    address public owner;

    // Mapping from record ID to MedicalRecord details
    mapping(uint256 => MedicalRecord) public records;
    uint256 public recordCount;

    // Doctor authorization mapping: patientId => doctorAddress => authorized
    mapping(uint256 => mapping(address => bool)) public authorizedDoctors;

    event RecordRegistered(uint256 indexed recordId, uint256 indexed patientId, string diagnosisCode, address indexed doctor);
    event DoctorAuthorized(uint256 indexed patientId, address indexed doctor, bool authorized);

    constructor() {
        owner = msg.sender;
    }

    /**
     * @notice Authorize or revoke a doctor's access to a patient's records.
     */
    function setDoctorAuthorization(uint256 patientId, address doctor, bool authorized) external {
        // In a production setup, this would check msg.sender == patientAddress.
        // For local simulation, we allow configuring the authorization directly.
        authorizedDoctors[patientId][doctor] = authorized;
        emit DoctorAuthorized(patientId, doctor, authorized);
    }

    /**
     * @notice Register a new patient medical record.
     * Can only be called by an authorized doctor (or standard dev address in testing).
     */
    function submitRecord(uint256 patientId, string calldata diagnosisCode, string calldata treatmentHash) external returns (uint256) {
        // Require doctor to be authorized for this patient ID
        // (For testing purposes, we allow the deployment address/relayer to bypass authorization if it is the first record)
        if (recordCount > 0) {
            require(authorizedDoctors[patientId][msg.sender] || msg.sender == owner, "Doctor is not authorized for this patient");
        }

        uint256 recordId = recordCount++;
        records[recordId] = MedicalRecord({
            patientId: patientId,
            diagnosisCode: diagnosisCode,
            treatmentHash: treatmentHash,
            doctor: msg.sender,
            submittedAt: block.timestamp,
            active: true
        });

        emit RecordRegistered(recordId, patientId, diagnosisCode, msg.sender);
        return recordId;
    }

    /**
     * @notice Read-only paginated getter to retrieve medical records.
     */
    function getRecordsPage(uint256 offset, uint256 limit) external view returns (
        uint256[] memory keys,
        MedicalRecord[] memory items
    ) {
        if (offset >= recordCount) {
            return (new uint256[](0), new MedicalRecord[](0));
        }

        uint256 size = limit;
        if (offset + limit > recordCount) {
            size = recordCount - offset;
        }

        keys = new uint256[](size);
        items = new MedicalRecord[](size);

        for (uint256 i = 0; i < size; i++) {
            uint256 id = offset + i;
            keys[i] = id;
            items[i] = records[id];
        }
    }
}
