;; Define the fungible token
(define-fungible-token wanderlust-token)

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant TOKEN_NAME "Wanderlust Token")
(define-constant TOKEN_SYMBOL "WANDER")
(define-constant TOKEN_DECIMALS u6)
(define-constant TOTAL_SUPPLY u1000000000000000) ;; 1 billion tokens with 6 decimals
(define-constant MICRO_WANDER u1000000) ;; 1 WANDER = 1,000,000 micro-WANDER

;; Error constants
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_STAKING_NOT_FOUND (err u103))
(define-constant ERR_STAKING_LOCKED (err u104))
(define-constant ERR_INVALID_DURATION (err u105))
(define-constant ERR_REWARD_POOL_EMPTY (err u106))
(define-constant ERR_NOT_AUTHORIZED_MINTER (err u107))

;; Data Variables
(define-data-var total-supply uint TOTAL_SUPPLY)
(define-data-var reward-pool uint u0)
(define-data-var total-staked uint u0)
(define-data-var staking-enabled bool true)
(define-data-var governance-threshold uint u5000000000) ;; 5000 WANDER minimum for proposals

;; Maps
(define-map token-balances principal uint)
(define-map token-allowances {spender: principal, owner: principal} uint)

;; Staking system
(define-map user-stakes principal {
    amount: uint,
    start-block: uint,
    lock-duration: uint,
    reward-multiplier: uint,
    auto-compound: bool
})

(define-map stake-tiers uint {
    min-amount: uint,
    min-duration: uint,
    reward-multiplier: uint,
    tier-name: (string-ascii 20)
})

;; Travel-specific features
(define-map travel-rewards principal {
    total-earned: uint,
    review-rewards: uint,
    discovery-rewards: uint,
    booking-rewards: uint,
    referral-rewards: uint
})

(define-map authorized-minters principal bool)
(define-map reward-categories (string-ascii 20) {
    base-reward: uint,
    multiplier-cap: uint,
    daily-limit: uint,
    requires-verification: bool
})

;; Travel activity tracking
(define-map user-travel-stats principal {
    countries-visited: uint,
    experiences-completed: uint,
    reviews-submitted: uint,
    discoveries-made: uint,
    reputation-score: uint
})

;; Initialize stake tiers
(map-set stake-tiers u1 {
    min-amount: u1000000000, ;; 1000 WANDER
    min-duration: u144, ;; ~1 day in blocks
    reward-multiplier: u110, ;; 1.1x multiplier (110%)
    tier-name: "Explorer"
})

(map-set stake-tiers u2 {
    min-amount: u5000000000, ;; 5000 WANDER  
    min-duration: u1008, ;; ~1 week in blocks
    reward-multiplier: u125, ;; 1.25x multiplier
    tier-name: "Adventurer"
})

(map-set stake-tiers u3 {
    min-amount: u25000000000, ;; 25000 WANDER
    min-duration: u4320, ;; ~1 month in blocks
    reward-multiplier: u150, ;; 1.5x multiplier
    tier-name: "Nomad"
})

(map-set stake-tiers u4 {
    min-amount: u100000000000, ;; 100000 WANDER
    min-duration: u25920, ;; ~6 months in blocks
    reward-multiplier: u200, ;; 2x multiplier
    tier-name: "Legend"
})

;; Initialize reward categories
(map-set reward-categories "review" {
    base-reward: u5000000, ;; 5 WANDER base
    multiplier-cap: u300, ;; 3x max multiplier
    daily-limit: u50000000, ;; 50 WANDER daily limit
    requires-verification: true
})

(map-set reward-categories "discovery" {
    base-reward: u25000000, ;; 25 WANDER base
    multiplier-cap: u500, ;; 5x max multiplier
    daily-limit: u200000000, ;; 200 WANDER daily limit
    requires-verification: true
})

(map-set reward-categories "booking" {
    base-reward: u2000000, ;; 2 WANDER base
    multiplier-cap: u150, ;; 1.5x max multiplier
    daily-limit: u20000000, ;; 20 WANDER daily limit
    requires-verification: false
})

