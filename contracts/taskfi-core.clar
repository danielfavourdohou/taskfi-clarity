;; TaskFi Core Contract - Main task lifecycle management
;; Handles task creation, acceptance, delivery submission, and completion

;; Error codes
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-INVALID-INPUT (err u400))
(define-constant ERR-ALREADY-EXISTS (err u409))
(define-constant ERR-DEADLINE-PASSED (err u410))
(define-constant ERR-INSUFFICIENT-STAKE (err u411))
(define-constant ERR-TASK-NOT-ACCEPTED (err u412))
(define-constant ERR-TASK-COMPLETED (err u413))
(define-constant ERR-INSUFFICIENT-REPUTATION (err u414))

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
(define-map tasks
    uint
    {
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
        completed-at: (optional uint),
    }
)

;; Principal to tasks mapping for efficient lookups
(define-map requester-tasks
    principal
    (list 50 uint)
)
(define-map worker-tasks
    principal
    (list 50 uint)
)

;; Create a new task with reward escrow
;; @param title: Task title (max 64 chars)
;; @param description: Task description (max 256 chars)
;; @param reward: Reward amount in microSTX
;; @param deadline: Block height deadline
;; @param min-reputation: Minimum reputation required for workers
;; @returns: Task ID on success
(define-public (create-task
        (title (string-ascii 64))
        (description (string-ascii 256))
        (reward uint)
        (deadline uint)
        (min-reputation uint)
    )
    (let (
            (task-id (+ (var-get task-id-counter) u1))
            (current-block-height stacks-block-height)
        )
        ;; Validate inputs
        (asserts! (> (len title) u0) ERR-INVALID-INPUT)
        (asserts! (>= (len description) u1) ERR-INVALID-INPUT)
        (asserts! (>= reward MIN-TASK-REWARD) ERR-INVALID-INPUT)
        (asserts! (> deadline current-block-height) ERR-INVALID-INPUT)

        ;; Deposit reward into escrow (simplified for now)
        ;; In a full implementation, this would call the escrow contract
        ;; (try! (contract-call? .taskfi-escrow deposit-reward tx-sender task-id reward))

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
            completed-at: none,
        })

        ;; Update requester task list
        (let ((current-tasks (default-to (list) (map-get? requester-tasks tx-sender))))
            (map-set requester-tasks tx-sender
                (unwrap! (as-max-len? (append current-tasks task-id) u50)
                    ERR-INVALID-INPUT
                ))
        )

        ;; Increment task counter
        (var-set task-id-counter task-id)

        (ok task-id)
    )
)

;; Worker accepts a task by staking collateral
;; @param task-id: ID of task to accept
;; @param stake-amount: Amount to stake as collateral
;; @returns: Success confirmation
(define-public (accept-task
        (task-id uint)
        (stake-amount uint)
    )
    (let ((task-data (unwrap! (map-get? tasks task-id) ERR-NOT-FOUND)))
        ;; Validate task can be accepted
        (asserts! (is-eq (get status task-data) TASK-STATUS-OPEN)
            ERR-INVALID-INPUT
        )
        (asserts! (<= stacks-block-height (get deadline task-data))
            ERR-DEADLINE-PASSED
        )
        (asserts! (is-none (get worker task-data)) ERR-ALREADY-EXISTS)

        ;; Check worker reputation meets minimum (simplified for now)
        ;; In a full implementation, this would call the reputation contract
        (asserts! (>= u100 (get min-reputation task-data))
            ERR-INSUFFICIENT-REPUTATION
        )

        ;; Stake collateral (simplified for now)
        ;; In a full implementation, this would call the staking contract
        (asserts! (>= stake-amount u1000000) ERR-INSUFFICIENT-STAKE)

        ;; Update task with worker
        (map-set tasks task-id
            (merge task-data {
                worker: (some tx-sender),
                status: TASK-STATUS-ACCEPTED,
                accepted-at: (some stacks-block-height),
            })
        )

        ;; Update worker task list
        (let ((current-tasks (default-to (list) (map-get? worker-tasks tx-sender))))
            (map-set worker-tasks tx-sender
                (unwrap! (as-max-len? (append current-tasks task-id) u50)
                    ERR-INVALID-INPUT
                ))
        )

        (ok true)
    )
)

