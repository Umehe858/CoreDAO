;; CoreDAO Governance Contract - Comprehensive Decentralized Governance System

;; Error Constants
(define-constant ERROR-UNAUTHORIZED (err u100))
(define-constant ERROR-PROPOSAL-EXISTS (err u101))
(define-constant ERROR-PROPOSAL-NOT-FOUND (err u102))
(define-constant ERROR-ALREADY-VOTED (err u103))
(define-constant ERROR-PROPOSAL-CONCLUDED (err u104))
(define-constant ERROR-INSUFFICIENT-TOKENS (err u105))
(define-constant ERROR-INVALID-TITLE (err u106))
(define-constant ERROR-INVALID-DESCRIPTION (err u107))
(define-constant ERROR-INVALID-AMOUNT (err u108))
(define-constant ERROR-INVALID-BENEFICIARY (err u109))
(define-constant ERROR-PROPOSAL-INACTIVE (err u110))
(define-constant ERROR-PROPOSAL-ONGOING (err u111))
(define-constant ERROR-INVALID-VOTE-AMOUNT (err u112))
(define-constant ERROR-INSUFFICIENT-VOTING-POWER (err u113))
(define-constant ERROR-TREASURY-UNDERFUNDED (err u114))
(define-constant ERROR-PROPOSAL-EXECUTED (err u115))
(define-constant ERROR-SELF-DELEGATION (err u116))
(define-constant ERROR-INVALID-QUORUM (err u117))
(define-constant ERROR-INVALID-METADATA (err u118))

;; Configuration Variables with Administrative Controls
(define-data-var governance-admin principal tx-sender)
(define-data-var min-proposal-stake uint u100000000) ;; 100 STX minimum
(define-data-var voting-duration uint u144) ;; ~24 hours in blocks
(define-data-var quorum-requirement uint u500000000000) ;; 500 STX minimum total votes
(define-data-var proposal-creation-enabled bool true)
(define-data-var voting-system-active bool true)
(define-data-var min-voting-delay uint u10) ;; Minimum blocks before voting starts
(define-data-var max-voting-delay uint u100) ;; Maximum blocks before voting starts

;; Enhanced Proposal Structure
(define-map proposals
    {proposal-id: uint}
    {
        creator: principal,
        title: (string-utf8 256),
        description: (string-utf8 1024),
        requested-amount: uint,
        beneficiary: principal,
        voting-start-height: uint,
        voting-end-height: uint,
        yes-votes: uint,
        no-votes: uint,
        executed: bool,
        cancelled: bool,
        execution-delay: uint,
        last-updated: uint,
        metadata: (optional (string-utf8 1024))
    }
)

;; Enhanced Voting System
(define-map votes
    {proposal-id: uint, voter: principal}
    {
        amount: uint,
        support: bool,
        voting-power: uint,
        timestamp: uint,
        delegate: (optional principal)
    }
)

;; Enhanced Delegation System
(define-map delegation-registry
    {delegator: principal}
    {
        delegate: principal,
        voting-power: uint,
        last-updated: uint,
        can-revoke: bool
    }
)

;; Voter Activity Tracking
(define-map voter-activity
    principal
    {
        total-votes: uint,
        proposals-voted: (list 50 uint)  ;; Store last 50 proposals voted on
    }
)

;; State Variables
(define-data-var proposal-counter uint u0)
(define-data-var dao-treasury uint u0)
(define-data-var total-voting-power uint u0)

;; Governance Token
(define-fungible-token nexus-token)

;; Access Control Functions
(define-private (is-governance-admin)
    (is-eq tx-sender (var-get governance-admin))
)

(define-private (is-authorized-creator (sender principal))
    (and 
        (var-get proposal-creation-enabled)
        (>= (ft-get-balance nexus-token sender) (var-get min-proposal-stake))
    )
)

;; Voter Activity Functions
(define-private (get-voter-participation-count (voter principal))
    (match (map-get? voter-activity voter)
        activity-info (get total-votes activity-info)
        u0
    )
)

