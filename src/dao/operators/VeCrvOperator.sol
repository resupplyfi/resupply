// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { CoreOwnable } from "src/dependencies/CoreOwnable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPrismaVoterProxy } from "src/interfaces/prisma/IPrismaVoterProxy.sol";
import { ICurveEscrow } from "src/interfaces/curve/ICurveEscrow.sol";
import { IVeBoost } from "src/interfaces/curve/IVeBoost.sol";
import { ICurveFeeDistributor } from "src/interfaces/curve/ICurveFeeDistributor.sol";
import { IERC4626 } from "src/interfaces/IERC4626.sol";

contract VeCrvOperator is CoreOwnable {
    using SafeERC20 for IERC20;

    address public constant PRISMA_VOTER = 0x490b8C6007fFa5d3728A49c2ee199e51f05D2F7e;
    address public constant FEE_DISTRIBUTOR = 0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914;
    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant SCRVUSD = 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367;

    address public constant BOOST_DELEGATION = 0xD37A6aa3d8460Bd2b6536d608103D880695A23CD;
    address public constant YEARN_VOTER = 0xF147b8125d2ef93FB6965Db97D6746952a133934;
    address public constant CONVEX_VOTER = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;
    address public constant VE = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    uint256 public constant SHARE_PRECISION = 1e18;
    
    address public receiver = 0x4444444455bF42de586A88426E5412971eA48324;
    uint256 public convexBoostShare = 0.667e18;
    address public manager;

    event ReceiverSet(address indexed receiver);
    event BoostShareSet(uint256 convexShare, uint256 yearnShare);
    event ManagerSet(address indexed manager);

    constructor(address _core) CoreOwnable(_core) {
        IERC20(CRVUSD).forceApprove(SCRVUSD, type(uint256).max);
        manager = 0xFE11a5009f2121622271e7dd0FD470264e076af6;
        emit ManagerSet(manager);
    }

    modifier onlyOwnerOrManager() {
        require(msg.sender == owner() || msg.sender == manager, "!authorized");
        _;
    }

    /// @notice Set the manager address allowed to perform actions.
    /// @param _manager The new manager address.
    function setManager(address _manager) external onlyOwner {
        manager = _manager;
        emit ManagerSet(_manager);
    }

    /// @notice Claim Prisma fees and forward to the receiver without wrapping.
    /// @return amount The amount of crvUSD claimed from the voter.
    function claimFees() external onlyOwnerOrManager returns (uint256 amount) {
        return _claimFees(false, receiver);
    }

    /// @notice Claim Prisma fees with optional wrapping and recipient override.
    /// @param wrap Whether to wrap crvUSD into scrvUSD.
    /// @param recipient The recipient address (defaults to receiver if zero).
    /// @return amount The amount of crvUSD claimed from the voter.
    function claimFees(bool wrap, address recipient) external onlyOwnerOrManager returns (uint256 amount) {
        return _claimFees(wrap, recipient);
    }

    function _claimFees(bool wrap, address recipient) internal returns (uint256 amount) {
        if (recipient == address(0)) recipient = receiver;
        ICurveFeeDistributor(FEE_DISTRIBUTOR).claim(PRISMA_VOTER);

        amount = IERC20(CRVUSD).balanceOf(PRISMA_VOTER);
        if (amount == 0) return 0;
        IPrismaVoterProxy.TokenBalance[] memory balances = new IPrismaVoterProxy.TokenBalance[](1);
        balances[0] = IPrismaVoterProxy.TokenBalance({ token: IERC20(CRVUSD), amount: amount });

        if (wrap) {
            IPrismaVoterProxy(PRISMA_VOTER).transferTokens(address(this), balances);
            IERC4626(SCRVUSD).deposit(amount, recipient);
            return amount;
        }

        IPrismaVoterProxy(PRISMA_VOTER).transferTokens(recipient, balances);
    }

    /// @notice Delegate available Prisma boost between Convex and Yearn.
    function delegateBoost() external onlyOwnerOrManager {
        uint256 _endtime = extendLock();
        uint256 _amount = delegableBalance();
        if (_amount == 0) return;
        uint256 convexAmount = _amount * convexBoostShare / SHARE_PRECISION;
        uint256 yearnAmount = _amount - convexAmount;
        if (_endtime <= block.timestamp) return;
        _endtime = _endtime / 1 weeks * 1 weeks;
        if (convexAmount != 0) IVeBoost(BOOST_DELEGATION).boost(CONVEX_VOTER, convexAmount, _endtime, PRISMA_VOTER);
        if (yearnAmount != 0) IVeBoost(BOOST_DELEGATION).boost(YEARN_VOTER, yearnAmount, _endtime, PRISMA_VOTER);
    }

    /// @notice Return the amount of boost currently delegable by the Prisma voter.
    function delegableBalance() public view returns (uint256) {
        return IVeBoost(BOOST_DELEGATION).delegable_balance(PRISMA_VOTER);
    }

    /// @notice Max lock the Prisma voter
    function extendLock() public onlyOwnerOrManager returns (uint256 lockEnd) {
        bytes memory _lockCalldata = abi.encodeWithSelector(
            ICurveEscrow.increase_unlock_time.selector,
            block.timestamp + (4 * 365 days)
        );
        bytes memory _data = abi.encodeWithSelector(
            IPrismaVoterProxy.execute.selector,
            VE,
            _lockCalldata
        );
        core.execute(PRISMA_VOTER, _data);
        return ICurveEscrow(VE).locked__end(PRISMA_VOTER);
    }

    /// @notice Set the share of boost delegated to Convex (1e18 = 100%).
    /// @param _newConvexShare The new Convex boost share. Yearn share is the remainder.
    function setBoostShare(uint256 _newConvexShare) external onlyOwnerOrManager {
        require(_newConvexShare <= SHARE_PRECISION, "invalid share");
        convexBoostShare = _newConvexShare;
        emit BoostShareSet(_newConvexShare, SHARE_PRECISION - _newConvexShare);
    }

    /// @notice Set the receiver for wrapped fee distributions.
    /// @param _receiver The address to receive scrvUSD.
    function setReceiver(address _receiver) external onlyOwnerOrManager {
        require(_receiver != address(0), "invalid receiver");
        receiver = _receiver;
        emit ReceiverSet(_receiver);
    }

    /// @notice Vote in the Curve DAO on a proposal.
    /// @param aragon The Curve DAO Aragon voting contract.
    /// @param id The proposal id.
    /// @param support Whether to support the proposal.
    function voteInCurveDao(address aragon, uint256 id, bool support) external onlyOwnerOrManager {
        IPrismaVoterProxy(PRISMA_VOTER).voteInCurveDao(aragon, id, support);
    }

    /// @notice Vote for gauge weights.
    /// @param votes The gauge weight votes to cast.
    function voteForGaugeWeights(IPrismaVoterProxy.GaugeWeightVote[] calldata votes) external onlyOwnerOrManager {
        IPrismaVoterProxy(PRISMA_VOTER).voteForGaugeWeights(votes);
    }
}
