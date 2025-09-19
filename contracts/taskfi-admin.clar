;; TaskFi Admin Contract - Protocol administration and governance
;; Manages protocol parameters, pausing, and emergency functions

;; Error codes
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-INVALID-INPUT (err u400))
(define-constant ERR-PROTOCOL-PAUSED (err u410))

;; Admin roles
(define-constant ADMIN-ROLE u1)
(define-constant MODERATOR-ROLE u2)
(define-constant EMERGENCY-ROLE u3)

;; Protocol parameters
(define-data-var protocol-paused bool false)
(define-data-var min-stake-amount uint u1000000) ;; 1 STX minimum stake
(define-data-var max-task-reward uint u100000000000) ;; 100k STX max reward
(define-data-var dispute-fee uint u500000) ;; 0.5 STX dispute fee
(define-data-var protocol-fee-rate uint u250) ;; 2.5% (out of 10000)

;; Admin addresses
(define-data-var contract-owner principal tx-sender)
(define-map admin-roles principal uint)

;; Protocol statistics
(define-data-var total-tasks-created uint u0)
(define-data-var total-tasks-completed uint u0)
(define-data-var total-disputes-opened uint u0)
(define-data-var total-volume-processed uint u0)

;; Emergency pause functionality
(define-data-var emergency-contacts (list 5 principal) (list))

;; Initialize admin roles
(map-set admin-roles tx-sender ADMIN-ROLE)

;; Check if caller has admin privileges
;; @param required-role: Minimum role required
;; @returns: True if authorized
(define-private (is-authorized (required-role uint))
  (let ((caller-role (default-to u0 (map-get? admin-roles tx-sender))))
    (>= caller-role required-role)))

;; Add admin or moderator
;; @param new-admin: Principal to grant admin role
;; @param role: Role level to grant
;; @returns: Success confirmation
(define-public (add-admin (new-admin principal) (role uint))
  (begin
    ;; Only existing admins can add new admins
    (asserts! (is-authorized ADMIN-ROLE) ERR-UNAUTHORIZED)
    ;; Validate role
    (asserts! (and (>= role u1) (<= role u3)) ERR-INVALID-INPUT)

    ;; Grant role
    (map-set admin-roles new-admin role)
    (ok true)))

;; Remove admin privileges
;; @param admin-to-remove: Principal to remove admin role from
;; @returns: Success confirmation
(define-public (remove-admin (admin-to-remove principal))
  (begin
    ;; Only contract owner can remove admins
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    ;; Cannot remove contract owner
    (asserts! (not (is-eq admin-to-remove (var-get contract-owner))) ERR-UNAUTHORIZED)

    ;; Remove role
    (map-delete admin-roles admin-to-remove)
    (ok true)))

;; Pause/unpause protocol
;; @param pause: True to pause, false to unpause
;; @returns: Success confirmation
(define-public (set-protocol-paused (pause bool))
  (begin
    ;; Only admins can pause/unpause
    (asserts! (is-authorized ADMIN-ROLE) ERR-UNAUTHORIZED)

    (var-set protocol-paused pause)
    (ok true)))

;; Emergency pause (can be called by emergency contacts)
;; @returns: Success confirmation
(define-public (emergency-pause)
  (begin
    ;; Check if caller is emergency contact or admin
    (asserts! (or (is-authorized EMERGENCY-ROLE)
                  (is-some (index-of (var-get emergency-contacts) tx-sender))) ERR-UNAUTHORIZED)

    (var-set protocol-paused true)
    (ok true)))

;; Update minimum stake amount
;; @param new-amount: New minimum stake amount
;; @returns: Success confirmation
(define-public (set-min-stake (new-amount uint))
  (begin
    (asserts! (is-authorized ADMIN-ROLE) ERR-UNAUTHORIZED)
    (asserts! (> new-amount u0) ERR-INVALID-INPUT)

    (var-set min-stake-amount new-amount)
    (ok true)))

;; Update maximum task reward
;; @param new-amount: New maximum task reward
;; @returns: Success confirmation
(define-public (set-max-task-reward (new-amount uint))
  (begin
    (asserts! (is-authorized ADMIN-ROLE) ERR-UNAUTHORIZED)
    (asserts! (> new-amount u0) ERR-INVALID-INPUT)

    (var-set max-task-reward new-amount)
    (ok true)))

