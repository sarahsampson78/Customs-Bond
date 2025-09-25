;; Automated Customs Bonding Smart Contract
;; Manages customs bonds with automated release upon compliance verification

;; Error constants
(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-BOND-NOT-FOUND (err u101))
(define-constant ERR-BOND-ALREADY-EXISTS (err u102))
(define-constant ERR-INSUFFICIENT-BOND-AMOUNT (err u103))
(define-constant ERR-BOND-NOT-ACTIVE (err u104))
(define-constant ERR-BOND-ALREADY-RELEASED (err u105))
(define-constant ERR-BOND-ALREADY-FORFEITED (err u106))
(define-constant ERR-INVALID-COMPLIANCE-STATUS (err u107))
(define-constant ERR-COMPLIANCE-PERIOD-EXPIRED (err u108))
(define-constant ERR-INVALID-BOND-AMOUNT (err u109))
(define-constant ERR-TRANSFER-FAILED (err u110))
(define-constant ERR-INVALID-INPUT (err u111))
(define-constant ERR-ZERO-AMOUNT (err u112))

;; Contract owner for administrative functions
(define-constant CONTRACT-OWNER tx-sender)

;; Bond status constants
(define-constant STATUS-ACTIVE u1)
(define-constant STATUS-RELEASED u2)
(define-constant STATUS-FORFEITED u3)

;; Compliance status constants
(define-constant COMPLIANCE-PENDING u0)
(define-constant COMPLIANCE-VERIFIED u1)
(define-constant COMPLIANCE-FAILED u2)

;; Minimum bond amount (in microSTX)
(define-constant MIN-BOND-AMOUNT u1000000) ;; 1 STX minimum

;; Maximum bond amount (in microSTX) - prevent overflow attacks
(define-constant MAX-BOND-AMOUNT u1000000000000) ;; 1 million STX maximum

;; Maximum compliance deadline (blocks from current) - prevent far future deadlines
(define-constant MAX-COMPLIANCE-PERIOD u52560) ;; Approximately 1 year in blocks

;; Data structures
;; Main bond information structure containing all relevant bond details
(define-map bonds
  { bond-id: uint }
  {
    importer: principal,           ;; Address of the importer posting the bond
    bond-amount: uint,             ;; Amount of the customs bond in microSTX
    status: uint,                  ;; Current status of the bond (active/released/forfeited)
    created-at: uint,              ;; Block height when bond was created
    compliance-deadline: uint,     ;; Block height deadline for compliance verification
    compliance-status: uint,       ;; Current compliance verification status
    customs-declaration-hash: (buff 32), ;; Hash of customs declaration documents
    release-conditions: (string-utf8 500) ;; Text description of release conditions
  }
)

;; Mapping to track authorized customs officials who can verify compliance
(define-map authorized-officials
  { official: principal }
  { authorized: bool, added-at: uint }
)

;; Mapping to store compliance verification details
(define-map compliance-verifications
  { bond-id: uint }
  {
    verified-by: principal,       ;; Official who verified compliance
    verification-date: uint,      ;; Block height when verification occurred
    verification-notes: (string-utf8 500), ;; Additional verification notes
    documents-hash: (buff 32)     ;; Hash of compliance verification documents
  }
)

;; Counter for generating unique bond IDs
(define-data-var next-bond-id uint u1)

;; Total number of active bonds for tracking purposes
(define-data-var total-active-bonds uint u0)

