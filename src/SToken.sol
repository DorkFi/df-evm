// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title SToken
/// @notice ERC-20 (arc200-style) with EIP-2612 Permit and mintable interface. Represents debt in borrow-only or standard markets.
/// @dev Only the LendingPool can mint/burn. Transfer and approve work as standard ERC-20; supports permit for gasless approvals.
contract SToken {
    string public name;
    string public symbol;
    uint8 public decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public immutable lendingPool;
    uint64 public immutable marketId;

    mapping(address => uint256) public nonces;
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);

    error Unauthorized();

    modifier onlyLendingPool() {
        if (msg.sender != lendingPool) revert Unauthorized();
        _;
    }

    constructor(
        address _lendingPool,
        uint64 _marketId,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) {
        lendingPool = _lendingPool;
        marketId = _marketId;
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(_name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    /// @notice Mint STokens. Only callable by LendingPool (e.g. on borrow).
    function mint(address to, uint256 amount) external onlyLendingPool {
        if (amount == 0) return;
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Mint(to, amount);
        emit Transfer(address(0), to, amount);
    }

    /// @notice Burn STokens from an account. Only callable by LendingPool (e.g. on repay).
    function burnFrom(address from, uint256 amount) external onlyLendingPool {
        if (amount == 0) return;
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Burn(from, amount);
        emit Transfer(from, address(0), amount);
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "Permit expired");
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                owner,
                spender,
                value,
                nonces[owner]++,
                deadline
            )
        );
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );
        address signer = ecrecover(hash, v, r, s);
        require(signer != address(0) && signer == owner, "Invalid signature");
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }
}
