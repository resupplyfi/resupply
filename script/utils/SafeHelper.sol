// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

// 💬 ABOUT
// Gnosis Safe transaction batching script

// 🧩 MODULES
import {Script, console2, StdChains, stdJson, stdMath, StdStorage, stdStorageSafe, VmSafe} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import {Surl} from "lib/surl/src/Surl.sol";

// ⭐️ SCRIPT
abstract contract SafeHelper is Script, Test {
    using stdJson for string;
    using Surl for *;

    //     "to": "<checksummed address>",
    //     "value": 0, // Value in wei
    //     "data": "<0x prefixed hex string>",
    //     "operation": 0,  // 0 CALL, 1 DELEGATE_CALL
    //     "safeTxGas": 0,  // Max gas to use in the transaction

    // Used by refund mechanism, not needed here
    //     "gasToken": "<checksummed address>", // Token address (hold by the Safe) to be used as a refund to the sender, if `null` is Ether
    //     "baseGas": 0,  // Gast costs not related to the transaction execution (signature check, refund payment...)
    //     "gasPrice": 0,  // Gas price used for the refund calculation
    //     "refundReceiver": "<checksummed address>", //Address of receiver of gas payment (or `null` if tx.origin)

    //     "nonce": 0,  // Nonce of the Safe, transaction cannot be executed until Safe's nonce is not equal to this nonce
    //     "contractTransactionHash": "string",  // Contract transaction hash calculated from all the field
    //     "sender": "<checksummed address>",  // Owner of the Safe proposing the transaction. Must match one of the signatures
    //     "signature": "<0x prefixed hex string>",  // One or more ethereum ECDSA signatures of the `contractTransactionHash` as an hex string

    // Not required
    //     "origin": "string"  // Give more information about the transaction, e.g. "My Custom Safe app"

    // Hash constants
    // Safe version for this script, hashes below depend on this
    string private constant VERSION = "1.4.1";

    // keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH =
        0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

    // keccak256(
    //     "SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)"
    // );
    bytes32 private constant SAFE_TX_TYPEHASH =
        0xbb8310d486368db6bd6f849402fdd73ad53d316b5a4b2644ad6efe0f941286d8;

    // Deterministic deployment address of the Gnosis Safe Multisend contract, configured by chain.
    address private SAFE_MULTISEND_ADDRESS;

    // Chain ID, configured by chain.
    uint256 private chainId;

    // Safe API base URL, configured by chain.
    string private SAFE_API_BASE_URL;
    string private constant SAFE_API_MULTISIG_SEND = "/multisig-transactions/";

    // Wallet information
    bytes32 private walletType;
    uint256 private mnemonicIndex;
    bytes32 private privateKey;

    bytes32 private constant LOCAL = keccak256("local");
    bytes32 private constant LEDGER = keccak256("ledger");

    // Address to send transaction from
    address private safe;

    DeployMode public deployMode = DeployMode.PRODUCTION;

    // Gas tracking
    uint256 public totalGasUsed;

    enum Operation {
        CALL,
        DELEGATECALL
    }

    enum DeployMode {
        PRODUCTION,
        FORK
    }

    struct Batch {
        address to;
        uint256 value;
        bytes data;
        Operation operation;
        uint256 safeTxGas;
        uint256 baseGas;
        uint256 gasPrice;
        address gasToken;
        address refundReceiver;
        uint256 nonce;
        bytes32 txHash;
        bytes signature;
    }

    // New struct to track a batch and its gas
    struct BatchData {
        bytes[] encodedTxns; // Array to store encoded transactions
        uint256 totalGas;    // Total gas used by the batch
    }

    // Replace single array with array of batches
    BatchData[] public batches;
    
    // Current batch index
    uint256 private currentBatchIndex;
    
    // Maximum gas per batch
    uint256 public maxGasPerBatch = 12_000_000;

    constructor() {
        // Initialize first batch
        batches.push(BatchData({
            encodedTxns: new bytes[](0),
            totalGas: 0
        }));
    }

    modifier isBatch(address safe_) {
        // Set the Safe API base URL and multisend address based on chain
        chainId = block.chainid;
        SAFE_API_BASE_URL = string.concat("https://safe-client.safe.global/v1/chains/", vm.toString(chainId), "/");
        SAFE_MULTISEND_ADDRESS = 0x40A2aCCbd92BCA938b02010E17A5b8929b49130D;
        safe = safe_;

        // Load wallet information
        walletType = keccak256(abi.encodePacked(vm.envString("WALLET_TYPE")));
        if (walletType == LOCAL) {
            privateKey = vm.envBytes32("SAFE_PROPOSER_PRIVATE_KEY");
        } else if (walletType == LEDGER) {
            mnemonicIndex = vm.envUint("MNEMONIC_INDEX");
        } else {
            revert("Unsupported wallet type");
        }
        _;
    }

    // Adds an encoded transaction to the batch.
    // Encodes the transaction as packed bytes of:
    // - `operation` as a `uint8` with `0` for a `call` or `1` for a `delegatecall` (=> 1 byte),
    // - `to` as an `address` (=> 20 bytes),
    // - `value` as in msg.value, sent as a `uint256` (=> 32 bytes),
    // -  length of `data` as a `uint256` (=> 32 bytes),
    // - `data` as `bytes`.
    function addToBatch(
        address to_,
        uint256 value_,
        bytes memory data_
    ) internal returns (bytes memory) {
        if (deployMode == DeployMode.FORK) vm.startBroadcast(safe);
        if (deployMode != DeployMode.FORK) vm.prank(safe);

        // Simulate transaction to get gas used
        uint256 gasStart = gasleft();
        (bool success, bytes memory returnData) = to_.call{value: value_}(data_);
        uint256 gasUsed = gasStart - gasleft();
        if (deployMode == DeployMode.FORK) vm.stopBroadcast();

        uint256 gasInCurrentBatch = batches[currentBatchIndex].totalGas;
        // Check if adding this transaction would exceed our max gas limit. If so create a new batch.
        if (gasInCurrentBatch + gasUsed > maxGasPerBatch) {
            currentBatchIndex++;
            batches.push(BatchData({
                encodedTxns: new bytes[](0),
                totalGas: 0
            }));
        }

        // Encode the transaction and add it to the current batch
        bytes memory encodedTxn = abi.encodePacked(Operation.CALL, to_, value_, data_.length, data_);
        batches[currentBatchIndex].encodedTxns.push(encodedTxn);
        batches[currentBatchIndex].totalGas += gasUsed;

        if (success) {
            return returnData;
        } else {
            revert(string(returnData));
        }
    }

    // Helper to call `addToBatch` with implied 0 value.
    function addToBatch(
        address to_,
        bytes memory data_
    ) internal returns (bytes memory) {
        return addToBatch(to_, 0, data_);
    }

    // Executes all batches, sending each to the Safe API
    function executeBatch(bool send_) internal {
        for (uint256 i = 0; i <= currentBatchIndex; i++) {
            Batch memory batch = _createBatchFromIndex(i);
            if (send_) {
                batch = _signBatch(safe, batch);
                _sendBatch(safe, batch);
            }
        }
    }

    // Creates a batch from the transactions at the specified index
    function _createBatchFromIndex(uint256 batchIndex) private returns (Batch memory batch) {
        batch.to = SAFE_MULTISEND_ADDRESS;
        batch.value = 0;
        batch.operation = Operation.DELEGATECALL;

        // Concatenate all encoded transactions into a single data payload
        bytes memory data;
        uint256 len = batches[batchIndex].encodedTxns.length;
        for (uint256 i; i < len; ++i) {
            data = bytes.concat(data, batches[batchIndex].encodedTxns[i]);
        }
        batch.data = abi.encodeWithSignature("multiSend(bytes)", data);
        batch.nonce = batchIndex;// _getNonce(safe);
        batch.txHash = _getTransactionHash(safe, batch);
        return batch;
    }

    // Returns information about a specific batch
    function getBatchInfo(uint256 batchIndex) public view returns (uint256 txCount, uint256 gasUsed) {
        require(batchIndex <= currentBatchIndex, "Invalid batch index");
        return (
            batches[batchIndex].encodedTxns.length,
            batches[batchIndex].totalGas
        );
    }

    // Returns the total number of batches
    function getTotalBatches() public view returns (uint256) {
        return currentBatchIndex + 1;
    }

    function _signBatch(
        address safe_,
        Batch memory batch_
    ) private returns (Batch memory) {
        // Get the typed data to sign
        string memory typedData = _getTypedData(safe_, batch_);

        // Construct the sign command
        string memory commandStart = "cast wallet sign ";
        string memory wallet;
        if (walletType == LOCAL) {
            wallet = string.concat(
                "--private-key ",
                vm.toString(privateKey),
                " "
            );
        } else if (walletType == LEDGER) {
            wallet = string.concat(
                "--ledger --mnemonic-index ",
                vm.toString(mnemonicIndex),
                " "
            );
        } else {
            revert("Unsupported wallet type");
        }
        string memory commandEnd = "--data ";

        // Sign the typed data from the CLI and get the signature
        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = string.concat(
            commandStart,
            wallet,
            commandEnd,
            "'",
            typedData,
            "'"
        );
        bytes memory signature = vm.ffi(inputs);

        // Set the signature on the batch
        batch_.signature = signature;

        return batch_;
    }

    function _getSignerAddress() private returns (address signer) {
        if (walletType == LOCAL) {
            signer = vm.addr(uint256(privateKey));
        } else { // LEDGER
            // For Ledger, we'll need the address from the derivation path
            string[] memory inputs = new string[](4);
            inputs[0] = "cast";
            inputs[1] = "wallet";
            inputs[2] = "address";
            inputs[3] = string.concat("--ledger --mnemonic-index ", vm.toString(mnemonicIndex));
            bytes memory addr = vm.ffi(inputs);
            signer = address(bytes20(addr));
        }
    }

    function _sendBatch(address safe_, Batch memory batch_) private {
        string memory endpoint = _getSafeTransactionAPIEndpoint(safe_);

        // Create json payload for API call to Gnosis transaction service
        string memory placeholder = "";
        placeholder.serialize("safe", safe_);
        placeholder.serialize("to", batch_.to);
        placeholder.serialize("value", vm.toString(batch_.value));
        placeholder.serialize("data", batch_.data);
        placeholder.serialize("operation", uint256(batch_.operation));
        placeholder.serialize("gasToken", address(0));
        placeholder.serialize("safeTxGas", vm.toString(batch_.safeTxGas));
        placeholder.serialize("baseGas", vm.toString(batch_.baseGas));
        placeholder.serialize("gasPrice", vm.toString(batch_.gasPrice));
        string memory txnHash = vm.toString(batch_.txHash);
        string memory sig = bytesToHexString(batch_.signature);
        placeholder.serialize("contractTransactionHash", txnHash);
        console2.log('txnHash',txnHash);
        console2.log('signer',_getSignerAddress());
        console2.log('signature',sig);
        placeholder.serialize("safeTxHash", txnHash);
        placeholder.serialize("refundReceiver", address(0));
        placeholder.serialize("nonce", vm.toString(batch_.nonce));
        placeholder.serialize("signature", sig);
        string memory payload = placeholder.serialize("sender", vm.toString(_getSignerAddress()));

        // Send batch
        (uint256 status, bytes memory data) = endpoint.post(
            _getHeaders(),
            payload
        );

        if (status == 200 || status == 201) {
            console2.log("Batch sent successfully");
        } else {
            // console2.log(string(data));
            revert("Send batch failed!");
        }
    }

    // Computes the EIP712 hash of a Safe transaction.
    // Look at https://github.com/safe-global/safe-eth-py/blob/174053920e0717cc9924405e524012c5f953cd8f/gnosis/safe/safe_tx.py#L186
    // and https://github.com/safe-global/safe-eth-py/blob/master/gnosis/eth/eip712/__init__.py
    function _getTransactionHash(
        address safe_,
        Batch memory batch_
    ) private view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    hex"1901",
                    keccak256(
                        abi.encode(DOMAIN_SEPARATOR_TYPEHASH, chainId, safe_)
                    ),
                    keccak256(
                        abi.encode(
                            SAFE_TX_TYPEHASH,
                            batch_.to,
                            batch_.value,
                            keccak256(batch_.data),
                            batch_.operation,
                            batch_.safeTxGas,
                            batch_.baseGas,
                            batch_.gasPrice,
                            address(0),
                            address(0),
                            batch_.nonce
                        )
                    )
                )
            );
    }

    function _getTypedData(
        address safe_,
        Batch memory batch_
    ) private returns (string memory) {
        // Create EIP712 structured data for the batch transaction to sign externally via cast

        // EIP712Domain Field Types
        string[] memory domainTypes = new string[](2);
        string memory t = "domainType0";
        vm.serializeString(t, "name", "verifyingContract");
        domainTypes[0] = vm.serializeString(t, "type", "address");
        t = "domainType1";
        vm.serializeString(t, "name", "chainId");
        domainTypes[1] = vm.serializeString(t, "type", "uint256");

        // SafeTx Field Types
        string[] memory txnTypes = new string[](10);
        t = "txnType0";
        vm.serializeString(t, "name", "to");
        txnTypes[0] = vm.serializeString(t, "type", "address");
        t = "txnType1";
        vm.serializeString(t, "name", "value");
        txnTypes[1] = vm.serializeString(t, "type", "uint256");
        t = "txnType2";
        vm.serializeString(t, "name", "data");
        txnTypes[2] = vm.serializeString(t, "type", "bytes");
        t = "txnType3";
        vm.serializeString(t, "name", "operation");
        txnTypes[3] = vm.serializeString(t, "type", "uint8");
        t = "txnType4";
        vm.serializeString(t, "name", "safeTxGas");
        txnTypes[4] = vm.serializeString(t, "type", "uint256");
        t = "txnType5";
        vm.serializeString(t, "name", "baseGas");
        txnTypes[5] = vm.serializeString(t, "type", "uint256");
        t = "txnType6";
        vm.serializeString(t, "name", "gasPrice");
        txnTypes[6] = vm.serializeString(t, "type", "uint256");
        t = "txnType7";
        vm.serializeString(t, "name", "gasToken");
        txnTypes[7] = vm.serializeString(t, "type", "address");
        t = "txnType8";
        vm.serializeString(t, "name", "refundReceiver");
        txnTypes[8] = vm.serializeString(t, "type", "address");
        t = "txnType9";
        vm.serializeString(t, "name", "nonce");
        txnTypes[9] = vm.serializeString(t, "type", "uint256");

        // Create the top level types object
        t = "topLevelTypes";
        t.serialize("EIP712Domain", domainTypes);
        string memory types = t.serialize("SafeTx", txnTypes);

        // Create the message object
        string memory m = "message";
        m.serialize("to", batch_.to);
        m.serialize("value", batch_.value);
        m.serialize("data", batch_.data);
        m.serialize("operation", uint256(batch_.operation));
        m.serialize("safeTxGas", batch_.safeTxGas);
        m.serialize("baseGas", batch_.baseGas);
        m.serialize("gasPrice", batch_.gasPrice);
        m.serialize("gasToken", address(0));
        m.serialize("refundReceiver", address(0));
        string memory message = m.serialize("nonce", batch_.nonce);

        // Create the domain object
        string memory d = "domain";
        d.serialize("verifyingContract", safe_);
        string memory domain = d.serialize("chainId", chainId);

        // Create the payload object
        string memory p = "payload";
        p.serialize("types", types);
        vm.serializeString(p, "primaryType", "SafeTx");
        p.serialize("domain", domain);
        string memory payload = p.serialize("message", message);

        payload = _stripSlashQuotes(payload);

        return payload;
    }

    function _stripSlashQuotes(
        string memory str_
    ) private returns (string memory) {
        // Remove slash quotes from string
        string memory command = string.concat(
            "sed 's/",
            '\\\\"/"',
            "/g; s/",
            '\\"',
            "\\[/\\[/g; s/",
            '\\]\\"',
            "/\\]/g; s/",
            '\\"',
            "{/{/g; s/",
            '}\\"',
            "/}/g;' <<< "
        );

        string[] memory inputs = new string[](3);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = string.concat(command, "'", str_, "'");
        bytes memory res = vm.ffi(inputs);

        return string(res);
    }

    function _getNonce(address safe_) private returns (uint256) {
        string memory endpoint = string.concat(
            _getSafeNonceAPIEndpoint(safe_)
        );
        (uint256 status, bytes memory data) = endpoint.get();
        if (status == 200) {
            string memory resp = string(data);
            return resp.readUint(".recommendedNonce");
        } else {
            revert(string(abi.encodePacked("Error fetching nonce: ", vm.toString(status), ", ", string(data))));
        }
    }

    function _getSafeTransactionAPIEndpoint(
        address safe_
    ) private view returns (string memory) {
        return
            string.concat(
                SAFE_API_BASE_URL,
                'transactions/',
                vm.toString(safe_),
                '/propose'
            );
    }

    function _getSafeNonceAPIEndpoint(
        address safe_
    ) private view returns (string memory) {
        return
            string.concat(
                SAFE_API_BASE_URL,
                'safes/',
                vm.toString(safe_),
                '/nonces'
            );
    }

    function _getHeaders() private pure returns (string[] memory) {
        string[] memory headers = new string[](1);
        headers[0] = "Content-Type: application/json";
        return headers;
    }

    // Signatures need to be converted to hex strings with 0x prefix
    function bytesToHexString(bytes memory data) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory hexString = new bytes(data.length * 2);

        for (uint256 i = 0; i < data.length; i++) {
            hexString[i * 2] = hexChars[uint8(data[i] >> 4)];
            hexString[i * 2 + 1] = hexChars[uint8(data[i] & 0x0f)];
        }

        return string(abi.encodePacked("0x", hexString));
    }
}