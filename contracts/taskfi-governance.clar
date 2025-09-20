;; TaskFi Governance Contract - Protocol governance and voting system
;; Manages protocol upgrades, parameter changes, and community voting

;; Error codes
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-INVALID-INPUT (err u400))
(define-constant ERR-ALREADY-EXISTS (err u409))
(define-constant ERR-VOTING-ENDED (err u410))
(define-constant ERR-VOTING-ACTIVE (err u411))
(define-constant ERR-ALREADY-VOTED (err u412))
(define-constant ERR-INSUFFICIENT-STAKE (err u413))
(define-constant ERR-PROPOSAL-EXPIRED (err u414))
(define-constant ERR-QUORUM-NOT-MET (err u415))

;; Authorized contracts
(define-constant AUTHORIZED-ADMIN .taskfi-admin)

;; Governance constants
(define-constant MIN-PROPOSAL-STAKE u10000000) ;; 10 STX to create proposal
(define-constant VOTING-PERIOD u2016) ;; ~14 days in blocks
(define-constant EXECUTION-DELAY u1440) ;; ~10 days delay after voting ends
(define-constant QUORUM-THRESHOLD u3000) ;; 30% of total staked tokens
(define-constant APPROVAL-THRESHOLD u5100) ;; 51% approval needed

;; Proposal types
(define-constant PROPOSAL-TYPE-PARAMETER u1)
(define-constant PROPOSAL-TYPE-CONTRACT-UPGRADE u2)
(define-constant PROPOSAL-TYPE-EMERGENCY-PAUSE u3)
(define-constant PROPOSAL-TYPE-TREASURY u4)

;; Proposal status
(define-constant PROPOSAL-STATUS-ACTIVE u1)
(define-constant PROPOSAL-STATUS-PASSED u2)
(define-constant PROPOSAL-STATUS-FAILED u3)
(define-constant PROPOSAL-STATUS-EXECUTED u4)
(define-constant PROPOSAL-STATUS-EXPIRED u5)

;; Data variables
(define-data-var proposal-counter uint u0)
(define-data-var total-voting-power uint u0)

;; Proposal structure
(define-map proposals
    uint
    {
        proposer: principal,
        title: (string-ascii 64),
        description: (string-ascii 256),
        proposal-type: uint,
        target-contract: (optional principal),
        function-name: (optional (string-ascii 32)),
        parameters: (optional (buff 256)),
        stake-amount: uint,
        votes-for: uint,
        votes-against: uint,
        total-votes: uint,
        status: uint,
        created-at: uint,
        voting-ends-at: uint,
        execution-available-at: uint,
        executed-at: (optional uint),
    }
)

;; Vote tracking
(define-map votes
    { proposal-id: uint, voter: principal }
    {
        vote: bool, ;; true = for, false = against
        voting-power: uint,
        voted-at: uint,
    }
)

;; Voter eligibility (based on staking)
(define-map voter-power
    principal
    {
        power: uint,
        last-updated: uint,
    }
)

;; Proposal execution queue
(define-map execution-queue
    uint
    {
        proposal-id: uint,
        ready-at: uint,
        executed: bool,
    }
)

