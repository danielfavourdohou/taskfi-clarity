;; TaskFi Staking Contract - Manages collateral stakes for workers and jurors
;; Handles staking, unstaking with timelock, and slashing mechanisms

;; Error codes
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-INVALID-INPUT (err u400))
(define-constant ERR-ALREADY-EXISTS (err u409))
(define-constant ERR-INSUFFICIENT-FUNDS (err u410))
(define-constant ERR-TIMELOCK-ACTIVE (err u411))
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
(define-map stakes
    principal
    {
        amount: uint,
        status: uint,
        staked-at: uint,
        unstake-requested-at: (optional uint),
        unstake-available-at: (optional uint),
        last-activity: uint,
    }
)
;; Slashing history for transparency
(define-map slash-history
    principal
    (list
        10
        {
            amount: uint,
            reason: (string-ascii 64),
            block-height: uint,
        }
    )
)
;; Total staked amount for protocol health monitoring
(define-data-var total-staked uint u0)
(define-data-var total-slashed uint u0)
;; Active stakers list for juror selection
(define-data-var active-stakers (list 100 principal) (list))
;; Stake STX tokens for task participation
;; @param staker: Principal who is staking
;; @param amount: Amount to stake in microSTX
;; @returns: Success confirmation
(define-public (stake
        (staker principal)
        (amount uint)
    )
    (if (and
            ;; Verify authorization - core contract or staker themselves
            (or
                (is-eq contract-caller AUTHORIZED-CORE)
                (is-eq tx-sender staker)
            )
            ;; Validate stake amount
            (>= amount MIN-STAKE-AMOUNT)
            (<= amount MAX-STAKE-AMOUNT)
        )
        ;; Handle existing stake or create new one
        (let ((existing-stake (map-get? stakes staker)))
            (if (is-some existing-stake)
                ;; Add to existing stake
                (let ((current-stake (unwrap-panic existing-stake)))
                    (begin
                        (asserts!
                            (is-eq (get status current-stake) STAKE-STATUS-ACTIVE)
                            ERR-INVALID-INPUT
                        )

                        ;; Transfer additional STX
                        (try! (stx-transfer? amount staker (as-contract tx-sender)))

                        ;; Update stake record
                        (map-set stakes staker {
                            amount: (+ (get amount current-stake) amount),
                            status: STAKE-STATUS-ACTIVE,
                            staked-at: (get staked-at current-stake),
                            unstake-requested-at: none,
                            unstake-available-at: none,
                            last-activity: stacks-block-height,
                        })

                        ;; Update total staked amount
                        (var-set total-staked (+ (var-get total-staked) amount))

                        (ok true)
                    )
                )
                ;; Create new stake
                (begin
                    ;; Transfer STX to contract
                    (try! (stx-transfer? amount staker (as-contract tx-sender)))

                    ;; Create stake record
                    (map-set stakes staker {
                        amount: amount,
                        status: STAKE-STATUS-ACTIVE,
                        staked-at: stacks-block-height,
                        unstake-requested-at: none,
                        unstake-available-at: none,
                        last-activity: stacks-block-height,
                    })

                    ;; Add to active stakers list
                    (let ((current-stakers (var-get active-stakers)))
                        (if (< (len current-stakers) u100)
                            (begin
                                (var-set active-stakers
                                    (unwrap!
                                        (as-max-len?
                                            (append current-stakers staker)
                                            u100
                                        )
                                        ERR-INVALID-INPUT
                                    ))
                                ;; Update total staked amount
                                (var-set total-staked
                                    (+ (var-get total-staked) amount)
                                )
                                (ok true)
                            )
                            (begin
                                ;; Update total staked amount
                                (var-set total-staked
                                    (+ (var-get total-staked) amount)
                                )
                                (ok true)
                            )
                        )
                    )
                )
            )
        )
        ;; Return error if validation fails
        ERR-INVALID-INPUT
    )
)
;; Request unstaking with timelock
;; @param staker: Principal requesting unstaking
;; @returns: Success confirmation
(define-public (request-unstake (staker principal))
    (let ((stake-data (unwrap! (map-get? stakes staker) (err ERR-NOT-FOUND))))
        ;; Verify authorization
        (asserts!
            (or
                (is-eq tx-sender staker)
                (is-eq contract-caller AUTHORIZED-ADMIN)
            )
            (err ERR-UNAUTHORIZED)
        )
        ;; Must be actively staking
        (asserts! (is-eq (get status stake-data) STAKE-STATUS-ACTIVE)
            (err ERR-INVALID-INPUT)
        )

        ;; Set unstaking timelock
        (let ((available-at (+ stacks-block-height UNSTAKE-TIMELOCK-BLOCKS)))
            (map-set stakes staker
                (merge stake-data {
                    status: STAKE-STATUS-UNSTAKING,
                    unstake-requested-at: (some stacks-block-height),
                    unstake-available-at: (some available-at),
                })
            )

            ;; Remove from active stakers list
            (let ((current-stakers (var-get active-stakers)))
                (var-set active-stakers (filter is-not-staker current-stakers))
            )

            (ok available-at)
        )
    )
)
;; Helper function to filter out unstaking principal from active list
;; @param principal-check: Principal to check against tx-sender
;; @returns: True if not the unstaking principal
(define-private (is-not-staker (principal-check principal))
    (not (is-eq principal-check tx-sender))
)
;; Complete unstaking and withdraw funds
;; @param staker: Principal completing unstaking
;; @returns: Success confirmation
(define-public (withdraw-stake (staker principal))
    (let ((stake-data (unwrap! (map-get? stakes staker) ERR-NOT-FOUND)))
        ;; Verify authorization
        (asserts!
            (or
                (is-eq tx-sender staker)
                (is-eq contract-caller AUTHORIZED-ADMIN)
            )
            ERR-UNAUTHORIZED
        )
        ;; Must be in unstaking status
        (asserts! (is-eq (get status stake-data) STAKE-STATUS-UNSTAKING)
            ERR-INVALID-INPUT
        )
        ;; Check if timelock has passed
        (let ((available-at (unwrap! (get unstake-available-at stake-data) ERR-INVALID-INPUT)))
            (asserts! (>= stacks-block-height available-at) ERR-TIMELOCK-ACTIVE)
        )

        ;; Transfer funds back to staker
        (try! (as-contract (stx-transfer? (get amount stake-data) tx-sender staker)))

        ;; Update stake record
        (map-set stakes staker
            (merge stake-data {
                status: STAKE-STATUS-WITHDRAWN,
                last-activity: stacks-block-height,
            })
        )

        ;; Update total staked amount
        (let ((current-total (var-get total-staked)))
            (var-set total-staked
                (if (>= current-total (get amount stake-data))
                    (- current-total (get amount stake-data))
                    u0
                ))
        )

        (ok true)
    )
)

