//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../common/ArrayUtils.sol";
import "../registry/ProxyRegistry.sol";
import "../registry/TokenTransferProxy.sol";
import "../exchange/SaleKindInterface.sol";
import "../registry/AuthenticatedProxy.sol";

contract ExchangeTest is ReentrancyGuard, Ownable {
    enum FeeMethod {
        ProtocolFee,
        SplitFee
    }

    struct Order {
        address exchange;
        address maker;
        address taker;
        uint256 makerRelayerFee;
        uint256 takerRelayerFee;
        uint256 makerProtocolFee;
        uint256 takerProtocolFee;
        address feeRecipient;
        FeeMethod feeMethod;
        SaleKindInterface.Side side;
        SaleKindInterface.SaleKind saleKind;
        address target;
        AuthenticatedProxy.HowToCall howToCall;
        bytes calldatas;
        bytes replacementPattern;
        address staticTarget;
        bytes staticExtradata;
        address paymentToken;
        uint256 basePrice;
        uint256 extra;
        uint256 listingTime;
        uint256 expirationTime;
        uint256 salt;
    }

    function GetTime() public view returns (uint256) {
        return block.timestamp;
    }

    function ordersCanMatch_(
        address[14] memory addrs,
        uint256[18] memory uints,
        uint8[8] memory feeMethodsSidesKindsHowToCalls,
        bytes memory calldataBuy,
        bytes memory calldataSell,
        bytes memory replacementPatternBuy,
        bytes memory replacementPatternSell,
        bytes memory staticExtradataBuy,
        bytes memory staticExtradataSell
    ) public view returns (uint256) {
        Order memory buy = Order(
            addrs[0],
            addrs[1],
            addrs[2],
            uints[0],
            uints[1],
            uints[2],
            uints[3],
            addrs[3],
            FeeMethod(feeMethodsSidesKindsHowToCalls[0]),
            SaleKindInterface.Side(feeMethodsSidesKindsHowToCalls[1]),
            SaleKindInterface.SaleKind(feeMethodsSidesKindsHowToCalls[2]),
            addrs[4],
            AuthenticatedProxy.HowToCall(feeMethodsSidesKindsHowToCalls[3]),
            calldataBuy,
            replacementPatternBuy,
            addrs[5],
            staticExtradataBuy,
            (addrs[6]),
            uints[4],
            uints[5],
            uints[6],
            uints[7],
            uints[8]
        );
        Order memory sell = Order(
            addrs[7],
            addrs[8],
            addrs[9],
            uints[9],
            uints[10],
            uints[11],
            uints[12],
            addrs[10],
            FeeMethod(feeMethodsSidesKindsHowToCalls[4]),
            SaleKindInterface.Side(feeMethodsSidesKindsHowToCalls[5]),
            SaleKindInterface.SaleKind(feeMethodsSidesKindsHowToCalls[6]),
            addrs[11],
            AuthenticatedProxy.HowToCall(feeMethodsSidesKindsHowToCalls[7]),
            calldataSell,
            replacementPatternSell,
            addrs[12],
            staticExtradataSell,
            (addrs[13]),
            uints[13],
            uints[14],
            uints[15],
            uints[16],
            uints[17]
        );
        return ordersCanMatch(buy, sell);
    }

    function ordersCanMatch(Order memory buy, Order memory sell)
        internal
        view
        returns (uint256)
    {
        if (
            (buy.side == SaleKindInterface.Side.Buy &&
                sell.side == SaleKindInterface.Side.Sell) == false
        ) {
            return 1;
        }
        if ((buy.feeMethod == sell.feeMethod) == false) {
            return 2;
        }

        if ((buy.paymentToken == sell.paymentToken) == false) {
            return 3;
        }

        if ((sell.taker == address(0) || sell.taker == buy.maker) == false) {
            return 4;
        }

        if ((buy.taker == address(0) || buy.taker == sell.maker) == false) {
            return 5;
        }

        if (
            ((sell.feeRecipient == address(0) &&
                buy.feeRecipient != address(0)) ||
                (sell.feeRecipient != address(0) &&
                    buy.feeRecipient == address(0))) == false
        ) {
            return 6;
        }

        if ((buy.target == sell.target) == false) {
            return 7;
        }

        if ((buy.howToCall == sell.howToCall) == false) {
            return 8;
        }

        if (
            SaleKindInterface.canSettleOrder(
                buy.listingTime,
                buy.expirationTime
            ) == false
        ) {
            return 9;
        }

        if (
            SaleKindInterface.canSettleOrder(
                sell.listingTime,
                sell.expirationTime
            ) == false
        ) {
            return 10;
        }

        return 0;
    }
}
