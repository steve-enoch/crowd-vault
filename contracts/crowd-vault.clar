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