(map-set reward-categories "referral" {
    base-reward: u10000000, ;; 10 WANDER base
    multiplier-cap: u200, ;; 2x max multiplier
    daily-limit: u100000000, ;; 100 WANDER daily limit
    requires-verification: false
})

;; Initialize contract owner balance
(ft-mint? wanderlust-token TOTAL_SUPPLY CONTRACT_OWNER)

;; SIP-010 Fungible Token Standard Implementation

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
    (begin
        (asserts! (is-eq tx-sender sender) ERR_UNAUTHORIZED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (try! (ft-transfer? wanderlust-token amount sender recipient))
        (print {action: "transfer", sender: sender, recipient: recipient, amount: amount, memo: memo})
        (ok true)
    )
)

(define-read-only (get-name)
    (ok TOKEN_NAME)
)

(define-read-only (get-symbol)
    (ok TOKEN_SYMBOL)
)

(define-read-only (get-decimals)
    (ok TOKEN_DECIMALS)
)

(define-read-only (get-balance (who principal))
    (ok (ft-get-balance wanderlust-token who))
)

(define-read-only (get-total-supply)
    (ok (var-get total-supply))
)

(define-read-only (get-token-uri)
    (ok (some u"https://api.wanderlust-protocol.com/token-metadata"))
)

;; Custom transfer function with travel-specific features
(define-public (transfer-with-reward-check (amount uint) (recipient principal) (memo (optional (buff 34))))
    (let (
        (sender-balance (ft-get-balance wanderlust-token tx-sender))
    )
        (asserts! (>= sender-balance amount) ERR_INSUFFICIENT_BALANCE)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        
        ;; Execute transfer
        (try! (ft-transfer? wanderlust-token amount tx-sender recipient))
        
        ;; Update travel stats if this is a reward transfer
        (if (is-some memo)
            (update-transfer-stats tx-sender recipient amount)
            true
        )
        
        (print {
            action: "transfer-with-rewards",
            sender: tx-sender,
            recipient: recipient,
            amount: amount,
            memo: memo
        })
        (ok true)
    )
)

;; Allowance system
(define-public (approve (spender principal) (amount uint))
    (begin
        (map-set token-allowances {spender: spender, owner: tx-sender} amount)
        (print {action: "approve", owner: tx-sender, spender: spender, amount: amount})
        (ok true)
    )
)

(define-public (transfer-from (amount uint) (owner principal) (recipient principal) (memo (optional (buff 34))))
    (let (
        (allowance (get-allowance owner tx-sender))
    )
        (asserts! (>= allowance amount) ERR_UNAUTHORIZED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        
        ;; Update allowance
        (map-set token-allowances 
            {spender: tx-sender, owner: owner} 
            (- allowance amount)
        )
        
        ;; Execute transfer
        (try! (ft-transfer? wanderlust-token amount owner recipient))
        
        (print {
            action: "transfer-from",
            owner: owner,
            spender: tx-sender,
            recipient: recipient,
            amount: amount
        })
        (ok true)
    )
)

(define-read-only (get-allowance (owner principal) (spender principal))
    (default-to u0 (map-get? token-allowances {spender: spender, owner: owner}))
)

;; Staking System

(define-public (stake-tokens (amount uint) (duration uint) (auto-compound bool))
    (let (
        (user-balance (ft-get-balance wanderlust-token tx-sender))
        (tier-info (get-stake-tier amount duration))
    )
        (asserts! (var-get staking-enabled) ERR_UNAUTHORIZED)
        (asserts! (>= user-balance amount) ERR_INSUFFICIENT_BALANCE)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (>= duration u144) ERR_INVALID_DURATION) ;; Minimum 1 day
        (asserts! (is-some tier-info) ERR_INVALID_AMOUNT)
        
        ;; Check if user already has an active stake
        (asserts! (is-none (map-get? user-stakes tx-sender)) ERR_STAKING_NOT_FOUND)
        
        ;; Transfer tokens to staking pool
        (try! (ft-transfer? wanderlust-token amount tx-sender (as-contract tx-sender)))
        
        ;; Record stake
        (map-set user-stakes tx-sender {
            amount: amount,
            start-block: block-height,
            lock-duration: duration,
            reward-multiplier: (get reward-multiplier (unwrap-panic tier-info)),
            auto-compound: auto-compound
        })
        
        ;; Update total staked
        (var-set total-staked (+ (var-get total-staked) amount))
        
        (print {
            action: "stake",
            user: tx-sender,
            amount: amount,
            duration: duration,
            tier: (get tier-name (unwrap-panic tier-info))
        })
        (ok true)
    )
)

