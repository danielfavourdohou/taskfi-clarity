;; TaskFi Utils Contract - Shared constants, types, and utility functions
;; Provides common functionality used across all TaskFi contracts

;; ===== ERROR CODES =====
;; Common error codes used across all contracts
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-INVALID-INPUT (err u400))
(define-constant ERR-ALREADY-EXISTS (err u409))
(define-constant ERR-DEADLINE-PASSED (err u410))
(define-constant ERR-INSUFFICIENT-FUNDS (err u411))
(define-constant ERR-INSUFFICIENT-STAKE (err u412))
(define-constant ERR-INSUFFICIENT-REPUTATION (err u413))
(define-constant ERR-TASK-NOT-FOUND (err u414))
(define-constant ERR-TASK-COMPLETED (err u415))
(define-constant ERR-DISPUTE-ACTIVE (err u416))
(define-constant ERR-VOTING-ENDED (err u417))
(define-constant ERR-ALREADY-VOTED (err u418))
(define-constant ERR-PAUSED (err u419))
(define-constant ERR-OVERFLOW (err u420))

;; ===== PROTOCOL CONSTANTS =====
;; Task status constants
(define-constant TASK-STATUS-OPEN u1)
(define-constant TASK-STATUS-ACCEPTED u2)
(define-constant TASK-STATUS-SUBMITTED u3)
(define-constant TASK-STATUS-COMPLETED u4)
(define-constant TASK-STATUS-DISPUTED u5)
(define-constant TASK-STATUS-CANCELLED u6)

;; Stake status constants
(define-constant STAKE-STATUS-ACTIVE u1)
(define-constant STAKE-STATUS-UNSTAKING u2)
(define-constant STAKE-STATUS-SLASHED u3)
(define-constant STAKE-STATUS-WITHDRAWN u4)

;; Dispute status constants
(define-constant DISPUTE-STATUS-VOTING u1)
(define-constant DISPUTE-STATUS-RESOLVED-FOR-REQUESTER u2)
(define-constant DISPUTE-STATUS-RESOLVED-FOR-WORKER u3)
(define-constant DISPUTE-STATUS-EXPIRED u4)

;; Escrow status constants
(define-constant ESCROW-STATUS-DEPOSITED u1)
(define-constant ESCROW-STATUS-RELEASED u2)
(define-constant ESCROW-STATUS-REFUNDED u3)

;; Reputation constants
(define-constant INITIAL-REPUTATION u100)
(define-constant MAX-REPUTATION u1000)
(define-constant MIN-REPUTATION u0)

;; Protocol limits
(define-constant MAX-TASK-REWARD u100000000000) ;; 100k STX
(define-constant MIN-STAKE-AMOUNT u1000000) ;; 1 STX
(define-constant MAX-STAKE-AMOUNT u10000000000) ;; 10k STX
(define-constant MAX-TASKS-PER-USER u50)
(define-constant MAX-JURORS u10)
(define-constant MAX-VOTING-PERIOD u1440) ;; ~10 days in blocks
(define-constant MIN-VOTING-PERIOD u144) ;; ~1 day in blocks

;; Time constants (in blocks)
(define-constant BLOCKS-PER-DAY u144) ;; Approximate blocks per day
(define-constant UNSTAKE-TIMELOCK-BLOCKS u1008) ;; ~7 days
(define-constant DISPUTE-VOTING-PERIOD u432) ;; ~3 days
(define-constant REPUTATION-DECAY-PERIOD u4320) ;; ~30 days

;; Fee constants (basis points - out of 10000)
(define-constant PROTOCOL-FEE-RATE u250) ;; 2.5%
(define-constant DISPUTE-FEE-RATE u500) ;; 5%
(define-constant SLASH-PERCENTAGE u2000) ;; 20%

;; ===== UTILITY FUNCTIONS =====

;; Safe math functions to prevent overflow/underflow
(define-read-only (safe-add
        (a uint)
        (b uint)
    )
    (let ((result (+ a b)))
        (if (< result a) ;; Overflow check
            ERR-OVERFLOW
            (ok result)
        )
    )
)

(define-read-only (safe-sub
        (a uint)
        (b uint)
    )
    (if (< a b) ;; Underflow check
        ERR-OVERFLOW
        (ok (- a b))
    )
)

(define-read-only (safe-mul
        (a uint)
        (b uint)
    )
    (let ((result (* a b)))
        (if (and (> a u0) (< result (/ result a))) ;; Overflow check
            ERR-OVERFLOW
            (ok result)
        )
    )
)

;; Calculate percentage of amount (basis points)
;; @param amount: Base amount
;; @param rate: Rate in basis points (out of 10000)
;; @returns: Calculated percentage
(define-read-only (calculate-percentage
        (amount uint)
        (rate uint)
    )
    (/ (* amount rate) u10000)
)

;; Calculate protocol fee
;; @param amount: Transaction amount
;; @returns: Protocol fee amount
(define-read-only (calculate-protocol-fee (amount uint))
    (calculate-percentage amount PROTOCOL-FEE-RATE)
)

;; Calculate dispute fee
;; @param amount: Task reward amount
;; @returns: Dispute fee amount
(define-read-only (calculate-dispute-fee (amount uint))
    (calculate-percentage amount DISPUTE-FEE-RATE)
)

;; Validate task reward amount
;; @param amount: Reward amount to validate
;; @returns: True if valid, false otherwise
(define-read-only (is-valid-reward (amount uint))
    (and (> amount u0) (<= amount MAX-TASK-REWARD))
)

