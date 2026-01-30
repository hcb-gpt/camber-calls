-- Enable fuzzy matching extensions
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;

COMMENT ON EXTENSION pg_trgm IS 'Trigram similarity for fuzzy text matching';
COMMENT ON EXTENSION fuzzystrmatch IS 'Levenshtein, Soundex, Metaphone for phonetic matching';;
