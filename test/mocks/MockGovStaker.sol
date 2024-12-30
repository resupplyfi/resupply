import { GovStaker } from "../../src/dao/staking/GovStaker.sol";

contract MockGovStaker is GovStaker {
    address immutable previousStaker;
    constructor(address _core, address _registry, address _stakeToken, uint24 _cooldownEpochs, address _previousStaker) GovStaker(_core, _registry, _stakeToken, _cooldownEpochs) {
        previousStaker = _previousStaker;
    }

    function onMigrate(address account) external override {
        require(msg.sender == previousStaker, "!migrate");
        accountData[account].isPermaStaker = true;
    }
}