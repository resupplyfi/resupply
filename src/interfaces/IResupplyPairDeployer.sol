pragma solidity 0.8.28;

interface IResupplyPairDeployer {
    error Create2Failed();
    error NonUniqueName();
    error ProtocolAlreadyExists();
    error ProtocolNameEmpty();
    error ProtocolNameTooLong();
    error ProtocolNotFound();
    error WhitelistedDeployersOnly();
    event LogDeploy(
        address indexed address_,
        address indexed collateral,
        uint256 indexed protocolId,
        string name,
        bytes configData,
        bytes immutables,
        bytes customConfigData
    );
    event ProtocolUpdated(
        uint256 indexed protocolId,
        string protocolName,
        bytes4 borrowTokenSig,
        bytes4 collateralTokenSig
    );
    event SetOperator(address indexed _op, bool _valid);

    function addSupportedProtocol(
        string memory _protocolName,
        bytes4 _borrowTokenSig,
        bytes4 _collateralTokenSig
    ) external returns (uint256);

    function collateralId(
        uint256 protocolId,
        address borrowToken,
        address collateralToken
    ) external view returns (uint256 id);

    function contractAddress1() external view returns (address);

    function contractAddress2() external view returns (address);

    function core() external view returns (address);

    function deploy(
        uint256 _protocolId,
        bytes memory _configData,
        address _underlyingStaking,
        uint256 _underlyingStakingId
    ) external returns (address _pairAddress);

    function getNextName(uint256 _protocolId, address _collateral)
        external
        view
        returns (
            string memory _name,
            address _borrowToken,
            address _collateralToken
        );

    function govToken() external view returns (address);

    function operators(address) external view returns (bool);

    function owner() external view returns (address);

    function platformNameById(uint256 protocolId)
        external
        view
        returns (string memory);

    function registry() external view returns (address);

    function setCreationCode(bytes memory _creationCode) external;

    function setOperator(address _operator, bool _valid) external;

    function supportedProtocols(uint256)
        external
        view
        returns (
            string memory protocolName,
            bytes4 borrowTokenSig,
            bytes4 collateralTokenSig
        );

    function updateSupportedProtocol(
        uint256 protocolId,
        string memory _protocolName,
        bytes4 _borrowTokenSig,
        bytes4 _collateralTokenSig
    ) external returns (uint256);

    function version()
        external
        pure
        returns (
            uint256 _major,
            uint256 _minor,
            uint256 _patch
        );
}