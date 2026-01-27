// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import { console } from "lib/forge-std/src/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC4626 } from "src/interfaces/IERC4626.sol";
import { Setup } from "test/integration/Setup.sol";
import { CurveLendOperator } from "src/dao/CurveLendOperator.sol";
import { CurveLendMinterFactory } from "src/dao/CurveLendMinterFactory.sol";
import { ICrvusdController } from 'src/interfaces/ICrvusdController.sol';

contract QuickTest is Setup {
    
    CurveLendMinterFactory public factory;
    CurveLendOperator public lender;
    ICrvusdController public crvusdController;
    IERC20 public market;
    IERC4626 public marketVault;
    address public feeReceiver;

    function setUp() public override {
        super.setUp();
    }

    function test_quick() public {

       IERC20 squill = IERC20(address(0x7ebAB7190d3d574ce82D29F2FA1422f18E29969C));
       //vlsquill 0x2aEA77C4757D897AaE2710B8a60280777f504e8c

       bytes memory approval = abi.encodeWithSelector(
            bytes4(keccak256("approve(address,uint256)")), 
            address(0x2aEA77C4757D897AaE2710B8a60280777f504e8c),
            type(uint256).max);
       console.log("approve");
       console.logBytes(approval);
       console.log("\n");

       bytes memory deposit = abi.encodeWithSelector(
            bytes4(keccak256("deposit(uint256,address)")),
            12000000000000000000000,
            address(0x4444444455bF42de586A88426E5412971eA48324));
       console.log("deposit");
       console.logBytes(deposit);
       console.log("\n");


       bytes memory delegate = abi.encodeWithSelector(
            bytes4(keccak256("delegate(address)")),
            address(0xFE11a5009f2121622271e7dd0FD470264e076af6));
       console.log("delegate");
       console.logBytes(delegate);
       console.log("\n");
    
    //registry 0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446

        bytes memory snapshotsetdelegate = abi.encodeWithSelector(
            bytes4(keccak256("setDelegate(bytes32,address)")),
            "openindex.eth",
            address(0xFE11a5009f2121622271e7dd0FD470264e076af6));
       console.log("snapshotsetdelegate");
       console.logBytes(snapshotsetdelegate);
       console.log("\n");

        bytes memory claim = abi.encodeWithSelector(
            bytes4(keccak256("claim()")));
       console.log("claim");
       console.logBytes(claim);
       console.log("\n");  
    }

}