(define-private (update-voter-activity (voter principal) (proposal-id uint))
    (let (
        (current-activity (default-to 
            {total-votes: u0, proposals-voted: (list)}
            (map-get? voter-activity voter)
        ))
    )
        (map-set voter-activity
            voter
            {
                total-votes: (+ (get total-votes current-activity) u1),
                proposals-voted: (unwrap-panic (as-max-len? 
                    (append (get proposals-voted current-activity) proposal-id)
                    u50))
            }
        )
    )
)

;; Enhanced Read-only Functions
(define-read-only (get-proposal-info (proposal-id uint))
    (match (map-get? proposals {proposal-id: proposal-id})
        proposal (ok {
            proposal: proposal,
            quorum-met: (>= (+ (get yes-votes proposal) (get no-votes proposal)) (var-get quorum-requirement)),
            vote-margin: (- (get yes-votes proposal) (get no-votes proposal)),
            can-execute: (and 
                (>= (+ (get yes-votes proposal) (get no-votes proposal)) (var-get quorum-requirement))
                (> (get yes-votes proposal) (get no-votes proposal))
                (not (get executed proposal))
                (not (get cancelled proposal))
                (>= block-height (get voting-end-height proposal))
            )
        })
        ERROR-PROPOSAL-NOT-FOUND
    )
)

(define-read-only (get-voter-info (voter principal))
    (ok {
        voting-power: (ft-get-balance nexus-token voter),
        delegation: (map-get? delegation-registry {delegator: voter}),
        total-votes-cast: (get-voter-participation-count voter)
    })
)

;; Enhanced Helper Functions
(define-private (validate-proposal-params 
    (title (string-utf8 256))
    (description (string-utf8 1024))
    (requested-amount uint)
    (beneficiary principal)
)
    (and
        (is-valid-title title)
        (is-valid-description description)
        (is-valid-amount requested-amount)
        (is-valid-beneficiary beneficiary)
        (>= (var-get dao-treasury) requested-amount)
    )
)

(define-private (process-vote 
    (proposal-id uint)
    (voter principal)
    (amount uint)
    (support bool)
)
    (match (map-get? proposals {proposal-id: proposal-id})
        proposal (let (
            (voting-power (ft-get-balance nexus-token voter))
        )
            (asserts! (>= voting-power amount) ERROR-INSUFFICIENT-VOTING-POWER)
            (asserts! (not (get executed proposal)) ERROR-PROPOSAL-EXECUTED)
            (asserts! (not (get cancelled proposal)) ERROR-PROPOSAL-INACTIVE)
            (ok {
                voting-power: voting-power,
                amount: amount,
                support: support,
                timestamp: block-height
            }))
        ERROR-PROPOSAL-NOT-FOUND
    )
)

;; Input Validation Functions
(define-private (is-valid-title (title (string-utf8 256)))
    (and (>= (len title) u1) (<= (len title) u256))
)

(define-private (is-valid-description (description (string-utf8 1024)))
    (and (>= (len description) u1) (<= (len description) u1024))
)

(define-private (is-valid-amount (amount uint))
    (> amount u0)
)

(define-private (is-valid-beneficiary (beneficiary principal))
    (not (is-eq beneficiary (as-contract tx-sender)))
)

(define-private (is-valid-metadata (metadata (optional (string-utf8 1024))))
    (match metadata
        value (and (>= (len value) u1) (<= (len value) u1024))
        true
    )
)

