// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CoreOwnable } from '../dependencies/CoreOwnable.sol';
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { SafeERC20 } from "../libraries/SafeERC20.sol";
import { IResupplyRegistry } from "../interfaces/IResupplyRegistry.sol";


contract PairNameHelper is CoreOwnable {
    using Strings for uint256;
    using SafeERC20 for IERC20;

    mapping(address => uint256) public collateralId;
    address public immutable resupplyRegistry;
    ProtocolData[] public protocols;

    struct ProtocolData {
        address registry;
        string protocolName;
        bytes4 regsitryLookupSig;
        bytes4 registryLookupValue; // 0x00000000 to use collateral address
        bytes4 borrowLookupSig;
        bytes4 collateralLookupSig;
        bool supported;
    }

    event ProtocolDataUpdated(
        address indexed registry,
        string protocolName, 
        bytes4 regsitryLookupSig,
        bytes4 registryLookupValue,
        bytes4 borrowLookupSig, 
        bytes4 collateralLookupSig,
        bool indexed supported
    );

    

    constructor(address _core, address _resupplyRegistry) CoreOwnable(_core) {
        resupplyRegistry = _resupplyRegistry;
    }

    function setProtocolData(
        string memory _protocolName,
        address _registry,
        bytes4 _registryLookupSig,
        bytes4 _registryLookupValue,
        bytes4 _borrowLookupSig,
        bytes4 _collateralLookupSig,
        bool _supported
    ) external onlyOwner {
        require(bytes(_protocolName).length > 0, "Protocol name cannot be empty");
        require(_registry != address(0), "Registry cannot be zero address");
        
        // Check if protocol already exists
        uint256 length = protocols.length;
        for (uint256 i = 0; i < length; i++) {
            if (keccak256(bytes(protocols[i].protocolName)) == keccak256(bytes(_protocolName))) {
                protocols[i].registry = _registry;
                protocols[i].regsitryLookupSig = _registryLookupSig;
                protocols[i].registryLookupValue = _registryLookupValue;
                protocols[i].borrowLookupSig = _borrowLookupSig;
                protocols[i].collateralLookupSig = _collateralLookupSig;
                protocols[i].supported = _supported;
                emit ProtocolDataUpdated(_registry, _protocolName, _registryLookupSig, _registryLookupValue, _borrowLookupSig, _collateralLookupSig, _supported);
                return;
            }
        }
        
        // Add new protocol if not found
        protocols.push(ProtocolData({
            registry: _registry,
            protocolName: _protocolName,
            regsitryLookupSig: _registryLookupSig,
            registryLookupValue: _registryLookupValue,
            borrowLookupSig: _borrowLookupSig,
            collateralLookupSig: _collateralLookupSig,
            supported: _supported
        }));
        emit ProtocolDataUpdated(_registry, _protocolName, _registryLookupSig, _registryLookupValue, _borrowLookupSig, _collateralLookupSig, _supported);
    }

    /**
     * @notice Get the next name for a collateral
     * @param _collateral The collateral address
     * @return _name The next name for the collateral following the protocol naming convention
     * @dev The naming convention is:
     * - Resupply Pair (Protocol: BorrowTokenSymbol/CollateralTokenSymbol) - Collateral ID
     */
    function getNextName(
        address _collateral
    ) external view returns (string memory _name) {
        uint256 _collateralId = IResupplyRegistry(resupplyRegistry).collateralId(_collateral) + 1;
        uint256 length = protocols.length;
        for (uint256 i = 0; i < length; i++) {
            address registry = protocols[i].registry;
            
            // Prepare registry lookup input based on registryLookupValue
            bytes memory lookupInput;
            
            if (protocols[i].registryLookupValue == bytes4(0)) {
                lookupInput = abi.encode(_collateral);
            } else {
                (bool success, bytes memory data) = _collateral.staticcall(abi.encodeWithSelector(protocols[i].registryLookupValue));
                require(success, "Registry lookup failed");
                lookupInput = abi.decode(data, (bytes));
            }
            
            // Call registry with lookup signature and input
            (bool success, bytes memory data) = registry.staticcall(
                abi.encodeWithSelector(protocols[i].regsitryLookupSig, lookupInput)
            );
            if (!success || !abi.decode(data, (bool))) continue;
            
            // Find matching protocol data
            string memory protocolName;
            bytes4 borrowSig;
            bytes4 collateralSig;
            
            for (uint256 j = 0; j < protocols.length; j++) {
                if (protocols[j].registry == registry && protocols[j].supported) {
                    protocolName = protocols[j].protocolName;
                    borrowSig = protocols[j].borrowLookupSig;
                    collateralSig = protocols[j].collateralLookupSig;
                    break;
                }
            }
            
            if (bytes(protocolName).length == 0) revert ProtocolNotFound(); // Collateral not supported by any protocol registry
            // Get token addresses using protocol-specific function signatures
            (bool successBorrow, bytes memory borrowData) = _collateral.staticcall(abi.encodeWithSelector(borrowSig));
            (bool successCollat, bytes memory collatData) = _collateral.staticcall(abi.encodeWithSelector(collateralSig));
            
            require(successBorrow && successCollat, "Token lookup failed");
            
            address borrowToken = abi.decode(borrowData, (address));
            address collatToken = abi.decode(collatData, (address));
            
            string memory borrowSymbol = IERC20(borrowToken).safeName();
            string memory collatSymbol = IERC20(collatToken).safeName();
            
            _name = string(
                abi.encodePacked(
                    "Resupply Pair (",
                    protocolName,
                    ": ",
                    borrowSymbol,
                    "/",
                    collatSymbol,
                    ") - ",
                    _collateralId.toString()
                )
            );
            break;
        }

        // If no protocol match found, use default Resupply naming
        if (bytes(_name).length == 0) {
            _name = _formatDefaultName(_collateral, _collateralId);
        }

        // Verify name uniqueness
        if(IResupplyRegistry(resupplyRegistry).pairsByName(_name) != address(0)){
            revert NonUniqueName();
        }
    }

    function _formatDefaultName(
        address _collateral,
        uint256 _id
    ) internal view returns (string memory) {
        string memory _baseName = string(
            abi.encodePacked(
                "Resupply Pair (",
                IERC20(_collateral).safeName(),
                ")"
            )
        );
        return string(abi.encodePacked(_baseName, " - ", _id.toString()));
    }

    // ============================================================================================
    // Errors
    // ============================================================================================

    error NonUniqueName();
    error ProtocolNotFound();
}