;; Create a new governance proposal
;; @param title: Proposal title
;; @param description: Proposal description
;; @param proposal-type: Type of proposal
;; @param target-contract: Target contract for upgrades (optional)
;; @param function-name: Function to call (optional)
;; @param parameters: Function parameters (optional)
;; @returns: Proposal ID
(define-public (create-proposal
        (title (string-ascii 64))
        (description (string-ascii 256))
        (proposal-type uint)
        (target-contract (optional principal))
        (function-name (optional (string-ascii 32)))
        (parameters (optional (buff 256)))
    )
    (let (
            (proposal-id (+ (var-get proposal-counter) u1))
            (current-block stacks-block-height)
            (voting-ends-at (+ current-block VOTING-PERIOD))
            (execution-available-at (+ voting-ends-at EXECUTION-DELAY))
        )
        ;; Validate inputs
        (asserts! (> (len title) u0) ERR-INVALID-INPUT)
        (asserts! (> (len description) u0) ERR-INVALID-INPUT)
        (asserts! (<= proposal-type PROPOSAL-TYPE-TREASURY) ERR-INVALID-INPUT)

        ;; Check proposer has minimum stake
        (let ((proposer-stake (get-voting-power tx-sender)))
            (asserts! (>= proposer-stake MIN-PROPOSAL-STAKE) ERR-INSUFFICIENT-STAKE)
        )

        ;; Create proposal
        (map-set proposals proposal-id {
            proposer: tx-sender,
            title: title,
            description: description,
            proposal-type: proposal-type,
            target-contract: target-contract,
            function-name: function-name,
            parameters: parameters,
            stake-amount: MIN-PROPOSAL-STAKE,
            votes-for: u0,
            votes-against: u0,
            total-votes: u0,
            status: PROPOSAL-STATUS-ACTIVE,
            created-at: current-block,
            voting-ends-at: voting-ends-at,
            execution-available-at: execution-available-at,
            executed-at: none,
        })

        ;; Add to execution queue
        (map-set execution-queue proposal-id {
            proposal-id: proposal-id,
            ready-at: execution-available-at,
            executed: false,
        })

        ;; Update counter
        (var-set proposal-counter proposal-id)

        (ok proposal-id)
    )
)

;; Cast vote on a proposal
;; @param proposal-id: ID of proposal to vote on
;; @param vote: true for yes, false for no
;; @returns: Success confirmation
(define-public (cast-vote (proposal-id uint) (vote bool))
    (let (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-NOT-FOUND))
            (voting-power (get-voting-power tx-sender))
            (current-block stacks-block-height)
        )
        ;; Validate voting conditions
        (asserts! (is-eq (get status proposal) PROPOSAL-STATUS-ACTIVE) ERR-VOTING-ENDED)
        (asserts! (< current-block (get voting-ends-at proposal)) ERR-VOTING-ENDED)
        (asserts! (> voting-power u0) ERR-INSUFFICIENT-STAKE)
        (asserts! (is-none (map-get? votes { proposal-id: proposal-id, voter: tx-sender })) ERR-ALREADY-VOTED)

        ;; Record vote
        (map-set votes { proposal-id: proposal-id, voter: tx-sender } {
            vote: vote,
            voting-power: voting-power,
            voted-at: current-block,
        })

        ;; Update proposal vote counts
        (let (
                (new-votes-for (if vote (+ (get votes-for proposal) voting-power) (get votes-for proposal)))
                (new-votes-against (if vote (get votes-against proposal) (+ (get votes-against proposal) voting-power)))
                (new-total-votes (+ (get total-votes proposal) voting-power))
            )
            (map-set proposals proposal-id
                (merge proposal {
                    votes-for: new-votes-for,
                    votes-against: new-votes-against,
                    total-votes: new-total-votes,
                })
            )
        )

        (ok true)
    )
)

;; Finalize voting on a proposal
;; @param proposal-id: ID of proposal to finalize
;; @returns: Success confirmation
(define-public (finalize-proposal (proposal-id uint))
    (let (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-NOT-FOUND))
            (current-block stacks-block-height)
            (total-staked (var-get total-voting-power))
        )
        ;; Check voting has ended
        (asserts! (>= current-block (get voting-ends-at proposal)) ERR-VOTING-ACTIVE)
        (asserts! (is-eq (get status proposal) PROPOSAL-STATUS-ACTIVE) ERR-INVALID-INPUT)

        ;; Check quorum
        (let (
                (quorum-required (/ (* total-staked QUORUM-THRESHOLD) u10000))
                (approval-required (/ (* (get total-votes proposal) APPROVAL-THRESHOLD) u10000))
                (votes-for (get votes-for proposal))
                (total-votes (get total-votes proposal))
            )
            (let (
                    (quorum-met (>= total-votes quorum-required))
                    (proposal-passed (and quorum-met (>= votes-for approval-required)))
                    (new-status (if proposal-passed PROPOSAL-STATUS-PASSED PROPOSAL-STATUS-FAILED))
                )
                ;; Update proposal status
                (map-set proposals proposal-id
                    (merge proposal { status: new-status })
                )

                (ok proposal-passed)
            )
        )
    )
)

