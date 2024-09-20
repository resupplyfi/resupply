// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "src/protocol/fraxlend/FraxlendPairRegistry.sol";

library FraxlendPairRegistryHelper {
    function __setSingleDeployer(FraxlendPairRegistry _fraxlendPairRegistry, address _deployer, bool _bool) internal {
        address[] memory _deployers = new address[](1);
        _deployers[0] = _deployer;
        _fraxlendPairRegistry.setDeployers(_deployers, _bool);
    }
}
