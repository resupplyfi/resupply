// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ICore } from "src/interfaces/ICore.sol";
import { CoreOwnable } from "src/dependencies/CoreOwnable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IResupplyPair } from "src/interfaces/IResupplyPair.sol";
import { IResupplyRegistry } from "src/interfaces/IResupplyRegistry.sol";
import { IResupplyPairDeployer } from "src/interfaces/IResupplyPairDeployer.sol";


//A core operator that is a helper contract to add pairs to registry with some extra checks
contract PoolRegistration is CoreOwnable {
    using SafeERC20 for IERC20;


    address immutable public factory;
    address immutable public burner;

    constructor(address _core, address _factory, address _burner) CoreOwnable(_core) {
        factory = _factory;
        burner = _burner;
    }

    function addPair(address _pair) external onlyOwner{

        (,uint40 deployTime) = IResupplyPairDeployer(factory).deployInfo(_pair);
        require(deployTime > 0, "not a factory pair");

        address collateral = IResupplyPair(_pair).collateral();
        require(IERC20(collateral).balanceOf(burner) > 0, "need share burn");
        
        core.execute(
            _pair,
            abi.encodeWithSelector(
                IResupplyRegistry.addPair.selector,
                _pair
            )
        );
    }

}
