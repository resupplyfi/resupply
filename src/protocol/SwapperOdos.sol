// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { CoreOwnable } from "src/dependencies/CoreOwnable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";

contract SwapperOdos is CoreOwnable, ReentrancyGuard {
    using BytesLib for bytes;
    using SafeERC20 for IERC20;

    address public constant odosRouter = 0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559;
    address public constant registry = 0x10101010E0C3171D894B71B3400668aF311e7D94;
    address public constant reusd = 0x57aB1E0003F623289CD798B1824Be09a793e4Bec;
    uint256 public nextPairIndex;
    bool public approvalsRevoked;

    constructor(address _core) CoreOwnable(_core) {
        IERC20(reusd).forceApprove(odosRouter, type(uint256).max);
    }

    /**
     * @notice Executes a swap through Odos router using an encoded payload in the path parameter
     * @dev This function accepts bytes data encoded as an address[] for compatibility with the legacy interface in PairCore
     */
    function swap(
        address,
        uint256,
        address[] memory _path,
        address
    ) external nonReentrant {
        bytes memory payload = decode(_path);
        (bool success, bytes memory result) = odosRouter.call{value: 0}(payload);
        require(success, "Odos swap failed");
    }

    /**
     * @notice Permissionless function to update the approvals for the collateral tokens that have not yet been approved
     */
    function updateApprovals() external {
        if (!canUpdateApprovals()) return;
        uint256 _nextIndex = nextPairIndex;
        address[] memory pairs = IResupplyRegistry(registry).getAllPairAddresses();
        for (; _nextIndex < pairs.length; _nextIndex++) {
            address _pair = pairs[_nextIndex];
            address _collateral = IResupplyPair(_pair).collateral();
            IERC20(_collateral).forceApprove(odosRouter, type(uint256).max);
        }
        nextPairIndex = _nextIndex;
    }

    function revokeApprovals() external onlyOwner {
        approvalsRevoked = true;
        address[] memory pairs = IResupplyRegistry(registry).getAllPairAddresses();
        for (uint256 i = 0; i < pairs.length; i++) {
            address _pair = pairs[i];
            address _collateral = IResupplyPair(_pair).collateral();
            IERC20(_collateral).forceApprove(odosRouter, 0);
        }
        IERC20(reusd).forceApprove(odosRouter, 0);
    }

    /**
     * @notice Returns true if there are new pairs to update approvals for
     */
    function canUpdateApprovals() public view returns (bool) {
        return !approvalsRevoked && nextPairIndex < IResupplyRegistry(registry).getAllPairAddresses().length;
    }

    /**
     * @notice Encodes any-length bytes into address[] for transport via the pair interface
     * @dev This function is not gas efficient, and should only be used by off-chain calls 
            to prepare a payload for the leveragedPosition or repayWithCollateral functions in a pair.
     * @param payload The bytes payload to encode
     * @return path The encoded address[]
     */
    function encode(bytes memory payload) external pure returns (address[] memory path) {
        uint totalLen = payload.length;
        // determine the total number of chunks needed to store the payload
        // each chunk is 20 bytes, so we add 19 to the total length to ensure result is always rounded up
        uint chunkCount = (totalLen + 19) / 20;
        uint numReservedItems = 1; // 1 to store extra data: the length
        path = new address[](chunkCount + numReservedItems);
        path[0] = address(uint160(totalLen)); // packs into the low 20 bytes (safe)
        for (uint i = 0; i < chunkCount; i++) {
            uint offset = i * 20;
            uint end = offset + 20 > totalLen ? totalLen : offset + 20;
            bytes memory chunk = payload.slice(offset, end - offset);
            // Pad to 20 bytes if needed
            if (chunk.length < 20) {
                bytes memory padded = new bytes(20);
                for (uint j = 0; j < chunk.length; j++) {
                    padded[j] = chunk[j];
                }
                chunk = padded;
            }

            path[i + numReservedItems] = bytesToAddress(chunk);
        }
    }

    /**
     * @notice Decodes an address array back into its original bytes payload
     * @dev The first address in the path contains the total length of the original payload as a uint96
     * @dev Each subsequent address contains 20 bytes of the original payload
     * @param path The address array containing the encoded payload
     * @return payload The decoded bytes payload
     */
    function decode(address[] memory path) public pure returns (bytes memory payload) {
        require(path.length > 0, "Empty path");

        uint totalLen = uint(uint160(path[1]));
        uint numReservedItems = 1;
        uint lastDataIndex = path.length - 1;
        // Append all complete chunks using abi.encodePacked
        for (uint i = numReservedItems; i < lastDataIndex; i++) {
            payload = abi.encodePacked(payload, path[i]);
        }
        uint remainingBytes = totalLen % 20;
        if(remainingBytes == 0){
            remainingBytes = 20;
        }
        payload = abi.encodePacked(payload, addressToBytes(path[lastDataIndex], remainingBytes));
        require(payload.length == totalLen, "Length mismatch");
    }

    function recoverERC20(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function bytesToAddress(bytes memory b) internal pure returns (address a) {
        require(b.length == 20, "Chunk must be 20 bytes");
        assembly {
            a := mload(add(b, 20))
        }
    }

    function addressToBytes(address a, uint256 size) internal pure returns (bytes memory b) {
        b = new bytes(size);
        assembly {
            mstore(add(b, 32), shl(96, a))
        }
    }
}