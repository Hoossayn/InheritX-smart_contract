// Import the contract modules
use inheritx::imple::InheritXClaim::InheritxClaim;
use inheritx::imple::InheritXPlan::InheritxPlan;
use inheritx::interfaces::IInheritX::{IInheritX, IInheritXDispatcher, IInheritXDispatcherTrait};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
use starknet::ContractAddress;
use starknet::class_hash::ClassHash;
use starknet::contract_address::contract_address_const;
use starknet::testing::{set_caller_address, set_contract_address};
use snforge_std::{cheat_caller_address, CheatSpan};


fn setup() -> ContractAddress {
    let declare_result = declare("InheritX");
    assert(declare_result.is_ok(), 'Contract declaration failed');

    let contract_class = declare_result.unwrap().contract_class();
    let mut calldata = array![];

    let deploy_result = contract_class.deploy(@calldata);
    assert(deploy_result.is_ok(), 'Contract deployment failed');

    let (contract_address, _) = deploy_result.unwrap();

    (contract_address)
}

#[test]
fn test_initial_data() {
    let contract_address = setup();

    let dispatcher = IInheritXDispatcher { contract_address };

    // Ensure dispatcher methods exist
    let deployed = dispatcher.test_deployment();

    assert(deployed == true, 'deployment failed');
}


#[test]
fn test_create_claim() {
    let contract_address = setup();
    let dispatcher = IInheritXDispatcher { contract_address };
    let benefactor: ContractAddress = contract_address_const::<'benefactor'>();
    let beneficiary: ContractAddress = contract_address_const::<'beneficiary'>();

    // Test input values
    let name: felt252 = 'John';
    let email: felt252 = 'John@yahoo.com';
    let personal_message = 'i love you my son';
    let claim_code = 2563;

    // Ensure the caller is the admin
    cheat_caller_address(contract_address, benefactor, CheatSpan::Indefinite);

    // Call create_claim
    let claim_id = dispatcher
        .create_claim(name, email, beneficiary, personal_message, 1000, claim_code);

    // Validate that the claim ID is correctly incremented
    assert(claim_id == 0, 'claim ID should start from 0');

    // Retrieve the claim to verify it was stored correctly
    let claim = dispatcher.retrieve_claim(claim_id);
    assert(claim.id == claim_id, 'claim ID mismatch');
    assert(claim.name == name, 'claim title mismatch');
    assert(claim.personal_message == personal_message, 'claim description mismatch');
    assert(claim.code == claim_code, 'claim price mismatch');
    assert(claim.wallet_address == beneficiary, 'cbenificiary address mismatch');
    assert(claim.email == email, 'claim email mismatch');
    assert(claim.benefactor == benefactor, 'benefactor address mismatch');
}


#[test]
fn test_collect_claim() {
    let contract_address = setup();
    let dispatcher = IInheritXDispatcher { contract_address };
    let benefactor: ContractAddress = contract_address_const::<'benefactor'>();
    let beneficiary: ContractAddress = contract_address_const::<'beneficiary'>();

    // Test input values
    let name: felt252 = 'John';
    let email: felt252 = 'John@yahoo.com';
    let personal_message = 'i love you my son';
    let claim_code = 2563;

    // Ensure the caller is the admin
    cheat_caller_address(contract_address, benefactor, CheatSpan::Indefinite);

    // Call create_claim
    let claim_id = dispatcher
        .create_claim(name, email, beneficiary, personal_message, 1000, claim_code);

    // Validate that the claim ID is correctly incremented
    assert(claim_id == 0, 'claim ID should start from 0');
    cheat_caller_address(contract_address, beneficiary, CheatSpan::Indefinite);

    let success = dispatcher.collect_claim(0, beneficiary, 2563);

    assert(success, 'Claim unsuccessful');
}

#[test]
#[should_panic(expected: 'Not your claim')]
fn test_collect_claim_with_wrong_address() {
    let contract_address = setup();
    let dispatcher = IInheritXDispatcher { contract_address };
    let benefactor: ContractAddress = contract_address_const::<'benefactor'>();
    let beneficiary: ContractAddress = contract_address_const::<'beneficiary'>();
    let malicious: ContractAddress = contract_address_const::<'malicious'>();

    // Test input values
    let name: felt252 = 'John';
    let email: felt252 = 'John@yahoo.com';
    let personal_message = 'i love you my son';
    let claim_code = 2563;

    // Ensure the caller is the admin
    cheat_caller_address(contract_address, benefactor, CheatSpan::Indefinite);

    // Call create_claim
    let claim_id = dispatcher
        .create_claim(name, email, beneficiary, personal_message, 1000, claim_code);

    // Validate that the claim ID is correctly incremented
    assert(claim_id == 0, 'claim ID should start from 0');
    cheat_caller_address(contract_address, beneficiary, CheatSpan::Indefinite);

    let success = dispatcher.collect_claim(0, malicious, 2563);

    assert(success, 'Claim unsuccessful');
}

#[test]
#[should_panic(expected: 'Invalid claim code')]
fn test_collect_claim_with_wrong_code() {
    let contract_address = setup();
    let dispatcher = IInheritXDispatcher { contract_address };
    let benefactor: ContractAddress = contract_address_const::<'benefactor'>();
    let beneficiary: ContractAddress = contract_address_const::<'beneficiary'>();
    let malicious: ContractAddress = contract_address_const::<'malicious'>();

    // Test input values
    let name: felt252 = 'John';
    let email: felt252 = 'John@yahoo.com';
    let personal_message = 'i love you my son';
    let claim_code = 2563;

    // Ensure the caller is the admin
    cheat_caller_address(contract_address, benefactor, CheatSpan::Indefinite);

    // Call create_claim
    let claim_id = dispatcher
        .create_claim(name, email, beneficiary, personal_message, 1000, claim_code);

    // Validate that the claim ID is correctly incremented
    assert(claim_id == 0, 'claim ID should start from 0');
    cheat_caller_address(contract_address, beneficiary, CheatSpan::Indefinite);

    let success = dispatcher.collect_claim(0, beneficiary, 63);

    assert(success, 'Claim unsuccessful');
}

#[test]
#[should_panic(expected: 'You have already made a claim')]
fn test_collect_claim_twice() {
    let contract_address = setup();
    let dispatcher = IInheritXDispatcher { contract_address };
    let benefactor: ContractAddress = contract_address_const::<'benefactor'>();
    let beneficiary: ContractAddress = contract_address_const::<'beneficiary'>();
    let malicious: ContractAddress = contract_address_const::<'malicious'>();

    // Test input values
    let name: felt252 = 'John';
    let email: felt252 = 'John@yahoo.com';
    let personal_message = 'i love you my son';
    let claim_code = 2563;

    // Ensure the caller is the admin
    cheat_caller_address(contract_address, benefactor, CheatSpan::Indefinite);

    // Call create_claim
    let claim_id = dispatcher
        .create_claim(name, email, beneficiary, personal_message, 1000, claim_code);

    // Validate that the claim ID is correctly incremented
    assert(claim_id == 0, 'claim ID should start from 0');
    cheat_caller_address(contract_address, beneficiary, CheatSpan::Indefinite);

    let success = dispatcher.collect_claim(0, beneficiary, 2563);

    assert(success, 'Claim unsuccessful');

    let success2 = dispatcher.collect_claim(0, beneficiary, 2563);
}
