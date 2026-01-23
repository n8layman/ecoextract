Compare new records against existing records. Return the indices (1-based) of new records that are NOT duplicates.

Two records are duplicates if ALL key fields semantically match. Fields can match even with different spelling, abbreviations, synonyms, or language (e.g., "Borrelia burgdorferi" = "Lyme disease spirochete", "NYC" = "New York", "PCR" = "Polymerase chain reaction").

When uncertain, err on the side of treating records as UNIQUE. It's easier to clean up duplicate records than to recover missed data.