;; Update dispute fee
;; @param new-fee: New dispute fee amount
;; @returns: Success confirmation
(define-public (set-dispute-fee (new-fee uint))
  (begin
    (asserts! (is-authorized ADMIN-ROLE) ERR-UNAUTHORIZED)
    (asserts! (> new-fee u0) ERR-INVALID-INPUT)

    (var-set dispute-fee new-fee)
    (ok true)))

;; Update protocol fee rate
;; @param new-rate: New fee rate (out of 10000)
;; @returns: Success confirmation
(define-public (set-protocol-fee-rate (new-rate uint))
  (begin
    (asserts! (is-authorized ADMIN-ROLE) ERR-UNAUTHORIZED)
    (asserts! (<= new-rate u1000) ERR-INVALID-INPUT) ;; Max 10%

    (var-set protocol-fee-rate new-rate)
    (ok true)))

;; Add emergency contact
;; @param contact: Principal to add as emergency contact
;; @returns: Success confirmation
(define-public (add-emergency-contact (contact principal))
  (begin
    (asserts! (is-authorized ADMIN-ROLE) ERR-UNAUTHORIZED)

    (let ((current-contacts (var-get emergency-contacts)))
      (if (< (len current-contacts) u5)
        (begin
          (var-set emergency-contacts
                   (unwrap! (as-max-len? (append current-contacts contact) u5) ERR-INVALID-INPUT))
          (ok true))
        ERR-INVALID-INPUT))))

;; Update protocol statistics (called by other contracts)
;; @param stat-type: Type of statistic to update
;; @param amount: Amount to add
;; @returns: Success confirmation
(define-public (update-stats (stat-type (string-ascii 32)) (amount uint))
  (begin
    ;; Only protocol contracts can update stats
    (asserts! (or (is-eq contract-caller .taskfi-core)
                  (is-eq contract-caller .taskfi-escrow)
                  (is-eq contract-caller .taskfi-dispute)) ERR-UNAUTHORIZED)

    (begin
      (if (is-eq stat-type "tasks-created")
        (var-set total-tasks-created (+ (var-get total-tasks-created) amount))
        (if (is-eq stat-type "tasks-completed")
          (var-set total-tasks-completed (+ (var-get total-tasks-completed) amount))
          (if (is-eq stat-type "disputes-opened")
            (var-set total-disputes-opened (+ (var-get total-disputes-opened) amount))
            (if (is-eq stat-type "volume-processed")
              (var-set total-volume-processed (+ (var-get total-volume-processed) amount))
              true))))
      (ok true))))

;; Read-only functions for parameter access

(define-read-only (is-paused)
  (var-get protocol-paused))

(define-read-only (get-min-stake)
  (var-get min-stake-amount))

(define-read-only (get-max-task-reward)
  (var-get max-task-reward))

(define-read-only (get-dispute-fee)
  (var-get dispute-fee))

(define-read-only (get-protocol-fee-rate)
  (var-get protocol-fee-rate))

(define-read-only (get-admin-role (admin principal))
  (default-to u0 (map-get? admin-roles admin)))

(define-read-only (get-contract-owner)
  (var-get contract-owner))

(define-read-only (get-emergency-contacts)
  (var-get emergency-contacts))

;; Protocol statistics getters
(define-read-only (get-total-tasks-created)
  (var-get total-tasks-created))

(define-read-only (get-total-tasks-completed)
  (var-get total-tasks-completed))

(define-read-only (get-total-disputes-opened)
  (var-get total-disputes-opened))

(define-read-only (get-total-volume-processed)
  (var-get total-volume-processed))

;; Get protocol health metrics
(define-read-only (get-protocol-metrics)
  {
    tasks-created: (var-get total-tasks-created),
    tasks-completed: (var-get total-tasks-completed),
    disputes-opened: (var-get total-disputes-opened),
    volume-processed: (var-get total-volume-processed),
    completion-rate: (if (> (var-get total-tasks-created) u0)
                       (/ (* (var-get total-tasks-completed) u100) (var-get total-tasks-created))
                       u0),
    dispute-rate: (if (> (var-get total-tasks-created) u0)
                    (/ (* (var-get total-disputes-opened) u100) (var-get total-tasks-created))
                    u0)
  })
