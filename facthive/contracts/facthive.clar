;; Community-Driven News and Fact-Checking Platform
;; Clarity Smart Contracts for Stacks Blockchain

;; ==============================================
;; CONSTANTS AND ERROR CODES
;; ==============================================

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ARTICLE-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-VOTED (err u102))
(define-constant ERR-INSUFFICIENT-REPUTATION (err u103))
(define-constant ERR-INVALID-STATUS (err u104))
(define-constant ERR-FACT-CHECK-NOT-FOUND (err u105))
(define-constant ERR-ALREADY-FACT-CHECKED (err u106))

;; Minimum reputation required for different actions
(define-constant MIN-REP-SUBMIT u10)
(define-constant MIN-REP-FACT-CHECK u50)
(define-constant MIN-REP-MODERATE u100)

;; ==============================================
;; DATA STRUCTURES
;; ==============================================

;; Article structure
(define-map articles
  { article-id: uint }
  {
    title: (string-ascii 200),
    content-hash: (buff 32),
    author: principal,
    timestamp: uint,
    status: (string-ascii 20),
    credibility-votes: uint,
    questionable-votes: uint,
    false-votes: uint,
    total-votes: uint,
    fact-check-count: uint,
    sources-hash: (buff 32)
  })

;; User reputation and profile
(define-map users
  { user: principal }
  {
    reputation: uint,
    articles-submitted: uint,
    fact-checks-completed: uint,
    votes-cast: uint,
    join-date: uint,
    is-verified: bool
  })

;; Fact-check records
(define-map fact-checks
  { check-id: uint }
  {
    article-id: uint,
    checker: principal,
    findings-hash: (buff 32),
    credibility-rating: uint,
    sources-verified: uint,
    timestamp: uint,
    status: (string-ascii 20),
    community-rating: uint
  })

;; Vote tracking to prevent double voting
(define-map article-votes
  { article-id: uint, voter: principal }
  { vote-type: (string-ascii 15), timestamp: uint })

;; Fact-check votes
(define-map fact-check-votes
  { check-id: uint, voter: principal }
  { rating: uint, timestamp: uint })

;; ==============================================
;; COUNTERS
;; ==============================================

(define-data-var next-article-id uint u1)
(define-data-var next-check-id uint u1)
(define-data-var total-articles uint u0)
(define-data-var platform-reputation uint u0)

;; ==============================================
;; PRIVATE FUNCTIONS
;; ==============================================

(define-private (get-user-reputation (user principal))
  (default-to u0 
    (get reputation (map-get? users { user: user }))))

(define-private (increment-user-reputation (user principal) (amount uint))
  (let ((current-rep (get-user-reputation user)))
    (map-set users
      { user: user }
      (merge 
        (default-to 
          { reputation: u0, articles-submitted: u0, fact-checks-completed: u0, 
            votes-cast: u0, join-date: stacks-block-height, is-verified: false }
          (map-get? users { user: user }))
        { reputation: (+ current-rep amount) }))))

(define-private (calculate-credibility-score (credible uint) (questionable uint) (false-votes uint))
  (let ((total (+ credible (+ questionable false-votes))))
    (if (> total u0)
      (/ (* credible u100) total)
      u50)))

;; ==============================================
;; PUBLIC FUNCTIONS - ARTICLE MANAGEMENT
;; ==============================================

;; Submit a new article
(define-public (submit-article 
  (title (string-ascii 200))
  (content-hash (buff 32))
  (sources-hash (buff 32)))
  (let ((article-id (var-get next-article-id))
        (user-rep (get-user-reputation tx-sender)))
    (asserts! (>= user-rep MIN-REP-SUBMIT) ERR-INSUFFICIENT-REPUTATION)
    
    ;; Create article record
    (map-set articles
      { article-id: article-id }
      {
        title: title,
        content-hash: content-hash,
        author: tx-sender,
        timestamp: stacks-block-height,
        status: "pending",
        credibility-votes: u0,
        questionable-votes: u0,
        false-votes: u0,
        total-votes: u0,
        fact-check-count: u0,
        sources-hash: sources-hash
      })
    
    ;; Update user stats
    (map-set users
      { user: tx-sender }
      (merge 
        (default-to 
          { reputation: u0, articles-submitted: u0, fact-checks-completed: u0,
            votes-cast: u0, join-date: stacks-block-height, is-verified: false }
          (map-get? users { user: tx-sender }))
        { articles-submitted: (+ (default-to u0 
            (get articles-submitted (map-get? users { user: tx-sender }))) u1) }))
    
    ;; Increment counters
    (var-set next-article-id (+ article-id u1))
    (var-set total-articles (+ (var-get total-articles) u1))
    
    (ok article-id)))

