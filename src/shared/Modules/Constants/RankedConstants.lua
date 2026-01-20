local RankedConstants = {}

-- Ranked PvP (MVP) tuning
RankedConstants.START_RATING = 1000
RankedConstants.WIN_DELTA = 25
RankedConstants.LOSE_DELTA = 20

-- Matchmaking tuning
RankedConstants.INITIAL_RANGE = 100      -- +/- range
RankedConstants.RANGE_STEP = 100         -- expand by this when empty
RankedConstants.MAX_RANGE = 600          -- hard cap expansion
RankedConstants.MAX_CANDIDATES = 50      -- fetched from index for random pick

-- Bucketization (DataStore fallback / long-lived index)
RankedConstants.BUCKET_SIZE = 100
RankedConstants.DATASTORE_SNAPSHOT_TTL = 24 * 60 * 60 -- consider snapshots stale after 24h
RankedConstants.DATASTORE_BUCKET_CAP = 500 -- soft cap for bucket entries (cleanup on write)

-- MemoryStore tuning (seconds)
RankedConstants.SNAPSHOT_TTL = 15 * 60   -- deck snapshot time-to-live
RankedConstants.INDEX_TTL = 15 * 60      -- rating index TTL
RankedConstants.TICKET_TTL = 60          -- opponent selection ticket TTL (two-phase flow)

-- Ghost decks (cold start fallback)
RankedConstants.GHOST_ENABLED = true
RankedConstants.GHOST_MIN_STRENGTH_MULT = 0.60
RankedConstants.GHOST_MAX_STRENGTH_MULT = 1.25
RankedConstants.GHOST_SIZE_VARIANCE = 3
RankedConstants.GHOST_LEVEL_VARIANCE_MIN = 1
RankedConstants.GHOST_LEVEL_VARIANCE_MAX = 4
RankedConstants.GHOST_ATTEMPTS = 250
RankedConstants.GHOST_RATING_JITTER = 75 -- displayed rating offset (+/- jitter)

return RankedConstants

