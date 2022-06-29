//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library SaleKindInterface {
    enum Side {
        Buy,
        Sell
    }

    enum SaleKind {
        FixedPrice,
        DutchAuction
    }

    function validateParameters(SaleKind saleKind, uint256 expirationTime)
        internal
        pure
        returns (bool)
    {
        return (saleKind == SaleKind.FixedPrice || expirationTime > 0);
    }

    function canSettleOrder(uint256 listingTime, uint256 expirationTime)
        internal
        view
        returns (bool)
    {
        return
            (listingTime < block.timestamp) &&
            (expirationTime == 0 || block.timestamp < expirationTime);
    }

    function calculateFinalPrice(
        Side side,
        SaleKind saleKind,
        uint256 basePrice,
        uint256 extra,
        uint256 listingTime,
        uint256 expirationTime
    ) internal view returns (uint256 finalPrice) {
        if (saleKind == SaleKind.FixedPrice) {
            return basePrice;
        } else if (saleKind == SaleKind.DutchAuction) {
            uint256 diff = (extra * (block.timestamp - listingTime)) /
                (expirationTime - listingTime);
            if (side == Side.Sell) {
                return basePrice - diff;
            } else {
                return basePrice + diff;
            }
        }
    }
}
