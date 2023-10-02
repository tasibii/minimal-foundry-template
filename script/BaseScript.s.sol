// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { CollisionCheck } from "./utils/CollisionCheck.sol";
import { Script, console2 } from "forge-std/Script.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

interface Proxy {
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(address newImplementation, bytes memory data) external;
}

contract BaseScript is CollisionCheck {
    bytes internal constant EMPTY_PARAMS = "";

    /**
     * * @dev Identify the admin of the transparent proxy contract.
     * * for upgradeable feature
     *
     * ! This must be overridden when deploying with a transparent proxy.
     */
    function admin() public view virtual returns (address) { }

    /**
     * * @dev Replace the contract file, including the file extension.
     *
     * ! This must be overridden when your contract name and contract file name do not match.
     */
    function contractFile() public view virtual returns (string memory) { }

    /**
     * @dev Deploy a non-proxy contract and return the deployed address.
     */
    function _deployRaw(string memory contractName, bytes memory args) internal returns (address) {
        address deployment = deployCode(_prefixName(contractName), args);

        _deploymentLogs(address(0), deployment, contractName, block.chainid);

        vm.label(deployment, contractName);
        return deployment;
    }

    /**
     * @dev Deploy a proxy contract and return the address of the deployed payable proxy.
     */
    function _deployProxyRaw(
        string memory contractName,
        bytes memory args,
        string memory kind
    )
        internal
        returns (address payable)
    {
        address payable proxy;
        address implementation = deployCode(_prefixName(contractName), EMPTY_PARAMS);

        if (_areStringsEqual(kind, "uups")) {
            proxy = payable(address(new ERC1967Proxy(implementation, args)));
        }
        if (_areStringsEqual(kind, "transparent")) {
            proxy = payable(address(new TransparentUpgradeableProxy(implementation, admin(), args)));
        }
        if (!_areStringsEqual(kind, "uups") && !_areStringsEqual(kind, "transparent")) {
            revert("Proxy type not currently supported");
        }
        _deploymentLogs(proxy, implementation, contractName, block.chainid);

        vm.label(implementation, string.concat("Logic-", contractName));
        vm.label(proxy, string.concat("Proxy-", contractName));

        return proxy;
    }

    /**
     * @dev Utilized in the event of upgrading to new logic.
     */
    function _upgradeTo(address proxy, string memory contractName, bool skip) internal {
        address sender = vm.addr(vm.envUint("PRIVATE_KEY"));
        address newImplementation = computeCreateAddress(sender, uint256(vm.getNonce(sender)));

        _deploymentLogs(proxy, newImplementation, contractName, block.chainid);
        _storageLayoutTemp(_getContractLogPath(contractName, block.chainid));

        if (skip) {
            address deployed = deployCode(_prefixName(contractName), EMPTY_PARAMS);
            if (deployed != newImplementation) revert("Wrong address.");
            Proxy(proxy).upgradeTo(newImplementation);
        } else {
            _diff();

            bool success = _checkForCollision(contractName, block.chainid);
            // show diff log:
            if (success) {
                console2.log("\n==========================", unicode"\nAuto compatibility check: ✅ Passed");
            } else {
                console2.log("\n==========================", unicode"\nAuto compatibility check: ❌ Failed");
            }

            console2.log(
                "\n==========================",
                "\nIf you sure storage slot not collision. ",
                "\nSet assign true to skip variable"
            );

            _overrideNullStorageLayout(_getContractLogPath(contractName, block.chainid));
        }

        _rmrf(_getTemporaryStoragePath(""));
    }

    /**
     * @dev Utilized in the event of upgrading to new logic, along with associated data.
     */
    function _upgradeToAndCall(address proxy, string memory contractName, bytes memory data, bool skip) internal {
        address sender = vm.addr(vm.envUint("PRIVATE_KEY"));
        address newImplementation = computeCreateAddress(sender, uint256(vm.getNonce(sender)));

        _deploymentLogs(proxy, newImplementation, contractName, block.chainid);
        _storageLayoutTemp(_getContractLogPath(contractName, block.chainid));

        if (skip) {
            address deployed = deployCode(_prefixName(contractName), EMPTY_PARAMS);
            if (deployed != newImplementation) revert("Wrong address.");
            Proxy(proxy).upgradeToAndCall(newImplementation, data);
        } else {
            _diff();

            bool success = _checkForCollision(contractName, block.chainid);
            // show diff log:
            if (success) {
                console2.log("\n==========================", unicode"\nAuto compatibility check: ✅ Passed");
            } else {
                console2.log("\n==========================", unicode"\nAuto compatibility check: ❌ Failed");
            }
            console2.log("\n==========================");
            console2.log(
                unicode"\n ❗️",
                "\nIf you sure storage slot not collision. ",
                "\nAssign the value true to the skip param.",
                "\n=========================="
            );

            _overrideNullStorageLayout(_getContractLogPath(contractName, block.chainid));
        }

        _rmrf(_getTemporaryStoragePath(""));
    }

    function _prefixName(string memory name) internal view returns (string memory) {
        if (abi.encodePacked(contractFile()).length != 0) {
            return string.concat(contractFile(), ":", name);
        }
        return string.concat(name, ".sol:", name);
    }
}
