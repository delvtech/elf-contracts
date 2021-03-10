// SPDX-License-Identifier: Apache-2.0

import "./Tranche.sol";
import "./assets/YC.sol";
import "./interfaces/IWrappedPosition.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IYCFactory.sol";
import "./interfaces/IYC.sol";

pragma solidity ^0.8.0;

contract TrancheFactory {
    event TrancheCreated(
        address indexed trancheAddress,
        address indexed wpAddress,
        uint256 indexed duration
    );

    IYCFactory internal ycFactory;
    address internal tempWpAddress;
    uint256 internal tempExpiration;
    IYC internal tempYC;
    bytes32 public constant trancheCreationHash = keccak256(
        type(Tranche).creationCode
    );

    /// @notice Create a new Tranche.
    /// @param _ycFactory Address of the YC factory.
    constructor(address _ycFactory) {
        ycFactory = IYCFactory(_ycFactory);
    }

    /// @notice Deploy a new Tranche contract.
    /// @param expiration The expiration timestamp for the tranche.
    /// @param wpAddress Address of the Wrapped Position contract the tranche will use.
    /// @return The deployed Tranche contract.
    function deployTranche(uint256 expiration, address wpAddress)
        public
        returns (Tranche)
    {
        tempWpAddress = wpAddress;
        tempExpiration = expiration;

        IWrappedPosition wpContract = IWrappedPosition(wpAddress);
        bytes32 salt = keccak256(abi.encodePacked(wpAddress, expiration));
        string memory wpSymbol = wpContract.symbol();
        IERC20 underlying = wpContract.token();
        uint8 underlyingDecimals = underlying.decimals();

        // derive the expected tranche address
        address predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            trancheCreationHash
                        )
                    )
                )
            )
        );

        tempYC = ycFactory.deployYc(
            predictedAddress,
            wpSymbol,
            expiration,
            underlyingDecimals
        );

        Tranche tranche = new Tranche{ salt: salt }();
        emit TrancheCreated(
            address(tranche),
            wpAddress,
            expiration - block.timestamp
        );

        require(
            address(tranche) == predictedAddress,
            "CREATE2 address mismatch"
        );

        // set back to 0-value for some gas savings
        delete tempWpAddress;
        delete tempExpiration;
        delete tempYC;

        return tranche;
    }

    /// @notice Callback function called by the Tranche.
    /// @dev This is called by the Tranche contract constructor.
    /// The return data is used for Tranche initialization. Using this, the Tranche avoids
    /// constructor arguments which can make the Tranche bytecode needed for create2 address
    /// derivation non-constant.
    /// @return Wrapped Position contract address, expiration timestamp, and YC contract
    function getData()
        external
        returns (
            address,
            uint256,
            IYC
        )
    {
        return (tempWpAddress, tempExpiration, tempYC);
    }
}
