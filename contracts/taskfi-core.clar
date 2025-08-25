;; TaskFi Escrow Contract - Manages reward deposits and releases
;; Holds funds securely until task completion or dispute resolution
(use-trait .taskfi-utils)
;; Import error codes from utils
(define-constant ERR-NOT-FOUND (contract-call? .taskfi-utils get-error-not-found))
(define-constant ERR-UNAUTHORIZED (contract-call? .taskfi-utils get-error-unauthorized))
(define-constant ERR-INVALID-INPUT (contract-call? .taskfi-utils get-error-invalid-input))
(define-constant ERR-ALREADY-EXISTS (contract-call? .taskfi-utils get-error-already-exists))
(define-constant ERR-INSUFFICIENT-FUNDS (contract-call? .taskfi-utils get-error-insufficient-funds))
;; Authorized callers (core, dispute, admin contracts)
(define-constant AUTHORIZED-CORE .taskfi-core)
(define-constant AUTHORIZED-DISPUTE .taskfi-dispute)
(define-constant AUTHORIZED-ADMIN .taskfi-admin)
;; Escrow status constants
(define-constant ESCROW-STATUS-DEPOSITED u1)
(define-constant ESCROW-STATUS-RELEASED u2)
(define-constant ESCROW-STATUS-REFUNDED u3)
;; Maximum reward amount to prevent overflow
(define-constant MAX-REWARD-AMOUNT u1000000000000) ;; 1M STX
;; Escrow records mapping task ID to escrow details
(define-map escrows uint {
depositor: principal,
amount: uint,
status: uint,
deposited-at: uint,
released-at: (optional uint),
recipient: (optional principal)
})
;; Principal balance tracking for security
(define-map depositor-balances principal uint)
(define-data-var total-escrowed uint u0)
;; Deposit reward into escrow for a specific task
;; @param depositor: Principal depositing the reward
;; @param task-id: Unique task identifier
;; @param amount: Amount to escrow in microSTX
;; @returns: Success confirmation
(define-public (deposit-reward (depositor principal) (task-id uint) (amount uint))
(begin
;; Verify caller authorization
(asserts! (or (is-eq contract-caller AUTHORIZED-CORE)
(is-eq contract-caller AUTHORIZED-ADMIN)) (err ERR-UNAUTHORIZED))
;; Validate inputs
(asserts! (> amount u0) (err ERR-INVALID-INPUT))
(asserts! (<= amount MAX-REWARD-AMOUNT) (err ERR-INVALID-INPUT))
(asserts! (is-none (map-get? escrows task-id)) (err ERR-ALREADY-EXISTS))

;; Transfer STX from depositor to this contract
(try! (stx-transfer? amount depositor (as-contract tx-sender)))

;; Create escrow record
(map-set escrows task-id {
  depositor: depositor,
  amount: amount,
  status: ESCROW-STATUS-DEPOSITED,
  deposited-at: block-height,
  released-at: none,
  recipient: none
})

;; Update depositor balance tracking
(let ((current-balance (default-to u0 (map-get? depositor-balances depositor))))
  (map-set depositor-balances depositor (+ current-balance amount)))

;; Update total escrowed amount
(var-set total-escrowed (+ (var-get total-escrowed) amount))

(ok true)))
;; Release escrowed reward to specified recipient
;; @param task-id: Task identifier for escrow
;; @param recipient: Principal to receive the funds
;; @returns: Success confirmation
(define-public (release-reward (task-id uint) (recipient principal))
(let ((escrow-data (unwrap! (map-get? escrows task-id) (err ERR-NOT-FOUND))))
;; Verify caller authorization
(asserts! (or (is-eq contract-caller AUTHORIZED-CORE)
(is-eq contract-caller AUTHORIZED-DISPUTE)) (err ERR-UNAUTHORIZED))
;; Validate escrow status
(asserts! (is-eq (get status escrow-data) ESCROW-STATUS-DEPOSITED) (err ERR-INVALID-INPUT))

;; Transfer funds from contract to recipient
(try! (as-contract (stx-transfer? (get amount escrow-data) tx-sender recipient)))

;; Update escrow record
(map-set escrows task-id (merge escrow-data {
  status: ESCROW-STATUS-RELEASED,
  released-at: (some block-height),
  recipient: (some recipient)
}))

;; Update depositor balance tracking
(let ((current-balance (default-to u0 (map-get? depositor-balances (get depositor escrow-data)))))
  (map-set depositor-balances (get depositor escrow-data)
           (if (>= current-balance (get amount escrow-data))
               (- current-balance (get amount escrow-data))
               u0)))

;; Update total escrowed amount
(let ((current-total (var-get total-escrowed)))
  (var-set total-escrowed
           (if (>= current-total (get amount escrow-data))
               (- current-total (get amount escrow-data))
               u0)))

(ok true)))
;; Refund escrowed reward back to original depositor
;; @param task-id: Task identifier for escrow
;; @param refund-to: Principal to receive refund (should be original depositor)
;; @returns: Success confirmation
(define-public (refund-reward (task-id uint) (refund-to principal))
(let ((escrow-data (unwrap! (map-get? escrows task-id) (err ERR-NOT-FOUND))))
;; Verify caller authorization
(asserts! (or (is-eq contract-caller AUTHORIZED-CORE)
(is-eq contract-caller AUTHORIZED-DISPUTE)
(is-eq contract-caller AUTHORIZED-ADMIN)) (err ERR-UNAUTHORIZED))
;; Validate escrow status and refund recipient
(asserts! (is-eq (get status escrow-data) ESCROW-STATUS-DEPOSITED) (err ERR-INVALID-INPUT))
(asserts! (is-eq refund-to (get depositor escrow-data)) (err ERR-UNAUTHORIZED))

;; Transfer funds from contract back to depositor
(try! (as-contract (stx-transfer? (get amount escrow-data) tx-sender refund-to)))

;; Update escrow record
(map-set escrows task-id (merge escrow-data {
  status: ESCROW-STATUS-REFUNDED,
  released-at: (some block-height),
  recipient: (some refund-to)
}))

;; Update depositor balance tracking
(let ((current-balance (default-to u0 (map-get? depositor-balances (get depositor escrow-data)))))
  (map-set depositor-balances (get depositor escrow-data)
           (if (>= current-balance (get amount escrow-data))
               (- current-balance (get amount escrow-data))
               u0)))

;; Update total escrowed amount
(let ((current-total (var-get total-escrowed)))
  (var-set total-escrowed
           (if (>= current-total (get amount escrow-data))
               (- current-total (get amount escrow-data))
               u0)))

(ok true)))
;; Emergency withdrawal function for admin use only
;; @param task-id: Task identifier for escrow
;; @returns: Success confirmation
(define-public (admin-emergency-withdraw (task-id uint))
(let ((escrow-data (unwrap! (map-get? escrows task-id) (err ERR-NOT-FOUND))))
;; Only admin contract can call this
(asserts! (is-eq contract-caller AUTHORIZED-ADMIN) (err ERR-UNAUTHORIZED))
;; Must be deposited status
(asserts! (is-eq (get status escrow-data) ESCROW-STATUS-DEPOSITED) (err ERR-INVALID-INPUT))

;; Refund to original depositor
(try! (refund-reward task-id (get depositor escrow-data)))

(ok true)))
;; Get escrow details for a task
;; @param task-id: Task identifier
;; @returns: Escrow data or none
(define-read-only (get-escrow (task-id uint))
(map-get? escrows task-id))
;; Get depositor's total escrowed balance
;; @param depositor: Principal to check balance for
;; @returns: Total escrowed amount
(define-read-only (get-depositor-balance (depositor principal))
(default-to u0 (map-get? depositor-balances depositor)))
;; Get total amount currently held in escrow
;; @returns: Total escrowed amount across all tasks
(define-read-only (get-total-escrowed)
(var-get total-escrowed))
;; Check if escrow exists for task
;; @param task-id: Task identifier to check
;; @returns: True if escrow exists
(define-read-only (escrow-exists (task-id uint))
(is-some (map-get? escrows task-id)))
;; Get contract's STX balance for verification
;; @returns: Contract STX balance
(define-read-only (get-contract-balance)
(stx-get-balance (as-contract tx-sender)))