;; Vote on article credibility
(define-public (vote-on-article (article-id uint) (vote-type (string-ascii 15)))
  (let ((article (unwrap! (map-get? articles { article-id: article-id }) ERR-ARTICLE-NOT-FOUND))
        (existing-vote (map-get? article-votes { article-id: article-id, voter: tx-sender })))
    
    ;; Check if user already voted
    (asserts! (is-none existing-vote) ERR-ALREADY-VOTED)
    
    ;; Record the vote
    (map-set article-votes
      { article-id: article-id, voter: tx-sender }
      { vote-type: vote-type, timestamp: stacks-block-height })
    
    ;; Update article vote counts based on vote type
    (if (is-eq vote-type "credible")
      (map-set articles
        { article-id: article-id }
        (merge article
          { credibility-votes: (+ (get credibility-votes article) u1), 
            total-votes: (+ (get total-votes article) u1) }))
      (if (is-eq vote-type "questionable")
        (map-set articles
          { article-id: article-id }
          (merge article
            { questionable-votes: (+ (get questionable-votes article) u1), 
              total-votes: (+ (get total-votes article) u1) }))
        (map-set articles
          { article-id: article-id }
          (merge article
            { false-votes: (+ (get false-votes article) u1), 
              total-votes: (+ (get total-votes article) u1) }))))
    
    ;; Update user stats
    (map-set users
      { user: tx-sender }
      (merge 
        (default-to 
          { reputation: u0, articles-submitted: u0, fact-checks-completed: u0,
            votes-cast: u0, join-date: stacks-block-height, is-verified: false }
          (map-get? users { user: tx-sender }))
        { votes-cast: (+ (default-to u0 
            (get votes-cast (map-get? users { user: tx-sender }))) u1) }))
    
    ;; Award reputation for voting
    (increment-user-reputation tx-sender u1)
    (ok true)))

;; ==============================================
;; PUBLIC FUNCTIONS - FACT CHECKING
;; ==============================================

;; Submit a fact-check for an article
(define-public (submit-fact-check
  (article-id uint)
  (findings-hash (buff 32))
  (credibility-rating uint)
  (sources-verified uint))
  (let ((check-id (var-get next-check-id))
        (user-rep (get-user-reputation tx-sender))
        (article (unwrap! (map-get? articles { article-id: article-id }) ERR-ARTICLE-NOT-FOUND)))
    
    (asserts! (>= user-rep MIN-REP-FACT-CHECK) ERR-INSUFFICIENT-REPUTATION)
    (asserts! (<= credibility-rating u100) ERR-INVALID-STATUS)
    
    ;; Create fact-check record
    (map-set fact-checks
      { check-id: check-id }
      {
        article-id: article-id,
        checker: tx-sender,
        findings-hash: findings-hash,
        credibility-rating: credibility-rating,
        sources-verified: sources-verified,
        timestamp: stacks-block-height,
        status: "pending-review",
        community-rating: u0
      })
    
    ;; Update article fact-check count
    (map-set articles
      { article-id: article-id }
      (merge article
        { fact-check-count: (+ (get fact-check-count article) u1) }))
    
    ;; Update user stats and reputation
    (map-set users
      { user: tx-sender }
      (merge 
        (default-to 
          { reputation: u0, articles-submitted: u0, fact-checks-completed: u0,
            votes-cast: u0, join-date:stacks-block-height, is-verified: false }
          (map-get? users { user: tx-sender }))
        { fact-checks-completed: (+ (default-to u0 
            (get fact-checks-completed (map-get? users { user: tx-sender }))) u1) }))
    
    (increment-user-reputation tx-sender u5)
    (var-set next-check-id (+ check-id u1))
    
    (ok check-id)))

