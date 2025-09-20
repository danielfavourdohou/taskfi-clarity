;; Governance Contract
;; Community governance system for HourBank platform parameters and upgrades

(define-constant ERR_UNAUTHORIZED (err u800))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u801))
(define-constant ERR_INVALID_INPUT (err u802))
(define-constant ERR_VOTING_ENDED (err u803))
(define-constant ERR_VOTING_ACTIVE (err u804))
(define-constant ERR_ALREADY_VOTED (err u805))
(define-constant ERR_INSUFFICIENT_REPUTATION (err u806))
(define-constant ERR_PROPOSAL_EXECUTED (err u807))

;; Governance parameters
(define-data-var min-reputation-to-propose uint u100)
(define-data-var min-reputation-to-vote uint u10)
(define-data-var voting-period uint u1008) ;; ~7 days in blocks
(define-data-var execution-delay uint u144) ;; ~1 day in blocks
(define-data-var quorum-threshold uint u20) ;; 20% of total reputation
(define-data-var approval-threshold uint u60) ;; 60% approval needed

;; Contract owner and governance council
(define-data-var contract-owner principal tx-sender)
(define-data-var governance-active bool false)

;; Proposal types
(define-constant PROPOSAL_TYPE_PARAMETER u1)
(define-constant PROPOSAL_TYPE_UPGRADE u2)
(define-constant PROPOSAL_TYPE_EMERGENCY u3)

;; Proposal data structure
(define-map proposals
  uint
  {
    proposer: principal,
    title: (string-ascii 64),
    description: (string-ascii 256),
    proposal-type: uint,
    target-parameter: (optional (string-ascii 32)),
    new-value: (optional uint),
    created-at: uint,
    voting-ends-at: uint,
    execution-available-at: uint,
    yes-votes: uint,
    no-votes: uint,
    total-voting-power: uint,
    executed: bool,
    cancelled: bool,
  }
)

(define-data-var next-proposal-id uint u1)

;; Voting records
(define-map votes
  {
    proposal-id: uint,
    voter: principal,
  }
  {
    vote: bool,
    voting-power: uint,
    voted-at: uint,
  }
)

;; Voter reputation snapshots (taken at proposal creation)
(define-map voter-power
  {
    proposal-id: uint,
    voter: principal,
  }
  uint
)

