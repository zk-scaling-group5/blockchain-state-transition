use k256::ecdsa::signature::Signer;
use k256::ecdsa::{Signature, SigningKey, VerifyingKey};
use rand_core::OsRng;
use sha3::Keccak256;
use std::collections::BTreeMap;

fn main() {
    println!("Hello, world!");
}

// TODO next: prove state transition function:
// given a start_state_root, input paths (to balances) and a list of transactions, and an output root, verify:
// 1. that all transactions are valid
// 2. that the root of computed state is the same as the output root

pub trait Hashable {
    fn bytes_to_hash(&self) -> Vec<u8>;
}

#[derive(Clone)]
pub struct AccountBalance {
    pub pubkey: Pubkey,
    pub balance: u8,
}
impl Hashable for AccountBalance {
    fn bytes_to_hash(&self) -> Vec<u8> {
        let mut out = self.pubkey.0.to_sec1_bytes().to_vec();
        out.extend_from_slice(&self.balance.to_le_bytes());
        out
    }
}
impl std::fmt::Debug for AccountBalance {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "AccountBalance {{ pubkey: {}, balance: {} }}",
            self.pubkey, self.balance
        )
    }
}

#[derive(Clone)]
pub struct K256Hash {
    pub bytes: [u8; 32],
}
impl K256Hash {
    pub fn from_slice(slice: &[u8]) -> Self {
        K256Hash {
            bytes: slice.try_into().expect("slice length should be 32"),
        }
    }
}
impl Hashable for K256Hash {
    fn bytes_to_hash(&self) -> Vec<u8> {
        self.bytes.to_vec()
    }
}
impl std::fmt::Display for K256Hash {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", hex::encode(&self.bytes))
    }
}
impl std::fmt::Debug for K256Hash {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:?}", &self.bytes)
    }
}

#[derive(Clone)]
pub struct StateTree {
    leaves: BTreeMap<Pubkey, u8>,  // map makes it easier to update a leaf
    hash_tree: Vec<Vec<K256Hash>>, // layers of hashes above leaves, to authenticate state
}
impl StateTree {
    fn from_balances(leaves: &[AccountBalance]) -> Self {
        StateTree {
            leaves: leaves
                .iter()
                .map(|ab| (ab.pubkey.clone(), ab.balance))
                .collect::<BTreeMap<_, _>>(),
            hash_tree: Vec::new(),
        }
        .with_update_hashes()
    }
    fn update_hashes(&mut self) {
        self.hash_tree.clear();
        let mut last_layr_len = 0;
        while last_layr_len != 1 {
            let next_layer = match self.hash_tree.last() {
                Some(lvl) => Self::hash_by_pair(lvl),
                None => Self::hash_by_pair(&self.account_balances()),
            };
            last_layr_len = next_layer.len();
            self.hash_tree.push(next_layer);
        }
    }
    fn with_update_hashes(mut self) -> Self {
        self.update_hashes();
        self
    }

    pub fn upsert_balance(&mut self, balance: AccountBalance) {
        self.leaves.insert(balance.pubkey, balance.balance);
        self.update_hashes();
    }

    pub fn apply_transaction(&mut self, tx: Transaction) -> anyhow::Result<()> {
        if self.leaves.get(&tx.from()).is_none() {
            return Err(anyhow::anyhow!("Sender not found"));
        }
        if self.leaves.get(&tx.from()).unwrap_or(&0) < &tx.amount() {
            return Err(anyhow::anyhow!("Sender balance not enough"));
        }

        self.upsert_balance(AccountBalance {
            pubkey: tx.from().clone(),
            balance: self
                .leaves
                .get(&tx.from())
                .unwrap_or(&0)
                .saturating_sub(tx.amount()),
        });
        self.upsert_balance(AccountBalance {
            pubkey: tx.to().clone(),
            balance: self
                .leaves
                .get(&tx.to())
                .unwrap_or(&0)
                .saturating_add(tx.amount()),
        });
        self.update_hashes();

        Ok(())
    }

    fn hash_by_pair<T: Hashable>(items: &[T]) -> Vec<K256Hash> {
        use sha3::Digest;
        let mut next_layer = Vec::new();
        let mut hasher = Keccak256::new();

        for pair in items.chunks(2) {
            for item in pair {
                hasher.update(item.bytes_to_hash());
            }
            let hash = K256Hash::from_slice(&hasher.finalize_reset());
            next_layer.push(hash)
        }
        next_layer
    }

    pub fn account_balances(&self) -> Vec<AccountBalance> {
        self.leaves
            .iter()
            .map(|(vk, balance)| AccountBalance {
                pubkey: vk.clone(),
                balance: *balance,
            })
            .collect()
    }
    pub fn root(&self) -> K256Hash {
        self.hash_tree.last().unwrap().first().unwrap().clone()
    }
}
impl std::fmt::Debug for StateTree {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        writeln!(f, "balances: {:?}", self.account_balances())?;
        writeln!(f, "hash tree: {:?}", self.hash_tree)
    }
}

