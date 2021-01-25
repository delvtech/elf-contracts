// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.5.8 <0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IERC20Permit.sol";
import "./interfaces/IElf.sol";
import "./interfaces/ITranche.sol";
import "./interfaces/IWETH.sol";
import "./libraries/Authorizable.sol";

contract UserProxy is Authorizable {
    // This contract is a convenience libary to consolidate
    // the actions needed to create FYT/YC to one call.
    // It will hold user allowances, and can be disabled
    // by an owner for security.
    // If frozen users still control their own tokens
    // so can manually redeem them.

    // Store the accessiblity state of the contract
    bool public isFrozen = true;
    // Constant wrapped ether address
    IWETH public immutable weth;
    // A constant which represents ether
    address ETH_CONSTANT = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// @param _weth The constant weth contract address
    /// @dev Marks the msg.sender as authorized and sets them
    ///      as the owner in authorization library
    constructor(IWETH _weth) public Authorizable() {
        _authorize(msg.sender);
        weth = _weth;
    }

    /// @dev Requires that the contract is not frozen
    modifier notFrozen() {
        require(!isFrozen, "Contract frozen");
        _;
    }

    /// @dev Allows an authorized address to freeze or unfreeze this contract
    /// @param newState True for frozen and false for unfrozen
    function setIsFrozen(bool newState) external onlyAuthorized() {
        isFrozen = newState;
    }

    /// @dev Sets an allowance on an instance of an ELF contract
    ///      so that the ELF contract can move underlying from the proxy
    /// @param underlying The ERC20 which is the token in the Elf contract
    /// @param assetProxy The asset proxy which is attached to the ELF contract
    // TODO - Does this need to be only authorized?
    function allowElf(IERC20 underlying, address assetProxy)
        external
        onlyAuthorized()
    {
        IElf elf = deriveElf(assetProxy);
        underlying.approve(address(elf), uint256(-1));
    }

    /// @dev Sets an allowance on an instance of an Trance contract
    ///      so that the Trance contract can move ELF from the proxy
    /// @param assetProxy The asset proxy which is attached to the ELF contract
    /// @param expiration The expieration time of the Tranche
    // TODO - Does this need to be only authorized?
    function allowTranche(address assetProxy, uint256 expiration)
        external
        onlyAuthorized()
    {
        IElf elf = deriveElf(assetProxy);
        ITranche tranche = deriveTranche(address(elf), expiration);
        elf.approve(address(tranche), uint256(-1));
    }

    /// @dev Mints a FYT/YC token pair from either underlying token or Eth
    ///      then returns the FYT YC to the caller. This function assumes
    ///      that it already has an allowance for the token in question.
    /// @param amount The amount of underlying to turn into FYT/YC
    /// @param underlying Either (1) The underlying ERC20 token contract
    ///                   or (2) the ETH_CONSTANT to indicate the user has sent eth.
    /// @param expiration The expiration time of the Tranche contract
    /// @param assetProxy The asset proxy which manages the position.
    function mint(
        uint256 amount,
        IERC20 underlying,
        uint256 expiration,
        address assetProxy
    ) external payable notFrozen() {
        // If the underlying token matches this predefined 'ETH token'
        // then we create weth for the user and go from there
        if (address(underlying) == ETH_CONSTANT) {
            // Check that the amount matches the amount provided
            require(msg.value == amount, "Incorrect amount provided");
            // Create weth from the provided eth
            weth.deposit{value: msg.value}();
            // Proceed to internal minting steps
            _mint(amount, expiration, assetProxy);
        } else {
            // Move the user's funds to this contract
            underlying.transferFrom(msg.sender, address(this), amount);
            // Proceed to internal minting steps
            _mint(amount, expiration, assetProxy);
        }
    }

    /// @dev Mints a FYT/YC token pair from a underlying token which supports
    ///      the permit method. This call sets the allowance on this contract
    ///      for the underlying ERC20 token to be unlimited and expects the
    ///      signature to have an expiration time of uint256.max
    /// @param amount The amount of underlying to turn into FYT/YC
    /// @param underlying The underlying ERC20 token contract
    /// @param expiration The expiration time of the Tranche contract
    /// @param assetProxy The asset proxy which manages the position.
    /// @param v The bit indicator which allows address recover from signature
    /// @param r The r component of the signature.
    /// @param s The s componet of the signature.
    function mintPermit(
        uint256 amount,
        IERC20Permit underlying,
        uint256 expiration,
        address assetProxy,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external notFrozen() {
        // Permit this contract to have unlimited access to
        // the msg.sender's funds
        underlying.permit(
            msg.sender,
            address(this),
            uint256(-1),
            uint256(-1),
            v,
            r,
            s
        );
        // Move the user's funds to this contract
        underlying.transferFrom(msg.sender, address(this), amount);
        // Pass call to interal function which works once approved
        _mint(amount, expiration, assetProxy);
    }

    /// @dev This method allows a user to redeem a FYT and receive underlying.
    ///      It uses permit to give itself an unlimited allowance on the FYT.
    ///      Please note the permit signature expects a max expiration time
    /// @param amount The amount of FYT to redeem
    /// @param expiration The expiration time of the Tranche contract
    /// @param assetProxy The asset proxy which manages the position.
    /// @param underlying Either (1) The underlying ERC20 token contract
    ///                   or (2) the ETH_CONSTANT if the user wants eth
    /// @param v The bit indicator which allows address recover from signature
    /// @param r The r component of the signature.
    /// @param s The s componet of the signature.
    function redeeemFYT(
        uint256 amount,
        uint256 expiration,
        address assetProxy,
        IERC20 underlying,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external notFrozen() {
        // Create2 Derive the elf and tranche contracts
        IElf elf = deriveElf(assetProxy);
        // Create2 Derive the Traunche contract
        ITranche tranche = deriveTranche(address(elf), expiration);
        // TODO - Add signed withdraw method to Traunch to condense this
        // Give ourselves the approval to move tokens
        tranche.permit(
            msg.sender,
            address(this),
            uint256(-1),
            uint256(-1),
            v,
            r,
            s
        );
        // Move tokens to this contract
        tranche.transferFrom(msg.sender, address(this), amount);
        // Get back ELF tokens
        uint256 elfRedeemed = tranche.withdrawFyt(amount);
        // Now turn the elf tokens to underlying
        uint256 underlyingAmount = elf.withdraw(address(this), elfRedeemed);
        // Sends the underlying amount to the caller
        sendBalance(underlying, underlyingAmount);
    }

    /// @dev This method allows a user to redeem a YC and receive underlying
    ///      it uses permit to give itself an unlimited allowance on the YC
    ///      Please not the permit signature expects a max expiration time
    /// @param amount The amount of YC to redeem
    /// @param expiration The expiration time of the Tranche contract
    /// @param assetProxy The asset proxy which manages the position.
    /// @param underlying Either (1) The underlying ERC20 token contract
    ///                   or (2) the ETH_CONSTANT if the user wants eth
    /// @param v The bit indicator which allows address recover from signature
    /// @param r The r component of the signature.
    /// @param s The s componet of the signature.
    function redeeemYC(
        uint256 amount,
        uint256 expiration,
        address assetProxy,
        IERC20 underlying,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external notFrozen() {
        // Create2 Derive the elf and tranche contracts
        IElf elf = deriveElf(assetProxy);
        // Create2 Derive the Traunche contract
        ITranche tranche = deriveTranche(address(elf), expiration);
        // Load the YC contract
        IERC20Permit YC = IERC20Permit(tranche.getYC());
        // Permit this address to get the user's YC
        YC.permit(msg.sender, address(this), uint256(-1), uint256(-1), v, r, s);
        // Move tokens to this contract
        YC.transferFrom(msg.sender, address(this), amount);

        // Get back ELF tokens
        uint256 elfRedeemed = tranche.withdrawYc(amount);
        // Now turn the elf tokens to underlying
        uint256 underlyingAmount = elf.withdraw(address(this), elfRedeemed);
        // Sends the underlying amount to the caller
        sendBalance(underlying, underlyingAmount);
    }

    /// @dev This helper function sends the msg.sender the amount owed
    ///      by either unwrapping weth and sending eth or ERC20 transfering
    /// @param underlying Either (1) The underlying ERC20 token contract
    ///                   or (2) the ETH_CONSTANT
    /// @param amount The amount to send
    function sendBalance(IERC20 underlying, uint256 amount) private {
        // If the user wants eth back we redeem the weth for eth
        if (address(underlying) == ETH_CONSTANT) {
            // Redeem the received weth for eth
            weth.withdraw(amount);
            // Send this contract's balance to the caller
            msg.sender.transfer(amount);
        } else {
            // Send the underlying token to the caller
            underlying.transfer(msg.sender, amount);
        }
    }

    /// @dev This internal mint function preforms the core minting logic after
    ///      the contract already has the token which it will deposit
    /// @param amount The amount of underlying
    /// @param expiration The tranche expiration time
    /// @param assetProxy The proxy which interacts with the yield bearing strategy
    function _mint(
        uint256 amount,
        uint256 expiration,
        address assetProxy
    ) internal {
        // Use create2 to derive the elf
        IElf elf = deriveElf(assetProxy);
        // Create ELF token
        uint256 elfShares = elf.deposit(address(this), amount);
        // Use create2 to derive the traunche contract
        ITranche tranche = deriveTranche(address(elf), expiration);
        // Move funds into the Tranche contract
        uint256 fytShares = tranche.deposit(elfShares);
        // Transfer to the sender the FYT and YC
        tranche.transfer(msg.sender, fytShares);
        // TODO - Replace YC creation with create2 to cut this gas cost.
        IERC20 yc = IERC20(tranche.getYC());
        yc.transfer(msg.sender, elfShares);
    }

    /// @dev This internal function produces the determinstic create2
    ///      address of the ELF contract indicated by an asset proxy
    /// @param assetProxy The asset proxy which is hashed into the create2 seed
    // TODO - Cordinate with Nicholas on exactly what needs to be hashed here
    function deriveElf(address assetProxy) internal pure returns (IElf) {
        return IElf(0);
    }

    /// @dev This internal function produces the determinstic create2
    ///      address of the Tranche contract from an elf contract and expiration
    /// @param elf The ELF contract address
    /// @param expiration The expiration time of the tranche
    function deriveTranche(address elf, uint256 expiration)
        internal
        pure
        returns (ITranche)
    {
        return ITranche(0);
    }
}
