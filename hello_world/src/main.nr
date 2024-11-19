use std::collections::map::HashMap;
use std::hash::BuildHasherDefault;
use std::hash::poseidon2::Poseidon2Hasher;
use std::hash::Hash;
use std::hash::keccak256;

fn main(prev_state:StateTree,transactions: BoundedVec<Transaction,8>, next_state_root:K256Hash) {
    // assert(x != y);
    // TODO assert transactions are valid in order
    // TODO apply transactions
    // TODO recompute root, assert equal
}


global MAX_ACCOUNTS = 4;
pub struct StateTree {
    // map makes it easier to update a specific leaf
    leaves: HashMap<Pubkey, u8, 4, BuildHasherDefault<Poseidon2Hasher>>,
    // layers of hashes above leaves, to make balances verifiable
    hash_tree: BoundedVec<BoundedVec<K256Hash,2>,2>,
}
impl StateTree {
    pub fn genesis() -> Self {
        StateTree {
            leaves: {let mut map = HashMap::default(); map.insert(ALICE,100); map},
            hash_tree: BoundedVec::new(),
        }.with_update_hashes()
    }
    // pub fn from_balances(balances: [AccountBalance]) -> Self {
    //             StateTree {
    //         leaves: leaves
    //             .iter()
    //             .map(|ab| (ab.address.clone(), ab.balance))
    //             .collect::<BTreeMap<_, _>>(),
    //         hash_tree: Vec::new(),
    //     }
    //     .with_update_hashes()
    // }
    
    pub fn update_hashes(&mut self) {
        // we have 2 hash layers max for a 4-wide tree
        let mut layer_1: BoundedVec<K256Hash,2>  = BoundedVec::new();
        for index in 0..MAX_ACCOUNTS/2 {
            // take 2 if there are still 2
            if index*2+1 < self.account_balances().len() {
                let first = self.account_balances().get(index*2);
                let second = self.account_balances().get(index*2+1);
                // println(first);
                // println(second);
                let to_hash = first.bytes_to_hash().as_slice().append(second.bytes_to_hash().as_slice());
                let hash = K256Hash::hash::<18>(to_hash.as_array());
                layer_1.push(hash);
            } 
            // else take only 1 if there is only 1 left
            else if index*2 < self.account_balances().len() {
                let first = self.account_balances().get(index*2);
                // println(first);
                let to_hash = first.bytes_to_hash().as_slice();
                let hash = K256Hash::hash::<34>(to_hash.as_array());
                layer_1.push(hash);
            }   
        }
        if self.hash_tree.len() < 1 {
            self.hash_tree.push(layer_1);
        } else {
            self.hash_tree.set(0, layer_1);
        }

        let mut layer_2:BoundedVec<K256Hash,2> = BoundedVec::new();
        for i in 0..MAX_ACCOUNTS/4 {
            // take 2 if there are still 2
            if i*2+1 < self.account_balances().len() {
                let first = self.account_balances().get(i*2);
                let second = self.account_balances().get(i*2+1);
                let to_hash = first.bytes_to_hash().as_slice().append(second.bytes_to_hash().as_slice());
                let hash = K256Hash::hash::<18>(to_hash.as_array());
                layer_2.push(hash);
            }
            // else take only 1 if there is only 1 left
            else if i*2 < self.account_balances().len() {
                let first = self.account_balances().get(i*2);
                let to_hash = first.bytes_to_hash().as_slice();
                let hash = K256Hash::hash::<34>(to_hash.as_array());
                layer_1.push(hash);
            }  
        }
        if self.hash_tree.len() < 2 {
            self.hash_tree.push(layer_2);
        } else {
            self.hash_tree.set(1, layer_2);
        }
    }
    pub fn with_update_hashes(mut self) -> StateTree {
        self.update_hashes();
        self
    }

    pub fn account_balances(self) -> BoundedVec<AccountBalance,4> {
        self.leaves.entries().map(|(pubkey,balance):(Pubkey,u8)| AccountBalance {pubkey, balance})
    }

    pub fn apply_transaction_no_update_hashes(&mut self, transaction:Transaction) {
        // TODO check transaction valid for prev state (signature, balance)
        // TODO update leaf
    }
}


pub trait Hashable<let N: u32> {
    fn bytes_to_hash(self) -> [u8; N];
}

pub struct K256Hash {
    pub hash: [u8;32],
}
impl K256Hash {
    pub fn hash<let N:u32>(bytes_to_hash: [u8;N]) -> Self {
        K256Hash {
            hash: keccak256(bytes_to_hash,N)
        }
    }
}

