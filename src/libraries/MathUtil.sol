// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

library MathUtil {
    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) external pure returns (uint256) {
        return a >= b ? a : b;
    }
}