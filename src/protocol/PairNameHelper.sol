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

    address public immutable registry;
    ProtocolData[] public protocols;
    mapping(
        uint256 platformId => mapping(
        address collateral => mapping(
        address borrow => mapping(
        address collat => uint256 id
    )))) public collateralId;

    struct ProtocolData {
        string protocolName;
        bytes4 borrowLookupSig;
        bytes4 collateralLookupSig;
    }

    event ProtocolDataUpdated(
        string protocolName, 
        bytes4 borrowLookupSig, 
        bytes4 collateralLookupSig
    );

    constructor(address _core, address _registry) CoreOwnable(_core) {
        registry = _registry;
    }

    /**
     * @notice Get the next name for a collateral
     * @param _collateral The collateral address
     * @return _name The next name for the collateral following the protocol naming convention
     * @dev The naming convention is:
     * - Resupply Pair (Protocol: BorrowTokenSymbol/CollateralTokenSymbol) - Collateral ID
     */
    function getNextName(
        uint256 platformId,
        address _collateral
    ) external view returns (string memory _name) {
        uint256 length = protocols.length;
        if (platformId >= length) revert ProtocolNotFound();
        ProtocolData memory pData = protocols[platformId];

        // Get token addresses using protocol-specific function signatures
        (bool successBorrow, bytes memory borrowData) = _collateral.staticcall(abi.encodeWithSelector(pData.borrowLookupSig));
        (bool successCollat, bytes memory collatData) = _collateral.staticcall(abi.encodeWithSelector(pData.collateralLookupSig));
        
        require(successBorrow && borrowData.length >= 32, "Borrow token lookup failed");
        require(successCollat && collatData.length >= 32, "Collateral token lookup failed");
        
        address borrowToken = abi.decode(borrowData, (address));
        address collatToken = abi.decode(collatData, (address));
        
        string memory borrowSymbol = IERC20(borrowToken).safeSymbol();
        string memory collatSymbol = IERC20(collatToken).safeSymbol();

        uint256 _collateralId = collateralId[platformId][_collateral][borrowToken][collatToken] + 1;

        _name = string(
            abi.encodePacked(
                "Resupply Pair (",
                pData.protocolName,
                ": ",
                borrowSymbol,
                "/",
                collatSymbol,
                ") - ",
                _collateralId.toString()
            )
        );

        // If no protocol match found, use default Resupply naming
        if (bytes(_name).length == 0) {
            _name = _formatDefaultName(_collateral, _collateralId);
        }
    }

    function addProtocolData(
        string memory _protocolName,
        bytes4 _borrowLookupSig,
        bytes4 _collateralLookupSig
    ) external onlyOwner returns (uint256) {
        if (bytes(_protocolName).length == 0) revert ProtocolNameEmpty();
        if (bytes(_protocolName).length > 50) revert ProtocolNameTooLong();
        
        // Check if protocol already exists
        uint256 length = protocols.length;
        for (uint256 i = 0; i < length; i++) {
            if (keccak256(bytes(protocols[i].protocolName)) == keccak256(bytes(_protocolName))) {
                revert ProtocolAlreadyExists();
            }
        }
        
        // Add new protocol
        protocols.push(ProtocolData({
            protocolName: _protocolName,
            borrowLookupSig: _borrowLookupSig,
            collateralLookupSig: _collateralLookupSig
        }));
        emit ProtocolDataUpdated(_protocolName, _borrowLookupSig, _collateralLookupSig);
        return length;
    }

    function updateProtocolData(
        uint256 platformId,
        string memory _protocolName,
        bytes4 _borrowLookupSig,
        bytes4 _collateralLookupSig
    ) external onlyOwner returns (uint256) {
        if (bytes(_protocolName).length == 0) revert ProtocolNameEmpty();
        if (bytes(_protocolName).length > 50) revert ProtocolNameTooLong();
        if (platformId >= protocols.length) revert ProtocolNotFound();
        protocols[platformId].protocolName = _protocolName;
        protocols[platformId].borrowLookupSig = _borrowLookupSig;
        protocols[platformId].collateralLookupSig = _collateralLookupSig;
        emit ProtocolDataUpdated(_protocolName, _borrowLookupSig, _collateralLookupSig);
        return platformId;
    }

    function platformNameById(
        uint256 platformId
    ) external view returns (string memory) {
        return protocols[platformId].protocolName;
    }

    function _formatDefaultName(
        address _collateral,
        uint256 _id
    ) internal view returns (string memory) {
        string memory _baseName = string(
            abi.encodePacked(
                "Resupply Pair (",
                IERC20(_collateral).safeSymbol(),
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
    error ProtocolNotSupported();
    error ProtocolNameEmpty();
    error ProtocolNameTooLong();
    error ProtocolAlreadyExists();
}