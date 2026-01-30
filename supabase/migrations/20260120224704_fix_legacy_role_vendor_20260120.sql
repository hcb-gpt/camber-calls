-- Fix legacy role='vendor' values
-- These should be actual roles based on context

-- Subcontractors with role='vendor' -> 'Subcontractor' 
UPDATE contacts 
SET role = 'Subcontractor'
WHERE role = 'vendor' AND contact_type = 'subcontractor';

-- Suppliers with role='vendor' -> 'Sales Rep' (most are sales contacts)
UPDATE contacts 
SET role = 'Sales Rep'
WHERE role = 'vendor' AND contact_type = 'supplier';

-- Professionals with role='vendor' -> infer from trade
UPDATE contacts 
SET role = 'Architect'
WHERE role = 'vendor' AND contact_type = 'professional' AND trade = 'Architecture';

-- The one remaining vendor (auto body) 
UPDATE contacts 
SET role = NULL, contact_type = 'other'
WHERE role = 'vendor' AND contact_type = 'vendor';;
