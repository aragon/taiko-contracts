// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {AragonTest} from "./base/AragonTest.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {EncryptionRegistry} from "../src/EncryptionRegistry.sol";
import {SignerList} from "../src/SignerList.sol";
import {DaoBuilder} from "./helpers/DaoBuilder.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig} from "../src/Multisig.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract SignerListTestTemp is AragonTest {
    SignerList signerList;
    EncryptionRegistry encryptionRegistry;
    DaoBuilder builder;
    DAO dao;
    Multisig multisig;
    address[] signers;

    // Events/errors to be tested here (duplicate)
    error SignerListLengthOutOfBounds(uint16 limit, uint256 actual);
    error InvalidEncryptionRegitry(address givenAddress);

    function setUp() public {
        builder = new DaoBuilder();
        (dao, , multisig, , , signerList, encryptionRegistry, ) = builder
            .withMultisigMember(alice)
            .withMultisigMember(bob)
            .withMultisigMember(carol)
            .withMultisigMember(david)
            .build();

        signers = new address[](4);
        signers[0] = alice;
        signers[1] = bob;
        signers[2] = carol;
        signers[3] = david;
    }

    // Initialize
    function test_InitializeRevertsIfInitialized() public {
        signerList = new SignerList();
        signerList.initialize(
            dao,
            signers,
            SignerList.Settings(EncryptionRegistry(address(0)), 0)
        );

        vm.expectRevert(
            bytes("Initializable: contract is already initialized")
        );
        signerList.initialize(
            dao,
            signers,
            SignerList.Settings(EncryptionRegistry(address(0)), 0)
        );
    }

    function test_InitializeSetsTheRightValues() public {
        // 1
        signerList = new SignerList();
        signerList.initialize(
            dao,
            signers,
            SignerList.Settings(EncryptionRegistry(address(0)), 0)
        );

        (EncryptionRegistry reg, uint16 minSignerListLength) = signerList
            .settings();
        vm.assertEq(address(reg), address(0), "Incorrect address");
        vm.assertEq(minSignerListLength, 0);
        vm.assertEq(signerList.addresslistLength(), 4, "Incorrect length");
        vm.assertEq(signerList.isListed(alice), true, "Should be a signer");
        vm.assertEq(signerList.isListed(bob), true, "Should be a signer");
        vm.assertEq(signerList.isListed(carol), true, "Should be a signer");
        vm.assertEq(signerList.isListed(david), true, "Should be a signer");
        vm.assertEq(
            signerList.isListed(address(100)),
            false,
            "Should not be a signer"
        );
        vm.assertEq(
            signerList.isListed(address(200)),
            false,
            "Should not be a signer"
        );

        // 2
        signerList = new SignerList();
        signerList.initialize(
            dao,
            signers,
            SignerList.Settings(EncryptionRegistry(encryptionRegistry), 0)
        );

        (reg, minSignerListLength) = signerList.settings();
        vm.assertEq(
            address(reg),
            address(encryptionRegistry),
            "Incorrect address"
        );
        vm.assertEq(minSignerListLength, 0);
        vm.assertEq(signerList.addresslistLength(), 4, "Incorrect length");
        vm.assertEq(signerList.isListed(alice), true, "Should be a signer");
        vm.assertEq(signerList.isListed(bob), true, "Should be a signer");
        vm.assertEq(signerList.isListed(carol), true, "Should be a signer");
        vm.assertEq(signerList.isListed(david), true, "Should be a signer");
        vm.assertEq(
            signerList.isListed(address(100)),
            false,
            "Should not be a signer"
        );
        vm.assertEq(
            signerList.isListed(address(200)),
            false,
            "Should not be a signer"
        );

        // 3
        signerList = new SignerList();
        signerList.initialize(
            dao,
            signers,
            SignerList.Settings(EncryptionRegistry(encryptionRegistry), 2)
        );

        (reg, minSignerListLength) = signerList.settings();
        vm.assertEq(
            address(reg),
            address(encryptionRegistry),
            "Incorrect address"
        );
        vm.assertEq(minSignerListLength, 2);
        vm.assertEq(signerList.addresslistLength(), 4, "Incorrect length");
        vm.assertEq(signerList.isListed(alice), true, "Should be a signer");
        vm.assertEq(signerList.isListed(bob), true, "Should be a signer");
        vm.assertEq(signerList.isListed(carol), true, "Should be a signer");
        vm.assertEq(signerList.isListed(david), true, "Should be a signer");
        vm.assertEq(
            signerList.isListed(address(100)),
            false,
            "Should not be a signer"
        );
        vm.assertEq(
            signerList.isListed(address(200)),
            false,
            "Should not be a signer"
        );

        // 4
        signers = new address[](2);
        signers[0] = address(100);
        signers[0] = address(200);
        signerList = new SignerList();
        signerList.initialize(
            dao,
            signers,
            SignerList.Settings(EncryptionRegistry(encryptionRegistry), 1)
        );

        (reg, minSignerListLength) = signerList.settings();
        vm.assertEq(
            address(reg),
            address(encryptionRegistry),
            "Incorrect address"
        );
        vm.assertEq(minSignerListLength, 1);
        vm.assertEq(signerList.addresslistLength(), 2, "Incorrect length");
        vm.assertEq(
            signerList.isListed(alice),
            false,
            "Should not be a signer"
        );
        vm.assertEq(signerList.isListed(bob), false, "Should not be a signer");
        vm.assertEq(
            signerList.isListed(carol),
            false,
            "Should not be a signer"
        );
        vm.assertEq(
            signerList.isListed(david),
            false,
            "Should not be a signer"
        );
        vm.assertEq(
            signerList.isListed(address(100)),
            true,
            "Should be a signer"
        );
        vm.assertEq(
            signerList.isListed(address(200)),
            true,
            "Should be a signer"
        );
    }

    function test_InitializingWithAnInvalidRegistryShouldRevert() public {
        // 1
        signerList = new SignerList();
        signerList.initialize(
            dao,
            signers,
            SignerList.Settings(EncryptionRegistry(address(alice)), 2)
        );

        vm.expectRevert(InvalidEncryptionRegitry.selector);

        // 2
        signerList = new SignerList();
        signerList.initialize(
            dao,
            signers,
            SignerList.Settings(EncryptionRegistry(address(bob)), 3)
        );

        vm.expectRevert(InvalidEncryptionRegitry.selector);

        // OK
        signerList = new SignerList();
        signerList.initialize(
            dao,
            signers,
            SignerList.Settings(EncryptionRegistry(encryptionRegistry), 2)
        );
    }

    function test_InitializingWithTooManySignersReverts() public {
        // 1
        signers = new address[](type(uint16).max + 1);

        signerList = new SignerList();
        vm.expectRevert(
            abi.encodeWithSelector(
                SignerListLengthOutOfBounds.selector,
                type(uint16).max,
                type(uint16).max + 1
            )
        );
        signerList.initialize(
            dao,
            signers,
            SignerList.Settings(EncryptionRegistry(address(0)), 0)
        );

        // 2
        signers = new address[](type(uint16).max + 10);

        signerList = new SignerList();
        vm.expectRevert(
            abi.encodeWithSelector(
                SignerListLengthOutOfBounds.selector,
                type(uint16).max,
                type(uint16).max + 10
            )
        );
        signerList.initialize(
            dao,
            signers,
            SignerList.Settings(EncryptionRegistry(address(0)), 0)
        );
    }

    // function test_SupportsIMembership() public view {
    //         bool supported = multisig.supportsInterface(type(IMembership).interfaceId);
    //         assertEq(supported, true, "Should support IMembership");
    //     }

    function test_SupportsAddresslist() public view {
        bool supported = multisig.supportsInterface(
            type(Addresslist).interfaceId
        );
        assertEq(supported, true, "Should support Addresslist");
    }

    function test_DoesntSupportTheEmptyInterface() public view {
        bool supported = multisig.supportsInterface(0);
        assertEq(supported, false, "Should not support the empty interface");
    }

    function test_SupportsIERC165Upgradeable() public view {
        bool supported = multisig.supportsInterface(
            type(IERC165Upgradeable).interfaceId
        );
        assertEq(supported, true, "Should support IERC165Upgradeable");
    }

    function test_IsMemberShouldReturnWhenApropriate() public {
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            destinationProposalDuration: 4 days,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        address[] memory signers = new address[](1);
        signers[0] = alice;

        multisig = Multisig(
            createProxyAndCall(
                address(MULTISIG_BASE),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        assertEq(multisig.isMember(alice), true, "Should be a member");
        assertEq(multisig.isMember(bob), false, "Should not be a member");
        assertEq(multisig.isMember(carol), false, "Should not be a member");
        assertEq(multisig.isMember(david), false, "Should not be a member");

        // More members
        settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            destinationProposalDuration: 4 days,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        signers = new address[](3);
        signers[0] = bob;
        signers[1] = carol;
        signers[2] = david;

        multisig = Multisig(
            createProxyAndCall(
                address(MULTISIG_BASE),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        assertEq(multisig.isMember(alice), false, "Should not be a member");
        assertEq(multisig.isMember(bob), true, "Should be a member");
        assertEq(multisig.isMember(carol), true, "Should be a member");
        assertEq(multisig.isMember(david), true, "Should be a member");
    }

    function test_IsMemberIsListedShouldReturnTheSameValue() public {
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            destinationProposalDuration: 4 days,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        address[] memory signers = new address[](1);
        signers[0] = alice;

        multisig = Multisig(
            createProxyAndCall(
                address(MULTISIG_BASE),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        assertEq(
            multisig.isListed(alice),
            multisig.isMember(alice),
            "isMember isListed should be equal"
        );
        assertEq(
            multisig.isListed(bob),
            multisig.isMember(bob),
            "isMember isListed should be equal"
        );
        assertEq(
            multisig.isListed(carol),
            multisig.isMember(carol),
            "isMember isListed should be equal"
        );
        assertEq(
            multisig.isListed(david),
            multisig.isMember(david),
            "isMember isListed should be equal"
        );

        // More members
        settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            destinationProposalDuration: 4 days,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        signers = new address[](3);
        signers[0] = bob;
        signers[1] = carol;
        signers[2] = david;

        multisig = Multisig(
            createProxyAndCall(
                address(MULTISIG_BASE),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        assertEq(
            multisig.isListed(alice),
            multisig.isMember(alice),
            "isMember isListed should be equal"
        );
        assertEq(
            multisig.isListed(bob),
            multisig.isMember(bob),
            "isMember isListed should be equal"
        );
        assertEq(
            multisig.isListed(carol),
            multisig.isMember(carol),
            "isMember isListed should be equal"
        );
        assertEq(
            multisig.isListed(david),
            multisig.isMember(david),
            "isMember isListed should be equal"
        );
    }

    function testFuzz_IsMemberIsFalseByDefault(uint256 _randomEntropy) public {
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            destinationProposalDuration: 4 days,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        address[] memory signers = new address[](1); // 0x0... would be a member but the chance is negligible

        multisig = Multisig(
            createProxyAndCall(
                address(MULTISIG_BASE),
                abi.encodeCall(Multisig.initialize, (dao, signers, settings))
            )
        );

        assertEq(multisig.isListed(randomWallet), false, "Should be false");
        assertEq(
            multisig.isListed(
                vm.addr(uint256(keccak256(abi.encodePacked(_randomEntropy))))
            ),
            false,
            "Should be false"
        );
    }

    function test_AddsNewMembersAndEmits() public {
        dao.grant(
            address(multisig),
            alice,
            multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );

        // No
        assertEq(
            multisig.isMember(randomWallet),
            false,
            "Should not be a member"
        );

        address[] memory addrs = new address[](1);
        addrs[0] = randomWallet;

        vm.expectEmit();
        emit MembersAdded({members: addrs});
        multisig.addAddresses(addrs);

        // Yes
        assertEq(multisig.isMember(randomWallet), true, "Should be a member");

        // Next
        addrs = new address[](3);
        addrs[0] = vm.addr(1234);
        addrs[1] = vm.addr(2345);
        addrs[2] = vm.addr(3456);

        // No
        assertEq(multisig.isMember(addrs[0]), false, "Should not be a member");
        assertEq(multisig.isMember(addrs[1]), false, "Should not be a member");
        assertEq(multisig.isMember(addrs[2]), false, "Should not be a member");

        vm.expectEmit();
        emit MembersAdded({members: addrs});
        multisig.addAddresses(addrs);

        // Yes
        assertEq(multisig.isMember(addrs[0]), true, "Should be a member");
        assertEq(multisig.isMember(addrs[1]), true, "Should be a member");
        assertEq(multisig.isMember(addrs[2]), true, "Should be a member");
    }

    function test_RemovesMembersAndEmits() public {
        dao.grant(
            address(multisig),
            alice,
            multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            destinationProposalDuration: 4 days,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        multisig.updateMultisigSettings(settings);

        // Before
        assertEq(multisig.isMember(alice), true, "Should be a member");
        assertEq(multisig.isMember(bob), true, "Should be a member");
        assertEq(multisig.isMember(carol), true, "Should be a member");
        assertEq(multisig.isMember(david), true, "Should be a member");

        address[] memory addrs = new address[](2);
        addrs[0] = alice;
        addrs[1] = bob;

        vm.expectEmit();
        emit MembersRemoved({members: addrs});
        multisig.removeAddresses(addrs);

        // After
        assertEq(multisig.isMember(alice), false, "Should not be a member");
        assertEq(multisig.isMember(bob), false, "Should not be a member");
        assertEq(multisig.isMember(carol), true, "Should be a member");
        assertEq(multisig.isMember(david), true, "Should be a member");

        // Next
        addrs = new address[](3);
        addrs[0] = vm.addr(1234);
        addrs[1] = vm.addr(2345);
        addrs[2] = vm.addr(3456);
        multisig.addAddresses(addrs);

        // Remove
        addrs = new address[](2);
        addrs[0] = carol;
        addrs[1] = david;

        vm.expectEmit();
        emit MembersRemoved({members: addrs});
        multisig.removeAddresses(addrs);

        // Yes
        assertEq(multisig.isMember(carol), false, "Should not be a member");
        assertEq(multisig.isMember(david), false, "Should not be a member");
    }

    function test_RevertsIfAddingTooManyMembers() public {
        dao.grant(
            address(multisig),
            alice,
            multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );

        address[] memory addrs = new address[](type(uint16).max);
        addrs[0] = address(12345678);

        assertEq(multisig.isMember(addrs[0]), false, "Should not be a member");
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.AddresslistLengthOutOfBounds.selector,
                type(uint16).max,
                uint256(type(uint16).max) + 4
            )
        );
        multisig.addAddresses(addrs);

        assertEq(multisig.isMember(addrs[0]), false, "Should not be a member");
    }

    function test_ShouldRevertIfEmptySignersList() public {
        dao.grant(
            address(multisig),
            alice,
            multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );
        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            destinationProposalDuration: 4 days,
            proposalExpirationPeriod: MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        multisig.updateMultisigSettings(settings);

        // Before
        assertEq(multisig.isMember(alice), true, "Should be a member");
        assertEq(multisig.isMember(bob), true, "Should be a member");
        assertEq(multisig.isMember(carol), true, "Should be a member");
        assertEq(multisig.isMember(david), true, "Should be a member");

        // ok
        address[] memory addrs = new address[](1);
        addrs[0] = alice;
        multisig.removeAddresses(addrs);

        addrs[0] = bob;
        multisig.removeAddresses(addrs);

        addrs[0] = carol;
        multisig.removeAddresses(addrs);

        assertEq(multisig.isMember(alice), false, "Should not be a member");
        assertEq(multisig.isMember(bob), false, "Should not be a member");
        assertEq(multisig.isMember(carol), false, "Should not be a member");
        assertEq(multisig.isMember(david), true, "Should be a member");

        // ko
        addrs[0] = david;
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.MinApprovalsOutOfBounds.selector,
                1,
                0
            )
        );
        multisig.removeAddresses(addrs);

        // Next
        addrs = new address[](1);
        addrs[0] = vm.addr(1234);
        multisig.addAddresses(addrs);

        // Retry removing David
        addrs = new address[](1);
        addrs[0] = david;

        multisig.removeAddresses(addrs);

        // Yes
        assertEq(multisig.isMember(david), false, "Should not be a member");
    }

    function test_ShouldRevertIfLessThanMinApproval() public {
        dao.grant(
            address(multisig),
            alice,
            multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );

        // Before
        assertEq(multisig.isMember(alice), true, "Should be a member");
        assertEq(multisig.isMember(bob), true, "Should be a member");
        assertEq(multisig.isMember(carol), true, "Should be a member");
        assertEq(multisig.isMember(david), true, "Should be a member");

        // ok
        address[] memory addrs = new address[](1);
        addrs[0] = alice;
        multisig.removeAddresses(addrs);

        // ko
        addrs[0] = bob;
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.MinApprovalsOutOfBounds.selector,
                3,
                2
            )
        );
        multisig.removeAddresses(addrs);

        // ko
        addrs[0] = carol;
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.MinApprovalsOutOfBounds.selector,
                3,
                2
            )
        );
        multisig.removeAddresses(addrs);

        // ko
        addrs[0] = david;
        vm.expectRevert(
            abi.encodeWithSelector(
                Multisig.MinApprovalsOutOfBounds.selector,
                3,
                2
            )
        );
        multisig.removeAddresses(addrs);

        // Add and retry removing

        addrs = new address[](1);
        addrs[0] = vm.addr(1234);
        multisig.addAddresses(addrs);

        addrs = new address[](1);
        addrs[0] = bob;
        multisig.removeAddresses(addrs);

        // 2
        addrs = new address[](1);
        addrs[0] = vm.addr(2345);
        multisig.addAddresses(addrs);

        addrs = new address[](1);
        addrs[0] = carol;
        multisig.removeAddresses(addrs);

        // 3
        addrs = new address[](1);
        addrs[0] = vm.addr(3456);
        multisig.addAddresses(addrs);

        addrs = new address[](1);
        addrs[0] = david;
        multisig.removeAddresses(addrs);
    }

    function test_IsMemberShouldReturnWhenApropriate() public {
        assertEq(eMultisig.isMember(alice), true, "Should be a member");
        assertEq(eMultisig.isMember(bob), true, "Should be a member");
        assertEq(eMultisig.isMember(carol), true, "Should be a member");
        assertEq(eMultisig.isMember(david), true, "Should be a member");

        dao.grant(
            address(stdMultisig),
            alice,
            stdMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );
        address[] memory signers = new address[](1);
        signers[0] = bob;
        stdMultisig.removeAddresses(signers);

        assertEq(eMultisig.isMember(alice), true, "Should be a member");
        assertEq(eMultisig.isMember(bob), false, "Should not be a member");
        assertEq(eMultisig.isMember(carol), true, "Should be a member");
        assertEq(eMultisig.isMember(david), true, "Should be a member");

        // 2
        stdMultisig.addAddresses(signers); // Add Bob back
        signers[0] = alice;
        stdMultisig.removeAddresses(signers);

        assertEq(eMultisig.isMember(alice), false, "Should not be a member");
        assertEq(eMultisig.isMember(bob), true, "Should be a member");
        assertEq(eMultisig.isMember(carol), true, "Should be a member");
        assertEq(eMultisig.isMember(david), true, "Should be a member");

        // 3
        stdMultisig.addAddresses(signers); // Add Alice back
        signers[0] = carol;
        stdMultisig.removeAddresses(signers);

        assertEq(eMultisig.isMember(alice), true, "Should be a member");
        assertEq(eMultisig.isMember(bob), true, "Should be a member");
        assertEq(eMultisig.isMember(carol), false, "Should not be a member");
        assertEq(eMultisig.isMember(david), true, "Should be a member");

        // 4
        stdMultisig.addAddresses(signers); // Add Carol back
        signers[0] = david;
        stdMultisig.removeAddresses(signers);

        assertEq(eMultisig.isMember(alice), true, "Should be a member");
        assertEq(eMultisig.isMember(bob), true, "Should be a member");
        assertEq(eMultisig.isMember(carol), true, "Should be a member");
        assertEq(eMultisig.isMember(david), false, "Should not be a member");
    }

    function test_IsMemberIsListedShouldReturnTheSameValue() public {
        assertEq(
            stdMultisig.isListed(alice),
            eMultisig.isMember(alice),
            "isMember isListed should be equal"
        );
        assertEq(
            stdMultisig.isListed(bob),
            eMultisig.isMember(bob),
            "isMember isListed should be equal"
        );
        assertEq(
            stdMultisig.isListed(carol),
            eMultisig.isMember(carol),
            "isMember isListed should be equal"
        );
        assertEq(
            stdMultisig.isListed(david),
            eMultisig.isMember(david),
            "isMember isListed should be equal"
        );

        dao.grant(
            address(stdMultisig),
            alice,
            stdMultisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );
        address[] memory signers = new address[](1);
        signers[0] = alice;
        stdMultisig.removeAddresses(signers);

        assertEq(
            stdMultisig.isListed(alice),
            eMultisig.isMember(alice),
            "isMember isListed should be equal"
        );
        assertEq(
            stdMultisig.isListed(bob),
            eMultisig.isMember(bob),
            "isMember isListed should be equal"
        );
        assertEq(
            stdMultisig.isListed(carol),
            eMultisig.isMember(carol),
            "isMember isListed should be equal"
        );
        assertEq(
            stdMultisig.isListed(david),
            eMultisig.isMember(david),
            "isMember isListed should be equal"
        );

        // 2
        stdMultisig.addAddresses(signers); // Add Alice back
        signers[0] = bob;
        stdMultisig.removeAddresses(signers);

        assertEq(
            stdMultisig.isListed(alice),
            eMultisig.isMember(alice),
            "isMember isListed should be equal"
        );
        assertEq(
            stdMultisig.isListed(bob),
            eMultisig.isMember(bob),
            "isMember isListed should be equal"
        );
        assertEq(
            stdMultisig.isListed(carol),
            eMultisig.isMember(carol),
            "isMember isListed should be equal"
        );
        assertEq(
            stdMultisig.isListed(david),
            eMultisig.isMember(david),
            "isMember isListed should be equal"
        );

        // 3
        stdMultisig.addAddresses(signers); // Add Bob back
        signers[0] = carol;
        stdMultisig.removeAddresses(signers);

        assertEq(
            stdMultisig.isListed(alice),
            eMultisig.isMember(alice),
            "isMember isListed should be equal"
        );
        assertEq(
            stdMultisig.isListed(bob),
            eMultisig.isMember(bob),
            "isMember isListed should be equal"
        );
        assertEq(
            stdMultisig.isListed(carol),
            eMultisig.isMember(carol),
            "isMember isListed should be equal"
        );
        assertEq(
            stdMultisig.isListed(david),
            eMultisig.isMember(david),
            "isMember isListed should be equal"
        );

        // 4
        stdMultisig.addAddresses(signers); // Add Carol back
        signers[0] = david;
        stdMultisig.removeAddresses(signers);

        assertEq(
            stdMultisig.isListed(alice),
            eMultisig.isMember(alice),
            "isMember isListed should be equal"
        );
        assertEq(
            stdMultisig.isListed(bob),
            eMultisig.isMember(bob),
            "isMember isListed should be equal"
        );
        assertEq(
            stdMultisig.isListed(carol),
            eMultisig.isMember(carol),
            "isMember isListed should be equal"
        );
        assertEq(
            stdMultisig.isListed(david),
            eMultisig.isMember(david),
            "isMember isListed should be equal"
        );
    }

    function testFuzz_IsMemberIsFalseByDefault(uint256 _randomEntropy) public {
        // Deploy a new stdMultisig instance
        Multisig.MultisigSettings memory mSettings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1,
            destinationProposalDuration: 4 days,
            proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
        });
        address[] memory signers = new address[](1);
        signers[0] = address(0x0); // 0x0... would be a member but the chance is negligible

        stdMultisig = Multisig(
            createProxyAndCall(
                address(MULTISIG_BASE),
                abi.encodeCall(Multisig.initialize, (dao, signers, mSettings))
            )
        );
        EmergencyMultisig.MultisigSettings memory settings = EmergencyMultisig
            .MultisigSettings({
                onlyListed: true,
                minApprovals: 1,
                signerList: signerList,
                proposalExpirationPeriod: EMERGENCY_MULTISIG_PROPOSAL_EXPIRATION_PERIOD
            });
        eMultisig = EmergencyMultisig(
            createProxyAndCall(
                address(EMERGENCY_MULTISIG_BASE),
                abi.encodeCall(EmergencyMultisig.initialize, (dao, settings))
            )
        );

        assertEq(
            eMultisig.isMember(
                vm.addr(uint256(keccak256(abi.encodePacked(_randomEntropy))))
            ),
            false,
            "Should be false"
        );
    }

    function test_ShouldRevertIfDuplicatingAddresses() public {
        dao.grant(
            address(multisig),
            alice,
            multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );

        // ok
        address[] memory addrs = new address[](1);
        addrs[0] = vm.addr(1234);
        multisig.addAddresses(addrs);

        // ko
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        multisig.addAddresses(addrs);

        // 1
        addrs[0] = alice;
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        multisig.addAddresses(addrs);

        // 2
        addrs[0] = bob;
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        multisig.addAddresses(addrs);

        // 3
        addrs[0] = carol;
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        multisig.addAddresses(addrs);

        // 4
        addrs[0] = david;
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        multisig.addAddresses(addrs);

        // ok
        addrs[0] = vm.addr(1234);
        multisig.removeAddresses(addrs);

        // ko
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        multisig.removeAddresses(addrs);

        addrs[0] = vm.addr(2345);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        multisig.removeAddresses(addrs);

        addrs[0] = vm.addr(3456);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        multisig.removeAddresses(addrs);

        addrs[0] = vm.addr(4567);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        multisig.removeAddresses(addrs);

        addrs[0] = randomWallet;
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAddresslistUpdate.selector, addrs[0])
        );
        multisig.removeAddresses(addrs);
    }

    function test_onlyWalletWithPermissionsCanAddRemove() public {
        // ko
        address[] memory addrs = new address[](1);
        addrs[0] = vm.addr(1234);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(multisig),
                alice,
                multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
            )
        );
        multisig.addAddresses(addrs);

        // ko
        addrs[0] = alice;
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(multisig),
                alice,
                multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
            )
        );
        multisig.removeAddresses(addrs);

        // Permission
        dao.grant(
            address(multisig),
            alice,
            multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );

        // ok
        addrs[0] = vm.addr(1234);
        multisig.addAddresses(addrs);

        addrs[0] = alice;
        multisig.removeAddresses(addrs);
    }

    function testFuzz_PermissionedAddRemoveMembers(
        address randomAccount
    ) public {
        dao.grant(
            address(multisig),
            alice,
            multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
        );

        assertEq(multisig.isMember(randomWallet), false, "Should be false");

        // in
        address[] memory addrs = new address[](1);
        addrs[0] = randomWallet;
        multisig.addAddresses(addrs);
        assertEq(multisig.isMember(randomWallet), true, "Should be true");

        // out
        multisig.removeAddresses(addrs);
        assertEq(multisig.isMember(randomWallet), false, "Should be false");

        // someone else
        if (randomAccount != alice) {
            vm.startPrank(randomAccount);
            vm.expectRevert(
                abi.encodeWithSelector(
                    DaoUnauthorized.selector,
                    address(dao),
                    address(multisig),
                    randomAccount,
                    multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
                )
            );
            multisig.addAddresses(addrs);
            assertEq(multisig.isMember(randomWallet), false, "Should be false");

            addrs[0] = carol;
            assertEq(multisig.isMember(carol), true, "Should be true");
            vm.expectRevert(
                abi.encodeWithSelector(
                    DaoUnauthorized.selector,
                    address(dao),
                    address(multisig),
                    randomAccount,
                    multisig.UPDATE_MULTISIG_SETTINGS_PERMISSION_ID()
                )
            );
            multisig.removeAddresses(addrs);

            assertEq(multisig.isMember(carol), true, "Should be true");
        }

        vm.startPrank(alice);
    }
}