;; Input validation functions
(define-private (is-valid-principal (p principal))
  (not (is-eq p 'SP000000000000000000002Q6VF78))
)

(define-private (is-valid-bond-amount (amount uint))
  (and (>= amount MIN-BOND-AMOUNT) (<= amount MAX-BOND-AMOUNT))
)

(define-private (is-valid-compliance-deadline (deadline uint))
  (and (> deadline block-height) 
       (<= (- deadline block-height) MAX-COMPLIANCE-PERIOD))
)

(define-private (is-valid-compliance-status (status uint))
  (or (is-eq status COMPLIANCE-VERIFIED) (is-eq status COMPLIANCE-FAILED))
)

(define-private (is-non-zero-hash (hash (buff 32)))
  (not (is-eq hash 0x0000000000000000000000000000000000000000000000000000000000000000))
)

(define-private (is-valid-string (str (string-utf8 500)))
  (> (len str) u0)
)

;; Administrative function to authorize customs officials
;; Only contract owner can authorize officials to verify compliance
(define-public (authorize-official (official principal))
  (begin
    ;; Verify caller is contract owner
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Validate input principal
    (asserts! (is-valid-principal official) ERR-INVALID-INPUT)
    
    ;; Add official to authorized list with current block height
    (map-set authorized-officials 
      { official: official }
      { authorized: true, added-at: block-height }
    )
    
    (ok true)
  )
)

;; Administrative function to revoke authorization from customs officials
(define-public (revoke-official-authorization (official principal))
  (begin
    ;; Verify caller is contract owner
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Validate input principal
    (asserts! (is-valid-principal official) ERR-INVALID-INPUT)
    
    ;; Verify official is currently authorized
    (asserts! (is-authorized-official official) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Remove official from authorized list
    (map-delete authorized-officials { official: official })
    
    (ok true)
  )
)

;; Core function to create a new customs bond
;; Importer posts a bond with specified amount and compliance requirements
(define-public (create-bond 
  (bond-amount uint)
  (compliance-deadline uint)
  (customs-declaration-hash (buff 32))
  (release-conditions (string-utf8 500))
)
  (let
    (
      ;; Get current bond ID and increment for next use
      (bond-id (var-get next-bond-id))
    )
    
    ;; Validate all inputs
    (asserts! (is-valid-bond-amount bond-amount) ERR-INVALID-BOND-AMOUNT)
    (asserts! (is-valid-compliance-deadline compliance-deadline) ERR-COMPLIANCE-PERIOD-EXPIRED)
    (asserts! (is-non-zero-hash customs-declaration-hash) ERR-INVALID-INPUT)
    (asserts! (is-valid-string release-conditions) ERR-INVALID-INPUT)
    
    ;; Verify bond doesn't already exist
    (asserts! (is-none (map-get? bonds { bond-id: bond-id })) ERR-BOND-ALREADY-EXISTS)
    
    ;; Transfer bond amount from importer to contract
    (try! (stx-transfer? bond-amount tx-sender (as-contract tx-sender)))
    
    ;; Create new bond record with all required information
    (map-set bonds
      { bond-id: bond-id }
      {
        importer: tx-sender,
        bond-amount: bond-amount,
        status: STATUS-ACTIVE,
        created-at: block-height,
        compliance-deadline: compliance-deadline,
        compliance-status: COMPLIANCE-PENDING,
        customs-declaration-hash: customs-declaration-hash,
        release-conditions: release-conditions
      }
    )
    
    ;; Increment bond ID counter and active bonds counter
    (var-set next-bond-id (+ bond-id u1))
    (var-set total-active-bonds (+ (var-get total-active-bonds) u1))
    
    (ok bond-id)
  )
)

;; Function for authorized officials to verify compliance
;; Officials can mark bonds as compliant or non-compliant
(define-public (verify-compliance 
  (bond-id uint)
  (compliance-result uint)
  (verification-notes (string-utf8 500))
  (documents-hash (buff 32))
)
  (let
    (
      ;; Retrieve bond information
      (bond-info (unwrap! (map-get? bonds { bond-id: bond-id }) ERR-BOND-NOT-FOUND))
    )
    
    ;; Validate inputs
    (asserts! (> bond-id u0) ERR-INVALID-INPUT)
    (asserts! (is-valid-compliance-status compliance-result) ERR-INVALID-COMPLIANCE-STATUS)
    (asserts! (is-valid-string verification-notes) ERR-INVALID-INPUT)
    (asserts! (is-non-zero-hash documents-hash) ERR-INVALID-INPUT)
    
    ;; Verify caller is authorized official
    (asserts! (is-authorized-official tx-sender) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Ensure bond is currently active
    (asserts! (is-eq (get status bond-info) STATUS-ACTIVE) ERR-BOND-NOT-ACTIVE)
    
    ;; Check compliance deadline hasn't expired
    (asserts! (<= block-height (get compliance-deadline bond-info)) ERR-COMPLIANCE-PERIOD-EXPIRED)
    
    ;; Update bond with compliance verification result
    (map-set bonds
      { bond-id: bond-id }
      (merge bond-info { compliance-status: compliance-result })
    )
    
    ;; Record detailed verification information
    (map-set compliance-verifications
      { bond-id: bond-id }
      {
        verified-by: tx-sender,
        verification-date: block-height,
        verification-notes: verification-notes,
        documents-hash: documents-hash
      }
    )
    
    ;; Automatically process bond based on compliance result
    (if (is-eq compliance-result COMPLIANCE-VERIFIED)
      ;; If compliant, automatically release the bond
      (try! (release-bond bond-id))
      ;; If non-compliant, automatically forfeit the bond
      (try! (forfeit-bond bond-id))
    )
    
    (ok true)
  )
)

;; Internal function to release bond funds back to importer
;; Called automatically when compliance is verified
(define-private (release-bond (bond-id uint))
  (let
    (
      ;; Get bond information
      (bond-info (unwrap! (map-get? bonds { bond-id: bond-id }) ERR-BOND-NOT-FOUND))
    )
    
    ;; Verify bond is active and compliance is verified
    (asserts! (is-eq (get status bond-info) STATUS-ACTIVE) ERR-BOND-NOT-ACTIVE)
    (asserts! (is-eq (get compliance-status bond-info) COMPLIANCE-VERIFIED) ERR-INVALID-COMPLIANCE-STATUS)
    
    ;; Update bond status to released
    (map-set bonds
      { bond-id: bond-id }
      (merge bond-info { status: STATUS-RELEASED })
    )
    
    ;; Transfer bond amount back to importer
    (try! (as-contract (stx-transfer? (get bond-amount bond-info) tx-sender (get importer bond-info))))
    
    ;; Decrease active bonds counter
    (var-set total-active-bonds (- (var-get total-active-bonds) u1))
    
    (ok true)
  )
)

;; Internal function to forfeit bond funds
;; Called automatically when compliance verification fails
(define-private (forfeit-bond (bond-id uint))
  (let
    (
      ;; Get bond information
      (bond-info (unwrap! (map-get? bonds { bond-id: bond-id }) ERR-BOND-NOT-FOUND))
    )
    
    ;; Verify bond is active and compliance failed
    (asserts! (is-eq (get status bond-info) STATUS-ACTIVE) ERR-BOND-NOT-ACTIVE)
    (asserts! (is-eq (get compliance-status bond-info) COMPLIANCE-FAILED) ERR-INVALID-COMPLIANCE-STATUS)
    
    ;; Update bond status to forfeited
    (map-set bonds
      { bond-id: bond-id }
      (merge bond-info { status: STATUS-FORFEITED })
    )
    
    ;; Bond funds remain in contract (forfeited to customs authority)
    ;; Decrease active bonds counter
    (var-set total-active-bonds (- (var-get total-active-bonds) u1))
    
    (ok true)
  )
)

;; Administrative function to handle expired bonds
;; Contract owner can forfeit bonds that exceed compliance deadline
(define-public (process-expired-bond (bond-id uint))
  (let
    (
      ;; Get bond information
      (bond-info (unwrap! (map-get? bonds { bond-id: bond-id }) ERR-BOND-NOT-FOUND))
    )
    
    ;; Validate input
    (asserts! (> bond-id u0) ERR-INVALID-INPUT)
    
    ;; Verify caller is authorized (contract owner or authorized official)
    (asserts! 
      (or (is-eq tx-sender CONTRACT-OWNER)
          (is-authorized-official tx-sender))
      ERR-UNAUTHORIZED-ACCESS
    )
    
    ;; Verify bond is active and past compliance deadline
    (asserts! (is-eq (get status bond-info) STATUS-ACTIVE) ERR-BOND-NOT-ACTIVE)
    (asserts! (> block-height (get compliance-deadline bond-info)) ERR-COMPLIANCE-PERIOD-EXPIRED)
    
    ;; Mark compliance as failed and forfeit the bond
    (map-set bonds
      { bond-id: bond-id }
      (merge bond-info { 
        compliance-status: COMPLIANCE-FAILED,
        status: STATUS-FORFEITED 
      })
    )
    
    ;; Decrease active bonds counter
    (var-set total-active-bonds (- (var-get total-active-bonds) u1))
    
    (ok true)
  )
)

;; Administrative function for contract owner to withdraw forfeited funds
;; Allows customs authority to claim forfeited bond amounts
(define-public (withdraw-forfeited-funds (amount uint))
  (let
    (
      (contract-balance (stx-get-balance (as-contract tx-sender)))
    )
    
    ;; Validate input
    (asserts! (> amount u0) ERR-ZERO-AMOUNT)
    (asserts! (<= amount contract-balance) ERR-INSUFFICIENT-BOND-AMOUNT)
    
    ;; Only contract owner can withdraw forfeited funds
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED-ACCESS)
    
    ;; Transfer specified amount to contract owner
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT-OWNER)))
    
    (ok true)
  )
)

