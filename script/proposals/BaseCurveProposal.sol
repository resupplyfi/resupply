// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Protocol, Mainnet } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { ICurveVoting } from "src/interfaces/curve/ICurveVoting.sol";
import {Script} from "lib/forge-std/src/Script.sol";


abstract contract BaseCurveProposal is Script{
    ICurveVoting public constant ownershipVoting = ICurveVoting(Mainnet.CURVE_OWNERSHIP_VOTING);
    ICurveVoting public constant parameterVoting = ICurveVoting(Mainnet.CURVE_PARAMETER_VOTING);

    address public constant ConvexVoter = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;
    

    struct Action{
        address target;
        bytes data;
    }

    constructor() {
    }
    

    function proposeOwnershipVote(bytes memory script, string memory metadata) public returns(uint256 proposalId){

        // bytes memory script = buildScript(Mainnet.CURVE_OWNERSHIP_AGENT, actions);

        proposalId = ownershipVoting.newVote(script, metadata, false, false);

        (,,uint64 start, , ,, , , , bytes memory _script) = ownershipVoting.getVote(proposalId);
        console.log("start: ", start);
        console.logBytes(_script);
    }

    function buildScript(address agent, Action[] memory actions) internal returns(bytes memory script){
        script = abi.encodePacked(uint32(1));

        for(uint256 i=0; i < actions.length; i++){
            bytes memory actiondata = encodeAction(actions[i]);
            script = abi.encodePacked(script, agent, uint32(actiondata.length), actiondata);
        }
        console.logBytes(script);
    }

    function encodeAction(Action memory action) internal returns(bytes memory){
        return abi.encodeWithSelector(ICurveVoting.execute.selector, action.target, 0, action.data);
    }

    function printCallData(Action[] memory actions) public {
        for (uint256 i = 0; i < actions.length; i++) {
            console.log("Action", i+1);
            console.log(actions[i].target);
            console.logBytes(actions[i].data);
        }
    }

    function buildProposalScript() public virtual returns (bytes memory actions);
    /*
    example add gauge
    actions[0] = BaseCurveProposal.Action({
        target: address(0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB),
        data: abi.encodeWithSelector(
            bytes4(keccak256("add_gauge(address,int128,uint256)")), 
            address(0x1169ba7f4204F26Ff5aF55A7aAFbdAaDFDf9FAA2),
            0,
            0)
    });

    script = buildScript(actions)

    should build the script:
    0x0000000140907540d8a6c65c637785e8f8b742ae6b0b996800000104b61d27f60000000000000000000000002f50d538606fa9edd2b11e2446beb18c9d5846bb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000006418dfe9210000000000000000000000001169ba7f4204f26ff5af55a7aafbdaadfdf9faa20000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

    */
}