;; Execute a passed proposal
;; @param proposal-id: ID of proposal to execute
;; @returns: Success confirmation
(define-public (execute-proposal (proposal-id uint))
    (let (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-NOT-FOUND))
            (current-block stacks-block-height)
        )
        ;; Validate execution conditions
        (asserts! (is-eq (get status proposal) PROPOSAL-STATUS-PASSED) ERR-INVALID-INPUT)
        (asserts! (>= current-block (get execution-available-at proposal)) ERR-VOTING-ACTIVE)
        (asserts! (is-none (get executed-at proposal)) ERR-ALREADY-EXISTS)

        ;; Mark as executed
        (map-set proposals proposal-id
            (merge proposal {
                status: PROPOSAL-STATUS-EXECUTED,
                executed-at: (some current-block),
            })
        )

        ;; Update execution queue
        (map-set execution-queue proposal-id {
            proposal-id: proposal-id,
            ready-at: (get execution-available-at proposal),
            executed: true,
        })

        ;; Note: Actual execution logic would depend on proposal type
        ;; This is a simplified version for demonstration

        (ok true)
    )
)

;; Update voting power for a principal (called by staking contract)
;; @param voter: Principal whose power to update
;; @param power: New voting power amount
;; @returns: Success confirmation
(define-public (update-voting-power (voter principal) (power uint))
    (begin
        ;; Only staking contract can update voting power
        (asserts! (is-eq contract-caller .taskfi-staking) ERR-UNAUTHORIZED)

        ;; Update voter power
        (map-set voter-power voter {
            power: power,
            last-updated: stacks-block-height,
        })

        ;; Update total voting power
        (let ((current-total (var-get total-voting-power)))
            (var-set total-voting-power (+ current-total power))
        )

        (ok true)
    )
)

;; ===== READ-ONLY FUNCTIONS =====

;; Get proposal details
;; @param proposal-id: Proposal ID
;; @returns: Proposal data or none
(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

;; Get vote details
;; @param proposal-id: Proposal ID
;; @param voter: Voter principal
;; @returns: Vote data or none
(define-read-only (get-vote (proposal-id uint) (voter principal))
    (map-get? votes { proposal-id: proposal-id, voter: voter })
)

;; Get voting power for a principal
;; @param voter: Principal to check
;; @returns: Voting power amount
(define-read-only (get-voting-power (voter principal))
    (default-to u0 (get power (map-get? voter-power voter)))
)

;; Check if proposal can be executed
;; @param proposal-id: Proposal ID
;; @returns: True if executable, false otherwise
(define-read-only (can-execute-proposal (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal (and
            (is-eq (get status proposal) PROPOSAL-STATUS-PASSED)
            (>= stacks-block-height (get execution-available-at proposal))
            (is-none (get executed-at proposal))
        )
        false
    )
)

;; Get total voting power
;; @returns: Total voting power in system
(define-read-only (get-total-voting-power)
    (var-get total-voting-power)
)

;; Get proposal counter
;; @returns: Current proposal counter
(define-read-only (get-proposal-counter)
    (var-get proposal-counter)
)

;; Check if address has voted on proposal
;; @param proposal-id: Proposal ID
;; @param voter: Voter address
;; @returns: True if voted, false otherwise
(define-read-only (has-voted (proposal-id uint) (voter principal))
    (is-some (map-get? votes { proposal-id: proposal-id, voter: voter }))
)

;; Get proposal voting results
;; @param proposal-id: Proposal ID
;; @returns: Voting results summary
(define-read-only (get-voting-results (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal (some {
            votes-for: (get votes-for proposal),
            votes-against: (get votes-against proposal),
            total-votes: (get total-votes proposal),
            status: (get status proposal),
            quorum-met: (>= (get total-votes proposal) (/ (* (var-get total-voting-power) QUORUM-THRESHOLD) u10000)),
        })
        none
    )
)
