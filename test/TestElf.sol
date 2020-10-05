pragma solidity >=0.5.8 <0.8.0;

import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../contracts/funds/low/Elf.sol";

contract TestElf {
    using SafeERC20 for Elf;

    uint256 public initialBalance = 1 ether;

    function testDepositWithdraw() public {
        Elf elf = new Elf();
        ElfStrategy strategy = new ElfStrategy(address(elf));
        elf.setStrategy(address(strategy));

        (bool success, ) = address(elf).call{gas: 200317, value: 1 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(success, "Failed to transfer the funds, aborting.");
        Assert.equal(elf.balance(), 1 ether, "Balance is wrong after deposit");
        Assert.equal(
            elf.balanceOf(address(this)),
            1,
            "Shares are wrong after deposit"
        );

        elf.withdraw(1);
        Assert.equal(elf.balance(), 0 ether, "Balance is wrong after withdraw");
        Assert.equal(
            elf.balanceOf(address(this)),
            0,
            "Shares are wrong after withdraw"
        );

        (success, ) = address(elf).call{gas: 200317, value: 1 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(success, "Failed to transfer the funds, aborting.");
        Assert.equal(
            elf.balance(),
            1 ether,
            "Balance is wrong after 2nd deposit"
        );
        Assert.equal(
            elf.balanceOf(address(this)),
            1,
            "Shares are wrong after 2nd deposit"
        );
    }

    // require for withdraw tests to work
    fallback() external payable {}
}
