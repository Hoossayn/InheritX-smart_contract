#[starknet::contract]
pub mod InheritX {
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address};
    use crate::interfaces::IInheritX::{AssetAllocation, IInheritX, InheritancePlan};
    use crate::types::{
        ActivityRecord, ActivityType, NotificationSettings, SecuritySettings, SimpleBeneficiary,
        UserProfile, UserRole, VerificationStatus,
    };

    #[storage]
    struct Storage {
        // Contract addresses for component management
        admin: ContractAddress,
        security_contract: ContractAddress,
        plan_contract: ContractAddress,
        claim_contract: ContractAddress,
        profile_contract: ContractAddress,
        dashboard_contract: ContractAddress,
        swap_contract: ContractAddress,
        // Protocol configuration parameters
        protocol_fee: u256, // Base points (1 = 0.01%)
        min_guardians: u8, // Minimum guardians per plan
        max_guardians: u8, // Maximum guardians per plan
        min_timelock: u64, // Minimum timelock period in seconds
        max_timelock: u64, // Maximum timelock period in seconds
        is_paused: bool, // Protocol pause state
        // Protocol statistics for analytics
        total_plans: u256,
        active_plans: u256,
        claimed_plans: u256,
        total_value_locked: u256,
        total_fees_collected: u256,
        // Record user activities
        user_activities: Map<ContractAddress, Map<u256, ActivityRecord>>,
        user_activities_pointer: Map<ContractAddress, u256>,
        // Beneficiary to Recipient Mapping
        funds: Map<u256, SimpleBeneficiary>,
        plans_id: u256,
        // Dummy Mapping For transfer
        balances: Map<ContractAddress, u256>,
        deployed: bool,
        user_profiles: Map<ContractAddress, UserProfile>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        ActivityRecordEvent: ActivityRecordEvent,
    }

    #[derive(Drop, starknet::Event)]
    struct ActivityRecordEvent {
        user: ContractAddress,
        activity_id: u256,
    }
    //     #[derive(Copy, Drop, Serde)]
    //  enum VerificationStatus {
    //     Unverified,
    //     PendingVerification,
    //     Verified,
    //     Rejected,
    // }

    #[constructor]
    fn constructor(ref self: ContractState) { // Initialize contract state:
        // 1. Set admin address
        // 2. Set default protocol parameters:
        //    - protocol_fee = 50 (0.5%)
        //    - min_guardians = 1
        //    - max_guardians = 5
        //    - min_timelock = 7 days
        //    - max_timelock = 365 days
        // 3. Initialize all statistics to 0
        // 4. Set is_paused to false
        self.deployed.write(true);
        self.total_plans.write(0); // Initialize total_plans to 0
    }

    #[abi(embed_v0)]
    impl IInheritXImpl of IInheritX<ContractState> { // Contract Management Functions
        // Initialize a new claim with a claim code
        /// Initiates a claim for an inheritance plan by creating a new beneficiary entry
        /// and processing the payout.
        ///
        /// @param name - The name of the beneficiary.
        /// @param email - The email address of the beneficiary.
        /// @param beneficiary - The wallet address of the beneficiary.
        /// @param personal_message - A message associated with the inheritance.
        /// @param amount - The amount allocated for the beneficiary.
        /// @param claim_code - A unique code assigned to the claim.
        /// @param amountt - (Unused) Duplicate of `amount`, consider removing if unnecessary.
        /// @return felt252 - Returns `1` on successful claim initiation.
        fn create_claim(
            ref self: ContractState,
            name: felt252,
            email: felt252,
            beneficiary: ContractAddress,
            personal_message: felt252,
            amount: u256,
            claim_code: u256,
        ) -> u256 {
            let inheritance_id = self.plans_id.read(); // Use it before incrementing
            // Create a new beneficiary record
            let new_beneficiary = SimpleBeneficiary {
                id: inheritance_id,
                name,
                email,
                wallet_address: beneficiary,
                personal_message,
                amount,
                code: claim_code, // Ensure type compatibility
                claim_status: false,
                benefactor: get_caller_address(),
            };

            // Store the beneficiary details in the `funds` mapping
            self.funds.write(inheritance_id, new_beneficiary);

            // Increment the plan ID after storing the new entry

            self.plans_id.write(inheritance_id + 1);

            // Increment the total plans count
            let total_plans = self.total_plans.read();
            self.total_plans.write(total_plans + 1);

            // Transfer funds as part of the claim process
            self.transfer_funds(get_contract_address(), amount);

            // Return success code
            inheritance_id
        }
        /// Creates a new user profile and stores it in the contract state.
        ///
        /// @param self - Reference to the contract state.
        /// @param username - The user's chosen username.
        /// @param email - The user's email address.
        /// @param full_name - The user's full name.
        /// @param profile_image - A reference to the user's profile image.
        /// @return bool - Returns `true` if the profile is created successfully.
        fn create_profile(
            ref self: ContractState,
            username: felt252,
            email: felt252,
            full_name: felt252,
            profile_image: felt252,
        ) -> bool {
            // Create a new UserProfile with the provided values and defaults.
            // We assume `self.contract_address` returns the caller's or contract's address.
            // For connected_wallets, notification_settings, and security_settings, we assume
            // there are default constructors or values available.
            let new_profile = UserProfile {
                address: get_caller_address(),
                username: username,
                email: email,
                full_name: full_name,
                profile_image: profile_image,
                verification_status: VerificationStatus::Unverified,
                role: UserRole::User,
                notification_settings: NotificationSettings::Default,
                security_settings: SecuritySettings::Two_factor_enabled,
                created_at: get_block_timestamp(),
                last_active: get_block_timestamp(),
            };

            // Store the new profile in the contract state's user_profiles mapping.
            // Here we assume `user_profiles` is a mapping from an address to UserProfile.
            self.user_profiles.write(new_profile.address, new_profile);

            true
        }

        /// Allows a beneficiary to collect their claim.
        /// @param self - The contract state.
        /// @param inheritance_id - The ID of the inheritance claim.
        /// @param beneficiary - The wallet address of the beneficiary.
        /// @param claim_code - The unique code to verify the claim.
        /// @returns `true` if the claim is successfully collected, otherwise `false`.
        fn collect_claim(
            ref self: ContractState,
            inheritance_id: u256,
            beneficiary: ContractAddress,
            claim_code: u256,
        ) -> bool {
            // Retrieve the claim details from storage
            let mut claim = self.funds.read(inheritance_id);

            // Ensure the claim has not been collected before
            assert(!claim.claim_status, 'You have already made a claim');

            // Verify that the correct beneficiary is making the claim
            assert((claim.wallet_address == beneficiary), 'Not your claim');

            // Verify that the provided claim code matches the stored one
            assert((claim.code == claim_code), 'Invalid claim code');

            // Mark the claim as collected
            claim.claim_status = true;

            // Transfer the funds to the beneficiary
            self.transfer_funds(beneficiary, claim.amount);

            // Update the claim in storage after modifying it
            self.funds.write(inheritance_id, claim);

            // Return success status
            true
        }

        /// Records the activity of a user in the system
        /// @param self - The contract state.
        /// @param user - The user to record for.
        /// @param activity_type - the activity type (enum ActivityType).
        /// @param details - The details of the activity.
        /// @param ip_address - The ip address of where the activity is carried out from.
        /// @param device_info - The device information of where the activity is carried out from.
        /// @returns `u256` The id of the recorded activity.
        fn record_user_activity(
            ref self: ContractState,
            user: ContractAddress,
            activity_type: ActivityType,
            details: felt252,
            ip_address: felt252,
            device_info: felt252,
        ) -> u256 {
            // fetch the user activities map
            let user_activities = self.user_activities.entry(user);
            // get the user's curuser_profilesrent activity map pointer (tracking the map index)
            let current_pointer = self.user_activities_pointer.entry(user).read();
            // create a record from the given details
            let record = ActivityRecord {
                timestamp: get_block_timestamp(), activity_type, details, ip_address, device_info,
            };
            // create the next pointer
            let next_pointer = current_pointer + 1;
            // add the record to the position of the next pointer
            user_activities.entry(next_pointer).write(record);
            // Save the next pointer
            self.user_activities_pointer.entry(user).write(next_pointer);
            // Emit event
            self.emit(ActivityRecordEvent { user, activity_id: next_pointer });
            // return the id of the activity (next_pointer)
            next_pointer
        }

        /// Gets the user activity from the particular id
        /// @param self - The contract state.
        /// @param user - The user
        /// @param activity_id - the id of the activities saved in the contract storage.
        /// @returns ActivityRecord - The record of the activity.
        fn get_user_activity(
            ref self: ContractState, user: ContractAddress, activity_id: u256,
        ) -> ActivityRecord {
            self.user_activities.entry(user).entry(activity_id).read()
        }

        fn get_profile(ref self: ContractState, address: ContractAddress) -> UserProfile {
            let user = self.user_profiles.read(address);
            user
        }


        // Dummy Functions
        /// Retrieves the details of a claim using the inheritance ID.
        /// @param self - The contract state.
        /// @param inheritance_id - The ID of the inheritance claim.
        /// @returns The `SimpleBeneficiary` struct containing the claim details.
        fn retrieve_claim(ref self: ContractState, inheritance_id: u256) -> SimpleBeneficiary {
            self.funds.read(inheritance_id)
        }

        /// Retrieves a beneficiary by their wallet address.
        /// @param self - The contract state.
        /// @param beneficiary_address - The wallet address of the beneficiary to find.
        /// @returns The `SimpleBeneficiary` struct if found, or a default SimpleBeneficiary if not
        /// found.
        /// @dev This function iterates through all plans to find a beneficiary with the specified
        /// address.
        ///      If no matching beneficiary is found, it returns a default SimpleBeneficiary with
        ///      all fields zeroed.
        fn get_beneficiary_by_address(
            self: @ContractState, beneficiary_address: ContractAddress,
        ) -> SimpleBeneficiary {
            // Get the total number of plans
            let total_plans = self.plans_id.read();

            // Initialize a variable to store the found beneficiary
            let mut current_id: u256 = 0;

            // Iterate through all plans to find a matching beneficiary
            while current_id != total_plans {
                let beneficiary = self.funds.read(current_id);

                // Check if the wallet address matches
                if beneficiary.wallet_address == beneficiary_address {
                    return beneficiary;
                }

                // Move to the next plan
                current_id = current_id + 1;
            }

            // Return a default SimpleBeneficiary if no matching beneficiary is found
            let zero_address: ContractAddress = 0.try_into().unwrap();

            SimpleBeneficiary {
                id: 0,
                name: 0,
                email: 0,
                wallet_address: zero_address,
                personal_message: 0,
                amount: 0,
                code: 0,
                claim_status: false,
                benefactor: zero_address,
            }
        }

        fn transfer_funds(ref self: ContractState, beneficiary: ContractAddress, amount: u256) {
            let current_bal = self.balances.read(beneficiary);
            self.balances.write(beneficiary, current_bal + amount);
        }
        fn test_deployment(ref self: ContractState) -> bool {
            self.deployed.read()
        }

        /// Adds a media message to a specific plan.
        /// @param self - The contract state.
        /// @param plan_id - The ID of the plan.
        /// @param media_type - The type of media (e.g., 0 for image, 1 for video).
        /// @param media_content - The content of the media (e.g., IPFS hash or URL as felt252).
        #[external]
        fn add_media_message(
            ref self: ContractState, plan_id: u256, media_type: felt252, media_content: felt252,
        ) {
            // Get the current count of media messages for the plan
            let current_count = self.media_message_count.read(plan_id);

            // Create a new media message
            let new_message = MediaMessage {
                plan_id: plan_id, media_type: media_type, media_content: media_content,
            };

            // Store the new message at the next index
            self.media_messages.write((plan_id, current_count), new_message);

            // Increment the message count for the plan
            self.media_message_count.write(plan_id, current_count + 1);
        }

        fn get_activity_history(
            self: @ContractState, user: ContractAddress, start_index: u256, page_size: u256,
        ) -> Array<ActivityRecord> {
            assert(page_size > 0, 'Page size must be positive');
            let total_activity_count = self.user_activities_pointer.entry(user).read();

            let mut activity_history = ArrayTrait::new();

            let end_index = if start_index + page_size > total_activity_count {
                total_activity_count
            } else {
                start_index + page_size
            };

            // Iterate and collect activity records
            let mut current_index = start_index + 1;
            loop {
                if current_index > end_index {
                    break;
                }

                let record = self.user_activities.entry(user).entry(current_index).read();
                activity_history.append(record);

                current_index += 1;
            }

            activity_history
        }

        fn get_activity_history_length(self: @ContractState, user: ContractAddress) -> u256 {
            self.user_activities_pointer.entry(user).read()
        }

        fn get_total_plans(self: @ContractState) -> u256 {
            self.total_plans.read()
        }
    }
}