;; Input validation helpers
(define-private (is-valid-principal (principal principal))
  (not (is-eq principal 'SP000000000000000000002Q6VF78))
)

(define-private (is-valid-string (str (string-ascii 64)))
  (and (> (len str) u0) (<= (len str) u64))
)

(define-private (is-valid-description (desc (string-ascii 256)))
  (and (> (len desc) u0) (<= (len desc) u256))
)

(define-private (is-owner)
  (is-eq tx-sender (var-get contract-owner))
)

;; Get user reputation from reputation contract
(define-private (get-user-reputation (user principal))
  (contract-call? .taskfi-reputation get-reputation user)
)

;; Administrative functions
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (asserts! (is-valid-principal new-owner) ERR_INVALID_INPUT)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

(define-public (activate-governance)
  (begin
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (var-set governance-active true)
    (ok true)
  )
)

(define-public (set-governance-parameters
    (min-rep-propose uint)
    (min-rep-vote uint)
    (voting-period-blocks uint)
    (execution-delay-blocks uint)
    (quorum uint)
    (approval uint)
  )
  (begin
    (asserts! (is-owner) ERR_UNAUTHORIZED)
    (asserts! (> min-rep-propose u0) ERR_INVALID_INPUT)
    (asserts! (> min-rep-vote u0) ERR_INVALID_INPUT)
    (asserts! (> voting-period-blocks u0) ERR_INVALID_INPUT)
    (asserts! (> execution-delay-blocks u0) ERR_INVALID_INPUT)
    (asserts! (and (> quorum u0) (<= quorum u100)) ERR_INVALID_INPUT)
    (asserts! (and (> approval u50) (<= approval u100)) ERR_INVALID_INPUT)

    (var-set min-reputation-to-propose min-rep-propose)
    (var-set min-reputation-to-vote min-rep-vote)
    (var-set voting-period voting-period-blocks)
    (var-set execution-delay execution-delay-blocks)
    (var-set quorum-threshold quorum)
    (var-set approval-threshold approval)
    (ok true)
  )
)

;; Proposal creation
(define-public (create-proposal
    (title (string-ascii 64))
    (description (string-ascii 256))
    (proposal-type uint)
    (target-parameter (optional (string-ascii 32)))
    (new-value (optional uint))
  )
  (let (
      (proposer-reputation (get-user-reputation tx-sender))
      (proposal-id (var-get next-proposal-id))
      (current-block stacks-block-height)
    )
    (begin
      (asserts! (var-get governance-active) ERR_UNAUTHORIZED)
      (asserts! (>= proposer-reputation (var-get min-reputation-to-propose))
        ERR_INSUFFICIENT_REPUTATION
      )
      (asserts! (is-valid-string title) ERR_INVALID_INPUT)
      (asserts! (is-valid-description description) ERR_INVALID_INPUT)
      (asserts!
        (or
          (is-eq proposal-type PROPOSAL_TYPE_PARAMETER)
          (is-eq proposal-type PROPOSAL_TYPE_UPGRADE)
          (is-eq proposal-type PROPOSAL_TYPE_EMERGENCY)
        )
        ERR_INVALID_INPUT
      )

      (map-set proposals proposal-id {
        proposer: tx-sender,
        title: title,
        description: description,
        proposal-type: proposal-type,
        target-parameter: target-parameter,
        new-value: new-value,
        created-at: current-block,
        voting-ends-at: (+ current-block (var-get voting-period)),
        execution-available-at: (+ current-block (var-get voting-period) (var-get execution-delay)),
        yes-votes: u0,
        no-votes: u0,
        total-voting-power: u0,
        executed: false,
        cancelled: false,
      })

      (var-set next-proposal-id (+ proposal-id u1))
      (ok proposal-id)
    )
  )
)

;; Voting on proposals
(define-public (vote-on-proposal
    (proposal-id uint)
    (vote bool)
  )
  (let (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND))
      (voter-reputation (get-user-reputation tx-sender))
      (current-block stacks-block-height)
    )
    (begin
      (asserts! (var-get governance-active) ERR_UNAUTHORIZED)
      (asserts! (>= voter-reputation (var-get min-reputation-to-vote))
        ERR_INSUFFICIENT_REPUTATION
      )
      (asserts! (<= current-block (get voting-ends-at proposal)) ERR_VOTING_ENDED)
      (asserts!
        (is-none (map-get? votes {
          proposal-id: proposal-id,
          voter: tx-sender,
        }))
        ERR_ALREADY_VOTED
      )
      (asserts! (not (get executed proposal)) ERR_PROPOSAL_EXECUTED)
      (asserts! (not (get cancelled proposal)) ERR_PROPOSAL_NOT_FOUND)

      ;; Record the vote
      (map-set votes {
        proposal-id: proposal-id,
        voter: tx-sender,
      } {
        vote: vote,
        voting-power: voter-reputation,
        voted-at: current-block,
      })

      ;; Update proposal vote counts
      (let ((updated-proposal (if vote
          (merge proposal {
            yes-votes: (+ (get yes-votes proposal) voter-reputation),
            total-voting-power: (+ (get total-voting-power proposal) voter-reputation),
          })
          (merge proposal {
            no-votes: (+ (get no-votes proposal) voter-reputation),
            total-voting-power: (+ (get total-voting-power proposal) voter-reputation),
          })
        )))
        (map-set proposals proposal-id updated-proposal)
      )

      (ok true)
    )
  )
)

