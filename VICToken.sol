// SPDX-License-Identifier: MIT
//.
pragma solidity ^0.8.4;
import "./BEP20Detailed.sol";
import "./BEP20.sol";
import "./IPancakeSwapRouter.sol";
import "./SafeMathInt.sol";

contract SociToken is BEP20Detailed, BEP20 {
  using SafeMath for uint256;
  using SafeMathInt for int256;
  mapping(address => bool) public liquidityPool;
  mapping(address => bool) public whitelistTax;

  uint8 public buyTax;
  uint8 public sellTax; 
  uint8 public transferTax;
  uint256 private taxAmount;
  address public marketingPool;
  address public Pool2;
  uint8 public mktPercent;

  //swap 
  IPancakeSwapRouter public uniswapV2Router;
  uint256 public swapTokensAtAmount;
  uint256 public swapTokensMaxAmount;
  bool public swapping;
  bool public enableTax;

  event changeTax(bool _enableTax, uint8 _sellTax, uint8 _buyTax, uint8 _transferTax);
  event changesetMarketingPercent(uint8 _mktTaxPercent);
  event changeLiquidityPoolStatus(address lpAddress, bool status);
  event changeMarketingPool(address marketingPool);
  event changePool2(address Pool2);
  event changeWhitelistTax(address _address, bool status);  
  event UpdateUniswapV2Router(address indexed newAddress,address indexed oldAddress);
  
 
  constructor() payable BEP20Detailed("SociBall", "SOCI", 18) {
    uint256 totalTokens = 10000000 * 10**uint256(decimals());
    _mint(msg.sender, totalTokens);
    sellTax = 9;
    buyTax = 9;
    transferTax = 0;
    enableTax = false;
    marketingPool = 0x0B7df63b1DBa8cf4934a2FFA215dfd099F14f9C8;
    Pool2 = 0xa5419c766379d203Ce8e733c35BCcC8D76108429;
    mktPercent = 20;

    whitelistTax[address(this)] = true;
    whitelistTax[marketingPool] = true;
    whitelistTax[Pool2] = true;
    whitelistTax[owner()] = true;
    whitelistTax[address(0)] = true;
  
    uniswapV2Router = IPancakeSwapRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);//pancakeroter v2
    _approve(address(this), address(uniswapV2Router), ~uint256(0));
    swapTokensAtAmount = totalTokens*2/10**6; 
    swapTokensMaxAmount = totalTokens*2/10**4; 
  }

  

  //update fee
  function setLiquidityPoolStatus(address _lpAddress, bool _status) external onlyOwner {
    liquidityPool[_lpAddress] = _status;
    emit changeLiquidityPoolStatus(_lpAddress, _status);
  }
  function setMarketingPool(address _marketingPool) external onlyOwner {
    marketingPool = _marketingPool;
    whitelistTax[marketingPool] = true;
    emit changeMarketingPool(_marketingPool);
  }  
  function setPool2(address _Pool2) external onlyOwner {
    Pool2 = _Pool2;
    whitelistTax[Pool2] = true;
    emit changePool2(_Pool2);
  }  
  function setTaxes(bool _enableTax, uint8 _sellTax, uint8 _buyTax, uint8 _transferTax) external onlyOwner {
    require(_sellTax < 9);
    require(_buyTax < 9);
    require(_transferTax < 9);
    enableTax = _enableTax;
    sellTax = _sellTax;
    buyTax = _buyTax;
    transferTax = _transferTax;
    emit changeTax(_enableTax,_sellTax,_buyTax,_transferTax);
  }
  function setMarketingPercent(uint8 _mktPercent) external onlyOwner {
    require(_mktPercent <= 100);
    mktPercent = _mktPercent;
    emit changesetMarketingPercent(_mktPercent);
  }

  function setWhitelist(address _address, bool _status) external onlyOwner {
    whitelistTax[_address] = _status;
    emit changeWhitelistTax(_address, _status);
  }
  function getTaxes() external view returns (uint8 _sellTax, uint8 _buyTax, uint8 _transferTax) {
    return (sellTax, buyTax, transferTax);
  } 

  //update swap
  function updateUniswapV2Router(address newAddress) public onlyOwner {
    require(
        newAddress != address(uniswapV2Router),
        "The router already has that address"
    );
    uniswapV2Router = IPancakeSwapRouter(newAddress);
    _approve(address(this), address(uniswapV2Router), ~uint256(0));
    emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
  }
  function setSwapTokensAtAmount(uint256 _swapTokensAtAmount, uint256 _swapTokensMaxAmount) external onlyOwner {
    swapTokensAtAmount = _swapTokensAtAmount;
    swapTokensMaxAmount = _swapTokensMaxAmount;
  }
  
  //Tranfer and tax
  function _transfer(address sender, address receiver, uint256 amount) internal virtual override {
    if (amount == 0) {
        super._transfer(sender, receiver, 0);
        return;
    }

    if(enableTax && !whitelistTax[sender] && !whitelistTax[receiver]){
      //swap
      uint256 contractTokenBalance = balanceOf(address(this));
      bool canSwap = contractTokenBalance >= swapTokensAtAmount;
      if ( canSwap && !swapping && sender != owner() && receiver != owner() ) {
          if(contractTokenBalance > swapTokensMaxAmount){
            contractTokenBalance = swapTokensMaxAmount;
          }
          swapping = true;
          swapAndSendToFee(contractTokenBalance);
          swapping = false;
      }

      if(liquidityPool[sender] == true) {
        //It's an LP Pair and it's a buy
        taxAmount = (amount * buyTax) / 100;
      } else if(liquidityPool[receiver] == true) {      
        //It's an LP Pair and it's a sell
        taxAmount = (amount * sellTax) / 100;
      } else {
        taxAmount = (amount * transferTax) / 100;
      }
      
      if(taxAmount > 0) {
        uint256 mktTax = taxAmount.mul(mktPercent).div(100);
        uint256 Pool2Tax = taxAmount - mktTax;
        if(mktTax>0){
          super._transfer(sender, marketingPool, mktTax);
        }
        if(Pool2Tax>0){
          super._transfer(sender, address(this) , Pool2Tax);
        }
      }    
      super._transfer(sender, receiver, amount - taxAmount);
    }else{
      super._transfer(sender, receiver, amount);
    }
  }

  function swapAndSendToFee(uint256 tokens) private {
    swapTokensForEth(tokens);
    uint256 newBalance = address(this).balance;
    if(newBalance>0){
      payable(Pool2).transfer(newBalance);
    }
  }

  function swapTokensForEth(uint256 tokenAmount) private {
      // generate the uniswap pair path of token -> weth
      address[] memory path = new address[](2);
      path[0] = address(this);
      path[1] = uniswapV2Router.WETH();
      // make the swap
      try
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        )
      {} catch {}
  }

  receive() external payable {}
}
