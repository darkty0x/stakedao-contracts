// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/IUniswapRouter.sol";
import "../interfaces/ICurvePool.sol";
import "../interfaces/ICurveGauge.sol";
import "../interfaces/IController.sol";

contract StrategyCurveAave {
	using SafeERC20 for IERC20;
	using Address for address;
	using SafeMath for uint256;

	address public constant want = address(0x1337BedC9D22ecbe766dF105c9623922A27963EC);

	address public constant usdc = address(0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664);

	address public constant crv = address(0x249848BeCA43aC405b8102Ec90Dd5F22CA513c06); // wrong

	address public constant wavax = address(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

	address public constant pool = address(0x7f90122BF0700F9E7e1F688fe926940E8839F353);

	address public gauge = address(0x5B5CFE992AdAC0C9D48E05854B2d91C73a003858);

	address public constant joeRouter = address(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);

	uint256 public performanceFee = 1500;
	uint256 public constant performanceMax = 10000;

	uint256 public withdrawalFee = 50;
	uint256 public constant withdrawalMax = 10000;

	address public governance;
	address public controller;
	address public strategist;

	uint256 public earned;

	event Harvested(uint256 wantEarned, uint256 lifetimeEarned);

	modifier onlyGovernance() {
		require(msg.sender == governance, "!governance");
		_;
	}

	modifier onlyController() {
		require(msg.sender == controller, "!controller");
		_;
	}

	constructor(address _controller) public {
		governance = msg.sender;
		strategist = msg.sender;
		controller = _controller;
	}

	function getName() external pure returns (string memory) {
		return "StrategyCurveAave";
	}

	function setGauge(address _gauge) external onlyGovernance {
		gauge = _gauge;
	}

	function setStrategist(address _strategist) external onlyGovernance {
		strategist = _strategist;
	}

	function setWithdrawalFee(uint256 _withdrawalFee) external onlyGovernance {
		withdrawalFee = _withdrawalFee;
	}

	function setPerformanceFee(uint256 _performanceFee) external onlyGovernance {
		performanceFee = _performanceFee;
	}

	function deposit() public {
		uint256 _want = IERC20(want).balanceOf(address(this));
		if (_want > 0) {
			IERC20(want).approve(gauge, _want);
			ICurveGauge(gauge).deposit(_want);
		}
	}

	// Controller only function for creating additional rewards from dust
	function withdraw(IERC20 _asset) external onlyController returns (uint256 balance) {
		require(want != address(_asset), "want");
		require(usdc != address(_asset), "usdc");
		balance = _asset.balanceOf(address(this));
		_asset.safeTransfer(controller, balance);
	}

	// Withdraw partial funds, normally used with a vault withdrawal
	function withdraw(uint256 _amount) external onlyController {
		uint256 _balance = IERC20(want).balanceOf(address(this));
		if (_balance < _amount) {
			_withdrawSome(_amount.sub(_balance));
		}

		uint256 _fee = _amount.mul(withdrawalFee).div(withdrawalMax);

		IERC20(want).safeTransfer(IController(controller).rewards(), _fee);
		address _vault = IController(controller).vaults(address(want));
		require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds

		IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
	}

	function _withdrawSome(uint256 _amount) internal {
		ICurveGauge(gauge).withdraw(_amount);
	}

	// Withdraw all funds, normally used when migrating strategies
	function withdrawAll() external onlyController returns (uint256 balance) {
		_withdrawAll();

		balance = balanceOfWant();

		address _vault = IController(controller).vaults(address(want));
		require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
		IERC20(want).safeTransfer(_vault, balance);
	}

	function _withdrawAll() internal {
		uint256 _before = balanceOf();
		_withdrawSome(balanceOfPool());
		require(_before == balanceOf(), "!slippage");
	}

	function swapCRVToUsdc(uint256 amount) internal {}

	function swapWMATICToUsdc(uint256 amount) internal {}

	function _swapTraderJoeWithPath(address[] memory path, uint256 _amount) internal returns (uint256) {
		IERC20(path[0]).safeApprove(joeRouter, 0);
		IERC20(path[0]).safeApprove(joeRouter, _amount);

		uint256[] memory amounts = IUniswapRouter(joeRouter).getAmountsOut(_amount, path);

		uint256 minAmount = amounts[path.length - 1].mul(995).div(1000);

		uint256[] memory outputs = IUniswapRouter(joeRouter).swapExactTokensForTokens(
			_amount,
			minAmount,
			path,
			address(this),
			now.add(1800)
		);

		return outputs[1];
	}

	function harvest() public {
		require(msg.sender == strategist || msg.sender == governance, "!authorized");

		ICurveGauge(gauge).claim_rewards();

		uint256 _crv = IERC20(crv).balanceOf(address(this));
		uint256 _wavax = IERC20(wavax).balanceOf(address(this));

		if (_crv > 0) {}

		if (_wavax > 0) {
			address[] memory wavax_usdc_path = new address[](2);
			wavax_usdc_path[0] = wavax;
			wavax_usdc_path[1] = usdc;

			_swapTraderJoeWithPath(wavax_usdc_path, _wavax);
		}

		uint256 _usdc = IERC20(usdc).balanceOf(address(this));

		if (_usdc > 0) {
			IERC20(usdc).approve(pool, _usdc);
			ICurvePool(pool).add_liquidity([0, _usdc, 0], 0, true);
		}

		uint256 _want = IERC20(want).balanceOf(address(this));

		if (_want > 0) {
			uint256 _fee = _want.mul(performanceFee).div(performanceMax);
			IERC20(want).safeTransfer(IController(controller).rewards(), _fee);
			deposit();
		}

		earned = earned.add(_want);
		emit Harvested(_want, earned);
	}

	function balanceOfWant() public view returns (uint256) {
		return IERC20(want).balanceOf(address(this));
	}

	function balanceOfPool() public view returns (uint256) {
		return ICurveGauge(gauge).balanceOf(address(this));
	}

	function balanceOf() public view returns (uint256) {
		return balanceOfWant().add(balanceOfPool());
	}

	function setGovernance(address _governance) external onlyGovernance {
		governance = _governance;
	}

	function setController(address _controller) external onlyGovernance {
		controller = _controller;
	}
}
