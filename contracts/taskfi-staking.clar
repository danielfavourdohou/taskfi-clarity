;; TaskFi Staking Contract - Manages collateral stakes for workers and jurors
;; Handles staking, unstaking with timelock, and slashing mechanisms
(use-trait .taskfi-utils)
;; Import error codes from utils
(define-constant ERR-NOT-FOUND (contract-call? .taskfi-utils get-error-not-found))
(define-constant ERR-UNAUTHORIZED (contract-call? .taskfi-utils get-error-unauthorized))
(define-constant ERR-INVALID-INPUT (contract-call? .taskfi-utils get-error-invalid-input))
(define-constant ERR-ALREADY-EXISTS (contract-call? .taskfi-utils get-error-already-exists))
(define-constant ERR-INSUFFICIENT-FUNDS (contract-call? .taskfi-utils get-error-insufficient-funds))
(define-constant ERR-TIMELOCK-ACTIVE (contract-call? .taskfi-utils get-error-timelock-active))
;; Authorized caller contracts
(define-constant AUTHORIZED-CORE .taskfi-core)
(define-constant AUTHORIZED-DISPUTE .taskfi-dispute)
(define-constant AUTHORIZED-ADMIN .taskfi-admin)
;; Staking configuration constants
(define-constant MIN-STAKE-AMOUNT u1000000) ;; 1 STX minimum
(define-constant MAX-STAKE-AMOUNT u100000000000) ;; 100k STX maximum
(define-constant UNSTAKE-TIMELOCK-BLOCKS u2016) ;; ~2 weeks at 10min blocks
(define-constant SLASH-PERCENTAGE u50) ;; 50% slash rate (out of 100)
;; Stake status constants
(define-constant STAKE-STATUS-ACTIVE u1)
(define-constant STAKE-STATUS-UNSTAKING u2)
(define-constant STAKE-STATUS-WITHDRAWN u3)
(define-constant STAKE-STATUS-SLASHED u4)
;; Stake records for each principal
(define-map stakes principal {
amount: uint,
status: uint,
staked-at: uint,
unstake-requested-at: (optional uint),
unstake-available-at: (optional uint),
last-activity: uint
})
;; Slashing history for transparency
(define-map slash-history principal (list 10 {
amount: uint,
reason: (string-ascii 64),
block-height: uint
}))
;; Total staked amount for protocol health monitoring
(define-data-var total-staked uint u0)
(define-data-var total-slashed uint u0)
;; Active stakers list for juror selection
(define-data-var active-stakers (list 100 principal) (list))
;; Stake STX tokens for task participation
;; @param staker: Principal who is staking
;; @param amount: Amount to stake in microSTX
;; @returns: Success confirmation
(define-public (stake (staker principal) (amount uint))
(let ((existing-stake (map-get? stakes staker)))
;; Verify authorization - core contract or staker themselves
(asserts! (or (is-eq contract-caller AUTHORIZED-CORE)
(is-eq tx-sender staker)) (err ERR-UNAUTHORIZED))
;; Validate stake amount
(asserts! (>= amount MIN-STAKE-AMOUNT) (err ERR-INVALID-INPUT))
(asserts! (<= amount MAX-STAKE-AMOUNT) (err ERR-INVALID-INPUT))

;; Handle existing stake or create new one
(if (is-some existing-stake)
  ;; Add to existing stake
  (let ((current-stake (unwrap-panic existing-stake)))
    (asserts! (is-eq (get status current-stake) STAKE-STATUS-ACTIVE) (err ERR-INVALID-INPUT))

    ;; Transfer additional STX
    (try! (stx-transfer? amount staker (as-contract tx-sender)))

    ;; Update stake record
    (map-set stakes staker {
      amount: (+ (get amount current-stake) amount),
      status: STAKE-STATUS-ACTIVE,
      staked-at: (get staked-at current-stake),
      unstake-requested-at: none,
      unstake-available-at: none,
      last-activity: block-height
    }))
  ;; Create new stake
  (begin
    ;; Transfer STX to contract
    (try! (stx-transfer? amount staker (as-contract tx-sender)))

    ;; Create stake record
    (map-set stakes staker {
      amount: amount,
      status: STAKE-STATUS-ACTIVE,
      staked-at: block-height,
      unstake-requested-at: none,
      unstake-available-at: none,
      last-activity: block-height
    })

    ;; Add to active stakers list
    (let ((current-stakers (var-get active-stakers)))
      (if (< (len current-stakers) u100)
        (var-set active-stakers (unwrap! (as-max-len? (append current-stakers staker) u100) (err ERR-INVALID-INPUT)))
        (ok true)))))

;; Update total staked amount
(var-set total-staked (+ (var-get total-staked) amount))

(ok true)))
;; Request unstaking with timelock
;; @param staker: Principal requesting unstaking
;; @returns: Success confirmation
(define-public (request-unstake (staker principal))
(let ((stake-data (unwrap! (map-get? stakes staker) (err ERR-NOT-FOUND))))
;; Verify authorization
(asserts! (or (is-eq tx-sender staker)
(is-eq contract-caller AUTHORIZED-ADMIN)) (err ERR-UNAUTHORIZED))
;; Must be actively staking
(asserts! (is-eq (get status stake-data) STAKE-STATUS-ACTIVE) (err ERR-INVALID-INPUT))

;; Set unstaking timelock
(let ((available-at (+ block-height UNSTAKE-TIMELOCK-BLOCKS)))
  (map-set stakes staker (merge stake-data {
    status: STAKE-STATUS-UNSTAKING,
    unstake-requested-at: (some block-height),
    unstake-available-at: (some available-at)
  }))

  ;; Remove from active stakers list
  (let ((current-stakers (var-get active-stakers)))
    (var-set active-stakers (filter is-not-staker current-stakers)))

  (ok available-at))))
;; Helper function to filter out unstaking principal from active list
;; @param principal-check: Principal to check against tx-sender
;; @returns: True if not the unstaking principal
(define-private (is-not-staker (principal-check principal))
(not (is-eq principal-check tx-sender)))
;; Complete unstaking and withdraw funds
;; @param staker: Principal completing unstaking
;; @returns: Success confirmation
(define-public (withdraw-stake (staker principal))
(let ((stake-data (unwrap! (map-get? stakes staker