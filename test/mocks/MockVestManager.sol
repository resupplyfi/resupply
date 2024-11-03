interface IVesting {
    function createVest(address _recipient, uint32 _duration, uint112 _amount) external returns (uint256);
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
            uint32(_duration),
            uint112(_amount)
        );

        return vestId;
    }
}