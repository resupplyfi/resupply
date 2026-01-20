// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { IVoter } from "src/interfaces/IVoter.sol";
import { BaseProposal } from "script/proposals/BaseProposal.sol";
import { IPrismaFactory } from "src/interfaces/IPrismaFactory.sol";

contract RedeemPsm is BaseProposal {
    IPrismaFactory public constant factoryMkUsd = IPrismaFactory(0x70b66E20766b775B2E9cE5B718bbD285Af59b7E1);
    IPrismaFactory public constant factoryUltra = IPrismaFactory(0xDb2222735e926f3a18D7d1D0CFeEf095A66Aea2A);

    address public constant REDEEMER_MKUSD = 0x8ccc7a5871fE5A844bccd407E15B4b6dCBC3700e;
    address public constant REDEEMER_ULTRA = 0xF43c6EaE516eCc807978737Fc66b1FaB0413369F;

    function run() public isBatch(deployer) {
        deployMode = DeployMode.FORK;

        IVoter.Action[] memory data = buildProposalCalldata();
        proposeVote(data, "Deploy Prisma PSM redeemers for mkUSD and Ultra factories");

        if (deployMode == DeployMode.PRODUCTION) {
            executeBatch(true);
        }
    }

    function buildProposalCalldata() public override returns (IVoter.Action[] memory actions) {
        actions = new IVoter.Action[](2);

        IPrismaFactory.DeploymentParams memory params = IPrismaFactory.DeploymentParams({
            minuteDecayFactor: 100,
            redemptionFeeFloor: 0,
            maxRedemptionFee: 0,
            borrowingFeeFloor: 0,
            maxBorrowingFee: 0,
            interestRateInBps: 0,
            maxDebt: 0,
            MCR: 0
        });

        // 1: Deploy redeemer instance for mkUSD factory
        actions[0] = IVoter.Action({
            target: address(factoryMkUsd),
            data: abi.encodeWithSelector(
                IPrismaFactory.deployNewInstance.selector,
                address(0),
                address(0),
                REDEEMER_MKUSD,
                address(0),
                params
            )
        });

        // 2: Deploy redeemer instance for Ultra factory
        actions[1] = IVoter.Action({
            target: address(factoryUltra),
            data: abi.encodeWithSelector(
                IPrismaFactory.deployNewInstance.selector,
                address(0),
                address(0),
                REDEEMER_ULTRA,
                address(0),
                params
            )
        });

        console.log("Number of actions:", actions.length);
        console.log("Factory mkUSD:", address(factoryMkUsd));
        console.log("Factory Ultra:", address(factoryUltra));
    }
}