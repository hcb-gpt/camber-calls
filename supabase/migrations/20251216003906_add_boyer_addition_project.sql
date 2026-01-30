
-- Add Boyer Addition/Remodel project
INSERT INTO projects (
    name,
    aliases,
    street,
    city,
    state,
    zip,
    address,
    client_name,
    status,
    job_type,
    map_id,
    parcel_id,
    parcel_info,
    buildertrend_id
) VALUES (
    'Boyer Addition',
    ARRAY['Boyer', 'Boyer House', 'Boyer Remodel', '410 East Central'],
    '410 East Central Avenue',
    'Madison',
    'GA',
    '30650',
    '410 East Central Avenue, Madison, GA 30650',
    'Shane & Emily Boyer',
    'inactive',
    'Addition',
    'M19',
    '020',
    'Map M19 Parcel 020',
    '2023-131-RES'
);
;
