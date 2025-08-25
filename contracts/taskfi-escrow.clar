;; TaskFi Core Contract - Main task lifecycle management
;; Handles task creation, acceptance, delivery submission, and completion
(use-trait fungible-token-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)
(impl-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)
(use-trait .taskfi-utils)
(use-trait .taskfi-escrow)
(use-trait .taskfi-staking)
(use-trait .taskfi-reputation)
(use-trait .taskfi-dispute)
(use-trait .taskfi-admin)
;; Error codes imported from utils
(define-constant ERR-NOT-FOUND (contract-call? .taskfi-utils get-error-not-found))
(define-constant ERR-UNAUTHORIZED (contract-call? .taskfi-utils get-error-unauthorized))
(define-constant ERR-INVALID-INPUT (contract-call? .taskfi-utils get-error-invalid-input))
(define-constant ERR-ALREADY-EXISTS (contract-call? .taskfi-utils get-error-already-exists))
(define-constant ERR-DEADLINE-PASSED (contract-call? .taskfi-utils get-error-deadline-passed))
(define-constant ERR-INSUFFICIENT-STAKE (contract-call? .taskfi-utils get-error-insufficient-stake))
(define-constant ERR-TASK-NOT-ACCEPTED (contract-call? .taskfi-utils get-error-task-not-accepted))
(define-constant ERR-TASK-COMPLETED (contract-call? .taskfi-utils get-error-task-completed))
(define-constant ERR-INSUFFICIENT-REPUTATION (contract-call? .taskfi-utils get-error-insufficient-reputation))
;; Task status constants
(define-constant TASK-STATUS-OPEN u1)
(define-constant TASK-STATUS-ACCEPTED u2)
(define-constant TASK-STATUS-SUBMITTED u3)
(define-constant TASK-STATUS-COMPLETED u4)
(define-constant TASK-STATUS-DISPUTED u5)
(define-constant TASK-STATUS-CANCELLED u6)
;; Protocol constants
(define-constant MAX-TASK-DESCRIPTION-LENGTH u256)
(define-constant MIN-TASK-REWARD u1000000) ;; 1 STX minimum
(define-constant MAX-DELIVERY-CID-LENGTH u64)
;; Task counter for unique IDs
(define-data-var task-id-counter uint u0)
;; Task data structure
(define-map tasks uint {
requester: principal,
worker: (optional principal),
title: (string-ascii 64),
description: (string-ascii 256),
reward: uint,
deadline: uint,
min-reputation: uint,
status: uint,
delivery-cid: (optional (buff 64)),
created-at: uint,
accepted-at: (optional uint),
submitted-at: (optional uint),
completed-at: (optional uint)
})
;; Principal to tasks mapping for efficient lookups
(define-map requester-tasks principal (list 50 uint))
(define-map worker-tasks principal (list 50 uint))
;; Create a new task with reward escrow
;; @param title: Task title (max 64 chars)
;; @param description: Task description (max 256 chars)
;; @param reward: Reward amount in microSTX
;; @param deadline: Block height deadline
;; @param min-reputation: Minimum reputation required for workers
;; @returns: Task ID on success
(define-public (create-task (title (string-ascii 64))
(description (string-ascii 256))
(reward uint)
(deadline uint)
(min-reputation uint))
(let ((task-id (+ (var-get task-id-counter) u1))
(current-block-height block-height))
;; Validate inputs
(asserts! (> (len title) u0) (err ERR-INVALID-INPUT))
(asserts! (>= (len description) u1) (err ERR-INVALID-INPUT))
(asserts! (>= reward MIN-TASK-REWARD) (err ERR-INVALID-INPUT))
(asserts! (> deadline current-block-height) (err ERR-INVALID-INPUT))
;; Check if protocol is paused
(asserts! (is-eq (contract-call? .taskfi-admin is-paused) false) (err ERR-UNAUTHORIZED))

;; Deposit reward into escrow
(try! (contract-call? .taskfi-escrow deposit-reward tx-sender task-id reward))

;; Create task record
(map-set tasks task-id {
  requester: tx-sender,
  worker: none,
  title: title,
  description: description,
  reward: reward,
  deadline: deadline,
  min-reputation: min-reputation,
  status: TASK-STATUS-OPEN,
  delivery-cid: none,
  created-at: current-block-height,
  accepted-at: none,
  submitted-at: none,
  completed-at: none
})

;; Update requester task list
(let ((current-tasks (default-to (list) (map-get? requester-tasks tx-sender))))
  (map-set requester-tasks tx-sender (unwrap! (as-max-len? (append current-tasks task-id) u50) (err ERR-INVALID-INPUT))))

;; Increment task counter
(var-set task-id-counter task-id)

(ok task-id)))
;; Worker accepts a task by staking collateral
;; @param task-id: ID of task to accept
;; @param stake-amount: Amount to stake as collateral
;; @returns: Success confirmation
(define-public (accept-task (task-id uint) (stake-amount uint))
(let ((task-data (unwrap! (map-get? tasks task-id) (err ERR-NOT-FOUND))))
;; Validate task can be accepted
(asserts! (is-eq (get status task-data) TASK-STATUS-OPEN) (err ERR-INVALID-INPUT))
(asserts! (<= block-height (get deadline task-data)) (err ERR-DEADLINE-PASSED))
(asserts! (is-none (get worker task-data)) (err ERR-ALREADY-EXISTS))
;; Check worker reputation meets minimum
(let ((worker-reputation (contract-call? .taskfi-reputation get-reputation tx-sender)))
  (asserts! (>= worker-reputation (get min-reputation task-data)) (err ERR-INSUFFICIENT-REPUTATION)))

;; Check minimum stake requirement from admin
(let ((min-stake (contract-call? .taskfi-admin get-min-stake)))
  (asserts! (>= stake-amount min-stake) (err ERR-INSUFFICIENT-STAKE)))

;; Stake collateral
(try! (contract-call? .taskfi-staking stake tx-sender stake-amount))

;; Update task with worker
(map-set tasks task-id (merge task-data {
  worker: (some tx-sender),
  status: TASK-STATUS-ACCEPTED,
  accepted-at: (some block-height)
}))

;; Update worker task list
(let ((current-tasks (default-to (list) (map-get? worker-tasks tx-sender))))
  (map-set worker-tasks tx-sender (unwrap! (as-max-len? (append current-tasks task-id) u50) (err ERR-INVALID-INPUT))))

(ok true)))
;; Worker submits delivery for task completion
;; @param task-id: ID of task
;; @param delivery-cid: IPFS content identifier for delivery
;; @returns: Success confirmation
(define-public (submit-delivery (task-id uint) (delivery-cid (buff 64)))
(let ((task-data (unwrap! (map-get? tasks task-id) (err ERR-NOT-FOUND))))
;; Validate submission
(asserts! (is-eq (some tx-sender) (get worker task-data)) (err ERR-UNAUTHORIZED))
(asserts! (is-eq (get status task-data) TASK-STATUS-ACCEPTED) (err ERR-TASK-NOT-ACCEPTED))
(asserts! (<= block-height (get deadline task-data)) (err ERR-DEADLINE-PASSED))
(asserts! (<= (len delivery-cid) MAX-DELIVERY-CID-LENGTH) (err ERR-INVALID-INPUT))
(asserts! (> (len delivery-cid) u0) (err ERR-INVALID-INPUT))
;; Update task with delivery
(map-set tasks task-id (merge task-data {
  delivery-cid: (some delivery-cid),
  status: TASK-STATUS-SUBMITTED,
  submitted-at: (some block-height)
}))

(ok true)))
;; Requester accepts delivery and completes task
;; @param task-id: ID of task to complete
;; @returns: Success confirmation
(define-public (requester-accept (task-id uint))
(let ((task-data (unwrap! (map-get? tasks task-id) (err ERR-NOT-FOUND))))
;; Validate acceptance
(asserts! (is-eq tx-sender (get requester task-data)) (err ERR-UNAUTHORIZED))
(asserts! (is-eq (get status task-data) TASK-STATUS-SUBMITTED) (err ERR-INVALID-INPUT))
(asserts! (is-some (get worker task-data)) (err ERR-TASK-NOT-ACCEPTED))
(let ((worker (unwrap! (get worker task-data) (err ERR-TASK-NOT-ACCEPTED))))
  ;; Release escrow to worker
  (try! (contract-call? .taskfi-escrow release-reward task-id worker))

  ;; Return worker's stake
  (try! (contract-call? .taskfi-staking release-stake worker))

  ;; Increase worker reputation
  (try! (contract-call? .taskfi-reputation increase-reputation worker (get reward task-data)))

  ;; Update task status
  (map-set tasks task-id (merge task-data {
    status: TASK-STATUS-COMPLETED,
    completed-at: (some block-height)
  }))

  (ok true))))
