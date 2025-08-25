;; TaskFi Dispute Contract - Handles task disputes and resolution
;; Manages dispute process with voting mechanism

;; Error codes
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-INVALID-INPUT (err u400))
(define-constant ERR-ALREADY-EXISTS (err u409))
(define-constant ERR-DISPUTE-CLOSED (err u410))
(define-constant ERR-VOTING-ENDED (err u411))

;; Authorized callers
(define-constant AUTHORIZED-CORE .taskfi-core)
(define-constant AUTHORIZED-ADMIN .taskfi-admin)

;; Dispute constants
(define-constant DISPUTE-DURATION u1008) ;; ~1 week in blocks
(define-constant MIN-JURORS u3)
(define-constant MAX-JURORS u7)
(define-constant JUROR-REWARD u100000) ;; 0.1 STX per juror

;; Dispute status constants
(define-constant DISPUTE-STATUS-OPEN u1)
(define-constant DISPUTE-STATUS-VOTING u2)
(define-constant DISPUTE-STATUS-RESOLVED u3)
(define-constant DISPUTE-STATUS-CANCELLED u4)

;; Dispute records
(define-map disputes
  uint
  {
    task-id: uint,
    requester: principal,
    worker: principal,
    status: uint,
    created-at: uint,
    voting-ends-at: uint,
    jurors: (list 7 principal),
    votes-for-worker: uint,
    votes-for-requester: uint,
    resolved-at: (optional uint),
    winner: (optional principal),
  }
)

;; Juror votes tracking
(define-map juror-votes
  {
    dispute-id: uint,
    juror: principal,
  }
  {
    vote: bool, ;; true for worker, false for requester
    voted-at: uint,
  }
)

;; Dispute counter
(define-data-var dispute-counter uint u0)

