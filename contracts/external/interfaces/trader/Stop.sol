/*

    Copyright 2018 dYdX Trading Inc.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

*/

pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

import { OnlySolo } from "./helpers/OnlySolo.sol";
import { ICallee } from "../protocol/interfaces/ICallee.sol";
import { IAutoTrader } from "../protocol/interfaces/IAutoTrader.sol";
import { Acct } from "../protocol/lib/Acct.sol";
import { Types } from "../protocol/lib/Types.sol";


/**
 * @title Expiry
 * @author dYdX
 *
 * TODO
 */
contract Stop is
    OnlySolo,
    ICallee,
    IAutoTrader
{
    // ============ Events ============

    // TODO

    // ============ Structs ============

    struct StopOffer {
        uint128 price;
        uint92 arb;
        bool start;
        bool delta;
    }

    // ============ Storage ============

    // owner => number => market1 => market2 => offer
    mapping (address => mapping (uint256 => mapping (uint256 => mapping (uint256 => StopOffer)))) g_offers;

    // ============ Constructor ============

    constructor (
        address soloMargin
    )
        public
        OnlySolo(soloMargin)
    {}

    // ============ Public Functions ============

    function callFunction(
        address /* sender */,
        Acct.Info memory account,
        bytes memory data
    )
        public
        onlySolo(msg.sender)
    {
        (
            uint256 marketId1,
            uint256 marketId2,
            StopOffer memory offer
        ) = parseCallArgs(data);

        g_offers[account.owner][account.number][marketId1][marketId2] = offer;
    }

    function getTradeCost(
        uint256 inputMarketId,
        uint256 /* outputMarketId */,
        Acct.Info memory makerAccount,
        Acct.Info memory /* takerAccount */,
        Types.Par memory /* oldInputPar */,
        Types.Par memory /* newInputPar */,
        Types.Wei memory /* inputWei */,
        bytes memory /* data */
    )
        public
        // view
        returns (Types.Wei memory)
    {
        uint256 expiryTime = g_accountExpiries[makerAccount.owner][makerAccount.number]
            .expiryTimes[inputMarketId];

        require(
            block.timestamp >= expiryTime,
            "Expiry#getTradeCost: market not yet expired for account"
        );

        // TODO set the cost to the oracle price + spread or whatever we want to do
        return Types.Wei({
            sign: true,
            value: 0
        });
    }

    // ============ Private Functions ============

    function inputWeiToOutputWei(
        Types.Wei memory inputWei,
        uint256 inputMarketId,
        uint256 outputMarketId,
        StopOffer memory offer
    )
        private
        view
        returns (Types.Wei memory)
    {
        Decimal.D256 memory incentive = Decimal.D256({ value: offer. arb });
        uint256 nonSpreadValue = Math.getPartial(
            inputWei.value,
            SOLO_MARGIN.getMarketPrice(inputMarketId).value,
            SOLO_MARGIN.getMarketPrice(outputMarketId).value
        );
        return Types.Wei({
            sign: false,
            value: Decimal.mul(nonSpreadValue, incentive)
        });
    }

    function parseCallArgs(
        bytes memory data
    )
        private
        pure
        returns (
            uint256 market1,
            uint256 market2,
            StopOffer memory
        )
    {
        require(
            data.length == 192,
            "TODO_REASON"
        );

        uint256 rawPrice;
        uint256 rawArb;
        uint256 rawStart;
        uint256 rawDelta;

        /* solium-disable-next-line security/no-inline-assembly */
        assembly {
            marketId1 := mload(add(data, 32))
            marketId2 := mload(add(data, 64))
            rawPrice := mload(add(data, 96))
            rawArb := mload(add(data, 128))
            rawStart := mload(add(data, 160))
            rawDelta := mload(add(data, 192))
        }

        return (
            marketId1,
            marketId2,
            StopOffer({
                price: Decimal.D256({ value: rawPrice.to128() }),
                arb: Decimal.D256({ value: rawArb.to92() }),
                rawStart != 0,
                rawDelta != 0
            })
        );
    }
}
