-- Fix search_path security warnings on new functions
ALTER FUNCTION find_contact_by_name_or_alias(text) SET search_path = public;
ALTER FUNCTION match_text_to_contact(text) SET search_path = public;
;