;; Open a new dispute
;; @param task-id: ID of the disputed task
;; @returns: Dispute ID
(define-public (open-dispute (task-id uint))
  (let (
      (dispute-id (+ (var-get dispute-counter) u1))
      (selected-jurors (list 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM
        'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG
        'ST2JHG361ZXG51QTKY2NQCVBPPRRE2KZB1HR05NNC))
    )
    ;; Only core contract can open disputes
    (asserts! (is-eq contract-caller AUTHORIZED-CORE) ERR-UNAUTHORIZED)

    ;; Create dispute record
    (map-set disputes dispute-id {
      task-id: task-id,
      requester: tx-sender, ;; Simplified - assume caller is requester
      worker: 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM, ;; Simplified - dummy worker
      status: DISPUTE-STATUS-VOTING,
      created-at: stacks-block-height,
      voting-ends-at: (+ stacks-block-height DISPUTE-DURATION),
      jurors: selected-jurors,
      votes-for-worker: u0,
      votes-for-requester: u0,
      resolved-at: none,
      winner: none,
    })

    ;; Increment dispute counter
    (var-set dispute-counter dispute-id)

    (ok dispute-id)
  )
)

;; Helper function to select jurors (simplified selection)
;; @param stakers: List of active stakers
;; @param requester: Task requester (excluded from jury)
;; @param worker: Task worker (excluded from jury)
;; @returns: List of selected jurors
(define-private (select-jurors
    (stakers (list 100 principal))
    (requester principal)
    (worker principal)
  )
  ;; Simplified selection - just return a fixed list for now
  ;; In a real implementation, this would use proper randomization
  (if (>= (len stakers) MIN-JURORS)
    (list 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM
      'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG
      'ST2JHG361ZXG51QTKY2NQCVBPPRRE2KZB1HR05NNC)
    (list)
  )
)

;; Helper to filter out dispute parties from potential jurors
;; @param stakers: List of stakers
;; @param requester: Requester to exclude
;; @param worker: Worker to exclude
;; @returns: Filtered list
(define-private (filter-parties
    (stakers (list 100 principal))
    (requester principal)
    (worker principal)
  )
  (filter is-eligible-juror stakers)
)

;; Helper to check if a principal is eligible as juror
;; @param staker: Principal to check
;; @returns: True if eligible
(define-private (is-eligible-juror (staker principal))
  ;; This is a simplified check - in practice would exclude dispute parties
  true
)

;; Cast vote in a dispute
;; @param dispute-id: ID of dispute
;; @param vote-for-worker: True to vote for worker, false for requester
;; @returns: Success confirmation
(define-public (cast-vote
    (dispute-id uint)
    (vote-for-worker bool)
  )
  (let ((dispute-data (unwrap! (map-get? disputes dispute-id) ERR-NOT-FOUND)))
    ;; Check if voting is still open
    (asserts! (is-eq (get status dispute-data) DISPUTE-STATUS-VOTING)
      ERR-DISPUTE-CLOSED
    )
    (asserts! (<= stacks-block-height (get voting-ends-at dispute-data))
      ERR-VOTING-ENDED
    )

    ;; Check if caller is a juror
    (asserts! (is-some (index-of (get jurors dispute-data) tx-sender))
      ERR-UNAUTHORIZED
    )

    ;; Check if juror hasn't voted yet
    (asserts!
      (is-none (map-get? juror-votes {
        dispute-id: dispute-id,
        juror: tx-sender,
      }))
      ERR-ALREADY-EXISTS
    )

    ;; Record vote
    (map-set juror-votes {
      dispute-id: dispute-id,
      juror: tx-sender,
    } {
      vote: vote-for-worker,
      voted-at: stacks-block-height,
    })

    ;; Update vote counts
    (if vote-for-worker
      (map-set disputes dispute-id
        (merge dispute-data { votes-for-worker: (+ (get votes-for-worker dispute-data) u1) })
      )
      (map-set disputes dispute-id
        (merge dispute-data { votes-for-requester: (+ (get votes-for-requester dispute-data) u1) })
      )
    )

    ;; Check if we can resolve dispute (majority reached)
    (let ((updated-dispute (unwrap! (map-get? disputes dispute-id) ERR-NOT-FOUND)))
      (if (or
          (> (get votes-for-worker updated-dispute)
            (/ (len (get jurors updated-dispute)) u2)
          )
          (> (get votes-for-requester updated-dispute)
            (/ (len (get jurors updated-dispute)) u2)
          )
        )
        (begin
          (try! (resolve-dispute dispute-id))
          (ok true)
        )
        (ok true)
      )
    )
  )
)

;; Resolve dispute based on votes
;; @param dispute-id: ID of dispute to resolve
;; @returns: Success confirmation
(define-public (resolve-dispute (dispute-id uint))
  (let ((dispute-data (unwrap! (map-get? disputes dispute-id) ERR-NOT-FOUND)))
    ;; Check authorization and status
    (asserts!
      (or
        (is-eq contract-caller (as-contract tx-sender))
        (is-eq contract-caller AUTHORIZED-ADMIN)
      )
      ERR-UNAUTHORIZED
    )
    (asserts! (is-eq (get status dispute-data) DISPUTE-STATUS-VOTING)
      ERR-DISPUTE-CLOSED
    )

    ;; Determine winner
    (let ((winner (if (> (get votes-for-worker dispute-data)
          (get votes-for-requester dispute-data)
        )
        (get worker dispute-data)
        (get requester dispute-data)
      )))
      ;; Update dispute record
      (map-set disputes dispute-id
        (merge dispute-data {
          status: DISPUTE-STATUS-RESOLVED,
          resolved-at: (some stacks-block-height),
          winner: (some winner),
        })
      )

      ;; Finalize task in core contract (simplified for now)
      ;; In a full implementation, this would call the core contract
      ;; (try! (contract-call? .taskfi-core finalize-task (get task-id dispute-data) winner))

      ;; Reward jurors (simplified - equal reward for all)
      ;; In a full implementation, this would reward jurors
      ;; (try! (reward-jurors (get jurors dispute-data)))

      (ok winner)
    )
  )
)

;; Reward jurors for participation
;; @param jurors: List of juror principals
;; @returns: Success confirmation
(define-private (reward-jurors (jurors (list 7 principal)))
  ;; Simplified implementation - in practice would transfer rewards
  (ok true)
)

;; Get dispute details
;; @param dispute-id: ID of dispute
;; @returns: Dispute data or none
(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes dispute-id)
)

;; Get current dispute counter
;; @returns: Current dispute counter
(define-read-only (get-dispute-counter)
  (var-get dispute-counter)
)

;; Check if dispute exists
;; @param dispute-id: ID to check
;; @returns: True if dispute exists
(define-read-only (dispute-exists (dispute-id uint))
  (is-some (map-get? disputes dispute-id))
)
