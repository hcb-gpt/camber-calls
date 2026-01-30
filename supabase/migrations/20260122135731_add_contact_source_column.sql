-- Add source column for provenance tracking
ALTER TABLE contacts 
ADD COLUMN source text;

COMMENT ON COLUMN contacts.source IS 'Data provenance: vcf, gmail, buildertrend, manual, beside';;