pub struct Identity {
    pub name: String,
    pub privkey: SigningKey,
}
impl Identity {
    pub fn new_rand(name: &str) -> Self {
        let signing_key = SigningKey::random(&mut OsRng);
        let id = Identity {
            name: name.to_string(),
            privkey: signing_key,
        };
        println!("{name} privkey bytes: {:?}", id.to_bytes());
        id
    }
    fn from_privkey_bytes(name: &str, bytes: [u8; 32]) -> anyhow::Result<Self> {
        let id = Identity {
            name: name.to_string(),
            privkey: SigningKey::from_bytes(&bytes.into())?,
        };
        println!("{name} pubkey bytes: {:?}", id.pubkey().to_bytes());
        Ok(id)
    }
    pub fn to_bytes(&self) -> [u8; 32] {
        self.privkey.to_bytes().into()
    }

    pub fn pubkey(&self) -> Pubkey {
        Pubkey(VerifyingKey::from(&self.privkey))
    }
    pub fn transfer(&self, to: Pubkey, amount: u8) -> anyhow::Result<Transaction> {
        let transaction_unsigned = TransactionUnsigned {
            from: self.pubkey(),
            to,
            amount,
        };
        let tx = transaction_unsigned.sign(&self.privkey)?;
        Ok(tx)
    }
}

pub struct Transaction {
    details: TransactionUnsigned,
    signature: Signature,
}
impl Transaction {
    pub fn from(&self) -> Pubkey {
        self.details.from
    }
    pub fn to(&self) -> Pubkey {
        self.details.to
    }
    pub fn amount(&self) -> u8 {
        self.details.amount
    }
}
impl std::fmt::Debug for Transaction {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "Transaction {{
            from: {}, 
            to: {}, 
            amount: {}, 
            signature bytes: {:?} }}",
            self.from(),
            self.to(),
            self.amount(),
            self.signature.to_bytes()
        )
    }
}

pub struct TransactionUnsigned {
    from: Pubkey,
    to: Pubkey,
    amount: u8,
}
impl TransactionUnsigned {
    pub fn bytes_to_sign(&self) -> Vec<u8> {
        let mut out = self.from.0.to_sec1_bytes().to_vec();
        out.extend_from_slice(&self.to.0.to_sec1_bytes());
        out.extend_from_slice(&self.amount.to_le_bytes());
        out
    }
    pub fn sign(self, signkey: &SigningKey) -> anyhow::Result<Transaction> {
        let signature: Signature = signkey.sign(&self.bytes_to_sign());
        Ok(Transaction {
            details: self,
            signature,
        })
    }
}
impl std::fmt::Debug for TransactionUnsigned {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "TransactionUnsigned {{ from: {}, to: {}, amount: {} }}",
            self.from, self.to, self.amount
        )
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct Pubkey(pub VerifyingKey);
impl Pubkey {
    pub fn to_bytes(&self) -> [u8; 33] {
        let bytes = self.0.to_sec1_bytes().to_vec();
        bytes.try_into().unwrap()
    }
    pub fn from_bytes(bytes: [u8; 33]) -> anyhow::Result<Self> {
        Ok(Pubkey(VerifyingKey::from_sec1_bytes(&bytes)?))
    }
}
impl std::fmt::Display for Pubkey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Pubkey({})", hex::encode(&self.0.to_sec1_bytes()))
    }
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use std::sync::LazyLock;

    #[rustfmt::skip]
    static ALICE: LazyLock<Identity> = LazyLock::new(|| Identity::from_privkey_bytes("Alice",[253, 93, 226, 251, 110, 155, 129, 83, 118, 134, 204, 253, 193, 55, 66, 47, 30, 210, 106, 14, 101, 207, 115, 212, 251, 232, 220, 183, 93, 160, 255, 182]).unwrap());
    #[rustfmt::skip]
    static BOB: LazyLock<Identity> = LazyLock::new(|| Identity::from_privkey_bytes("Bob",[100, 220, 167, 38, 201, 62, 188, 60, 93, 120, 195, 169, 103, 28, 112, 216, 130, 67, 23, 240, 90, 141, 42, 242, 248, 207, 142, 55, 251, 154, 199, 225]).unwrap());
    #[rustfmt::skip]
    static CHARLIE: LazyLock<Identity> = LazyLock::new(|| Identity::from_privkey_bytes("Charlie",[42, 71, 172, 133, 124, 211, 240, 224, 82, 105, 227, 203, 232, 21, 252, 58, 253, 28, 159, 212, 41, 230, 36, 186, 20, 191, 57, 80, 182, 148, 235, 254]).unwrap());

    #[test]
    fn it_works() -> anyhow::Result<()> {
        let alice = AccountBalance {
            pubkey: ALICE.pubkey(),
            balance: 100,
        };
        let mut state = StateTree::from_balances(&[alice]);
        dbg!("INIT STATE", &state.root());

        let transactions = vec![
            ALICE.transfer(BOB.pubkey(), 10)?,
            BOB.transfer(CHARLIE.pubkey(), 8)?,
        ];
        for tx in transactions {
            state.apply_transaction(tx)?;
        }
        dbg!("NEW STATE", &state.root());

        assert_eq!(state.leaves.len(), 3);
        assert_eq!(state.leaves.get(&ALICE.pubkey()), Some(&90));
        assert_eq!(state.leaves.get(&BOB.pubkey()), Some(&2));
        assert_eq!(state.leaves.get(&CHARLIE.pubkey()), Some(&8));

        Ok(())
    }
}
