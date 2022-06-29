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
import "./SaleKindInterface.sol";
import "../registry/AuthenticatedProxy.sol";

contract ExchangeCore is ReentrancyGuard, Ownable {
    using Address for address;
    using Address for address payable;

    string public constant name = "Wyvern Exchange Contract";
    string public constant version = "2.3";

    bytes32 private constant _EIP_712_DOMAIN_TYPEHASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;
    bytes32 private constant _NAME_HASH =
        0x9a2ed463836165738cfa54208ff6e7847fd08cbaac309aac057086cb0a144d13;
    bytes32 private constant _VERSION_HASH =
        0xe2fd538c762ee69cab09ccd70e2438075b7004dd87577dc3937e9fcc8174bb64;
    bytes32 private constant _ORDER_TYPEHASH =
        0xdba08a88a748f356e8faf8578488343eab21b1741728779c9dcfdc782bc800f8;

    bytes4 private constant _EIP_1271_MAGIC_VALUE = 0x1626ba7e;

    bytes32 public DOMAIN_SEPARATOR;

    IERC20 public exchangeToken;

    ProxyRegistry public registry;

    TokenTransferProxy public tokenTransferProxy;

    mapping(bytes32 => bool) public cancelledOrFinalized;

    mapping(bytes32 => uint256) private _approvedOrdersByNonce;

    mapping(address => uint256) public nonces;

    uint256 public minimumMakerProtocolFee = 0;

    uint256 public minimumTakerProtocolFee = 0;

    address public protocolFeeRecipient;

    enum FeeMethod {
        ProtocolFee,
        SplitFee
    }

    uint256 public constant INVERSE_BASIS_POINT = 10000;

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

    event OrderApprovedPartOne(
        bytes32 indexed hash,
        address exchange,
        address indexed maker,
        address taker,
        uint256 makerRelayerFee,
        uint256 takerRelayerFee,
        uint256 makerProtocolFee,
        uint256 takerProtocolFee,
        address indexed feeRecipient,
        FeeMethod feeMethod,
        SaleKindInterface.Side side,
        SaleKindInterface.SaleKind saleKind,
        address target
    );
    event OrderApprovedPartTwo(
        bytes32 indexed hash,
        AuthenticatedProxy.HowToCall howToCall,
        bytes calldatas,
        bytes replacementPattern,
        address staticTarget,
        bytes staticExtradata,
        address paymentToken,
        uint256 basePrice,
        uint256 extra,
        uint256 listingTime,
        uint256 expirationTime,
        uint256 salt,
        bool orderbookInclusionDesired
    );
    event OrderCancelled(bytes32 indexed hash);
    event OrdersMatched(
        bytes32 buyHash,
        bytes32 sellHash,
        address indexed maker,
        address indexed taker,
        uint256 price,
        bytes32 indexed metadata
    );
    event NonceIncremented(address indexed maker, uint256 newNonce);

    constructor() {
        require(
            keccak256(
                "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
            ) == _EIP_712_DOMAIN_TYPEHASH
        );
        require(keccak256(bytes(name)) == _NAME_HASH);
        require(keccak256(bytes(version)) == _VERSION_HASH);
        require(
            keccak256(
                "Order(address exchange,address maker,address taker,uint256 makerRelayerFee,uint256 takerRelayerFee,uint256 makerProtocolFee,uint256 takerProtocolFee,address feeRecipient,uint8 feeMethod,uint8 side,uint8 saleKind,address target,uint8 howToCall,bytes calldata,bytes replacementPattern,address staticTarget,bytes staticExtradata,address paymentToken,uint256 basePrice,uint256 extra,uint256 listingTime,uint256 expirationTime,uint256 salt,uint256 nonce)"
            ) == _ORDER_TYPEHASH
        );

        uint256 chainID = 0;
        assembly {
            chainID := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                _EIP_712_DOMAIN_TYPEHASH,
                _NAME_HASH,
                _VERSION_HASH,
                chainID,
                address(this)
            )
        );
    }

    function incrementNonce() external {
        uint256 newNonce = ++nonces[msg.sender];
        emit NonceIncremented(msg.sender, newNonce);
    }

    function changeMinimumMakerProtocolFee(uint256 newMinimumMakerProtocolFee)
        public
        onlyOwner
    {
        minimumMakerProtocolFee = newMinimumMakerProtocolFee;
    }

    function changeMinimumTakerProtocolFee(uint256 newMinimumTakerProtocolFee)
        public
        onlyOwner
    {
        minimumTakerProtocolFee = newMinimumTakerProtocolFee;
    }

    function changeProtocolFeeRecipient(address newProtocolFeeRecipient)
        public
        onlyOwner
    {
        protocolFeeRecipient = newProtocolFeeRecipient;
    }

    function transferTokens(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        if (amount > 0) {
            tokenTransferProxy.transferFrom(token, from, to, amount);
        }
    }

    function chargeProtocolFee(
        address from,
        address to,
        uint256 amount
    ) internal {
        transferTokens(address(exchangeToken), from, to, amount);
    }

    function staticCall(
        address target,
        bytes memory calldatas,
        bytes memory extradata
    ) public view returns (bool result) {
        bytes memory combined = new bytes(calldatas.length + extradata.length);
        uint256 index;
        assembly {
            index := add(combined, 0x20)
        }
        index = ArrayUtils.unsafeWriteBytes(index, extradata);
        ArrayUtils.unsafeWriteBytes(index, calldatas);
        assembly {
            result := staticcall(
                gas(),
                target,
                add(combined, 0x20),
                mload(combined),
                mload(0x40),
                0
            )
        }
        return result;
    }

    function hashOrder(Order memory order, uint256 nonce)
        internal
        pure
        returns (bytes32 hash)
    {
        uint256 size = 800;
        bytes memory array = new bytes(size);
        uint256 index;
        assembly {
            index := add(array, 0x20)
        }
        index = ArrayUtils.unsafeWriteBytes32(index, _ORDER_TYPEHASH);
        index = ArrayUtils.unsafeWriteAddressWord(index, order.exchange);
        index = ArrayUtils.unsafeWriteAddressWord(index, order.maker);
        index = ArrayUtils.unsafeWriteAddressWord(index, order.taker);
        index = ArrayUtils.unsafeWriteUint(index, order.makerRelayerFee);
        index = ArrayUtils.unsafeWriteUint(index, order.takerRelayerFee);
        index = ArrayUtils.unsafeWriteUint(index, order.makerProtocolFee);
        index = ArrayUtils.unsafeWriteUint(index, order.takerProtocolFee);
        index = ArrayUtils.unsafeWriteAddressWord(index, order.feeRecipient);
        index = ArrayUtils.unsafeWriteUint8Word(index, uint8(order.feeMethod));
        index = ArrayUtils.unsafeWriteUint8Word(index, uint8(order.side));
        index = ArrayUtils.unsafeWriteUint8Word(index, uint8(order.saleKind));
        index = ArrayUtils.unsafeWriteAddressWord(index, order.target);
        index = ArrayUtils.unsafeWriteUint8Word(index, uint8(order.howToCall));
        index = ArrayUtils.unsafeWriteBytes32(
            index,
            keccak256(order.calldatas)
        );
        index = ArrayUtils.unsafeWriteBytes32(
            index,
            keccak256(order.replacementPattern)
        );
        index = ArrayUtils.unsafeWriteAddressWord(index, order.staticTarget);
        index = ArrayUtils.unsafeWriteBytes32(
            index,
            keccak256(order.staticExtradata)
        );
        index = ArrayUtils.unsafeWriteAddressWord(index, order.paymentToken);
        index = ArrayUtils.unsafeWriteUint(index, order.basePrice);
        index = ArrayUtils.unsafeWriteUint(index, order.extra);
        index = ArrayUtils.unsafeWriteUint(index, order.listingTime);
        index = ArrayUtils.unsafeWriteUint(index, order.expirationTime);
        index = ArrayUtils.unsafeWriteUint(index, order.salt);
        index = ArrayUtils.unsafeWriteUint(index, nonce);
        assembly {
            hash := keccak256(add(array, 0x20), size)
        }
        return hash;
    }

    function hashToSign(Order memory order, uint256 nonce)
        internal
        view
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    hashOrder(order, nonce)
                )
            );
    }

    function requireValidOrder(
        Order memory order,
        bytes memory sig,
        uint256 nonce
    ) internal view returns (bytes32) {
        bytes32 hash = hashToSign(order, nonce);
        require(validateOrder(hash, order, sig));
        return hash;
    }

    function validateOrderParameters(Order memory order)
        internal
        view
        returns (bool)
    {
        if (order.exchange != address(this)) {
            return false;
        }

        if (order.maker == address(0)) {
            return false;
        }

        if (
            !SaleKindInterface.validateParameters(
                order.saleKind,
                order.expirationTime
            )
        ) {
            return false;
        }

        if (
            order.feeMethod == FeeMethod.SplitFee &&
            (order.makerProtocolFee < minimumMakerProtocolFee ||
                order.takerProtocolFee < minimumTakerProtocolFee)
        ) {
            return false;
        }

        return true;
    }

    function validateOrder(
        bytes32 hash,
        Order memory order,
        bytes memory sig
    ) internal view returns (bool) {
        if (!validateOrderParameters(order)) {
            return false;
        }

        if (cancelledOrFinalized[hash]) {
            return false;
        }

        uint256 approvedOrderNoncePlusOne = _approvedOrdersByNonce[hash];
        if (approvedOrderNoncePlusOne != 0) {
            return approvedOrderNoncePlusOne == nonces[order.maker] + 1;
        }

        if (ECDSA.recover(hash, sig) == order.maker) {
            return true;
        }

        return _tryContractSignature(order.maker, hash, sig);
    }

    function _tryContractSignature(
        address orderMaker,
        bytes32 hash,
        bytes memory sig
    ) internal view returns (bool) {
        bytes memory isValidSignatureData = abi.encodeWithSelector(
            _EIP_1271_MAGIC_VALUE,
            hash,
            sig
        );

        bytes4 result;

        assembly {
            let success := staticcall(
                gas(),
                orderMaker,
                add(isValidSignatureData, 0x20),
                mload(isValidSignatureData),
                0,
                0
            )

            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            if eq(returndatasize(), 0x20) {
                returndatacopy(0, 0, 0x20)
                result := mload(0)
            }
        }

        return result == _EIP_1271_MAGIC_VALUE;
    }

    function approvedOrders(bytes32 hash) public view returns (bool approved) {
        return _approvedOrdersByNonce[hash] != 0;
    }

    function approveOrder(Order memory order, bool orderbookInclusionDesired)
        internal
    {
        require(msg.sender == order.maker);

        bytes32 hash = hashToSign(order, nonces[order.maker]);

        require(_approvedOrdersByNonce[hash] == 0);

        _approvedOrdersByNonce[hash] = nonces[order.maker] + 1;

        {
            emit OrderApprovedPartOne(
                hash,
                order.exchange,
                order.maker,
                order.taker,
                order.makerRelayerFee,
                order.takerRelayerFee,
                order.makerProtocolFee,
                order.takerProtocolFee,
                order.feeRecipient,
                order.feeMethod,
                order.side,
                order.saleKind,
                order.target
            );
        }
        {
            emit OrderApprovedPartTwo(
                hash,
                order.howToCall,
                order.calldatas,
                order.replacementPattern,
                order.staticTarget,
                order.staticExtradata,
                order.paymentToken,
                order.basePrice,
                order.extra,
                order.listingTime,
                order.expirationTime,
                order.salt,
                orderbookInclusionDesired
            );
        }
    }

    function cancelOrder(
        Order memory order,
        bytes memory sig,
        uint256 nonce
    ) internal {
        bytes32 hash = requireValidOrder(order, sig, nonce);

        require(msg.sender == order.maker);

        cancelledOrFinalized[hash] = true;

        emit OrderCancelled(hash);
    }

    function calculateCurrentPrice(Order memory order)
        internal
        view
        returns (uint256)
    {
        return
            SaleKindInterface.calculateFinalPrice(
                order.side,
                order.saleKind,
                order.basePrice,
                order.extra,
                order.listingTime,
                order.expirationTime
            );
    }

    function calculateMatchPrice(Order memory buy, Order memory sell)
        internal
        view
        returns (uint256)
    {
        uint256 sellPrice = SaleKindInterface.calculateFinalPrice(
            sell.side,
            sell.saleKind,
            sell.basePrice,
            sell.extra,
            sell.listingTime,
            sell.expirationTime
        );

        uint256 buyPrice = SaleKindInterface.calculateFinalPrice(
            buy.side,
            buy.saleKind,
            buy.basePrice,
            buy.extra,
            buy.listingTime,
            buy.expirationTime
        );

        require(buyPrice >= sellPrice);

        return sell.feeRecipient != address(0) ? sellPrice : buyPrice;
    }

    function executeFundsTransfer(Order memory buy, Order memory sell)
        internal
        returns (uint256)
    {
        if (sell.paymentToken != address(0)) {
            require(msg.value == 0);
        }

        uint256 price = calculateMatchPrice(buy, sell);

        if (price > 0 && sell.paymentToken != address(0)) {
            transferTokens(sell.paymentToken, buy.maker, sell.maker, price);
        }

        uint256 receiveAmount = price;

        uint256 requiredAmount = price;

        if (sell.feeRecipient != address(0)) {
            require(sell.takerRelayerFee <= buy.takerRelayerFee);

            if (sell.feeMethod == FeeMethod.SplitFee) {
                require(sell.takerProtocolFee <= buy.takerProtocolFee);

                if (sell.makerRelayerFee > 0) {
                    uint256 makerRelayerFee = (sell.makerRelayerFee * price) /
                        INVERSE_BASIS_POINT;
                    if (sell.paymentToken == address(0)) {
                        receiveAmount -= makerRelayerFee;
                        payable(sell.feeRecipient).sendValue(makerRelayerFee);
                    } else {
                        transferTokens(
                            sell.paymentToken,
                            sell.maker,
                            sell.feeRecipient,
                            makerRelayerFee
                        );
                    }
                }

                if (sell.takerRelayerFee > 0) {
                    uint256 takerRelayerFee = (sell.takerRelayerFee * price) /
                        INVERSE_BASIS_POINT;
                    if (sell.paymentToken == address(0)) {
                        requiredAmount += takerRelayerFee;
                        payable(sell.feeRecipient).sendValue(takerRelayerFee);
                    } else {
                        transferTokens(
                            sell.paymentToken,
                            buy.maker,
                            sell.feeRecipient,
                            takerRelayerFee
                        );
                    }
                }

                if (sell.makerProtocolFee > 0) {
                    uint256 makerProtocolFee = (sell.makerProtocolFee * price) /
                        INVERSE_BASIS_POINT;
                    if (sell.paymentToken == address(0)) {
                        receiveAmount -= makerProtocolFee;
                        payable(protocolFeeRecipient).sendValue(makerProtocolFee);
                    } else {
                        transferTokens(
                            sell.paymentToken,
                            sell.maker,
                            protocolFeeRecipient,
                            makerProtocolFee
                        );
                    }
                }

                if (sell.takerProtocolFee > 0) {
                    uint256 takerProtocolFee = (sell.takerProtocolFee * price) /
                        INVERSE_BASIS_POINT;
                    if (sell.paymentToken == address(0)) {
                        requiredAmount += takerProtocolFee;
                        payable(protocolFeeRecipient).sendValue(takerProtocolFee);
                    } else {
                        transferTokens(
                            sell.paymentToken,
                            buy.maker,
                            protocolFeeRecipient,
                            takerProtocolFee
                        );
                    }
                }
            } else {
                chargeProtocolFee(
                    sell.maker,
                    sell.feeRecipient,
                    sell.makerRelayerFee
                );

                chargeProtocolFee(
                    buy.maker,
                    sell.feeRecipient,
                    sell.takerRelayerFee
                );
            }
        } else {
            require(buy.takerRelayerFee <= sell.takerRelayerFee);

            if (sell.feeMethod == FeeMethod.SplitFee) {
                require(sell.paymentToken != address(0));
                require(buy.takerProtocolFee <= sell.takerProtocolFee);

                if (buy.makerRelayerFee > 0) {
                    uint256 makerRelayerFee = (buy.makerRelayerFee * price) /
                        INVERSE_BASIS_POINT;
                    transferTokens(
                        sell.paymentToken,
                        buy.maker,
                        buy.feeRecipient,
                        makerRelayerFee
                    );
                }

                if (buy.takerRelayerFee > 0) {
                    uint256 takerRelayerFee = (buy.takerRelayerFee * price) /
                        INVERSE_BASIS_POINT;
                    transferTokens(
                        sell.paymentToken,
                        sell.maker,
                        buy.feeRecipient,
                        takerRelayerFee
                    );
                }

                if (buy.makerProtocolFee > 0) {
                    uint256 makerProtocolFee = (buy.makerProtocolFee * price) /
                        INVERSE_BASIS_POINT;
                    transferTokens(
                        sell.paymentToken,
                        buy.maker,
                        protocolFeeRecipient,
                        makerProtocolFee
                    );
                }

                if (buy.takerProtocolFee > 0) {
                    uint256 takerProtocolFee = (buy.takerProtocolFee * price) /
                        INVERSE_BASIS_POINT;
                    transferTokens(
                        sell.paymentToken,
                        sell.maker,
                        protocolFeeRecipient,
                        takerProtocolFee
                    );
                }
            } else {
                chargeProtocolFee(
                    buy.maker,
                    buy.feeRecipient,
                    buy.makerRelayerFee
                );

                chargeProtocolFee(
                    sell.maker,
                    buy.feeRecipient,
                    buy.takerRelayerFee
                );
            }
        }

        if (sell.paymentToken == address(0)) {
            require(msg.value >= requiredAmount);
            payable(sell.maker).sendValue(receiveAmount);
            uint256 diff = msg.value - requiredAmount;
            if (diff > 0) {
                payable(buy.maker).sendValue(diff);
            }
        }

        return price;
    }

    function ordersCanMatch(Order memory buy, Order memory sell)
        internal
        view
        returns (bool)
    {
        return ((buy.side == SaleKindInterface.Side.Buy &&
            sell.side == SaleKindInterface.Side.Sell) &&
            (buy.feeMethod == sell.feeMethod) &&
            (buy.paymentToken == sell.paymentToken) &&
            (sell.taker == address(0) || sell.taker == buy.maker) &&
            (buy.taker == address(0) || buy.taker == sell.maker) &&
            ((sell.feeRecipient == address(0) &&
                buy.feeRecipient != address(0)) ||
                (sell.feeRecipient != address(0) &&
                    buy.feeRecipient == address(0))) &&
            (buy.target == sell.target) &&
            (buy.howToCall == sell.howToCall) &&
            SaleKindInterface.canSettleOrder(
                buy.listingTime,
                buy.expirationTime
            ) &&
            SaleKindInterface.canSettleOrder(
                sell.listingTime,
                sell.expirationTime
            ));
    }

    function atomicMatch(
        Order memory buy,
        bytes memory buySig,
        Order memory sell,
        bytes memory sellSig,
        bytes32 metadata
    ) internal nonReentrant {
        bytes32 buyHash;
        if (buy.maker == msg.sender) {
            require(validateOrderParameters(buy));
        } else {
            buyHash = _requireValidOrderWithNonce(buy, buySig);
        }

        bytes32 sellHash;
        if (sell.maker == msg.sender) {
            require(validateOrderParameters(sell));
        } else {
            sellHash = _requireValidOrderWithNonce(sell, sellSig);
        }

        require(ordersCanMatch(buy, sell));

        address target = sell.target;
        require(target.isContract());

        if (buy.replacementPattern.length > 0) {
            ArrayUtils.guardedArrayReplace(
                buy.calldatas,
                sell.calldatas,
                buy.replacementPattern
            );
        }
        if (sell.replacementPattern.length > 0) {
            ArrayUtils.guardedArrayReplace(
                sell.calldatas,
                buy.calldatas,
                sell.replacementPattern
            );
        }
        require(ArrayUtils.arrayEq(buy.calldatas, sell.calldatas));

        AuthenticatedProxy proxy = registry.proxies(sell.maker);
        require(address(proxy) != address(0));

        if (msg.sender != buy.maker) {
            cancelledOrFinalized[buyHash] = true;
        }
        if (msg.sender != sell.maker) {
            cancelledOrFinalized[sellHash] = true;
        }

        uint256 price = executeFundsTransfer(buy, sell);

        proxy.proxy(sell.target, sell.howToCall, sell.calldatas);

        if (buy.staticTarget != address(0)) {
            require(
                staticCall(
                    buy.staticTarget,
                    sell.calldatas,
                    buy.staticExtradata
                )
            );
        }

        if (sell.staticTarget != address(0)) {
            require(
                staticCall(
                    sell.staticTarget,
                    sell.calldatas,
                    sell.staticExtradata
                )
            );
        }

        emit OrdersMatched(
            buyHash,
            sellHash,
            sell.feeRecipient != address(0) ? sell.maker : buy.maker,
            sell.feeRecipient != address(0) ? buy.maker : sell.maker,
            price,
            metadata
        );
    }

    function _requireValidOrderWithNonce(Order memory order, bytes memory sig)
        internal
        view
        returns (bytes32)
    {
        return requireValidOrder(order, sig, nonces[order.maker]);
    }
}