;; Release stake for completed task (called by core contract)
;; @param staker: Principal whose stake to release
;; @returns: Success confirmation
(define-public (release-stake (staker principal))
    (let ((stake-data (unwrap! (map-get? stakes staker) ERR-NOT-FOUND)))
        ;; Only core contract can call this
        (asserts! (is-eq contract-caller AUTHORIZED-CORE) ERR-UNAUTHORIZED)
        ;; Must be actively staking
        (asserts! (is-eq (get status stake-data) STAKE-STATUS-ACTIVE)
            ERR-INVALID-INPUT
        )

        ;; Transfer funds back to staker
        (try! (as-contract (stx-transfer? (get amount stake-data) tx-sender staker)))

        ;; Update stake record
        (map-set stakes staker
            (merge stake-data {
                status: STAKE-STATUS-WITHDRAWN,
                last-activity: stacks-block-height,
            })
        )

        ;; Update total staked amount
        (let ((current-total (var-get total-staked)))
            (var-set total-staked
                (if (>= current-total (get amount stake-data))
                    (- current-total (get amount stake-data))
                    u0
                ))
        )

        ;; Remove from active stakers list
        (let ((current-stakers (var-get active-stakers)))
            (var-set active-stakers (filter is-not-target-staker current-stakers))
        )

        (ok true)
    )
)