;; Vote on fact-check quality
(define-public (rate-fact-check (check-id uint) (rating uint))
  (let ((fact-check (unwrap! (map-get? fact-checks { check-id: check-id }) ERR-FACT-CHECK-NOT-FOUND))
        (existing-vote (map-get? fact-check-votes { check-id: check-id, voter: tx-sender })))
    
    (asserts! (is-none existing-vote) ERR-ALREADY-VOTED)
    (asserts! (<= rating u5) ERR-INVALID-STATUS)
    
    ;; Record the rating
    (map-set fact-check-votes
      { check-id: check-id, voter: tx-sender }
      { rating: rating, timestamp: stacks-block-height })
    
    ;; Update fact-check community rating (simplified average)
    (let ((current-rating (get community-rating fact-check)))
      (map-set fact-checks
        { check-id: check-id }
        (merge fact-check
          { community-rating: (/ (+ current-rating rating) u2) })))
    
    ;; Award reputation to fact-checker based on rating
    (if (>= rating u4)
      (increment-user-reputation (get checker fact-check) u3)
      (increment-user-reputation (get checker fact-check) u1))
    
    (ok true)))

;; ==============================================
;; PUBLIC FUNCTIONS - MODERATION
;; ==============================================

;; Update article status (for moderators)
(define-public (update-article-status (article-id uint) (new-status (string-ascii 20)))
  (let ((article (unwrap! (map-get? articles { article-id: article-id }) ERR-ARTICLE-NOT-FOUND))
        (user-rep (get-user-reputation tx-sender)))
    
    (asserts! (>= user-rep MIN-REP-MODERATE) ERR-INSUFFICIENT-REPUTATION)
    
    (map-set articles
      { article-id: article-id }
      (merge article { status: new-status }))
    
    (ok true)))

;; Verify user status
(define-public (verify-user (user principal))
  (let ((user-rep (get-user-reputation tx-sender)))
    (asserts! (>= user-rep MIN-REP-MODERATE) ERR-INSUFFICIENT-REPUTATION)
    
    (map-set users
      { user: user }
      (merge 
        (default-to 
          { reputation: u0, articles-submitted: u0, fact-checks-completed: u0,
            votes-cast: u0, join-date:stacks-block-height, is-verified: false }
          (map-get? users { user: user }))
        { is-verified: true }))
    
    (increment-user-reputation user u10)
    (ok true)))

;; ==============================================
;; READ-ONLY FUNCTIONS
;; ==============================================

(define-read-only (get-article (article-id uint))
  (map-get? articles { article-id: article-id }))

(define-read-only (get-user-info (user principal))
  (map-get? users { user: user }))

(define-read-only (get-fact-check (check-id uint))
  (map-get? fact-checks { check-id: check-id }))

(define-read-only (get-article-credibility-score (article-id uint))
  (match (map-get? articles { article-id: article-id })
    article (ok (calculate-credibility-score 
                  (get credibility-votes article)
                  (get questionable-votes article)
                  (get false-votes article)))
    ERR-ARTICLE-NOT-FOUND))

(define-read-only (get-platform-stats)
  {
    total-articles: (var-get total-articles),
    next-article-id: (var-get next-article-id),
    next-check-id: (var-get next-check-id),
    platform-reputation: (var-get platform-reputation)
  })

(define-read-only (has-user-voted (article-id uint) (user principal))
  (is-some (map-get? article-votes { article-id: article-id, voter: user })))

;; ==============================================
;; INITIALIZATION
;; ==============================================

;; Initialize contract owner with high reputation
(map-set users
  { user: CONTRACT-OWNER }
  {
    reputation: u1000,
    articles-submitted: u0,
    fact-checks-completed: u0,
    votes-cast: u0,
    join-date: stacks-block-height,
    is-verified: true
  })