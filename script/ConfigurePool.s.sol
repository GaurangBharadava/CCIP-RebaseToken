// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {TokenPool} from "ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";

contract ConfigurePoolScript is Script {
    function run(
        address localPoolAddress,
        uint64 remoteChianSelector,
        address remotePoolAddress,
        address remoteToken,
        bool outboundRateLimiterIsEnabled,
        uint128 outbounfRateLimiterCapacity,
        uint128 outboundRateLimiterRate,
        bool inboundRateLimiterIsEnabled,
        uint128 inbounfRateLimiterCapacity,
        uint128 inboundRateLimiterRate
    ) public {
        vm.startBroadcast();
        TokenPool.ChainUpdate[] memory chainToAdd = new TokenPool.ChainUpdate[](1);
        chainToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChianSelector,
            allowed: true,
            remotePoolAddress: abi.encode(remotePoolAddress),
            remoteTokenAddress: abi.encode(remoteToken),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: outboundRateLimiterIsEnabled,
                capacity: outbounfRateLimiterCapacity,
                rate: outboundRateLimiterRate
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: inboundRateLimiterIsEnabled,
                capacity: inbounfRateLimiterCapacity,
                rate: inboundRateLimiterRate
            })
        });
        TokenPool(localPoolAddress).applyChainUpdates(chainToAdd);
        vm.stopBroadcast();
    }
}
