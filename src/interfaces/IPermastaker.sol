pragma solidity 0.8.28;

interface IPermastaker {
    error OwnableInvalidOwner( address owner );
    error OwnableUnauthorizedAccount( address account );
    event OperatorUpdated( address indexed operator ) ;
    event OwnershipTransferStarted( address indexed previousOwner,address indexed newOwner ) ;
    event OwnershipTransferred( address indexed previousOwner,address indexed newOwner ) ;
    function acceptOwnership(  ) external   ;
    function claimAndStake(  ) external  returns (uint256 amount) ;
    function core(  ) external view returns (address ) ;
    function execute( address target,bytes memory data ) external  returns (bool , bytes memory ) ;
    function migrateStaker(  ) external   ;
    function name(  ) external view returns (string memory ) ;
    function operator(  ) external view returns (address ) ;
    function owner(  ) external view returns (address ) ;
    function pendingOwner(  ) external view returns (address ) ;
    function registry(  ) external view returns (address ) ;
    function renounceOwnership(  ) external   ;
    function safeExecute( address target,bytes memory data ) external  returns (bytes memory ) ;
    function setOperator( address _operator ) external   ;
    function staker(  ) external view returns (address ) ;
    function transferOwnership( address newOwner ) external   ;
    function vestManager(  ) external view returns (address ) ;
}