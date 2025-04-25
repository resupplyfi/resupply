pragma solidity 0.8.28;

interface ISimpleReceiverFactory {
    error FailedDeployment();
    error InsufficientBalance(uint256 balance, uint256 needed);
    event ClaimerApproved(uint256 indexed index, address indexed claimer);
    event ImplementationSet(address indexed implementation);
    event ReceiverDeployed(
        address indexed receiver,
        address indexed implementation,
        uint256 index
    );

    function core() external view returns (address);

    function deployNewReceiver(
        string memory _name,
        address[] memory _approvedClaimers
    ) external returns (address receiver);

    function emissionsController() external view returns (address);

    function getDeterministicAddress(string memory _name)
        external
        view
        returns (address);

    function getReceiverByName(string memory _name)
        external
        view
        returns (address receiver);

    function getReceiverId(address _receiver) external view returns (uint256);

    function getReceiversLength() external view returns (uint256);

    function implementation() external view returns (address);

    function nameHashToReceiver(bytes32) external view returns (address);

    function owner() external view returns (address);

    function receivers(uint256) external view returns (address);

    function setImplementation(address _implementation) external;
}