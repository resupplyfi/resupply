// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Mainnet } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { ITreasury } from "src/interfaces/ITreasury.sol";
import { BaseCurveProposal } from "script/proposals/curve/BaseCurveProposal.sol";

interface IOwnable2Step {
    function acceptOwnership() external;
}

contract CurveProposalTreasuryStableDiversification is BaseCurveProposal {
    address public constant DIVERSIFIER = 0x70b3d2c2A508A87f9C18F46fe9ca42307CD021f7;
    address public constant TREASURY = 0x6508eF65b0Bd57eaBD0f1D52685A70433B2d290B;

    address public deployer = Mainnet.CONVEX_DEPLOYER;
    address public diversifier = DIVERSIFIER;
    address public treasury = TREASURY;

    function run() public {
        vm.startBroadcast(deployer);
        bytes memory actions = buildProposalScript();

        proposeOwnershipVote(actions, "Accept TreasuryStableDiversification ownership and approve usage of treasury crvUSD");
    }

    function setDeployAddresses(address _diversifier, address _treasury) public {
        diversifier = _diversifier;
        treasury = _treasury;
    }

    function buildProposalScript() public override returns (bytes memory script) {
        BaseCurveProposal.Action[] memory actions = new BaseCurveProposal.Action[](2);

        actions[0] = BaseCurveProposal.Action({
            target: diversifier,
            data: abi.encodeWithSelector(IOwnable2Step.acceptOwnership.selector)
        });

        actions[1] = BaseCurveProposal.Action({
            target: treasury,
            data: abi.encodeWithSelector(
                ITreasury.setTokenApproval.selector,
                Mainnet.CRVUSD_ERC20,
                diversifier,
                type(uint256).max
            )
        });

        console.log("Number of actions:", actions.length);
        console.log("diversifier:", diversifier);
        console.log("treasury:", treasury);
        console.log("crvUSD:", Mainnet.CRVUSD_ERC20);

        return buildScript(Mainnet.CURVE_OWNERSHIP_AGENT, actions);
    }
}
