// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // Specifies the Solidity compiler version.

// @author: Rocky Fikki -rfikki

// Import ERC20 token standard implementation from OpenZeppelin.
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// Import Ownable contract for access control from OpenZeppelin.
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Dinero Interface
 * @dev Defines the external functions for interacting with the original Dinero token contract.
 */
interface Dinero {
    /**
     * @dev Returns the Dinero token balance of a given address.
     * @param _owner The address to query the balance of.
     * @return The balance of Dinero tokens.
     */
    function coinBalanceOf(address _owner) external view returns (uint256);

    /**
     * @dev Sends a specified amount of Dinero tokens to a receiver.
     * @param _amount The amount of Dinero tokens to send.
     * @param _receiver The address of the recipient.
     */
    function sendCoin(uint256 _amount, address _receiver) external;
}

/**
 * @title DropBox Contract
 * @dev A contract that temporarily holds Dinero tokens for a user before they are wrapped.
 *      It is owned by the WrappedDinero contract to allow collection of tokens.
 */
contract DropBox is Ownable {
    /**
     * @dev Constructor that sets the initial owner of the DropBox.
     * @param initialOwner The address of the initial owner (typically the WrappedDinero contract).
     */
    constructor(address initialOwner) Ownable(initialOwner) {}

    /**
     * @dev Allows the owner (WrappedDinero contract) to collect Dinero tokens from this DropBox.
     *      The collected tokens are sent to the owner of this DropBox contract.
     * @param value The amount of Dinero tokens to collect.
     * @param wdInt The interface to interact with the Dinero token contract.
     */
    function collect(uint256 value, Dinero wdInt) public onlyOwner {
        wdInt.sendCoin(value, owner()); // `owner()` here refers to the owner of this DropBox contract.
    }
}

/**
 * @title WrappedDinero Contract
 * @dev An ERC20 token contract that represents Dinero tokens wrapped on the blockchain.
 *      Users deposit Dinero into a personal DropBox, then call `wrap` to mint WrappedDinero (DINO).
 *      Users can `unwrap` DINO to get back their original Dinero tokens.
 */
contract WrappedDinero is ERC20 {
    // Event emitted when a new DropBox is created for a user.
    event DropBoxCreated(address indexed owner);
    // Event emitted when Dinero tokens are wrapped into DINO tokens.
    event Wrapped(uint256 indexed value, address indexed owner);
    // Event emitted when DINO tokens are unwrapped back into Dinero tokens.
    event Unwrapped(uint256 indexed value, address indexed owner);

    // The constant address of the original Dinero token contract.
    address constant wdAddr = 0x374642AFe485D1A181B01f5b028d169bE58F3106;
    // A constant interface instance to interact with the Dinero token contract.
    Dinero constant wdInt = Dinero(wdAddr);

    // Mapping from a user's address to their personal DropBox contract address.
    mapping(address => address) public dropBoxes;

    /**
     * @dev Constructor for the WrappedDinero contract.
     *      Initializes the ERC20 token with a name "Wrapped Dinero" and symbol "DINO".
     */
    constructor() ERC20("Wrapped Dinero", "DINO") {}

    /**
     * @dev Creates a new DropBox contract for the caller (`msg.sender`).
     *      The WrappedDinero contract itself is set as the owner of the new DropBox.
     *      This allows the WrappedDinero contract to later call `collect` on the DropBox.
     *      Emits a `DropBoxCreated` event.
     */
    function createDropBox() public {
        require(dropBoxes[msg.sender] == address(0), "Drop box already exists");
        // Create a new DropBox, setting this WrappedDinero contract as its owner.
        dropBoxes[msg.sender] = address(new DropBox(address(this)));
        emit DropBoxCreated(msg.sender); // Event indicates the user for whom the DropBox was created.
    }

    /**
     * @dev Returns the address of the DropBox associated with the caller (`msg.sender`).
     * @return The address of the caller's DropBox. Returns address(0) if no DropBox exists.
     */
    function getDropBoxAddress() public view returns (address) {
        return dropBoxes[msg.sender];
    }

    /**
     * @dev Wraps Dinero tokens into WrappedDinero (DINO) tokens.
     *      The user must have first created a DropBox and transferred Dinero tokens to it.
     *      This function will instruct the user's DropBox to send its Dinero tokens to this WrappedDinero contract.
     *      Then, an equivalent amount of DINO tokens are minted to the user.
     *      Emits a `Wrapped` event.
     * @param value The amount of Dinero tokens to wrap.
     */
    function wrap(uint256 value) public {
        address dropBox = dropBoxes[msg.sender]; // Get the user's DropBox address.
        require(dropBox != address(0), "You must create a drop box first"); 
        require(wdInt.coinBalanceOf(dropBox) >= value, "Not enough coins in drop box");
        
        // Call `collect` on the user's DropBox.
        // Since `address(this)` (WrappedDinero contract) is the owner of the DropBox, this call is authorized.
        // The Dinero tokens will be sent from the `dropBox` to `address(this)`.
        DropBox(dropBox).collect(value, wdInt);
        
        // Mint the corresponding amount of DINO tokens to the user.
        _mint(msg.sender, value);
        emit Wrapped(value, msg.sender);
    }

    /**
     * @dev Unwraps WrappedDinero (DINO) tokens back into Dinero tokens.
     *      The user's DINO tokens are burned.
     *      An equivalent amount of Dinero tokens are transferred from this WrappedDinero contract to the user.
     *      Emits an `Unwrapped` event.
     * @param value The amount of DINO tokens to unwrap.
     */
    function unwrap(uint256 value) public {
        require(balanceOf(msg.sender) >= value, "Not enough coins to unwrap"); // Check DINO balance.
        
        // Burn the user's DINO tokens first to prevent reentrancy issues.
        _burn(msg.sender, value);
        
        // Send the original Dinero tokens from this contract back to the user.
        wdInt.sendCoin(value, msg.sender);
        emit Unwrapped(value, msg.sender);
    }

    /**
     * @dev Returns the number of decimals used to display token amounts.
     *      Wrapped Dinero (DINO) uses 0 decimals, meaning it's a non-divisible token.
     * @return The number of decimals (0).
     */
    function decimals() public pure override returns (uint8) {
        return 0;
    }
}
