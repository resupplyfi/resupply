pragma solidity 0.8.28;

import { BaseAction } from "script/actions/dependencies/BaseAction.sol";
import { Protocol } from "src/Constants.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";
import { CreateX } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";

contract DeployVoter is TenderlyHelper, CreateXHelper, BaseAction {
    address public constant deployer = Protocol.DEPLOYER;
    
    function run() public isBatch(deployer) {
        deployMode = DeployMode.PRODUCTION;

        deployVoter();

        if (deployMode == DeployMode.PRODUCTION) executeBatch(true, 88);
    }

    function deployVoter() public {
        bytes32 salt = CreateX.SALT_VOTER;
        bytes memory constructorArgs = abi.encode(
            address(Protocol.CORE),
            address(Protocol.GOV_STAKER),
            100,    // minCreateProposalPct
            3000    // quorumPct
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("Voter.sol:Voter"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        address predictedAddress = computeCreate3AddressFromSaltPreimage(salt, deployer, true, false);
        console.log("New voter deployed at", predictedAddress);
        require(predictedAddress.code.length > 0, "deployment failed");
        
        IVoter voter = IVoter(predictedAddress);
        console.log("minCreateProposalPct: ", voter.minCreateProposalPct());
        console.log("quorumPct: ", voter.quorumPct());
        console.log("minTimeBetweenProposals: ", voter.minTimeBetweenProposals());
    }
}