;; Enhanced Public Functions
(define-public (create-proposal (title (string-utf8 256)) 
                               (description (string-utf8 1024)) 
                               (requested-amount uint) 
                               (beneficiary principal)
                               (execution-delay uint)
                               (metadata (optional (string-utf8 1024))))
    (let (
        (proposal-id (+ (var-get proposal-counter) u1))
        (voting-start-height (+ block-height (var-get min-voting-delay)))
        (voting-end-height (+ voting-start-height (var-get voting-duration)))
    )
        (asserts! (is-authorized-creator tx-sender) ERROR-UNAUTHORIZED)
        (asserts! (validate-proposal-params title description requested-amount beneficiary) ERROR-INVALID-AMOUNT)
        (asserts! (<= execution-delay (var-get max-voting-delay)) ERROR-INVALID-AMOUNT)
        (asserts! (is-valid-metadata metadata) ERROR-INVALID-METADATA)
        
        (map-set proposals
            {proposal-id: proposal-id}
            {
                creator: tx-sender,
                title: title,
                description: description,
                requested-amount: requested-amount,
                beneficiary: beneficiary,
                voting-start-height: voting-start-height,
                voting-end-height: voting-end-height,
                yes-votes: u0,
                no-votes: u0,
                executed: false,
                cancelled: false,
                execution-delay: execution-delay,
                last-updated: block-height,
                metadata: metadata
            }
        )
        (var-set proposal-counter proposal-id)
        (ok proposal-id)
    )
)

(define-public (cast-vote (proposal-id uint) (amount uint) (support bool))
    (let (
        (vote-info (try! (process-vote proposal-id tx-sender amount support)))
        (proposal (unwrap! (map-get? proposals {proposal-id: proposal-id}) ERROR-PROPOSAL-NOT-FOUND))
    )
        (asserts! (var-get voting-system-active) ERROR-UNAUTHORIZED)
        (asserts! (>= block-height (get voting-start-height proposal)) ERROR-PROPOSAL-INACTIVE)
        (asserts! (< block-height (get voting-end-height proposal)) ERROR-PROPOSAL-CONCLUDED)
        (asserts! (is-none (map-get? votes {proposal-id: proposal-id, voter: tx-sender})) ERROR-ALREADY-VOTED)
        
        (map-set votes
            {proposal-id: proposal-id, voter: tx-sender}
            {
                amount: amount,
                support: support,
                voting-power: (get voting-power vote-info),
                timestamp: block-height,
                delegate: none
            }
        )
        
        (map-set proposals
            {proposal-id: proposal-id}
            (merge proposal {
                yes-votes: (if support (+ (get yes-votes proposal) amount) (get yes-votes proposal)),
                no-votes: (if support (get no-votes proposal) (+ (get no-votes proposal) amount)),
                last-updated: block-height
            })
        )
        
        (update-voter-activity tx-sender proposal-id)
        (ok true)
    )
)

(define-public (delegate-voting-power (delegate principal) (voting-power uint))
    (begin
        (asserts! (not (is-eq tx-sender delegate)) ERROR-SELF-DELEGATION)
        (asserts! (>= (ft-get-balance nexus-token tx-sender) voting-power) ERROR-INSUFFICIENT-VOTING-POWER)
        (asserts! (is-valid-beneficiary delegate) ERROR-INVALID-BENEFICIARY)
        
        (map-set delegation-registry
            {delegator: tx-sender}
            {
                delegate: delegate,
                voting-power: voting-power,
                last-updated: block-height,
                can-revoke: true
            }
        )
        (ok true)
    )
)

(define-public (revoke-delegation)
    (begin
        (asserts! (is-some (map-get? delegation-registry {delegator: tx-sender})) ERROR-PROPOSAL-NOT-FOUND)
        (map-delete delegation-registry {delegator: tx-sender})
        (ok true)
    )
)

(define-public (execute-proposal (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? proposals {proposal-id: proposal-id}) ERROR-PROPOSAL-NOT-FOUND))
        (total-votes (+ (get yes-votes proposal) (get no-votes proposal)))
    )
        (asserts! (>= total-votes (var-get quorum-requirement)) ERROR-INVALID-QUORUM)
        (asserts! (> (get yes-votes proposal) (get no-votes proposal)) ERROR-PROPOSAL-CONCLUDED)
        (asserts! (not (get executed proposal)) ERROR-PROPOSAL-EXECUTED)
        (asserts! (not (get cancelled proposal)) ERROR-PROPOSAL-INACTIVE)
        (asserts! (>= block-height (+ (get voting-end-height proposal) (get execution-delay proposal))) ERROR-PROPOSAL-ONGOING)
        
        (try! (stx-transfer? (get requested-amount proposal) (as-contract tx-sender) (get beneficiary proposal)))
        (var-set dao-treasury (- (var-get dao-treasury) (get requested-amount proposal)))
        
        (map-set proposals
            {proposal-id: proposal-id}
            (merge proposal {
                executed: true,
                last-updated: block-height
            })
        )
        (ok true)
    )
)