;; Requester disputes delivery, initiating dispute process
;; @param task-id: ID of task to dispute
;; @returns: Success confirmation
(define-public (requester-dispute (task-id uint))
(let ((task-data (unwrap! (map-get? tasks task-id) (err ERR-NOT-FOUND))))
;; Validate dispute
(asserts! (is-eq tx-sender (get requester task-data)) (err ERR-UNAUTHORIZED))
(asserts! (is-eq (get status task-data) TASK-STATUS-SUBMITTED) (err ERR-INVALID-INPUT))
(asserts! (is-some (get worker task-data)) (err ERR-TASK-NOT-ACCEPTED))
;; Open dispute
(try! (contract-call? .taskfi-dispute open-dispute task-id))

;; Update task status
(map-set tasks task-id (merge task-data {
  status: TASK-STATUS-DISPUTED
}))

(ok true)))
;; Finalize task after dispute resolution
;; @param task-id: ID of task to finalize
;; @param winner: Principal who wins the dispute
;; @returns: Success confirmation
(define-public (finalize-task (task-id uint) (winner principal))
(let ((task-data (unwrap! (map-get? tasks task-id) (err ERR-NOT-FOUND))))
;; Only dispute contract can call this
(asserts! (is-eq contract-caller .taskfi-dispute) (err ERR-UNAUTHORIZED))
(asserts! (is-eq (get status task-data) TASK-STATUS-DISPUTED) (err ERR-INVALID-INPUT))
(let ((worker (unwrap! (get worker task-data) (err ERR-TASK-NOT-ACCEPTED)))
      (requester (get requester task-data)))

  ;; Handle dispute outcome
  (if (is-eq winner worker)
    ;; Worker wins - release reward and stake, increase reputation
    (begin
      (try! (contract-call? .taskfi-escrow release-reward task-id worker))
      (try! (contract-call? .taskfi-staking release-stake worker))
      (try! (contract-call? .taskfi-reputation increase-reputation worker (/ (get reward task-data) u2))))
    ;; Requester wins - refund reward, slash worker stake, decrease reputation
    (begin
      (try! (contract-call? .taskfi-escrow refund-reward task-id requester))
      (try! (contract-call? .taskfi-staking slash-stake worker))
      (try! (contract-call? .taskfi-reputation decrease-reputation worker (/ (get reward task-data) u4)))))

  ;; Update task status
  (map-set tasks task-id (merge task-data {
    status: TASK-STATUS-COMPLETED,
    completed-at: (some block-height)
  }))

  (ok true))))
;; Get task details by ID
;; @param task-id: ID of task
;; @returns: Task data or none
(define-read-only (get-task (task-id uint))
(map-get? tasks task-id))
;; Get tasks created by a requester
;; @param requester: Principal of requester
;; @returns: List of task IDs
(define-read-only (get-requester-tasks (requester principal))
(default-to (list) (map-get? requester-tasks requester)))
;; Get tasks accepted by a worker
;; @param worker: Principal of worker
;; @returns: List of task IDs
(define-read-only (get-worker-tasks (worker principal))
(default-to (list) (map-get? worker-tasks worker)))
;; Get current task ID counter
;; @returns: Current task ID counter value
(define-read-only (get-task-counter)
(var-get task-id-counter))
;; Check if task exists
;; @param task-id: ID to check
;; @returns: True if task exists
(define-read-only (task-exists (task-id uint))
(is-some (map-get? tasks task-id)))