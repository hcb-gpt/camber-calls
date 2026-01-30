CREATE OR REPLACE FUNCTION sync_project_contact_to_affinity()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO correspondent_project_affinity
    (id, contact_id, project_id, weight, source, created_at, updated_at)
  VALUES
    (gen_random_uuid(), NEW.contact_id, NEW.project_id, 0.8, 
     'project_contacts_sync', NOW(), NOW())
  ON CONFLICT (contact_id, project_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_project_contact_to_affinity
AFTER INSERT ON project_contacts
FOR EACH ROW
EXECUTE FUNCTION sync_project_contact_to_affinity();;