;; Helper function to filter out target staker from active list
;; @param principal-check: Principal to check
;; @returns: True if not the target staker
(define-private (is-not-target-staker (principal-check principal))
    (not (is-eq principal-check tx-sender))
)

;; Slash stake for dispute resolution (called by dispute contract)
;; @param staker: Principal whose stake to slash
;; @returns: Success confirmation
(define-public (slash-stake (staker principal))
    (let ((stake-data (unwrap! (map-get? stakes staker) ERR-NOT-FOUND)))
        ;; Only dispute contract can call this
        (asserts! (is-eq contract-caller AUTHORIZED-DISPUTE) ERR-UNAUTHORIZED)
        ;; Must be actively staking
        (asserts! (is-eq (get status stake-data) STAKE-STATUS-ACTIVE)
            ERR-INVALID-INPUT
        )

        ;; Calculate slash amount
        (let (
                (slash-amount (/ (* (get amount stake-data) SLASH-PERCENTAGE) u100))
                (remaining-amount (- (get amount stake-data) slash-amount))
            )
            (begin
                ;; Transfer remaining amount back to staker
                (if (> remaining-amount u0)
                    (try! (as-contract (stx-transfer? remaining-amount tx-sender staker)))
                    true
                )

                ;; Update stake record
                (map-set stakes staker
                    (merge stake-data {
                        status: STAKE-STATUS-SLASHED,
                        amount: u0,
                        last-activity: stacks-block-height,
                    })
                )

                ;; Update slashing history
                (let ((current-history (default-to (list) (map-get? slash-history staker))))
                    (map-set slash-history staker
                        (unwrap!
                            (as-max-len?
                                (append current-history {
                                    amount: slash-amount,
                                    reason: "Task dispute resolution",
                                    block-height: stacks-block-height,
                                })
                                u10
                            )
                            ERR-INVALID-INPUT
                        ))
                )

                ;; Update totals
                (let ((current-total (var-get total-staked)))
                    (var-set total-staked
                        (if (>= current-total (get amount stake-data))
                            (- current-total (get amount stake-data))
                            u0
                        ))
                )
                (var-set total-slashed (+ (var-get total-slashed) slash-amount))

                ;; Remove from active stakers list
                (let ((current-stakers (var-get active-stakers)))
                    (var-set active-stakers
                        (filter is-not-target-staker current-stakers)
                    )
                )

                (ok true)
            )
        )
    )
)

;; Get stake details for a principal
;; @param staker: Principal to check
;; @returns: Stake data or none
(define-read-only (get-stake (staker principal))
    (map-get? stakes staker)
)

;; Get total amount staked in protocol
;; @returns: Total staked amount
(define-read-only (get-total-staked)
    (var-get total-staked)
)

;; Get total amount slashed in protocol
;; @returns: Total slashed amount
(define-read-only (get-total-slashed)
    (var-get total-slashed)
)

;; Get active stakers list
;; @returns: List of active staker principals
(define-read-only (get-active-stakers)
    (var-get active-stakers)
)

;; Get slashing history for a principal
;; @param staker: Principal to check
;; @returns: List of slash events
(define-read-only (get-slash-history (staker principal))
    (default-to (list) (map-get? slash-history staker))
)

;; Check if principal is actively staking
;; @param staker: Principal to check
;; @returns: True if actively staking
(define-read-only (is-staking (staker principal))
    (match (map-get? stakes staker)
        stake-data (is-eq (get status stake-data) STAKE-STATUS-ACTIVE)
        false
    )
)
