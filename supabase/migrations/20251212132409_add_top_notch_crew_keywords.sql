
-- Add carpentry keywords to Top Notch crew
UPDATE contacts 
SET core_business_keywords = '["carpentry", "carpenter", "finish carpentry", "trim", "molding", "crown molding", "baseboard", "casing", "door trim", "window trim", "wainscoting", "built-ins", "shelving", "mantel", "stair railing", "handrail", "millwork installation", "Top Notch Finishers"]'::jsonb
WHERE company = 'Top Notch Finishers, LLC';
;