;; Validate stake amount
;; @param amount: Stake amount to validate
;; @returns: True if valid, false otherwise
(define-read-only (is-valid-stake (amount uint))
    (and (>= amount MIN-STAKE-AMOUNT) (<= amount MAX-STAKE-AMOUNT))
)

;; Validate deadline (must be in future)
;; @param deadline: Block height deadline
;; @returns: True if valid, false otherwise
(define-read-only (is-valid-deadline (deadline uint))
    (> deadline stacks-block-height)
)

;; Check if deadline has passed
;; @param deadline: Block height deadline
;; @returns: True if passed, false otherwise
(define-read-only (is-deadline-passed (deadline uint))
    (>= stacks-block-height deadline)
)

;; Generate pseudo-random number using block hash
;; @param seed: Additional seed value
;; @param max: Maximum value (exclusive)
;; @returns: Pseudo-random number between 0 and max-1
(define-read-only (pseudo-random
        (seed uint)
        (max uint)
    )
    (if (is-eq max u0)
        u0
        (mod (+ seed stacks-block-height) max)
    )
)

;; Convert string to buffer for IPFS CID storage
;; @param str: String to convert
;; @returns: Buffer representation
(define-read-only (string-to-buff (str (string-ascii 64)))
    (unwrap-panic (to-consensus-buff? str))
)

;; Validate IPFS CID format (basic validation)
;; @param cid: CID buffer to validate
;; @returns: True if valid format, false otherwise
(define-read-only (is-valid-ipfs-cid (cid (buff 64)))
    (and
        (> (len cid) u0)
        (<= (len cid) u64)
    )
)

;; Helper function to get minimum of two values
;; @param a: First value
;; @param b: Second value
;; @returns: Minimum value
(define-read-only (min-uint
        (a uint)
        (b uint)
    )
    (if (<= a b)
        a
        b
    )
)

;; Calculate reputation change based on task value
;; @param task-reward: Task reward amount
;; @param success: Whether task was successful
;; @returns: Reputation change amount
(define-read-only (calculate-reputation-change
        (task-reward uint)
        (success bool)
    )
    (let ((base-change (/ task-reward u1000000)))
        ;; 1 rep per 1 STX
        (if success
            (min-uint base-change u50) ;; Max +50 rep per task
            (- u0 (min-uint base-change u25)) ;; Max -25 rep per task
        )
    )
)

;; Get current block timestamp (approximate)
;; @returns: Estimated timestamp based on block height
(define-read-only (get-block-timestamp)
    ;; Approximate: Genesis + (block-height * 10 minutes)
    (+ u1598306400 (* stacks-block-height u600))
    ;; Stacks 2.0 genesis timestamp
)

;; Check if address is a contract (simplified check)
;; @param address: Principal to check
;; @returns: True if contract, false if standard principal
(define-read-only (is-contract (address principal))
    ;; Simplified: assume all contracts start with a dot
    ;; In practice, this would need more sophisticated checking
    true
    ;; Placeholder - would need contract-specific logic
)

;; Validate principal format (simplified)
;; @param address: Principal to validate
;; @returns: True if valid, false otherwise
(define-read-only (is-valid-principal (address principal))
    ;; Basic validation - principal exists
    (not (is-eq address 'SP000000000000000000002Q6VF78))
)

;; ===== STATUS HELPERS =====

;; Check if task status allows acceptance
(define-read-only (can-accept-task (status uint))
    (is-eq status TASK-STATUS-OPEN)
)

;; Check if task status allows submission
(define-read-only (can-submit-delivery (status uint))
    (is-eq status TASK-STATUS-ACCEPTED)
)

;; Check if task status allows completion
(define-read-only (can-complete-task (status uint))
    (is-eq status TASK-STATUS-SUBMITTED)
)

;; Check if task status allows dispute
(define-read-only (can-dispute-task (status uint))
    (or (is-eq status TASK-STATUS-SUBMITTED) (is-eq status TASK-STATUS-COMPLETED))
)

;; Check if stake can be slashed
(define-read-only (can-slash-stake (status uint))
    (is-eq status STAKE-STATUS-ACTIVE)
)

;; Check if stake can be unstaked
(define-read-only (can-unstake (status uint))
    (is-eq status STAKE-STATUS-ACTIVE)
)

;; ===== CONSTANTS GETTERS =====
;; Read-only functions to access constants from other contracts

(define-read-only (get-task-status-open)
    TASK-STATUS-OPEN
)
(define-read-only (get-task-status-accepted)
    TASK-STATUS-ACCEPTED
)
(define-read-only (get-task-status-submitted)
    TASK-STATUS-SUBMITTED
)
(define-read-only (get-task-status-completed)
    TASK-STATUS-COMPLETED
)
(define-read-only (get-task-status-disputed)
    TASK-STATUS-DISPUTED
)
(define-read-only (get-task-status-cancelled)
    TASK-STATUS-CANCELLED
)

(define-read-only (get-initial-reputation)
    INITIAL-REPUTATION
)
(define-read-only (get-max-reputation)
    MAX-REPUTATION
)
(define-read-only (get-min-reputation)
    MIN-REPUTATION
)

(define-read-only (get-protocol-fee-rate)
    PROTOCOL-FEE-RATE
)
(define-read-only (get-dispute-fee-rate)
    DISPUTE-FEE-RATE
)
(define-read-only (get-slash-percentage)
    SLASH-PERCENTAGE
)
