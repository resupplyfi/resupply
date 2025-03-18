import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { ICore } from "src/interfaces/ICore.sol";
import { Protocol } from "script/protocol/ProtocolConstants.sol";

contract BaseAction is TenderlyHelper {
    address public core = Protocol.CORE;

    function _executeCore(address _target, bytes memory _data) internal returns (bytes memory) {
        return addToBatch(
            core,
            abi.encodeWithSelector(
                ICore.execute.selector, address(_target), _data
            )
        );
    }
}