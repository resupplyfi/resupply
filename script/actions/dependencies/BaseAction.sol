import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { Protocol } from "script/protocol/ProtocolConstants.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";

contract BaseAction is TenderlyHelper {
    address public core = Protocol.CORE;
    uint256 public epochLength;
    uint256 public startTime;

    constructor() {
        epochLength = ICore(core).epochLength();
        startTime = ICore(core).startTime();
    }

    function _executeCore(address _target, bytes memory _data) internal returns (bytes memory) {
        return addToBatch(
            core,
            abi.encodeWithSelector(
                ICore.execute.selector, address(_target), _data
            )
        );
    }

    function _executeTreasury(address _target, bytes memory _data) internal returns (bytes memory) {
        bytes memory result = _executeCore(
            Protocol.TREASURY,
            abi.encodeWithSelector(
                ITreasury.safeExecute.selector, 
                _target, 
                _data
            )
        );
        return abi.decode(result, (bytes));
    }

    function setCorePermissions(
        bytes4 selector, 
        address caller, 
        address target, 
        bool approve,
        address authHook
    ) internal {
        _executeCore(
            address(Protocol.CORE),
            abi.encodeWithSelector(
                ICore.setOperatorPermissions.selector,
                caller,
                target,
                selector,
                approve,
                authHook
            )
        );
    }
}