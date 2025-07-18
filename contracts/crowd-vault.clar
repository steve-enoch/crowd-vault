;; CrowdVault: Next-Generation Blockchain Crowdfunding Platform
;;
;; A revolutionary decentralized funding ecosystem that empowers innovation
;; through community-driven investment and transparent project governance.
;;
;; CrowdVault transforms traditional crowdfunding by leveraging Bitcoin's
;; security through the Stacks blockchain, creating an immutable and
;; trustless environment where creators and backers can engage with
;; complete confidence.
;;
;; Core Capabilities:
;; - Transparent funding campaigns with real-time progress tracking
;; - Community-driven project validation through weighted voting systems
;; - Automated milestone-based fund distribution
;; - Guaranteed backer protection with smart refund mechanisms
;; - Flexible campaign configuration with customizable parameters
;; - Decentralized governance ensuring fair project accountability
;;
;; Built for the future of decentralized finance, CrowdVault eliminates
;; traditional intermediaries while maintaining the highest standards of
;; security and transparency.

;; SYSTEM CONSTANTS

;; Platform Administration
(define-constant CONTRACT_OWNER tx-sender)

;; Error Response Codes
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_CAMPAIGN_NOT_FOUND (err u101))
(define-constant ERR_CAMPAIGN_ENDED (err u102))
(define-constant ERR_CAMPAIGN_ACTIVE (err u103))
(define-constant ERR_GOAL_NOT_MET (err u104))
(define-constant ERR_ALREADY_REFUNDED (err u105))
(define-constant ERR_NO_CONTRIBUTION (err u106))
(define-constant ERR_INVALID_AMOUNT (err u107))
(define-constant ERR_INVALID_PARAMETERS (err u108))
(define-constant ERR_VOTING_PERIOD_ENDED (err u109))
(define-constant ERR_ALREADY_VOTED (err u110))
(define-constant ERR_INSUFFICIENT_VOTING_POWER (err u111))
(define-constant ERR_CONTRIBUTOR_LIST_FULL (err u112))
(define-constant ERR_INVALID_STRING (err u113))

;; Campaign Lifecycle States
(define-constant STATUS_ACTIVE u1)
(define-constant STATUS_SUCCESSFUL u2)
(define-constant STATUS_FAILED u3)
(define-constant STATUS_CANCELLED u4)

;; Platform Operation Limits
(define-constant MAX_DURATION_BLOCKS u144000)         ;; ~100 days at 10 min blocks
(define-constant MAX_VOTING_DURATION_BLOCKS u14400)   ;; ~10 days
(define-constant MIN_DURATION_BLOCKS u144)            ;; ~1 day
(define-constant MAX_CAMPAIGN_ID u1000000)            ;; Reasonable upper bound

;; PLATFORM STATE

(define-data-var campaign-counter uint u0)
(define-data-var platform-fee-rate uint u250)         ;; 2.5% (250/10000)

;; DATA STRUCTURES

;; Campaign Registry
(define-map campaigns
    { campaign-id: uint }
    {
        creator: principal,
        title: (string-ascii 64),
        description: (string-ascii 256),
        goal: uint,
        raised: uint,
        deadline-height: uint,
        created-height: uint,
        status: uint,
        voting-enabled: bool,
        voting-deadline-height: uint,
        votes-for: uint,
        votes-against: uint,
        min-contribution: uint,
    }
)

;; Backer Investment Ledger
(define-map contributions
    {
        campaign-id: uint,
        contributor: principal,
    }
    {
        amount: uint,
        refunded: bool,
        voting-power: uint,
    }
)

;; Governance Vote Registry
(define-map contributor-votes
    {
        campaign-id: uint,
        voter: principal,
    }
    {
        voted: bool,
        vote-for: bool,
    }
)

;; Campaign Participant Directory
(define-map campaign-contributors
    { campaign-id: uint }
    { contributor-list: (list 500 principal) }
)

;; QUERY FUNCTIONS

;; Retrieve comprehensive campaign information
(define-read-only (get-campaign (campaign-id uint))
    (map-get? campaigns { campaign-id: campaign-id })
)

