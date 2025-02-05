/*
    Minter module for creating collections and NFTs powered by the digital asset standard.
    TODO:
        - update unit tests
        - add mint events
*/

module composable_token::batch_mint {

    use aptos_framework::aptos_coin::{AptosCoin as APT};
    use aptos_framework::coin;
    use aptos_framework::object;

    use aptos_std::type_info;

    use aptos_token_objects::token::{Self, Token as TokenV2};

    use std::option::Option;
    use std::signer;
    use std::string::{Self, String};

    use composable_token::composable_token::{Self, Composable, Trait, Indexed };
    use composable_token::resource_manager;

    const ENOT_ADMIN: u64 = 0;
    const ETYPE_NOT_RECOGNIZED: u64 = 1;
    const EINSUFFICIENT_FUNDS: u64 = 2;
    const ESHOULD_MINT_AT_LEAST_ONE: u64 = 3;

    // Glabal storage for mint price of a token
    struct MintData has key {
        token_addr: address,
        base_mint_price: u64
    }

    public entry fun initialize(signer_ref: &signer) {
        // assert that the signer is the owner of the module
        assert!(signer::address_of(signer_ref) == @composable_token, ENOT_ADMIN);
        // init resource
        resource_manager::initialize(signer_ref);
    }

    // -------------------------
    // Creator related functions
    // -------------------------

    // mint NFTs given a metadata and a number of tokens to mint; can either mint traits or composable_token.
    // tokens will be named this ways: <name_with_index_prefix+i+name_with_index_suffix>
    public entry fun batch_create_composable_token(
        creator_signer: &signer,
        collection: String,
        number_of_tokens_to_mint: u64,
        description: String,
        name_with_index_prefix: String,
        name_with_index_suffix: String,
        uri: String,
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>
    ) {
        let escrow_addr = resource_manager::resource_address();
        assert!(number_of_tokens_to_mint > 0, ESHOULD_MINT_AT_LEAST_ONE);
        for (i in 0..number_of_tokens_to_mint) {
            // mint object
            let constructor_ref = composable_token::create_token<Composable, Indexed>(
                creator_signer,
                collection,
                description,
                string::utf8(b""),
                name_with_index_prefix,
                name_with_index_suffix,
                uri,
                royalty_numerator,
                royalty_denominator,
                property_keys,
                property_types,
                property_values
            );
            // create mint_data resource and store under the token signer
            let token_signer = object::generate_signer(&constructor_ref);
            let token_obj = object::object_from_constructor_ref<Composable>(&constructor_ref);
            let obj_addr = object::object_address<Composable>(&token_obj);
            move_to(
                &token_signer,
                MintData {
                    token_addr: obj_addr,
                    base_mint_price: 0
                }
            );
            // transfer
            composable_token::transfer_token<Composable>(creator_signer, obj_addr, escrow_addr);
            i = i + 1;
        }   
    }

    public entry fun batch_create_traits(
        creator_signer: &signer,
        collection: String,
        number_of_tokens_to_mint: u64,
        description: String,
        name_with_index_prefix: String,
        name_with_index_suffix: String,
        uri: String,
        royalty_numerator: Option<u64>,
        royalty_denominator: Option<u64>,
        property_keys: vector<String>,
        property_types: vector<String>,
        property_values: vector<vector<u8>>
    ) {
        let escrow_addr = resource_manager::resource_address();
        assert!(number_of_tokens_to_mint > 0, ESHOULD_MINT_AT_LEAST_ONE);
        for (i in 0..number_of_tokens_to_mint) {
            // mint object
            let constructor_ref = composable_token::create_token<Trait, Indexed>(
                creator_signer,
                collection,
                description,
                string::utf8(b""),
                name_with_index_prefix,
                name_with_index_suffix,
                uri,
                royalty_numerator,
                royalty_denominator,
                property_keys,
                property_types,
                property_values
            );
            let token_signer = object::generate_signer(&constructor_ref);
            let token_obj = object::object_from_constructor_ref<Trait>(&constructor_ref);
            let obj_addr = object::object_address<Trait>(&token_obj);
            move_to(
                &token_signer,
                MintData {
                    token_addr: obj_addr,
                    base_mint_price: 0
                }
            );
            // transfer
            composable_token::transfer_token<Trait>(creator_signer, obj_addr, escrow_addr);
            i = i + 1;
        }
    }

    // ------------------------
    // Minter related functions
    // ------------------------

    // Assuming an NFT is already created, this function transfers it to the minter/caller
    // the minter pays the mint price to the creator
    public entry fun mint_token<Type: key>(signer_ref: &signer, token_addr: address) acquires MintData {
        let signer_addr = signer::address_of(signer_ref);
        let creator_addr = creator_addr_from_token_addr(token_addr);
        assert!(
            type_info::type_of<Type>() == type_info::type_of<Composable>() || type_info::type_of<Type>() == type_info::type_of<Trait>(), 
            ETYPE_NOT_RECOGNIZED
        );
        // get mint price
        let mint_price = base_mint_price(token_addr);
        assert!(coin::balance<APT>(signer_addr) >= mint_price, EINSUFFICIENT_FUNDS);
        // transfer composable from resource acc to the minter
        let resource_signer = &resource_manager::resource_signer();
        composable_token::transfer_token<Type>(resource_signer, token_addr, signer_addr);
        // transfer mint price to creator
        coin::transfer<APT>(signer_ref, creator_addr, mint_price);
    }

    // ---------
    // Accessors
    // ---------

    #[view]
    // get mint price of a given token
    public fun base_mint_price(token_addr: address): u64 acquires MintData {
        borrow_global<MintData>(token_addr).base_mint_price
    }

    // ----------------
    // Helper functions
    // ----------------

    inline fun creator_addr_from_token_addr(token_addr: address): address {
        let token_obj = object::address_to_object<TokenV2>(token_addr);
        token::creator<TokenV2>(token_obj)
    }

    // ----------
    // Unit tests
    // ----------

    #[test_only]
    use aptos_std::vector;

    #[test_only]
    public fun init_test(signer_ref: &signer) {
        // assert that the signer is the owner of the module
        assert!(signer::address_of(signer_ref) == @composable_token, ENOT_ADMIN);
        // init resource
        resource_manager::initialize(signer_ref);
    }

    // #[test_only]
    // public fun create_composable_token_and_return_addresses_test(
    //     creator_signer: &signer,
    //     collection_name: String,
    //     number_of_tokens_to_mint: u64,
    //     description: String,
    //     name_with_index_prefix: String,
    //     name_with_index_suffix: String,
    //     uri: String,
    //     base_mint_price: u64,
    //     royalty_numerator: u64,
    //     royalty_denominator: u64
    // ): vector<address> {
    //     let created_composable_token = vector::empty<address>();
    //     let escrow_addr = resource_manager::resource_address();
    //     for (i in 0..number_of_tokens_to_mint) {
    //         let token_object = composable_token::create_token_internal<Composable, Indexed>(
    //             creator_signer,
    //             collection_name,
    //             description,
    //             string::utf8(b""),  // ignored since naming style is Indexed
    //             name_with_index_prefix,
    //             name_with_index_suffix,
    //             uri,
    //             royalty_numerator,
    //             royalty_denominator
    //         );

    //         let obj_addr = object::object_address<Composable>(&token_object);
    //         composable_token::transfer_token<Composable>(creator_signer, obj_addr, escrow_addr);
    //         i = i + 1;

    //         vector::push_back(&mut created_composable_token, obj_addr);
    //     };
        
    //     // return the addresses of the created composable_token
    //     created_composable_token
    // }
}