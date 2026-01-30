-- Seed validated projects (notes column not in schema)
INSERT INTO public.projects (name, aliases, status)
VALUES 
  ('Winship', ARRAY['Winship Home','Lou Winship'], 'active'),
  ('Hurley',  ARRAY['Hurley Home'],                'active'),
  ('Sparta',  ARRAY['Sparta house'],               'active')
ON CONFLICT DO NOTHING;;