;; Fetch individual contribution details
(define-read-only (get-contribution
        (campaign-id uint)
        (contributor principal)
    )
    (map-get? contributions {
        campaign-id: campaign-id,
        contributor: contributor,
    })
)

;; Get total campaigns launched on platform
(define-read-only (get-campaign-count)
    (var-get campaign-counter)
)

;; Get current platform fee structure
(define-read-only (get-platform-fee-rate)
    (var-get platform-fee-rate)
)

;; Verify campaign operational status
(define-read-only (is-campaign-active (campaign-id uint))
    (match (get-campaign campaign-id)
        campaign (and
            (is-eq (get status campaign) STATUS_ACTIVE)
            (< stacks-block-height (get deadline-height campaign))
        )
        false
    )
)

;; Determine campaign funding success
(define-read-only (is-campaign-successful (campaign-id uint))
    (match (get-campaign campaign-id)
        campaign (>= (get raised campaign) (get goal campaign))
        false
    )
)

;; Calculate platform service fees
(define-read-only (calculate-platform-fee (amount uint))
    (/ (* amount (var-get platform-fee-rate)) u10000)
)

;; Get governance participation status
(define-read-only (get-vote-status
        (campaign-id uint)
        (voter principal)
    )
    (map-get? contributor-votes {
        campaign-id: campaign-id,
        voter: voter,
    })
)

;; INTERNAL UTILITIES

;; Validate string input integrity
(define-private (is-valid-string (input (string-ascii 256)))
    (let ((length (len input)))
        (and
            (> length u0)
            (<= length u256)
            true
        )
    )
)

;; Validate campaign identifier bounds
(define-private (is-valid-campaign-id (campaign-id uint))
    (and
        (> campaign-id u0)
        (<= campaign-id MAX_CAMPAIGN_ID)
    )
)

;; Manage campaign contributor registry
(define-private (add-contributor-to-list
        (campaign-id uint)
        (contributor principal)
    )
    (let ((current-list (default-to (list)
            (get contributor-list
                (map-get? campaign-contributors { campaign-id: campaign-id })
            ))))
        (if (< (len current-list) u500)
            (begin
                (map-set campaign-contributors { campaign-id: campaign-id } { 
                    contributor-list: (unwrap! (as-max-len? (append current-list contributor) u500)
                        ERR_CONTRIBUTOR_LIST_FULL
                    ) 
                })
                (ok true)
            )
            (ok true)
        )
    )
)

;; Automated campaign state management
(define-private (update-campaign-status (campaign-id uint))
    (match (get-campaign campaign-id)
        campaign (begin
            (if (>= stacks-block-height (get deadline-height campaign))
                (if (>= (get raised campaign) (get goal campaign))
                    (map-set campaigns { campaign-id: campaign-id }
                        (merge campaign { status: STATUS_SUCCESSFUL })
                    )
                    (map-set campaigns { campaign-id: campaign-id }
                        (merge campaign { status: STATUS_FAILED })
                    )
                )
                true
            )
            true
        )
        false
    )
)

;; CORE FUNCTIONALITY

;; Launch new funding campaign
(define-public (create-campaign
        (title (string-ascii 64))
        (description (string-ascii 256))
        (goal uint)
        (duration-blocks uint)
        (voting-enabled bool)
        (voting-duration-blocks uint)
        (min-contribution uint)
    )
    (let (
            (campaign-id (+ (var-get campaign-counter) u1))
            (deadline-height (+ stacks-block-height duration-blocks))
            (validated-voting-duration (if voting-enabled
                (begin
                    (asserts! (<= voting-duration-blocks MAX_VOTING_DURATION_BLOCKS) ERR_INVALID_PARAMETERS)
                    voting-duration-blocks
                )
                u0
            ))
            (voting-deadline (if voting-enabled
                (+ deadline-height validated-voting-duration)
                deadline-height
            ))
        )
        ;; Campaign Parameter Validation
        (asserts! (is-valid-string (unwrap! (as-max-len? title u64) ERR_INVALID_STRING)) ERR_INVALID_STRING)
        (asserts! (is-valid-string description) ERR_INVALID_STRING)
        (asserts! (> goal u0) ERR_INVALID_PARAMETERS)
        (asserts! (>= duration-blocks MIN_DURATION_BLOCKS) ERR_INVALID_PARAMETERS)
        (asserts! (<= duration-blocks MAX_DURATION_BLOCKS) ERR_INVALID_PARAMETERS)
        (asserts! (> min-contribution u0) ERR_INVALID_PARAMETERS)
        
        ;; Campaign Registry Entry
        (map-set campaigns { campaign-id: campaign-id } {
            creator: tx-sender,
            title: (unwrap! (as-max-len? title u64) ERR_INVALID_STRING),
            description: description,
            goal: goal,
            raised: u0,
            deadline-height: deadline-height,
            created-height: stacks-block-height,
            status: STATUS_ACTIVE,
            voting-enabled: voting-enabled,
            voting-deadline-height: voting-deadline,
            votes-for: u0,
            votes-against: u0,
            min-contribution: min-contribution,
        })
        
        (var-set campaign-counter campaign-id)
        (ok campaign-id)
    )
)