;; Read-only function to get complete bond information
(define-read-only (get-bond-info (bond-id uint))
  (begin
    ;; Validate input
    (asserts! (> bond-id u0) ERR-INVALID-INPUT)
    (ok (map-get? bonds { bond-id: bond-id }))
  )
)

;; Read-only function to get compliance verification details
(define-read-only (get-compliance-verification (bond-id uint))
  (begin
    ;; Validate input
    (asserts! (> bond-id u0) ERR-INVALID-INPUT)
    (ok (map-get? compliance-verifications { bond-id: bond-id }))
  )
)

;; Read-only function to check if an official is authorized
(define-read-only (is-authorized-official (official principal))
  (default-to false (get authorized (map-get? authorized-officials { official: official })))
)

;; Read-only function to get current total of active bonds
(define-read-only (get-total-active-bonds)
  (var-get total-active-bonds)
)

;; Read-only function to get the next bond ID that will be assigned
(define-read-only (get-next-bond-id)
  (var-get next-bond-id)
)

;; Read-only function to get contract balance (total forfeited funds available)
(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender))
)

;; Read-only function to check if a bond has expired
(define-read-only (is-bond-expired (bond-id uint))
  (begin
    ;; Validate input
    (asserts! (> bond-id u0) ERR-INVALID-INPUT)
    (ok 
      (match (map-get? bonds { bond-id: bond-id })
        bond-info 
        (and 
          (is-eq (get status bond-info) STATUS-ACTIVE)
          (> block-height (get compliance-deadline bond-info))
        )
        false
      )
    )
  )
)