(define-public (unstake-tokens)
    (let (
        (stake-info (unwrap! (map-get? user-stakes tx-sender) ERR_STAKING_NOT_FOUND))
        (stake-amount (get amount stake-info))
        (start-block (get start-block stake-info))
        (lock-duration (get lock-duration stake-info))
        (reward-multiplier (get reward-multiplier stake-info))
        (unlock-block (+ start-block lock-duration))
    )
        ;; Check if stake is unlocked
        (asserts! (>= block-height unlock-block) ERR_STAKING_LOCKED)
        
        ;; Calculate rewards
        (let (
            (staking-blocks (- block-height start-block))
            (base-reward (/ (* stake-amount staking-blocks) u100000)) ;; Base APY calculation
            (final-reward (/ (* base-reward reward-multiplier) u100))
        )
            ;; Return staked tokens
            (try! (as-contract (ft-transfer? wanderlust-token stake-amount tx-sender tx-sender)))
            
            ;; Distribute rewards if pool has sufficient funds
            (if (>= (var-get reward-pool) final-reward)
                (begin
                    (try! (as-contract (ft-transfer? wanderlust-token final-reward tx-sender tx-sender)))
                    (var-set reward-pool (- (var-get reward-pool) final-reward))
                )
                true ;; Skip reward if pool is empty
            )
            
            ;; Remove stake record
            (map-delete user-stakes tx-sender)
            
            ;; Update total staked
            (var-set total-staked (- (var-get total-staked) stake-amount))
            
            (print {
                action: "unstake",
                user: tx-sender,
                staked-amount: stake-amount,
                reward: final-reward,
                total-returned: (+ stake-amount final-reward)
            })
            (ok (+ stake-amount final-reward))
        )
    )
)

;; Travel Reward System

(define-public (mint-travel-reward (recipient principal) (category (string-ascii 20)) (multiplier uint))
    (let (
        (reward-config (unwrap! (map-get? reward-categories category) ERR_INVALID_AMOUNT))
        (base-reward (get base-reward reward-config))
        (max-multiplier (get multiplier-cap reward-config))
        (capped-multiplier (if (> multiplier max-multiplier) max-multiplier multiplier))
        (final-reward (/ (* base-reward capped-multiplier) u100))
    )
        ;; Only authorized minters can mint rewards
        (asserts! (default-to false (map-get? authorized-minters tx-sender)) ERR_NOT_AUTHORIZED_MINTER)
        
        ;; Mint tokens
        (try! (ft-mint? wanderlust-token final-reward recipient))
        (var-set total-supply (+ (var-get total-supply) final-reward))
        
        ;; Update user travel rewards
        (update-travel-rewards recipient category final-reward)
        
        (print {
            action: "travel-reward",
            recipient: recipient,
            category: category,
            amount: final-reward,
            multiplier: capped-multiplier
        })
        (ok final-reward)
    )
)

(define-public (fund-reward-pool (amount uint))
    (begin
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (try! (ft-transfer? wanderlust-token amount tx-sender (as-contract tx-sender)))
        (var-set reward-pool (+ (var-get reward-pool) amount))
        (print {action: "fund-reward-pool", funder: tx-sender, amount: amount})
        (ok true)
    )
)

;; Admin functions

(define-public (add-authorized-minter (minter principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set authorized-minters minter true)
        (print {action: "add-minter", minter: minter})
        (ok true)
    )
)

(define-public (remove-authorized-minter (minter principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-delete authorized-minters minter)
        (print {action: "remove-minter", minter: minter})
        (ok true)
    )
)

(define-public (set-staking-enabled (enabled bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set staking-enabled enabled)
        (print {action: "set-staking-enabled", enabled: enabled})
        (ok true)
    )
)