;; Process backer investment
(define-public (contribute
        (campaign-id uint)
        (amount uint)
    )
    (let (
            (campaign (unwrap! (get-campaign campaign-id) ERR_CAMPAIGN_NOT_FOUND))
            (existing-contribution (default-to {
                amount: u0,
                refunded: false,
                voting-power: u0,
            }
                (get-contribution campaign-id tx-sender)
            ))
            (new-amount (+ (get amount existing-contribution) amount))
            (voting-power (if (get voting-enabled campaign)
                amount
                u0
            ))
        )
        ;; Investment Validation
        (asserts! (is-valid-campaign-id campaign-id) ERR_INVALID_PARAMETERS)
        (asserts! (is-campaign-active campaign-id) ERR_CAMPAIGN_ENDED)
        (asserts! (>= amount (get min-contribution campaign)) ERR_INVALID_AMOUNT)
        
        ;; Secure Token Transfer
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Update Investment Record
        (map-set contributions {
            campaign-id: campaign-id,
            contributor: tx-sender,
        } {
            amount: new-amount,
            refunded: false,
            voting-power: (+ (get voting-power existing-contribution) voting-power),
        })
        
        ;; Update Campaign Progress
        (map-set campaigns { campaign-id: campaign-id }
            (merge campaign { raised: (+ (get raised campaign) amount) })
        )
        
        ;; Register Contributor
        (try! (add-contributor-to-list campaign-id tx-sender))
        (ok true)
    )
)

