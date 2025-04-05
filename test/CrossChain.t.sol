// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {TokenPool} from "ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";

import {CCIPLocalSimulatorFork} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {Register} from "@chainlink/local/src/ccip/Register.sol";
import {RegistryModuleOwnerCustom} from "ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RateLimiter} from "ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract CrossChain is Test {
    address owner = makeAddr("owner");
    address user = makeAddr("user");
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    uint256 constant SEND_VALUE = 1e18;

    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    RebaseToken sepoliaToken;
    RebaseToken arbToken;

    Vault vault;
    RebaseTokenPool sepoliaPool;
    RebaseTokenPool arbPool;

    Register.NetworkDetails sepoliaNetworkDetail;
    Register.NetworkDetails arbNetworkDetail;

    function setUp() public {
        sepoliaFork = vm.createSelectFork("sepolia-eth");
        arbSepoliaFork = vm.createFork("arb-sepolia");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork)); // which anables the ccipLocalSimulatorFork address persistent across forks.

        // Deploy and configure on sepolia
        sepoliaNetworkDetail = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        sepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
            sepoliaNetworkDetail.rmnProxyAddress,
            sepoliaNetworkDetail.routerAddress
        );
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));
        RegistryModuleOwnerCustom(sepoliaNetworkDetail.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(sepoliaToken)
        );
        TokenAdminRegistry(sepoliaNetworkDetail.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetail.tokenAdminRegistryAddress).setPool(
            address(sepoliaToken), address(sepoliaPool)
        );
        vm.stopPrank();

        // Deploy and configure on arbitrum
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        arbNetworkDetail = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        arbToken = new RebaseToken();
        arbPool = new RebaseTokenPool(
            IERC20(address(arbToken)),
            new address[](0),
            arbNetworkDetail.rmnProxyAddress,
            arbNetworkDetail.routerAddress
        );
        // arbToken.grantMintAndBurnRole(address(vault));
        arbToken.grantMintAndBurnRole(address(arbPool));
        RegistryModuleOwnerCustom(arbNetworkDetail.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbToken)
        );
        TokenAdminRegistry(arbNetworkDetail.tokenAdminRegistryAddress).acceptAdminRole(address(arbToken));
        TokenAdminRegistry(arbNetworkDetail.tokenAdminRegistryAddress).setPool(address(arbToken), address(arbPool));
        vm.stopPrank();
        configureTokenPool(
            sepoliaFork, address(sepoliaPool), arbNetworkDetail.chainSelector, address(arbPool), address(arbToken)
        );
        configureTokenPool(
            arbSepoliaFork,
            address(arbPool),
            sepoliaNetworkDetail.chainSelector,
            address(sepoliaPool),
            address(sepoliaToken)
        );
    }

    function configureTokenPool(
        uint256 fork,
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteTokenAddress
    ) public {
        vm.selectFork(fork);
        vm.prank(owner);
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);
        // struct ChainUpdate {
        //     uint64 remoteChainSelector; // ──╮ Remote chain selector
        //     bool allowed; // ────────────────╯ Whether the chain should be enabled
        //     bytes remotePoolAddress; //        Address of the remote pool, ABI encoded in the case of a remote EVM chain.
        //     bytes remoteTokenAddress; //       Address of the remote token, ABI encoded in the case of a remote EVM chain.
        //     RateLimiter.Config outboundRateLimiterConfig; // Outbound rate limited config, meaning the rate limits for all of the onRamps for the given chain
        //     RateLimiter.Config inboundRateLimiterConfig; // Inbound rate limited config, meaning the rate limits for all of the offRamps for the given chain
        // }
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true,
            remotePoolAddress: remotePoolAddresses[0],
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        TokenPool(localPool).applyChainUpdates(chainsToAdd);
    }

    function bridgeToken(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetail,
        Register.NetworkDetails memory remoteNetworkDetail,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);

        //   struct EVM2AnyMessage {
        //     bytes receiver; // abi.encode(receiver address) for dest EVM chains
        //     bytes data; // Data payload
        //     EVMTokenAmount[] tokenAmounts; // Token transfers
        //     address feeToken; // Address of feeToken. address(0) means you will send msg.value.
        //     bytes extraArgs; // Populate this with _argsToBytes(EVMExtraArgsV2)
        //   }
        Client.EVMTokenAmount[] memory evmTokenAmount = new Client.EVMTokenAmount[](1);
        evmTokenAmount[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(user)),
            data: "",
            tokenAmounts: evmTokenAmount,
            feeToken: localNetworkDetail.linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 100_000}))
        });
        uint256 fees =
            IRouterClient(localNetworkDetail.routerAddress).getFee(remoteNetworkDetail.chainSelector, message);
        // for sending the fees we have to get link token like pretanding that we have link token.
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fees);
        vm.prank(user);
        IERC20(localNetworkDetail.linkAddress).approve(localNetworkDetail.routerAddress, fees);
        vm.prank(user);
        IERC20(address(localToken)).approve(localNetworkDetail.routerAddress, amountToBridge);
        uint256 localBalanceBefore = localToken.balanceOf(user);
        vm.prank(user);
        IRouterClient(localNetworkDetail.routerAddress).ccipSend(remoteNetworkDetail.chainSelector, message);
        uint256 localBalanceAfter = localToken.balanceOf(user);

        assertEq(localBalanceAfter, localBalanceBefore - amountToBridge);

        uint256 localUserInterestRate = localToken.getUserInterestRate(user);

        // now propogate to remote fork to varify that maessage has been deliverd.
        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 20 minutes);
        uint256 remoteBalanceBefore = remoteToken.balanceOf(user);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);
        uint256 remoteBalanceAfter = remoteToken.balanceOf(user);

        assertEq(remoteBalanceAfter, remoteBalanceBefore + amountToBridge);

        uint256 remoteUserInterestRate = remoteToken.getUserInterestRate(user);
        // the user interest rate will be samebefore cross chain transferand after cross chain transfer
        assertEq(localUserInterestRate, remoteUserInterestRate);
    }

    function testBridgeAllTokens() public {
        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        assertEq(sepoliaToken.balanceOf(user), SEND_VALUE);

        bridgeToken(
            SEND_VALUE, sepoliaFork, arbSepoliaFork, sepoliaNetworkDetail, arbNetworkDetail, sepoliaToken, arbToken
        );

        // bridge token back
        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 1 hours);
        bridgeToken(
            arbToken.balanceOf(user),
            arbSepoliaFork,
            sepoliaFork,
            arbNetworkDetail,
            sepoliaNetworkDetail,
            arbToken,
            sepoliaToken
        );
    }
}