;; Worker submits delivery for task completion
;; @param task-id: ID of task
;; @param delivery-cid: IPFS content identifier for delivery
;; @returns: Success confirmation
(define-public (submit-delivery
        (task-id uint)
        (delivery-cid (buff 64))
    )
    (let ((task-data (unwrap! (map-get? tasks task-id) ERR-NOT-FOUND)))
        ;; Validate submission
        (asserts! (is-eq (some tx-sender) (get worker task-data))
            ERR-UNAUTHORIZED
        )
        (asserts! (is-eq (get status task-data) TASK-STATUS-ACCEPTED)
            ERR-TASK-NOT-ACCEPTED
        )
        (asserts! (<= stacks-block-height (get deadline task-data))
            ERR-DEADLINE-PASSED
        )
        (asserts! (<= (len delivery-cid) MAX-DELIVERY-CID-LENGTH)
            ERR-INVALID-INPUT
        )
        (asserts! (> (len delivery-cid) u0) ERR-INVALID-INPUT)

        ;; Update task with delivery
        (map-set tasks task-id
            (merge task-data {
                delivery-cid: (some delivery-cid),
                status: TASK-STATUS-SUBMITTED,
                submitted-at: (some stacks-block-height),
            })
        )

        (ok true)
    )
)

;; Requester accepts delivery and completes task
;; @param task-id: ID of task to complete
;; @returns: Success confirmation
(define-public (complete-task (task-id uint))
    (let ((task-data (unwrap! (map-get? tasks task-id) ERR-NOT-FOUND)))
        ;; Validate completion
        (asserts! (is-eq tx-sender (get requester task-data)) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status task-data) TASK-STATUS-SUBMITTED)
            ERR-INVALID-INPUT
        )
        (asserts! (is-some (get worker task-data)) ERR-TASK-NOT-ACCEPTED)

        (let ((worker (unwrap! (get worker task-data) ERR-TASK-NOT-ACCEPTED)))
            ;; Release escrow to worker (simplified for now)
            ;; In a full implementation, this would call the escrow contract
            ;; (try! (contract-call? .taskfi-escrow release-reward task-id worker))

            ;; Return worker's stake (simplified for now)
            ;; In a full implementation, this would call the staking contract
            ;; (try! (contract-call? .taskfi-staking release-stake worker))

            ;; Increase worker reputation (simplified for now)
            ;; In a full implementation, this would call the reputation contract
            ;; (try! (contract-call? .taskfi-reputation increase-reputation worker (get reward task-data)))

            ;; Update task status
            (map-set tasks task-id
                (merge task-data {
                    status: TASK-STATUS-COMPLETED,
                    completed-at: (some stacks-block-height),
                })
            )

            (ok true)
        )
    )
)

;; Get task details by ID
;; @param task-id: ID of task
;; @returns: Task data or none
(define-read-only (get-task (task-id uint))
    (map-get? tasks task-id)
)

;; Get tasks created by a requester
;; @param requester: Principal of requester
;; @returns: List of task IDs
(define-read-only (get-requester-tasks (requester principal))
    (default-to (list) (map-get? requester-tasks requester))
)

;; Get tasks accepted by a worker
;; @param worker: Principal of worker
;; @returns: List of task IDs
(define-read-only (get-worker-tasks (worker principal))
    (default-to (list) (map-get? worker-tasks worker))
)

;; Get current task ID counter
;; @returns: Current task ID counter value
(define-read-only (get-task-counter)
    (var-get task-id-counter)
)

;; Check if task exists
;; @param task-id: ID to check
;; @returns: True if task exists
(define-read-only (task-exists (task-id uint))
    (is-some (map-get? tasks task-id))
)
