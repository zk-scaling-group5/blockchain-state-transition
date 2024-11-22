use std::collections::map::HashMap;
use std::hash::BuildHasherDefault;
use std::hash::poseidon2::Poseidon2Hasher;
use std::hash::Hash;
use std::hash::keccak256;

fn main(
    // init_state:StateTree, 
    init_state_root:pub K256Hash, 
    transactions:pub BoundedVec<Transaction,8>, 
    next_state_root:pub K256Hash
) {
    let init_state = StateTree::genesis();
    // println(init_state);
    // println(init_state_root);
    // println(transactions);
    // println(next_state_root);


    let mut state = init_state;
    state.update_hashes();
    assert(state.root() == init_state_root);



    // assert transactions are valid in order, apply them
    let new_state = {
        let mut state = init_state;
        for i_tx in 0..transactions.max_len() {
            if i_tx < transactions.len() {
                let tx = transactions.get(i_tx);
                state.apply_transaction_no_update_hashes(tx);
            }
        }
        state.update_hashes();
        state
    };

    // println(new_state.account_balances());
    // println(new_state.hash_tree);

    // recompute root, assert equal to expected new root
    let new_state_root = new_state.root();
    assert(new_state_root == next_state_root);
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

    pub fn account_balances(self) -> BoundedVec<AccountBalance,4> {
        self.leaves.entries().map(|(pubkey,balance):(Pubkey,u8)| AccountBalance {pubkey, balance})
    }
    pub fn root(self) -> K256Hash {
        self.hash_tree.get(self.hash_tree.len()-1).get(0)
    }

    pub fn update_hashes(&mut self) {
        // we have 2 hash layers max for a 4-wide tree
        let mut layer_1: BoundedVec<K256Hash,2>  = BoundedVec::new();
        for index in 0..MAX_ACCOUNTS/2 {
            // take 2 if there are still 2
            if index*2+1 < self.account_balances().len() {
                let first = self.account_balances().get(index*2);
                let second = self.account_balances().get(index*2+1);
                let to_hash = first.bytes_to_hash().as_slice().append(second.bytes_to_hash().as_slice());
                // 1 AccountBalance is 34 bytes, 2 are 68
                let hash = K256Hash::hash::<68>(to_hash.as_array());
                layer_1.push(hash);
            } 
            // else take only 1 if there is only 1 left
            else if index*2 < self.account_balances().len() {
                let first = self.account_balances().get(index*2);
                let to_hash = first.bytes_to_hash().as_slice();
                // 1 AccountBalance is 34 bytes
                let hash = K256Hash::hash::<34>(to_hash.as_array());
                layer_1.push(hash);
            }   
        }
        if self.hash_tree.len() < 1 {
            self.hash_tree.push(layer_1);
        } else {
            self.hash_tree.set(0, layer_1);
        }

        // we use a 2-long vec to keep the same type as before, but we only have 1 hash to store on this layer (for a 4-wide tree)
        let mut layer_2: BoundedVec<K256Hash,2> = BoundedVec::new();
        for i in 0..MAX_ACCOUNTS/4 {
            // take 2 if there are still 2
            if i*2+1 < self.account_balances().len() {
                let first: K256Hash = layer_1.get(i*2);
                let second: K256Hash = layer_1.get(i*2+1);
                let to_hash = first.bytes_to_hash().as_slice().append(second.bytes_to_hash().as_slice());
                // 1 K256Hash is 32 bytes, 2 are 64
                let hash = K256Hash::hash::<64>(to_hash.as_array());
                layer_2.push(hash);
            }
            // else take only 1 if there is only 1 left
            else if i*2 < self.account_balances().len() {
                let first: K256Hash = layer_1.get(i*2);
                let to_hash = first.bytes_to_hash().as_slice();
                // 1 K256Hash is 32 bytes
                let hash = K256Hash::hash::<32>(to_hash.as_array());
                layer_2.push(hash);
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
    pub fn apply_transaction_no_update_hashes(&mut self, transaction:Transaction)  {
        // check transaction valid for prev state (signature, balance)
        let prev_sender_balance = self.leaves.get(transaction.from).unwrap_or(0);
        let prev_recver_balance = self.leaves.get(transaction.to).unwrap_or(0);

        let new_sender_balance = prev_sender_balance - transaction.amount;
        assert(new_sender_balance >= 0);
        // TODO verify signature
        let new_recver_balance = prev_recver_balance + transaction.amount;

        // update balances
        self.leaves.insert(transaction.from, new_sender_balance);
        self.leaves.insert(transaction.to, new_recver_balance);
    }
}


pub trait Hashable<let N: u32> {
    fn bytes_to_hash(self) -> [u8; N];
}

#[derive(Eq)]
pub struct K256Hash {
    bytes: [u8;32],
}
impl K256Hash {
    pub fn from_bytes(bytes: [u8;32]) -> Self {
        K256Hash { bytes }
    }
    pub fn hash<let N:u32>(bytes_to_hash: [u8;N]) -> Self {
        K256Hash {
            bytes: keccak256(bytes_to_hash, N)
        }
    }
}
impl Hashable<32> for K256Hash {
    fn bytes_to_hash(self) -> [u8;32] {
        self.bytes
    }
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


#[test]
fn test_main() {
    let init_state = StateTree::genesis();
    let init_root = init_state.root();

    let transactions = {
        let mut vec = BoundedVec::new();
        // signatures are pre-computed in Rust since we can't call arbitrary code in Noir
        vec.push(Transaction { from: ALICE, to: BOB, amount: 10, signature: Signature::from_bytes([230, 240, 213, 131, 66, 121, 220, 174, 250, 143, 166, 17, 33, 216, 117, 100, 48, 75, 148, 187, 116, 94, 65, 147, 150, 139, 215, 253, 55, 238, 74, 226, 88, 190, 76, 8, 155, 41, 227, 53, 72, 188, 157, 93, 247, 83, 42, 214, 151, 220, 204, 133, 46, 113, 175, 97, 79, 200, 121, 105, 96, 15, 237, 89]) });
        vec.push(Transaction { from: BOB, to: CHARLIE, amount: 8, signature: Signature::from_bytes([36, 45, 215, 238, 39, 246, 139, 192, 193, 41, 185, 205, 161, 60, 248, 96, 129, 223, 5, 157, 114, 69, 59, 219, 24, 91, 224, 142, 21, 108, 220, 107, 59, 170, 112, 155, 131, 144, 2, 82, 18, 205, 223, 167, 68, 51, 212, 239, 196, 90, 52, 114, 104, 182, 78, 47, 250, 246, 246, 176, 252, 237, 17, 248]) });
        vec
    };

    let NEXT_STATE_ROOT = K256Hash::from_bytes([25, 32, 24, 252, 22, 132, 90, 190, 254, 169, 198, 253, 144, 67, 83, 168, 37, 61, 32, 32, 68, 195, 59, 226, 44, 193, 194, 108, 115, 100, 130, 192]);

    main(
        // init_state, 
        init_root, transactions, NEXT_STATE_ROOT);
}
