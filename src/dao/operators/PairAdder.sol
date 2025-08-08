// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { ICore } from "src/interfaces/ICore.sol";
import { CoreOwnable } from "src/dependencies/CoreOwnable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";


//A core operator that is a helper contract to add pairs to registry with some extra checks
contract PairAdder is CoreOwnable {

    address public immutable registry;

    constructor(address _core, address _registry) CoreOwnable(_core) {
        registry = _registry;
    }

    function addPair(address _pair) external onlyOwner{
        //factory does sanity checks and share burning
        //just ensure that the given pair was made in pair factory
        address factory = IResupplyRegistry(registry).getAddress("DEPLOYER");
        (,uint40 deployTime) = IResupplyPairDeployer(factory).deployInfo(_pair);
        require(deployTime > 0, "not a factory pair");
        
        core.execute(
            _pair,
            abi.encodeWithSelector(
                IResupplyRegistry.addPair.selector,
                _pair
            )
        );
    }
}