;; Execute approved proposals
(define-public (execute-proposal (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (if (and
        (var-get governance-active)
        (>= stacks-block-height (get execution-available-at proposal))
        (not (get executed proposal))
        (not (get cancelled proposal))
      )
      ;; All basic checks passed
      (let (
          (total-reputation u10000)
          (quorum-met (>= (get total-voting-power proposal)
            (/ (* total-reputation (var-get quorum-threshold)) u100)
          ))
          (approval-met (>=
            (/ (* (get yes-votes proposal) u100)
              (get total-voting-power proposal)
            )
            (var-get approval-threshold)
          ))
        )
        (if (and quorum-met approval-met)
          (begin
            ;; Mark as executed
            (map-set proposals proposal-id (merge proposal { executed: true }))
            ;; Return success
            (ok true)
          )
          (err ERR_INVALID_INPUT)
        )
      )
      ;; Basic checks failed
      (if (not (var-get governance-active))
        (err ERR_UNAUTHORIZED)
        (if (< stacks-block-height (get execution-available-at proposal))
          (err ERR_VOTING_ACTIVE)
          (if (get executed proposal)
            (err ERR_PROPOSAL_EXECUTED)
            (err ERR_PROPOSAL_NOT_FOUND)
          )
        )
      )
    )
    (err ERR_PROPOSAL_NOT_FOUND)
  )
)

;; Execute parameter changes
(define-private (execute-parameter-change (proposal {
  proposer: principal,
  title: (string-ascii 64),
  description: (string-ascii 256),
  proposal-type: uint,
  target-parameter: (optional (string-ascii 32)),
  new-value: (optional uint),
  created-at: uint,
  voting-ends-at: uint,
  execution-available-at: uint,
  yes-votes: uint,
  no-votes: uint,
  total-voting-power: uint,
  executed: bool,
  cancelled: bool,
}))
  (match (get target-parameter proposal)
    param-name (match (get new-value proposal)
      new-val (begin
        ;; Handle different parameter types
        (if (is-eq param-name "min-reputation-to-propose")
          (var-set min-reputation-to-propose new-val)
          (if (is-eq param-name "min-reputation-to-vote")
            (var-set min-reputation-to-vote new-val)
            (if (is-eq param-name "voting-period")
              (var-set voting-period new-val)
              (if (is-eq param-name "quorum-threshold")
                (var-set quorum-threshold new-val)
                (var-set approval-threshold new-val)
              )
            )
          )
        )
        (ok true)
      )
      (err ERR_INVALID_INPUT)
    )
    (err ERR_INVALID_INPUT)
  )
)

;; Emergency functions (owner only)
(define-public (cancel-proposal (proposal-id uint))
  (let ((proposal (unwrap! (map-get? proposals proposal-id) ERR_PROPOSAL_NOT_FOUND)))
    (begin
      (asserts! (is-owner) ERR_UNAUTHORIZED)
      (asserts! (not (get executed proposal)) ERR_PROPOSAL_EXECUTED)
      (map-set proposals proposal-id (merge proposal { cancelled: true }))
      (ok true)
    )
  )
)

;; Read-only functions
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

(define-read-only (get-vote
    (proposal-id uint)
    (voter principal)
  )
  (map-get? votes {
    proposal-id: proposal-id,
    voter: voter,
  })
)

(define-read-only (get-governance-parameters)
  {
    min-reputation-to-propose: (var-get min-reputation-to-propose),
    min-reputation-to-vote: (var-get min-reputation-to-vote),
    voting-period: (var-get voting-period),
    execution-delay: (var-get execution-delay),
    quorum-threshold: (var-get quorum-threshold),
    approval-threshold: (var-get approval-threshold),
    governance-active: (var-get governance-active),
  }
)

(define-read-only (get-proposal-status (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (some (let ((current-block stacks-block-height))
      {
        voting-active: (and
          (<= current-block (get voting-ends-at proposal))
          (not (get executed proposal))
          (not (get cancelled proposal))
        ),
        can-execute: (and
          (>= current-block (get execution-available-at proposal))
          (not (get executed proposal))
          (not (get cancelled proposal))
        ),
        executed: (get executed proposal),
        cancelled: (get cancelled proposal),
      }
    ))
    none
  )
)

(define-read-only (get-next-proposal-id)
  (var-get next-proposal-id)
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-read-only (is-governance-active)
  (var-get governance-active)
)
