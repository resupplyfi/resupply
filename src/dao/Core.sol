// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
    @title Core
    @author Prisma Finance (with edits by Relend.fi)
    @notice Single source of truth for system-wide values and contract ownership.

            Ownership of this contract should be the DAO via `Voting`.
            Other ownable contracts inherit their ownership from this contract
            using `Ownable`.
 */
contract Core {
    address public feeReceiver;

    address public owner;
    address public pendingOwner;
    uint256 public ownershipTransferDelay;
    address public guardian;

    // We enforce a three day delay between committing and applying
    // an ownership change, as a sanity check on a proposed new owner
    // and to give users time to react in case the act is malicious.
    uint256 public constant OWNERSHIP_TRANSFER_DELAY = 3 days;
    uint256 public immutable startTime;
    uint256 public immutable epochLength;
    // System-wide pause. When true, disables trove adjustments across all collaterals.
    bool public paused;
    mapping(address => bool) public assetPaused;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner, uint256 deadline);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    event FeeReceiverSet(address feeReceiver);

    event GuardianSet(address guardian);

    event ProtocolPaused(bool indexed paused);

    event AssetPaused(address indexed asset, bool indexed paused);

    constructor(address _owner, uint256 _epochLength, address _guardian, address _feeReceiver) {
        require(_epochLength > 0, "Epoch length must be greater than 0");
        require(_epochLength <= 100 days, "Epoch length must be less than 100 days");
        startTime = (block.timestamp / _epochLength) * _epochLength;
        epochLength = _epochLength;
        owner = _owner;
        guardian = _guardian;
        feeReceiver = _feeReceiver;
        emit GuardianSet(_guardian);
        emit FeeReceiverSet(_feeReceiver);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    /**
     * @notice Set the receiver of all fees across the protocol
     * @param _feeReceiver Address of the fee's recipient
     */
    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        feeReceiver = _feeReceiver;
        emit FeeReceiverSet(_feeReceiver);
    }

    /**
     * @notice Set the guardian address
               The guardian can execute some emergency actions
     * @param _guardian Guardian address
     */
    function setGuardian(address _guardian) external onlyOwner {
        guardian = _guardian;
        emit GuardianSet(_guardian);
    }

    /**
     * @notice Sets the global pause state of the protocol
     *         Pausing is used to mitigate risks in exceptional circumstances.
     * @param _paused If true the protocol is paused
     */
    function pauseProtocol(bool _paused) external {
        require((_paused && msg.sender == guardian) || msg.sender == owner, "Unauthorized");
        paused = _paused;
        emit ProtocolPaused(_paused);
    }

    /**
     * @notice Pauses a specific asset within the protocol.
     * @param _asset Address of the asset to pause
     * @param _paused If true the asset is paused
     */
    function pauseAsset(address _asset, bool _paused) external {
        require((_paused && msg.sender == guardian) || msg.sender == owner, "Unauthorized");
        assetPaused[_asset] = _paused;
        emit AssetPaused(_asset, _paused);
    }

    function isPaused(address _asset) external view returns (bool) {
        return paused || assetPaused[_asset];
    }

    function transferOwnership(address newOwner) external onlyOwner {
        pendingOwner = newOwner;
        ownershipTransferDelay = block.timestamp + OWNERSHIP_TRANSFER_DELAY;

        emit OwnershipTransferStarted(msg.sender, newOwner, block.timestamp + OWNERSHIP_TRANSFER_DELAY);
    }

    function acceptTransferOwnership() external {
        require(msg.sender == pendingOwner, "Only new owner");
        require(block.timestamp >= ownershipTransferDelay, "Delay not passed");

        emit OwnershipTransferred(owner, pendingOwner);

        owner = pendingOwner;
        pendingOwner = address(0);
        ownershipTransferDelay = 0;
    }
}