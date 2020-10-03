pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./assets/YearnDaiVault.sol";
import "./assets/YearnUsdcVault.sol";
import "./assets/YearnTusdVault.sol";

contract ElfStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    struct Allocation {
        address asset;
        uint256 percent;
    }

    Allocation[] allocations;
    uint256 numAllocations;

    address public governance;
    address public fund;

    constructor(address _fund) public {
        governance = msg.sender;
        fund = _fund;
    }

    function setGovernance(address _governance) public {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function setAllocations(address[] memory _assets, uint256[] memory _percents, uint256 _numAllocations) public {
        require(msg.sender == governance, "!governance");
        // todo: validate that allocations add to 100
        delete allocations;
        for(uint256 i = 0; i < _numAllocations; i++) {
            allocations.push( Allocation(_assets[i], _percents[i]) );
        }
        numAllocations = _numAllocations;
    }

    function allocate(uint256 _amount) public {
        require(msg.sender == fund, "!fund");

        for(uint256 i = 0; i < numAllocations; i++) {
            // TODO: convert weth to asset base type (e.g. dai)
        
            // TODO: deposit into asset vault
        }
    }

    function deallocate(uint256 _amount) external {
        require(msg.sender == fund, "!fund");
        
        for(uint256 i = 0; i < numAllocations; i++) {
            // TODO: withdraw from  vault

            // TODO: convert to weth
        }

    }

    function balanceOf() public view returns (uint) {
        // TODO
        return 0;
    }


}