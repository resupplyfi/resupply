pragma solidity 0.8.30;

interface IStablecoin {
    error ERC20InsufficientAllowance(
        address spender,
        uint256 allowance,
        uint256 needed
    );
    error ERC20InsufficientBalance(
        address sender,
        uint256 balance,
        uint256 needed
    );
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidSpender(address spender);
    error InvalidDelegate();
    error InvalidEndpointCall();
    error InvalidLocalDecimals();
    error InvalidOptions(bytes options);
    error LzTokenUnavailable();
    error NoPeer(uint32 eid);
    error NotEnoughNative(uint256 msgValue);
    error OnlyEndpoint(address addr);
    error OnlyPeer(uint32 eid, bytes32 sender);
    error OnlySelf();
    error OwnableInvalidOwner(address owner);
    error OwnableUnauthorizedAccount(address account);
    error SafeERC20FailedOperation(address token);
    error SimulationResult(bytes result);
    error SlippageExceeded(uint256 amountLD, uint256 minAmountLD);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event EnforcedOptionSet(EnforcedOptionParam[] _enforcedOptions);
    event MsgInspectorSet(address inspector);
    event OFTReceived(
        bytes32 indexed guid,
        uint32 srcEid,
        address indexed toAddress,
        uint256 amountReceivedLD
    );
    event OFTSent(
        bytes32 indexed guid,
        uint32 dstEid,
        address indexed fromAddress,
        uint256 amountSentLD,
        uint256 amountReceivedLD
    );
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event PeerSet(uint32 eid, bytes32 peer);
    event PreCrimeSet(address preCrimeAddress);
    event SetOperator(address indexed _op, bool _valid);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function SEND() external view returns (uint16);

    function SEND_AND_CALL() external view returns (uint16);

    function allowInitializePath(Origin memory origin)
        external
        view
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approvalRequired() external pure returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function burn(address _from, uint256 _amount) external;

    function combineOptions(
        uint32 _eid,
        uint16 _msgType,
        bytes memory _extraOptions
    ) external view returns (bytes memory);

    function core() external view returns (address);

    function decimalConversionRate() external view returns (uint256);

    function decimals() external view returns (uint8);

    function endpoint() external view returns (address);

    function enforcedOptions(uint32 eid, uint16 msgType)
        external
        view
        returns (bytes memory enforcedOption);

    function isComposeMsgSender(
        Origin memory,
        bytes memory,
        address _sender
    ) external view returns (bool);

    function isPeer(uint32 _eid, bytes32 _peer) external view returns (bool);

    function lzReceive(
        Origin memory _origin,
        bytes32 _guid,
        bytes memory _message,
        address _executor,
        bytes memory _extraData
    ) external payable;

    function lzReceiveAndRevert(InboundPacket[] memory _packets)
        external
        payable;

    function lzReceiveSimulate(
        Origin memory _origin,
        bytes32 _guid,
        bytes memory _message,
        address _executor,
        bytes memory _extraData
    ) external payable;

    function mint(address _to, uint256 _amount) external;

    function msgInspector() external view returns (address);

    function name() external view returns (string memory);

    function nextNonce(uint32, bytes32) external view returns (uint64 nonce);

    function oApp() external view returns (address);

    function oAppVersion()
        external
        pure
        returns (uint64 senderVersion, uint64 receiverVersion);

    function oftVersion()
        external
        pure
        returns (bytes4 interfaceId, uint64 version);

    function operators(address) external view returns (bool);

    function owner() external view returns (address);

    function peers(uint32 eid) external view returns (bytes32 peer);

    function preCrime() external view returns (address);

    function quoteOFT(SendParam memory _sendParam)
        external
        view
        returns (
            OFTLimit memory oftLimit,
            OFTFeeDetail[] memory oftFeeDetails,
            OFTReceipt memory oftReceipt
        );

    function quoteSend(SendParam memory _sendParam, bool _payInLzToken)
        external
        view
        returns (MessagingFee memory msgFee);

    function renounceOwnership() external;

    function send(
        SendParam memory _sendParam,
        MessagingFee memory _fee,
        address _refundAddress
    )
        external
        payable
        returns (
            MessagingReceipt memory msgReceipt,
            OFTReceipt memory oftReceipt
        );

    function setDelegate(address _delegate) external;

    function setEnforcedOptions(EnforcedOptionParam[] memory _enforcedOptions)
        external;

    function setMsgInspector(address _msgInspector) external;

    function setOperator(address _operator, bool _valid) external;

    function setPeer(uint32 _eid, bytes32 _peer) external;

    function setPreCrime(address _preCrime) external;

    function sharedDecimals() external view returns (uint8);

    function symbol() external view returns (string memory);

    function token() external view returns (address);

    function totalSupply() external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function transferOwnership(address newOwner) external;
}

struct EnforcedOptionParam {
    uint32 eid;
    uint16 msgType;
    bytes options;
}

struct Origin {
    uint32 srcEid;
    bytes32 sender;
    uint64 nonce;
}

struct InboundPacket {
    Origin origin;
    uint32 dstEid;
    address receiver;
    bytes32 guid;
    uint256 value;
    address executor;
    bytes message;
    bytes extraData;
}

struct SendParam {
    uint32 dstEid;
    bytes32 to;
    uint256 amountLD;
    uint256 minAmountLD;
    bytes extraOptions;
    bytes composeMsg;
    bytes oftCmd;
}

struct OFTLimit {
    uint256 minAmountLD;
    uint256 maxAmountLD;
}

struct OFTFeeDetail {
    int256 feeAmountLD;
    string description;
}

struct OFTReceipt {
    uint256 amountSentLD;
    uint256 amountReceivedLD;
}

struct MessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}

struct MessagingReceipt {
    bytes32 guid;
    uint64 nonce;
    MessagingFee fee;
}