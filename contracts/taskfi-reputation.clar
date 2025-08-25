;; TaskFi Reputation Contract - Manages worker reputation scores
;; Tracks reputation based on task completion and dispute outcomes

;; Error codes
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-INVALID-INPUT (err u400))

;; Authorized callers
(define-constant AUTHORIZED-CORE .taskfi-core)
(define-constant AUTHORIZED-DISPUTE .taskfi-dispute)
(define-constant AUTHORIZED-ADMIN .taskfi-admin)

;; Reputation constants
(define-constant INITIAL-REPUTATION u100)
(define-constant MAX-REPUTATION u1000)
(define-constant MIN-REPUTATION u0)
(define-constant REPUTATION-MULTIPLIER u10) ;; Reputation per 1 STX reward

;; Reputation records
(define-map reputations principal {
  score: uint,
  tasks-completed: uint,
  tasks-disputed: uint,
  total-earned: uint,
  last-updated: uint
})

;; Reputation history for transparency
(define-map reputation-history principal (list 20 {
  change: int,
  reason: (string-ascii 64),
  block-height: uint
}))

;; Get reputation score for a principal
;; @param user: Principal to check
;; @returns: Reputation score
(define-read-only (get-reputation (user principal))
  (match (map-get? reputations user)
    reputation-data (get score reputation-data)
    INITIAL-REPUTATION))

;; Increase reputation after successful task completion
;; @param user: Principal whose reputation to increase
;; @param reward-amount: Task reward amount (affects reputation gain)
;; @returns: Success confirmation
(define-public (increase-reputation (user principal) (reward-amount uint))
  (begin
    ;; Verify caller authorization
    (asserts! (or (is-eq contract-caller AUTHORIZED-CORE)
                  (is-eq contract-caller AUTHORIZED-DISPUTE)) ERR-UNAUTHORIZED)
    
    ;; Calculate reputation increase based on reward
    (let ((reputation-increase (/ (* reward-amount REPUTATION-MULTIPLIER) u1000000))) ;; Per STX
      (let ((current-data (default-to {
              score: INITIAL-REPUTATION,
              tasks-completed: u0,
              tasks-disputed: u0,
              total-earned: u0,
              last-updated: u0
            } (map-get? reputations user))))
        
        ;; Calculate new score (capped at MAX-REPUTATION)
        (let ((new-score (if (> (+ (get score current-data) reputation-increase) MAX-REPUTATION)
                             MAX-REPUTATION
                             (+ (get score current-data) reputation-increase))))
          
          ;; Update reputation record
          (map-set reputations user {
            score: new-score,
            tasks-completed: (+ (get tasks-completed current-data) u1),
            tasks-disputed: (get tasks-disputed current-data),
            total-earned: (+ (get total-earned current-data) reward-amount),
            last-updated: stacks-block-height
          })
          
          ;; Add to history
          (let ((current-history (default-to (list) (map-get? reputation-history user))))
            (map-set reputation-history user 
                     (unwrap! (as-max-len? (append current-history {
                       change: (to-int reputation-increase),
                       reason: "Task completed successfully",
                       block-height: stacks-block-height
                     }) u20) ERR-INVALID-INPUT)))
          
          (ok new-score))))))

;; Decrease reputation after dispute loss
;; @param user: Principal whose reputation to decrease
;; @param penalty-amount: Amount to base penalty on
;; @returns: Success confirmation
(define-public (decrease-reputation (user principal) (penalty-amount uint))
  (begin
    ;; Verify caller authorization
    (asserts! (or (is-eq contract-caller AUTHORIZED-CORE)
                  (is-eq contract-caller AUTHORIZED-DISPUTE)) ERR-UNAUTHORIZED)
    
    ;; Calculate reputation decrease
    (let ((reputation-decrease (/ (* penalty-amount REPUTATION-MULTIPLIER) u2000000))) ;; Half rate for penalties
      (let ((current-data (default-to {
              score: INITIAL-REPUTATION,
              tasks-completed: u0,
              tasks-disputed: u0,
              total-earned: u0,
              last-updated: u0
            } (map-get? reputations user))))
        
        ;; Calculate new score (floored at MIN-REPUTATION)
        (let ((new-score (if (< (get score current-data) reputation-decrease)
                             MIN-REPUTATION
                             (- (get score current-data) reputation-decrease))))
          
          ;; Update reputation record
          (map-set reputations user {
            score: new-score,
            tasks-completed: (get tasks-completed current-data),
            tasks-disputed: (+ (get tasks-disputed current-data) u1),
            total-earned: (get total-earned current-data),
            last-updated: stacks-block-height
          })
          
          ;; Add to history
          (let ((current-history (default-to (list) (map-get? reputation-history user))))
            (map-set reputation-history user 
                     (unwrap! (as-max-len? (append current-history {
                       change: (- (to-int reputation-decrease)),
                       reason: "Dispute resolution penalty",
                       block-height: stacks-block-height
                     }) u20) ERR-INVALID-INPUT)))
          
          (ok new-score))))))

;; Get full reputation data for a principal
;; @param user: Principal to check
;; @returns: Full reputation record or default
(define-read-only (get-reputation-data (user principal))
  (default-to {
    score: INITIAL-REPUTATION,
    tasks-completed: u0,
    tasks-disputed: u0,
    total-earned: u0,
    last-updated: u0
  } (map-get? reputations user)))

;; Get reputation history for a principal
;; @param user: Principal to check
;; @returns: List of reputation changes
(define-read-only (get-reputation-history (user principal))
  (default-to (list) (map-get? reputation-history user)))

;; Check if user meets minimum reputation requirement
;; @param user: Principal to check
;; @param min-required: Minimum reputation required
;; @returns: True if user meets requirement
(define-read-only (meets-reputation-requirement (user principal) (min-required uint))
  (>= (get-reputation user) min-required))

;; Get reputation tier (for UI display)
;; @param user: Principal to check
;; @returns: Reputation tier as string
(define-read-only (get-reputation-tier (user principal))
  (let ((score (get-reputation user)))
    (if (>= score u800)
      "Expert"
      (if (>= score u600)
        "Advanced"
        (if (>= score u400)
          "Intermediate"
          (if (>= score u200)
            "Beginner"
            "Novice"))))))
