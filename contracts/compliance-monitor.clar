;; Compliance Monitor Contract
;; Monitors transactions for AML compliance and generates risk scores

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-REPORT-NOT-FOUND (err u501))
(define-constant ERR-INVALID-INPUT (err u502))
(define-constant ERR-WATCHLIST-EXISTS (err u503))

;; Risk Levels
(define-constant RISK-LOW u1)
(define-constant RISK-MEDIUM u2)
(define-constant RISK-HIGH u3)
(define-constant RISK-CRITICAL u4)

;; Data Variables
(define-data-var next-report-id uint u1)
(define-data-var next-alert-id uint u1)

;; Data Maps
(define-map compliance-reports
  { report-id: uint }
  {
    identity-id: uint,
    reporting-institution: principal,
    report-type: (string-ascii 30),
    risk-level: uint,
    description: (string-ascii 200),
    transaction-hash: (optional (buff 32)),
    amount: (optional uint),
    created-at: uint,
    status: (string-ascii 20),
    reviewed-by: (optional principal),
    reviewed-at: (optional uint)
  }
)

(define-map risk-scores
  { identity-id: uint }
  {
    current-score: uint,
    last-updated: uint,
    factors: (list 5 (string-ascii 30)),
    calculation-method: (string-ascii 50),
    updated-by: principal
  }
)

(define-map watchlist-entries
  { identity-id: uint }
  {
    reason: (string-ascii 100),
    added-by: principal,
    added-at: uint,
    severity: uint,
    status: (string-ascii 20),
    expires-at: (optional uint)
  }
)

(define-map suspicious-activities
  { alert-id: uint }
  {
    identity-id: uint,
    activity-type: (string-ascii 50),
    description: (string-ascii 200),
    risk-indicators: (list 3 (string-ascii 50)),
    detected-at: uint,
    auto-generated: bool,
    investigation-status: (string-ascii 20)
  }
)

(define-map compliance-metrics
  { institution: principal, date: uint }
  {
    reports-filed: uint,
    high-risk-customers: uint,
    alerts-generated: uint,
    investigations-completed: uint
  }
)

;; Private Functions
(define-private (is-valid-risk-level (risk-level uint))
  (and (>= risk-level RISK-LOW) (<= risk-level RISK-CRITICAL))
)

(define-private (calculate-risk-score (identity-id uint) (factors (list 5 (string-ascii 30))))
  ;; Simplified risk calculation based on factors
  (let
    (
      (base-score u50)
      (factor-count (len factors))
    )
    (if (> factor-count u0)
      (+ base-score (* factor-count u10))
      base-score
    )
  )
)

(define-private (get-today)
  (/ (unwrap-panic (get-block-info? time (- block-height u1))) u86400)
)

;; Public Functions

;; File compliance report
(define-public (file-compliance-report
  (identity-id uint)
  (report-type (string-ascii 30))
  (risk-level uint)
  (description (string-ascii 200))
  (transaction-hash (optional (buff 32)))
  (amount (optional uint)))
  (let
    (
      (report-id (var-get next-report-id))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (today (get-today))
    )
    (asserts! (is-valid-risk-level risk-level) ERR-INVALID-INPUT)
    (asserts! (> (len description) u0) ERR-INVALID-INPUT)

    (map-set compliance-reports
      { report-id: report-id }
      {
        identity-id: identity-id,
        reporting-institution: tx-sender,
        report-type: report-type,
        risk-level: risk-level,
        description: description,
        transaction-hash: transaction-hash,
        amount: amount,
        created-at: current-time,
        status: "pending",
        reviewed-by: none,
        reviewed-at: none
      }
    )

    ;; Update compliance metrics
    (match (map-get? compliance-metrics { institution: tx-sender, date: today })
      existing-metrics
      (map-set compliance-metrics
        { institution: tx-sender, date: today }
        (merge existing-metrics { reports-filed: (+ (get reports-filed existing-metrics) u1) })
      )
      (map-set compliance-metrics
        { institution: tx-sender, date: today }
        {
          reports-filed: u1,
          high-risk-customers: u0,
          alerts-generated: u0,
          investigations-completed: u0
        }
      )
    )

    (var-set next-report-id (+ report-id u1))
    (ok report-id)
  )
)

;; Update risk score
(define-public (update-risk-score (identity-id uint) (factors (list 5 (string-ascii 30))) (calculation-method (string-ascii 50)))
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (new-score (calculate-risk-score identity-id factors))
    )
    (asserts! (> (len factors) u0) ERR-INVALID-INPUT)
    (asserts! (> (len calculation-method) u0) ERR-INVALID-INPUT)

    (map-set risk-scores
      { identity-id: identity-id }
      {
        current-score: new-score,
        last-updated: current-time,
        factors: factors,
        calculation-method: calculation-method,
        updated-by: tx-sender
      }
    )

    (ok new-score)
  )
)