;; Administrative Functions
(define-public (set-governance-admin (new-admin principal))
    (begin
        (asserts! (is-governance-admin) ERROR-UNAUTHORIZED)
        (asserts! (is-valid-beneficiary new-admin) ERROR-INVALID-BENEFICIARY)
        (ok (var-set governance-admin new-admin))
    )
)

(define-public (update-governance-parameters
    (new-min-proposal-stake uint)
    (new-voting-duration uint)
    (new-quorum-requirement uint))
    (begin
        (asserts! (is-governance-admin) ERROR-UNAUTHORIZED)
        (asserts! (> new-quorum-requirement u0) ERROR-INVALID-QUORUM)
        (asserts! (> new-min-proposal-stake u0) ERROR-INVALID-AMOUNT)
        (asserts! (> new-voting-duration u0) ERROR-INVALID-AMOUNT)
        (var-set min-proposal-stake new-min-proposal-stake)
        (var-set voting-duration new-voting-duration)
        (var-set quorum-requirement new-quorum-requirement)
        (ok true)
    )
)

(define-public (toggle-proposal-creation (enabled bool))
    (begin
        (asserts! (is-governance-admin) ERROR-UNAUTHORIZED)
        (ok (var-set proposal-creation-enabled enabled))
    )
)

(define-public (toggle-voting-system (active bool))
    (begin
        (asserts! (is-governance-admin) ERROR-UNAUTHORIZED)
        (ok (var-set voting-system-active active))
    )
)

(define-public (cancel-proposal (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? proposals {proposal-id: proposal-id}) ERROR-PROPOSAL-NOT-FOUND))
    )
        (asserts! (or (is-governance-admin) (is-eq tx-sender (get creator proposal))) ERROR-UNAUTHORIZED)
        (asserts! (not (get executed proposal)) ERROR-PROPOSAL-EXECUTED)
        (asserts! (not (get cancelled proposal)) ERROR-PROPOSAL-INACTIVE)
        
        (map-set proposals
            {proposal-id: proposal-id}
            (merge proposal {
                cancelled: true,
                last-updated: block-height
            })
        )
        (ok true)
    )
)

;; Treasury Management
(define-public (deposit-to-treasury (amount uint))
    (begin
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set dao-treasury (+ (var-get dao-treasury) amount))
        (ok true)
    )
)

;; Token Management
(define-public (mint-tokens (recipient principal) (amount uint))
    (begin
        (asserts! (is-governance-admin) ERROR-UNAUTHORIZED)
        (try! (ft-mint? nexus-token amount recipient))
        (var-set total-voting-power (+ (var-get total-voting-power) amount))
        (ok true)
    )
)

(define-public (burn-tokens (amount uint))
    (begin
        (try! (ft-burn? nexus-token amount tx-sender))
        (var-set total-voting-power (- (var-get total-voting-power) amount))
        (ok true)
    )
)

;; Additional Read-only Functions
(define-read-only (get-dao-stats)
    (ok {
        total-proposals: (var-get proposal-counter),
        treasury-balance: (var-get dao-treasury),
        total-voting-power: (var-get total-voting-power),
        governance-admin: (var-get governance-admin),
        proposal-creation-enabled: (var-get proposal-creation-enabled),
        voting-system-active: (var-get voting-system-active)
    })
)

(define-read-only (get-governance-config)
    (ok {
        min-proposal-stake: (var-get min-proposal-stake),
        voting-duration: (var-get voting-duration),
        quorum-requirement: (var-get quorum-requirement),
        min-voting-delay: (var-get min-voting-delay),
        max-voting-delay: (var-get max-voting-delay)
    })
)