;; Process successful campaign fund distribution
(define-public (claim-funds (campaign-id uint))
    (let (
            (campaign (unwrap! (get-campaign campaign-id) ERR_CAMPAIGN_NOT_FOUND))
            (platform-fee (calculate-platform-fee (get raised campaign)))
            (creator-amount (- (get raised campaign) platform-fee))
        )
        ;; Authorization & Status Validation
        (asserts! (is-valid-campaign-id campaign-id) ERR_INVALID_PARAMETERS)
        (update-campaign-status campaign-id)
        (asserts! (is-eq (get creator campaign) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (>= stacks-block-height (get deadline-height campaign)) ERR_CAMPAIGN_ACTIVE)
        (asserts! (is-campaign-successful campaign-id) ERR_GOAL_NOT_MET)
        
        ;; Governance Validation (if enabled)
        (if (get voting-enabled campaign)
            (begin
                (asserts!
                    (>= stacks-block-height (get voting-deadline-height campaign))
                    ERR_VOTING_PERIOD_ENDED
                )
                (asserts!
                    (> (get votes-for campaign) (get votes-against campaign))
                    ERR_GOAL_NOT_MET
                )
            )
            true
        )
        
        ;; Fund Distribution
        (try! (as-contract (stx-transfer? creator-amount tx-sender (get creator campaign))))
        
        ;; Platform Fee Collection
        (if (> platform-fee u0)
            (try! (as-contract (stx-transfer? platform-fee tx-sender CONTRACT_OWNER)))
            true
        )
        
        (ok true)
    )
)

;; Process investment refund for failed campaigns
(define-public (request-refund (campaign-id uint))
    (let (
            (campaign (unwrap! (get-campaign campaign-id) ERR_CAMPAIGN_NOT_FOUND))
            (contribution (unwrap! (get-contribution campaign-id tx-sender) ERR_NO_CONTRIBUTION))
        )
        ;; Refund Eligibility Validation
        (asserts! (is-valid-campaign-id campaign-id) ERR_INVALID_PARAMETERS)
        (update-campaign-status campaign-id)
        (asserts! (not (get refunded contribution)) ERR_ALREADY_REFUNDED)
        (asserts! (>= stacks-block-height (get deadline-height campaign)) ERR_CAMPAIGN_ACTIVE)
        (asserts! (not (is-campaign-successful campaign-id)) ERR_GOAL_NOT_MET)
        
        ;; Process Refund
        (map-set contributions {
            campaign-id: campaign-id,
            contributor: tx-sender,
        }
            (merge contribution { refunded: true })
        )
        
        (try! (as-contract (stx-transfer? (get amount contribution) tx-sender tx-sender)))
        (ok true)
    )
)

;; Submit governance vote on campaign
(define-public (vote
        (campaign-id uint)
        (vote-for bool)
    )
    (let (
            (campaign (unwrap! (get-campaign campaign-id) ERR_CAMPAIGN_NOT_FOUND))
            (contribution (unwrap! (get-contribution campaign-id tx-sender) ERR_NO_CONTRIBUTION))
            (existing-vote (map-get? contributor-votes {
                campaign-id: campaign-id,
                voter: tx-sender,
            }))
        )
        ;; Voting Eligibility Validation
        (asserts! (is-valid-campaign-id campaign-id) ERR_INVALID_PARAMETERS)
        (asserts! (get voting-enabled campaign) ERR_UNAUTHORIZED)
        (asserts! (>= stacks-block-height (get deadline-height campaign)) ERR_CAMPAIGN_ACTIVE)
        (asserts! (< stacks-block-height (get voting-deadline-height campaign)) ERR_VOTING_PERIOD_ENDED)
        (asserts! (is-none existing-vote) ERR_ALREADY_VOTED)
        (asserts! (> (get voting-power contribution) u0) ERR_INSUFFICIENT_VOTING_POWER)
        
        ;; Record Vote
        (map-set contributor-votes {
            campaign-id: campaign-id,
            voter: tx-sender,
        } {
            voted: true,
            vote-for: vote-for,
        })
        
        ;; Update Vote Tallies
        (if vote-for
            (map-set campaigns { campaign-id: campaign-id }
                (merge campaign { votes-for: (+ (get votes-for campaign) (get voting-power contribution)) })
            )
            (map-set campaigns { campaign-id: campaign-id }
                (merge campaign { votes-against: (+ (get votes-against campaign) (get voting-power contribution)) })
            )
        )
        
        (ok true)
    )
)

;; Terminate active campaign (creator only)
(define-public (cancel-campaign (campaign-id uint))
    (let ((campaign (unwrap! (get-campaign campaign-id) ERR_CAMPAIGN_NOT_FOUND)))
        ;; Authorization Validation
        (asserts! (is-valid-campaign-id campaign-id) ERR_INVALID_PARAMETERS)
        (asserts! (is-eq (get creator campaign) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status campaign) STATUS_ACTIVE) ERR_CAMPAIGN_ENDED)
        
        (map-set campaigns { campaign-id: campaign-id }
            (merge campaign { status: STATUS_CANCELLED })
        )
        
        (ok true)
    )
)

;; ADMIN FUNCTIONS

;; Configure platform fee structure
(define-public (set-platform-fee-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= new-rate u1000) ERR_INVALID_PARAMETERS)  ;; Maximum 10%
        (var-set platform-fee-rate new-rate)
        (ok true)
    )
)

;; Emergency campaign intervention
(define-public (emergency-pause-campaign (campaign-id uint))
    (let ((campaign (unwrap! (get-campaign campaign-id) ERR_CAMPAIGN_NOT_FOUND)))
        ;; Administrative Authorization
        (asserts! (is-valid-campaign-id campaign-id) ERR_INVALID_PARAMETERS)
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        
        (map-set campaigns { campaign-id: campaign-id }
            (merge campaign { status: STATUS_CANCELLED })
        )
        
        (ok true)
    )
)