;; Add to watchlist
(define-public (add-to-watchlist (identity-id uint) (reason (string-ascii 100)) (severity uint) (duration (optional uint)))
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (expires-at (match duration
        some-duration (some (+ current-time some-duration))
        none
      ))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? watchlist-entries { identity-id: identity-id })) ERR-WATCHLIST-EXISTS)
    (asserts! (> (len reason) u0) ERR-INVALID-INPUT)
    (asserts! (<= severity u5) ERR-INVALID-INPUT)

    (map-set watchlist-entries
      { identity-id: identity-id }
      {
        reason: reason,
        added-by: tx-sender,
        added-at: current-time,
        severity: severity,
        status: "active",
        expires-at: expires-at
      }
    )

    (ok true)
  )
)

;; Generate suspicious activity alert
(define-public (generate-alert
  (identity-id uint)
  (activity-type (string-ascii 50))
  (description (string-ascii 200))
  (risk-indicators (list 3 (string-ascii 50))))
  (let
    (
      (alert-id (var-get next-alert-id))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (today (get-today))
    )
    (asserts! (> (len activity-type) u0) ERR-INVALID-INPUT)
    (asserts! (> (len description) u0) ERR-INVALID-INPUT)

    (map-set suspicious-activities
      { alert-id: alert-id }
      {
        identity-id: identity-id,
        activity-type: activity-type,
        description: description,
        risk-indicators: risk-indicators,
        detected-at: current-time,
        auto-generated: true,
        investigation-status: "pending"
      }
    )

    ;; Update compliance metrics
    (match (map-get? compliance-metrics { institution: tx-sender, date: today })
      existing-metrics
      (map-set compliance-metrics
        { institution: tx-sender, date: today }
        (merge existing-metrics { alerts-generated: (+ (get alerts-generated existing-metrics) u1) })
      )
      (map-set compliance-metrics
        { institution: tx-sender, date: today }
        {
          reports-filed: u0,
          high-risk-customers: u0,
          alerts-generated: u1,
          investigations-completed: u0
        }
      )
    )

    (var-set next-alert-id (+ alert-id u1))
    (ok alert-id)
  )
)

;; Review compliance report
(define-public (review-report (report-id uint) (approved bool))
  (let
    (
      (report (unwrap! (map-get? compliance-reports { report-id: report-id }) ERR-REPORT-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status report) "pending") ERR-INVALID-INPUT)

    (map-set compliance-reports
      { report-id: report-id }
      (merge report {
        status: (if approved "approved" "rejected"),
        reviewed-by: (some tx-sender),
        reviewed-at: (some current-time)
      })
    )

    (ok true)
  )
)

;; Update investigation status
(define-public (update-investigation-status (alert-id uint) (new-status (string-ascii 20)))
  (let
    (
      (alert (unwrap! (map-get? suspicious-activities { alert-id: alert-id }) ERR-REPORT-NOT-FOUND))
      (today (get-today))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len new-status) u0) ERR-INVALID-INPUT)

    (map-set suspicious-activities
      { alert-id: alert-id }
      (merge alert { investigation-status: new-status })
    )

    ;; Update metrics if investigation completed
    (if (is-eq new-status "completed")
      (match (map-get? compliance-metrics { institution: tx-sender, date: today })
        existing-metrics
        (map-set compliance-metrics
          { institution: tx-sender, date: today }
          (merge existing-metrics { investigations-completed: (+ (get investigations-completed existing-metrics) u1) })
        )
        (map-set compliance-metrics
          { institution: tx-sender, date: today }
          {
            reports-filed: u0,
            high-risk-customers: u0,
            alerts-generated: u0,
            investigations-completed: u1
          }
        )
      )
      true
    )

    (ok true)
  )
)

;; Read-only Functions

;; Get compliance report
(define-read-only (get-compliance-report (report-id uint))
  (map-get? compliance-reports { report-id: report-id })
)

;; Get risk score
(define-read-only (get-risk-score (identity-id uint))
  (map-get? risk-scores { identity-id: identity-id })
)

;; Check if on watchlist
(define-read-only (is-on-watchlist (identity-id uint))
  (match (map-get? watchlist-entries { identity-id: identity-id })
    watchlist-entry
    (let
      (
        (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      )
      (and
        (is-eq (get status watchlist-entry) "active")
        (match (get expires-at watchlist-entry)
          some-expiry (> some-expiry current-time)
          true
        )
      )
    )
    false
  )
)

;; Get suspicious activity alert
(define-read-only (get-suspicious-activity (alert-id uint))
  (map-get? suspicious-activities { alert-id: alert-id })
)

;; Get compliance metrics
(define-read-only (get-compliance-metrics (institution principal) (date uint))
  (map-get? compliance-metrics { institution: institution, date: date })
)

;; Get watchlist entry
(define-read-only (get-watchlist-entry (identity-id uint))
  (map-get? watchlist-entries { identity-id: identity-id })
)

;; Get next report ID
(define-read-only (get-next-report-id)
  (var-get next-report-id)
)

;; Get next alert ID
(define-read-only (get-next-alert-id)
  (var-get next-alert-id)
)
