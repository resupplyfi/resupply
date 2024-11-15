import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockCollateral is ERC20, IERC4626 {
    IERC20 public immutable assetToken;

    constructor(string memory name, string memory symbol, address assetTokenAddress) ERC20(name, symbol) {
        assetToken = IERC20(assetTokenAddress);
        _mint(msg.sender, 1_000_000e18);
    }

    function mint(address to, uint256 amount) external returns (uint256) {
        _mint(to, amount);
        return amount;
    }

    function asset() external view returns (address) {
        return address(assetToken);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        require(assetToken.transferFrom(msg.sender, address(this), assets), "Transfer failed");
        _mint(receiver, assets);
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        require(balanceOf(owner) >= assets, "Insufficient balance");
        _burn(owner, assets);
        require(assetToken.transfer(receiver, assets), "Transfer failed");
        return assets;
    }

    function totalAssets() external view returns (uint256) {
        return assetToken.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) external view returns (uint256 shares) {
        return assets;
    }

    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        return shares;
    }

    function maxDeposit(address) external view returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) external view returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        return balanceOf(owner);
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf(owner);
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        return assets;
    }

    function previewMint(uint256 shares) external view returns (uint256) {
        return shares;
    }

    function previewWithdraw(uint256 assets) external view returns (uint256) {
        return assets;
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(balanceOf(owner) >= shares, "Insufficient balance");
        _burn(owner, shares);
        require(assetToken.transfer(receiver, shares), "Transfer failed");
        return shares;
    }

    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        require(assetToken.transferFrom(msg.sender, address(this), shares), "Transfer failed");
        _mint(receiver, shares);
        return shares;
    }
}