pragma solidity >=0.5.8 <0.8.0;

import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../contracts/funds/low/Elf.sol";
import "./AnAsset.sol";
import "./AConverter.sol";

contract TestElf {
    using SafeERC20 for Elf;

    uint256 public initialBalance = 1 ether;

    function testDepositWithdraw() public {
        Elf elf = new Elf();

        // Create Strategy for Elf
        ElfStrategy strategy = new ElfStrategy(address(elf));
        elf.setStrategy(address(strategy));

        // Create Allocations for Strategy
        AnAsset asset1 = new AnAsset(address(strategy));
        address[] memory assets = new address[](4);
        assets[0] = address(asset1);
        assets[1] = address(asset1);
        assets[2] = address(asset1);
        assets[3] = address(asset1);
        uint256[] memory percents = new uint256[](4);
        percents[0] = uint256(25);
        percents[1] = uint256(25);
        percents[2] = uint256(25);
        percents[3] = uint256(25);
        uint256 numAllocations = uint256(4);
        strategy.setAllocations(assets, percents, numAllocations);

        // create a Converter for Strategy
        AConverter converter = new AConverter();
        AnAsset asset2 = new AnAsset(address(converter));
        converter.setAsset(address(asset2));
        strategy.setConverter(address(converter));

        // first call to deposit()
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

        // second call to deposit()
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