(define-public (update-governance-threshold (new-threshold uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set governance-threshold new-threshold)
        (print {action: "update-governance-threshold", threshold: new-threshold})
        (ok true)
    )
)

;; Read-only functions

(define-read-only (get-user-stake (user principal))
    (map-get? user-stakes user)
)

(define-read-only (get-stake-tier-info (tier uint))
    (map-get? stake-tiers tier)
)

(define-read-only (get-reward-category-info (category (string-ascii 20)))
    (map-get? reward-categories category)
)

(define-read-only (get-travel-rewards (user principal))
    (map-get? travel-rewards user)
)

(define-read-only (get-travel-stats (user principal))
    (map-get? user-travel-stats user)
)

(define-read-only (get-staking-info)
    {
        total-staked: (var-get total-staked),
        reward-pool: (var-get reward-pool),
        staking-enabled: (var-get staking-enabled),
        governance-threshold: (var-get governance-threshold)
    }
)

(define-read-only (is-authorized-minter (minter principal))
    (default-to false (map-get? authorized-minters minter))
)

(define-read-only (calculate-stake-rewards (user principal))
    (match (map-get? user-stakes user)
        stake-info 
        (let (
            (stake-amount (get amount stake-info))
            (start-block (get start-block stake-info))
            (reward-multiplier (get reward-multiplier stake-info))
            (staking-blocks (- block-height start-block))
            (base-reward (/ (* stake-amount staking-blocks) u100000))
            (final-reward (/ (* base-reward reward-multiplier) u100))
        )
            (ok final-reward)
        )
        (err ERR_STAKING_NOT_FOUND)
    )
)

;; Private helper functions

(define-private (get-stake-tier (amount uint) (duration uint))
    (if (and (>= amount u100000000000) (>= duration u25920))
        (some (unwrap-panic (map-get? stake-tiers u4)))
        (if (and (>= amount u25000000000) (>= duration u4320))
            (some (unwrap-panic (map-get? stake-tiers u3)))
            (if (and (>= amount u5000000000) (>= duration u1008))
                (some (unwrap-panic (map-get? stake-tiers u2)))
                (if (and (>= amount u1000000000) (>= duration u144))
                    (some (unwrap-panic (map-get? stake-tiers u1)))
                    none
                )
            )
        )
    )
)

(define-private (update-travel-rewards (user principal) (category (string-ascii 20)) (amount uint))
    (let (
        (current-rewards (default-to 
            {
                total-earned: u0,
                review-rewards: u0,
                discovery-rewards: u0,
                booking-rewards: u0,
                referral-rewards: u0
            }
            (map-get? travel-rewards user)
        ))
    )
        (map-set travel-rewards user 
            (merge current-rewards {
                total-earned: (+ (get total-earned current-rewards) amount),
                review-rewards: (if (is-eq category "review")
                    (+ (get review-rewards current-rewards) amount)
                    (get review-rewards current-rewards)
                ),
                discovery-rewards: (if (is-eq category "discovery")
                    (+ (get discovery-rewards current-rewards) amount)
                    (get discovery-rewards current-rewards)
                ),
                booking-rewards: (if (is-eq category "booking")
                    (+ (get booking-rewards current-rewards) amount)
                    (get booking-rewards current-rewards)
                ),
                referral-rewards: (if (is-eq category "referral")
                    (+ (get referral-rewards current-rewards) amount)
                    (get referral-rewards current-rewards)
                )
            })
        )
    )
)

(define-private (update-transfer-stats (sender principal) (recipient principal) (amount uint))
    ;; Update sender's outgoing transfer stats
    (let (
        (sender-stats (default-to 
            {
                countries-visited: u0,
                experiences-completed: u0,
                reviews-submitted: u0,
                discoveries-made: u0,
                reputation-score: u100
            }
            (map-get? user-travel-stats sender)
        ))
    )
        ;; Increment reputation slightly for active token usage
        (map-set user-travel-stats sender 
            (merge sender-stats {
                reputation-score: (+ (get reputation-score sender-stats) u1)
            })
        )
    )
)