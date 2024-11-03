interface IVesting {
    function createVest(address _recipient, uint256 _start, uint256 _duration, uint256 _amount) external returns (uint256);
}

contract MockVestManager {
    IVesting immutable public vesting;

    constructor(address _vesting) {
        vesting = IVesting(_vesting);
    }

    function createVest(
        address _account,
        uint256 _duration,
        uint256 _amount        
    ) external returns (uint256) {

        uint256 vestId = vesting.createVest(
            _account,
            block.timestamp,
            _duration,
            _amount
        );

        return vestId;
    }
}