// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import ERC20 token standard implementation from OpenZeppelin.
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// Import Ownable contract for access control from OpenZeppelin.
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Dinero Interface (Copied from WrappedDinero.sol)
 * @dev Defines the external functions for interacting with the original Dinero token contract.
 */
interface Dinero {
    function coinBalanceOf(address _owner) external view returns (uint256);
    function sendCoin(uint256 _amount, address _receiver) external;
    // In a real scenario, if Dinero was an ERC20, it would have approve/transferFrom.
    // For this specific test setup with MockDinero, we might need a way for DropBox to call sendCoin.
    // The MockDinero's sendCoin expects msg.sender to have tokens.
    // The DropBox will be msg.sender when calling MockDinero.sendCoin.
    // So, the DropBox needs to "own" the tokens it sends.
}

/**
 * @title DropBoxTest Contract (Slightly adapted for testing if needed, but original should work)
 * @dev A contract that temporarily holds Dinero tokens for a user before they are wrapped.
 *      It is owned by the WrappedDineroTest contract to allow collection of tokens.
 */
contract DropBoxTest is Ownable { // Renamed to avoid collision if in same project structure
    /**
     * @dev Constructor that sets the initial owner of the DropBoxTest.
     * @param initialOwner The address of the initial owner (the WrappedDineroTest contract).
     */
    constructor(address initialOwner) Ownable(initialOwner) {}

    /**
     * @dev Allows the owner (WrappedDineroTest contract) to collect Dinero tokens from this DropBoxTest.
     *      The collected tokens are sent from this DropBoxTest contract to its owner (WrappedDineroTest contract).
     * @param value The amount of Dinero tokens to collect.
     * @param dineroContract The interface to interact with the Dinero token contract (MockDinero in tests).
     */
    function collect(uint256 value, Dinero dineroContract) public onlyOwner {
        // In the actual Dinero contract, sendCoin would transfer from the caller (DropBoxTest)
        // to the recipient (owner() which is WrappedDineroTest).
        // The DropBoxTest contract itself needs to have the Dinero tokens to send them.
        dineroContract.sendCoin(value, owner());
    }
}

/**
 * @title WrappedDineroTest Contract
 * @dev Test version of WrappedDinero. An ERC20 token contract that represents Dinero tokens wrapped.
 *      This version accepts the Dinero token address in the constructor for testability with mocks.
 */
contract WrappedDineroTest is ERC20 {
    // Event emitted when a new DropBoxTest is created for a user.
    event DropBoxCreated(address indexed user, address indexed dropBoxAddress); // Added dropBoxAddress for easier testing
    // Event emitted when Dinero tokens are wrapped into DINO tokens.
    event Wrapped(uint256 indexed value, address indexed user);
    // Event emitted when DINO tokens are unwrapped back into Dinero tokens.
    event Unwrapped(uint256 indexed value, address indexed user);

    // Address of the Dinero token contract (MockDinero in tests).
    Dinero public dineroToken; // Made public for easier inspection in tests

    // Mapping from a user's address to their personal DropBoxTest contract address.
    mapping(address => address) public dropBoxes;

    /**
     * @dev Constructor for the WrappedDineroTest contract.
     *      Initializes the ERC20 token with a name "Wrapped Dinero" and symbol "DINO".
     *      Sets the address of the Dinero token contract (MockDinero for tests).
     * @param _dineroTokenAddress The address of the Dinero (or MockDinero) contract.
     */
    constructor(address _dineroTokenAddress) ERC20("Wrapped Dinero", "DINO") {
        require(_dineroTokenAddress != address(0), "WrappedDineroTest: Invalid Dinero token address");
        dineroToken = Dinero(_dineroTokenAddress);
    }

    /**
     * @dev Creates a new DropBoxTest contract for the caller (`msg.sender`).
     *      The WrappedDineroTest contract itself is set as the owner of the new DropBoxTest.
     *      Emits a `DropBoxCreated` event.
     */
    function createDropBox() public {
        require(dropBoxes[msg.sender] == address(0), "WrappedDineroTest: Drop box already exists for user");
        DropBoxTest newDropBox = new DropBoxTest(address(this));
        dropBoxes[msg.sender] = address(newDropBox);
        emit DropBoxCreated(msg.sender, address(newDropBox));
    }

    /**
     * @dev Returns the address of the DropBoxTest associated with the caller (`msg.sender`).
     * @return The address of the caller's DropBoxTest. Returns address(0) if no DropBoxTest exists.
     */
    function getDropBoxAddress() public view returns (address) {
        return dropBoxes[msg.sender];
    }

    /**
     * @dev Wraps Dinero tokens into WrappedDineroTest (DINO) tokens.
     *      The user must have first created a DropBoxTest and ensured Dinero tokens were transferred to it.
     *      This function instructs the user's DropBoxTest to send its Dinero tokens to this WrappedDineroTest contract.
     *      Then, an equivalent amount of DINO tokens are minted to the user.
     *      Emits a `Wrapped` event.
     * @param value The amount of Dinero tokens to wrap.
     */
    function wrap(uint256 value) public {
        require(value > 0, "WrappedDineroTest: Wrap amount must be greater than zero");
        address userDropBoxAddress = dropBoxes[msg.sender];
        require(userDropBoxAddress != address(0), "WrappedDineroTest: User must create a drop box first");
        
        // Check balance of Dinero in the user's DropBoxTest
        uint256 dropBoxBalance = dineroToken.coinBalanceOf(userDropBoxAddress);
        require(dropBoxBalance >= value, "WrappedDineroTest: Not enough Dinero in drop box");
        
        // Instruct the DropBoxTest to send its Dinero tokens to this WrappedDineroTest contract.
        // The DropBoxTest contract (userDropBoxAddress) calls dineroToken.sendCoin(value, address(this)).
        // For this to work with MockDinero, userDropBoxAddress must be the msg.sender to MockDinero.sendCoin
        // and have the actual tokens. This is handled by DropBoxTest.collect().
        DropBoxTest(userDropBoxAddress).collect(value, dineroToken);
        
        // Mint the corresponding amount of DINO tokens to the user.
        _mint(msg.sender, value);
        emit Wrapped(value, msg.sender);
    }

    /**
     * @dev Unwraps WrappedDineroTest (DINO) tokens back into Dinero tokens.
     *      The user's DINO tokens are burned.
     *      An equivalent amount of Dinero tokens are transferred from this WrappedDineroTest contract to the user.
     *      Emits an `Unwrapped` event.
     * @param value The amount of DINO tokens to unwrap.
     */
    function unwrap(uint256 value) public {
        require(value > 0, "WrappedDineroTest: Unwrap amount must be greater than zero");
        // Check DINO balance of the user.
        require(balanceOf(msg.sender) >= value, "WrappedDineroTest: Not enough DINO to unwrap");
        
        // Burn the user's DINO tokens first (checks-effects-interactions pattern).
        _burn(msg.sender, value);
        
        // Send the original Dinero tokens from this contract back to the user.
        // This WrappedDineroTest contract must have the Dinero tokens to send.
        dineroToken.sendCoin(value, msg.sender);
        emit Unwrapped(value, msg.sender);
    }

    /**
     * @dev Returns the number of decimals used to display token amounts.
     *      Wrapped Dinero (DINO) uses 0 decimals.
     * @return The number of decimals (0).
     */
    function decimals() public pure override returns (uint8) {
        return 0;
    }
}
