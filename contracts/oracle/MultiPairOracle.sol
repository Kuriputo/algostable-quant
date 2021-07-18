// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../interfaces/IOracle.sol";
import "../interfaces/IPairOracle.sol";

contract MultiPairOracle is Ownable {
    using SafeMath for uint256;

    address[] public pairs;
    mapping(address => bool) public mappingPairs;
    address public immutable token0;
    address public immutable token1;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function addPair(address _pair) external onlyOwner {
        require(!mappingPairs[_pair], "pair existed");
        IPairOracle oracle = IPairOracle(_pair);
        require((oracle.token0() == token0 && oracle.token1() == token1) || (oracle.token0() == token1 && oracle.token1() == token0), "invalid pair oracle");
        mappingPairs[_pair] = true;
        pairs.push(_pair);
    }

    function removePair(address _pair) external onlyOwner {
        require(mappingPairs[_pair], "pair not existed");
        delete mappingPairs[_pair];
        for (uint256 i = 0; i < pairs.length; i++) {
            if (pairs[i] == _pair) {
                pairs[i] = pairs[pairs.length - 1];
                break;
            }
        }
        pairs.pop();
    }

    function consult(address token, uint256 amountIn) external view returns (uint256 amountOut) {
        uint256 sum = 0;
        uint256 count = 0;
        for (uint256 i = 0; i < pairs.length; i++) {
            uint256 _result = _consultPair(pairs[i], token, amountIn);
            if (_result > 0) {
                sum = sum + _result;
                count++;
            }
        }
        require(count > 0, "invalid oracle");
        amountOut = sum / count;
    }

    function update() external {
        for (uint256 i = 0; i < pairs.length; i++) {
            IPairOracle(pairs[i]).update();
        }
    }

    function _consultPair(
        address pairOracle,
        address token,
        uint256 amountIn
    ) internal view returns (uint256) {
        return IPairOracle(pairOracle).consult(token, amountIn);
    }
}
