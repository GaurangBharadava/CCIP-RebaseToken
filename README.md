# Cross-chain Rebase token.

1. A protocol that allows user to deposite into a vault and get rebase token in return, that represent the underlaying balance.
2. Rebase token -> balanceOf function is dynamic to show tha increasing balance with time
    - Balance increase linearly with time.
    - mint tokens to our users every time when they perform any actions (minting, burnig, transfering, or bridging).
3. Interest rate.
    - individually set the interest rate for the each user at a time of deposit based on some globel interest rate at the time.
    - This globel interest can only decrease to reward eraly adopters.
    - Increase token adoption