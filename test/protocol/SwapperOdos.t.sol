// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "src/Constants.sol" as Constants;
import { console } from "lib/forge-std/src/console.sol";
import { SwapperOdos } from "src/protocol/SwapperOdos.sol";
import { PairTestBase } from "test/protocol/PairTestBase.t.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BytesLib } from "solidity-bytes-utils/contracts/BytesLib.sol";
import { OdosApi } from "test/utils/OdosApi.sol";
import { ResupplyPair } from "src/protocol/ResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { ResupplyPairDeployer } from "src/protocol/ResupplyPairDeployer.sol";

contract SwapperOdosTest is PairTestBase {
    SwapperOdos public swapper;
    address public weth = OdosApi.WETH;
    address public usdc = OdosApi.USDC;
    bytes public odosPayload;
    ResupplyPair public newPair;
    address public _core = 0xc07e000044F95655c11fda4cD37F70A94d7e0a7d;
    ResupplyPairDeployer pairDeployer = ResupplyPairDeployer(0x5555555524De7C56C1B20128dbEAace47d2C0417);
    IResupplyRegistry _registry = IResupplyRegistry(0x10101010E0C3171D894B71B3400668aF311e7D94);
    address public _stablecoin = 0x57aB1E0003F623289CD798B1824Be09a793e4Bec;
    
    function setUp() public override {
        super.setUp();
        swapper = new SwapperOdos(address(core));
    }

    function test_LiveOdosSwap() public {
        address[] memory pairs = _registry.getAllPairAddresses();
        newPair = ResupplyPair(pairs[0]);
        address collateral = address(newPair.collateral());
        vm.startPrank(address(_core));
        swapper = new SwapperOdos(_core);
        swapper.updateApprovals();
        newPair.setSwapper(address(swapper), true);
        vm.stopPrank();
        
        uint256 borrowAmount = 50_000e18;
        odosPayload = OdosApi.getPayload(
            _stablecoin,        // input token
            collateral,         // output token
            1e18,               // input amount
            3,                  // slippage pct
            address(newPair)    // recipient address
        );

        address[] memory path = swapper.encode(odosPayload, _stablecoin, collateral);

        console.log("Odos payload:", _bytesToFullHex(odosPayload));

        uint256 initialUnderlyingAmount = 100_000e18;
        IERC20 underlying = newPair.underlying();
        deal(address(underlying), address(this), initialUnderlyingAmount);
        underlying.approve(address(newPair), initialUnderlyingAmount);
        newPair.leveragedPosition(
            address(swapper), 
            borrowAmount,               // borrow amount
            initialUnderlyingAmount,    // initial collateral amount
            1e18,                       // amount collateral out min
            path                        // encoded path
        );


        uint256 amount = borrowAmount / 2;
        odosPayload = OdosApi.getPayload(
            collateral,         // input token
            _stablecoin,        // output token
            amount,       // input amount
            3,                  // slippage pct
            address(newPair)    // recipient address
        );
        path = swapper.encode(odosPayload, collateral, _stablecoin);
        bytes memory decodedPayload = swapper.decode(path);
        assertEq(keccak256(decodedPayload), keccak256(odosPayload), "Decoded payload does not match original payload");
        newPair.repayWithCollateral(
            address(swapper),
            amount,
            1e18,
            path
        );
    }

    function test_recoverERC20() public {
        deal(address(stablecoin), address(swapper), 1e18);
        address owner = swapper.owner();
        assertEq(stablecoin.balanceOf(owner), 0);
        vm.prank(owner);
        swapper.recoverERC20(address(stablecoin), 1e18);
        assertEq(stablecoin.balanceOf(address(swapper)), 0);
        assertEq(stablecoin.balanceOf(owner), 1e18);
    }

    function test_UpdateApprovals() public {
        bool canUpdateApprovals = swapper.canUpdateApprovals();
        console.log("Can update approvals:", canUpdateApprovals);
        swapper.updateApprovals();
        address[] memory pairs = registry.getAllPairAddresses();
        assertGt(pairs.length, 0);
        for (uint i = 0; i < pairs.length; i++) {
            address _pair = pairs[i];
            address collateral = address(ResupplyPair(_pair).collateral());
            address odosRouter = swapper.odosRouter();
            assertGt(IERC20(collateral).allowance(address(swapper), odosRouter), 1e40);
        }
        assertEq(swapper.canUpdateApprovals(), false);
    }

    function test_RevokeApprovals() public {
        vm.prank(swapper.owner());
        swapper.revokeApprovals();
        address[] memory pairs = registry.getAllPairAddresses();
        assertGt(pairs.length, 0);
        for (uint i = 0; i < pairs.length; i++) {
            address _pair = pairs[i];
            address collateral = address(ResupplyPair(_pair).collateral());
            address odosRouter = swapper.odosRouter();
            assertEq(IERC20(collateral).allowance(address(swapper), odosRouter), 0);
        }
        assertEq(IERC20(swapper.reusd()).allowance(address(swapper), swapper.odosRouter()), 0);
    }

    function test_EncodeDecodePayload() public {
        // At time of writing tests, our collateral tokens are not yet supported by Odos, so we use WETH/USDC for testing
        deal(weth, address(swapper), 100e18);
        vm.prank(address(swapper));
        IERC20(weth).approve(swapper.odosRouter(), type(uint256).max);
        odosPayload = OdosApi.getPayloadForWethToUsdc(1e18, 3, address(this));
        odosPayload = abi.encodePacked(
            odosPayload,
            "111" // add some extra data to the payload to help test that we are trimming properly
        );
        bytes memory decodedPayload = swapper.decode(swapper.encode(odosPayload, weth, usdc));
        // Verify the payload was correctly encoded and decoded
        assertEq(keccak256(odosPayload), keccak256(decodedPayload), "Original and decoded payloads don't match");
    }
    
    // Helper to convert full bytes array to hex string for visual comparison
    function _bytesToFullHex(bytes memory data) internal pure returns (string memory) {
        bytes memory hexBytes = new bytes(2 * data.length + 2);
        hexBytes[0] = "0";
        hexBytes[1] = "x";
        
        for (uint i = 0; i < data.length; i++) {
            uint8 b = uint8(data[i]);
            hexBytes[2 + i*2] = _hexChar(b / 16);
            hexBytes[3 + i*2] = _hexChar(b % 16);
        }
        
        return string(hexBytes);
    }
    
    // Helper to convert a byte to hex character
    function _hexChar(uint8 value) internal pure returns (bytes1) {
        if (value < 10) {
            return bytes1(uint8(bytes1("0")) + value);
        } else {
            return bytes1(uint8(bytes1("a")) + value - 10);
        }
    }
}