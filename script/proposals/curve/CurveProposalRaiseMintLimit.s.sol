// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Mainnet } from "src/Constants.sol";
import { console } from "lib/forge-std/src/console.sol";
import { BaseCurveProposal } from "script/proposals/curve/BaseCurveProposal.sol";
import { ICrvusdController } from "src/interfaces/ICrvusdController.sol";
import { ICurveLendOperator } from "src/interfaces/curve/ICurveLendOperator.sol";

/// @title CurveProposalRaiseMintLimit
/// @notice Raise the crvUSD lending cap to the sreUSD lending market from 15M to 30M.
/// @dev Mirrors the previously enacted 15M raise (on-chain vote #1259 on Curve Voting
///      Ownership 0xE478de…): debt-ceiling raise routed through the Curve eDAO admin proxy
///      (0xb7400D2E…, the ControllerFactory admin), followed by setMintLimit on the live
///      operator (callable by the Ownership Agent = operator admin).
contract CurveProposalRaiseMintLimit is BaseCurveProposal {

    address public deployer = Mainnet.CONVEX_DEPLOYER;

    /// @notice Build and broadcast the proposal (requires the deployer key in the signer).
    function run() public {
        vm.startBroadcast(deployer);
        bytes memory actions = buildProposalScript();
        proposeRaise(actions, "Raise Lending Limit of crvUSD to the sreUSD Lending Market to 30m");
    }

    /// @notice Build the two-actions execution script.
    function buildProposalScript() public override returns (bytes memory script) {
        BaseCurveProposal.Action[] memory actions = new BaseCurveProposal.Action[](2);

        // Action 1 — raise the crvUSD factory debt ceiling for the CurveLendMinterFactory to 30M.
        // ControllerFactory.admin() == Curve eDAO admin proxy (0xb7400D2E…), so the call is
        // wrapped in eDAOproxy.execute() to make msg.sender == admin — identical to vote #1259.
        actions[0] = _executeViaMintFactoryEDAOProxy(
            Mainnet.CURVE_CRVUSD_CONTROLLER,   // crvUSD ControllerFactory (debt-ceiling setter)
            abi.encodeWithSelector(
                ICrvusdController.set_debt_ceiling.selector,
                Mainnet.CURVE_LENDING_FACTORY, // CurveLendMinterFactory (ceiling subject)
                30_000_000e18                  // new debt ceiling
            )
        );

        // Action 2 — raise the sreUSD operator mint limit to 30M.
        // setMintLimit borrows the incremental 15M from the minter factory and deposits it into
        // the market. Operator.admin() == MinterFactory.admin() == the Ownership Agent, so the
        // Agent's execute() targets the operator directly (no proxy), as in vote #1259.
        actions[1] = BaseCurveProposal.Action({
            target: Mainnet.CURVELEND_SREUSD_CRVUSD_OPERATOR,
            data: abi.encodeWithSelector(
                ICurveLendOperator.setMintLimit.selector,
                30_000_000e18                  // new mint limit (operator mints up to it)
            )
        });

        console.log("Number of actions:", actions.length);
        console.log("Controller factory at: ", Mainnet.CURVE_CRVUSD_CONTROLLER);
        console.log("Lend factory at: ", Mainnet.CURVE_LENDING_FACTORY);
        console.log("sreUSD operator at: ", Mainnet.CURVELEND_SREUSD_CRVUSD_OPERATOR);

        return buildScript(Mainnet.CURVE_OWNERSHIP_AGENT, actions);
    }

    /// @notice Propose on the live Curve Voting Ownership (0xE478de…).
    /// @dev BaseCurveProposal.proposeOwnershipVote encodes newVote(bytes,string,bool,bool), but
    ///      the deployed Voting app only implements newVote(bytes,string) (selector 0xd5db2c80 —
    ///      the signature the prior 15M raise vote #1259 was created with). Call the 2-arg
    ///      overload directly against the verified on-chain ABI.
    function proposeRaise(bytes memory script, string memory metadata) public returns (uint256 proposalId) {
        (bool ok, bytes memory ret) = address(ownershipVoting).call(
            abi.encodeWithSelector(bytes4(0xd5db2c80), script, metadata)
        );
        require(ok, "newVote(bytes,string) failed");

        proposalId = abi.decode(ret, (uint256));
        (,,uint64 start, , ,, , , , bytes memory _script) = ownershipVoting.getVote(proposalId);
        console.log("start: ", start);
        console.logBytes(_script);
    }
}