// #[derive(Eq,Hash)]
// pub struct Addr {
//     pub address: [u8;8]
// }
// impl Addr {
//     pub fn new(addr: str<8>) -> Self {
//         Addr {
//             address: addr.as_bytes(),
//         }
//     }
// }



// pub struct Address {
//     // address is the 20 last bytes of the keccak256 hash of the pubkey
//     pub address: [u8;20]
// }
// // impl Address {
// //     pub fn new(address:str<32>) -> Self {
// //         address
// //     }
// // }

pub struct PubKey {
    bytes: [u8; 32]
}

pub struct AccountBalance{
    pubkey: Pubkey,
    balance: u8,
}
impl Hashable<34> for AccountBalance {
    fn bytes_to_hash(self) -> [u8;34] {
        self.pubkey.bytes.as_slice().append([self.balance]).as_array()
    }
}




pub struct Transaction {
    from: Pubkey,
    to: Pubkey,
    amount: u8,
    signature: Signature,
}
impl Transaction {
    // pub fn from_bytes(from:[u8;33],to:[u8;33], amount:u8, signature:[u8;64]) -> Self {
    //     Transaction {
    //         from: Pubkey::from_bytes(from),
    //         to: Pubkey::from_bytes(to),
    //         amount,
    //         signature: Signature::from_bytes(signature),
    //     }
    // }
}

#[derive(Eq,Hash)]
pub struct Pubkey {
    bytes: [u8;33]
}
impl Pubkey {
    pub fn from_bytes(bytes: [u8;33]) -> Self {
        Pubkey{ bytes }
    }
}


pub struct Signature {
    bytes: [u8;64]
}
impl Signature {
    pub fn from_bytes(bytes: [u8;64]) -> Self {
        Signature { bytes }
    }
}

#[cfg(test)]
global ALICE: Pubkey = Pubkey::from_bytes([2, 110, 38, 105, 168, 89, 232, 235, 109, 153, 98, 75, 67, 229, 255, 234, 68, 179, 136, 155, 65, 202, 253, 84, 212, 26, 176, 77, 233, 85, 152, 237, 161]);
#[cfg(test)]
global BOB: Pubkey = Pubkey::from_bytes([3, 253, 51, 121, 70, 54, 180, 41, 165, 31, 167, 187, 11, 130, 247, 181, 17, 93, 152, 143, 122, 200, 168, 195, 218, 143, 1, 241, 244, 79, 49, 150, 127]);
#[cfg(test)]
global CHARLIE: Pubkey = Pubkey::from_bytes([2, 55, 19, 219, 4, 82, 15, 223, 177, 48, 7, 39, 48, 228, 48, 59, 27, 104, 59, 227, 181, 252, 187, 113, 254, 31, 76, 187, 136, 59, 88, 66, 124]);
#[cfg(test)]
global TRANSACTIONS: BoundedVec<Transaction, 8> = {
    let mut vec = BoundedVec::new();
    // signatures are pre-computed in Rust since we can't call arbitraty code in Noir
    vec.push(Transaction { from: ALICE, to: BOB, amount: 10, signature: Signature::from_bytes([230, 240, 213, 131, 66, 121, 220, 174, 250, 143, 166, 17, 33, 216, 117, 100, 48, 75, 148, 187, 116, 94, 65, 147, 150, 139, 215, 253, 55, 238, 74, 226, 88, 190, 76, 8, 155, 41, 227, 53, 72, 188, 157, 93, 247, 83, 42, 214, 151, 220, 204, 133, 46, 113, 175, 97, 79, 200, 121, 105, 96, 15, 237, 89]) });
    vec.push(Transaction { from: BOB, to: CHARLIE, amount: 8, signature: Signature::from_bytes([36, 45, 215, 238, 39, 246, 139, 192, 193, 41, 185, 205, 161, 60, 248, 96, 129, 223, 5, 157, 114, 69, 59, 219, 24, 91, 224, 142, 21, 108, 220, 107, 59, 170, 112, 155, 131, 144, 2, 82, 18, 205, 223, 167, 68, 51, 212, 239, 196, 90, 52, 114, 104, 182, 78, 47, 250, 246, 246, 176, 252, 237, 17, 248]) });
    vec
};
#[cfg(test)]
global NEXT_STATE_ROOT = {
    let mut prev_state = StateTree::genesis();

    let updated_state = {
        let mut state = prev_state.clone();
        for tx in TRANSACTIONS {
            state.apply_transaction(tx);
        }
        state.update_hashes();
    };

    updated_state.root 
};



#[test]
fn test_main() {
    let prev_tree = StateTree::genesis();

    main(prev_tree, TRANSACTIONS, NEXT_STATE_ROOT);

    // Uncomment to make test fail
    // main(1, 1);  
}
