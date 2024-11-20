# Proving a state transition (between Ethereum-like state trees)

Say we have a layer-2 blockchain that stores its state (user balances) as a hash tree:

```mermaid
graph TD
    root["Root Hash"]
    H12["H12"]
    H3["H3"]
    
    A["Alice<br/>PubKey: 0x1234<br/>Balance: 100"]
    B["Bob<br/>PubKey: 0x5678<br/>Balance: 50"]
    C["Charlie<br/>PubKey: 0x9ABC<br/>Balance: 20"]
    
    root --- H12
    root --- H3
    H12 --- A
    H12 --- B
    H3 --- C
```

Then we have a state transition function: 
- we apply transactions
- we get a different output tree (of balances)

```mermaid
graph TD
    subgraph "Final State Tree"
        root["Root Hash"]
        H12["H12"]
        H3["H3"]
        
        A["Alice<br/>PubKey: 0x1234<br/>Balance: 100"]
        B["Bob<br/>PubKey: 0x5678<br/>Balance: 30"]
        C["Charlie<br/>PubKey: 0x9ABC<br/>Balance: 20"]
        
        root --- H12
        root --- H3
        H12 --- A
        H12 --- B
        H3 --- C
    end

    subgraph "Transactions"
        TX1["From: Alice<br/>To: Bob<br/>Amount: 50"]
        TX2["From: Bob<br/>To: Charlie<br/>Amount: 20"]
    end

    subgraph "Initial State Tree"
        root1["Initial Root Hash"]
        A1["Alice<br/>PubKey: 0x1234<br/>Balance: 100"]
        
        root1 --- A1
    end
```





## What are we proving ?

We want to generate a proof that the state transition function was applied correctly:
- For each transaction
    - Sender had enough balance to send
    - Sender's signature is valid
- When updating balances with the input transactions, I get the expected new state root hash

## What are the inputs to the proof ?

Public inputs:
- initial tree
- transactions applied to it
- expected output root hash

Private inputs: None (yet, see section [To improve](#to-improve))


## Packages
- `mk_static_inputs`: Rust code to generate data that can't be computed in Noir
    (for instance, transaction signatures)
- `state_transition`: Noir code that proves the state transition

## Developer quickstart

Setup using `nix develop` (needs Nix) or `direnv allow` (needs Nix and nix-direnv), then:
- Run Rust tests (generates and prints signature bytes): `utest`
- Run Noir tests (proves state transition): `nr`


## To improve

- pass init_state_tree as private input, pass only init_state_root as public input
- organize transactions as tree, pass root as public input, pass transactions as private input