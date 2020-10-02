pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../../interfaces/Strategy.sol";
import "./assets/YearnDaiVault.sol";
import "./assets/YearnUsdcVault.sol";
import "./assets/YearnTusdVault.sol";

contract ElfStrategy is Strategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public governance;
    address public fund;

    constructor(address _fund) public {
        governance = msg.sender;
        fund = _fund;
    }

    function allocateFunds(uint256 _amount) override public {
        // TODO: convert weth to dai
        
        // TODO: deposit into dai vault

        // TODO: convert weth to usdc

        // TODO: deposit into usdc vault

        // TODO: convert weth to tusd

        // TODO: deposit into Tusd vault
    }

    function deallocateFunds(uint256 _amount) override external {
        require(msg.sender == fund, "!fund");
        
        // TODO: withdraw from dai vault

        // TODO: convert dai to weth

        // TODO: withdraw from usdc vault

        // TODO: convert usdc to weth

        // TODO: withdraw from Tusd vault

        // TODO: convert tusd to weth

    }

    function balanceOf() public override view returns (uint) {
        // TODO
        return 0;
    }


}