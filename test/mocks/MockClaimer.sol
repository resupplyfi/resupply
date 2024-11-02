interface IVesting {
    function createVest(address _recipient, uint256 _amount, uint256 _duration) external returns (uint256);
}

contract MockClaimer {
    IVesting immutable public vesting;

    constructor(address _vesting) {
        vesting = IVesting(_vesting);
    }

    function createVest(
        address _account,
        uint256 _amount,
        uint256 _duration
    ) external returns (uint256) {

        uint256 vestId = vesting.createVest(
            _account,
            _amount,
            _duration
        );

        return vestId;
    }
}