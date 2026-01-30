-- Populate aliases for contacts based on notes field parsing and message corpus analysis

-- Bo Hurley - client (from notes: "Name variations: Joseph Hurley, Joe Hurley, J Hurley")
UPDATE contacts 
SET aliases = ARRAY['Joseph Hurley', 'Joe Hurley', 'J Hurley', 'Bo', 'J. Hurley']
WHERE name = 'Bo Hurley';

-- David Woodbery - client (from notes: "Name variations: Dave Woodbery, D Woodbery, David Woodberry, Dave Woodberry")
UPDATE contacts 
SET aliases = ARRAY['Dave Woodbery', 'D Woodbery', 'David Woodberry', 'Dave Woodberry', 'David Woodbury', 'Dave Woodbury', 'Dave', 'D. Woodbery']
WHERE name = 'David Woodbery';

-- Lou Winship - client (from notes: "Name variations: Louise Winship, L Winship")
UPDATE contacts 
SET aliases = ARRAY['Louise Winship', 'L Winship', 'Lou', 'L. Winship', 'Mrs. Winship']
WHERE name = 'Lou Winship';

-- Blanton Winship - client
UPDATE contacts 
SET aliases = ARRAY['Blanton', 'B Winship', 'B. Winship', 'Mr. Winship']
WHERE name = 'Blanton Winship';

-- Zack Sittler (work) - internal
UPDATE contacts 
SET aliases = ARRAY['Zachary Sittler', 'Z Sittler', 'Zach', 'Zach Sittler', 'Z', 'Zack S', 'Zack S.']
WHERE name = 'Zack Sittler' AND contact_type = 'internal';

-- Zack Sittler (personal)
UPDATE contacts 
SET aliases = ARRAY['Zachary Sittler', 'Zach Sittler', 'Zack', 'Z']
WHERE name = 'Zack Sittler (personal)';

-- Chad Barlow - internal
UPDATE contacts 
SET aliases = ARRAY['Chad', 'C Barlow', 'Chad B', 'C. Barlow']
WHERE name = 'Chad Barlow';

-- Jimmy Chastain - internal
UPDATE contacts 
SET aliases = ARRAY['Jimmy', 'Jim Chastain', 'J Chastain', 'Jimmy C', 'Jim', 'JC', 'Jimmy Work']
WHERE name = 'Jimmy Chastain';

-- Daniel Napier - internal
UPDATE contacts 
SET aliases = ARRAY['Daniel', 'Dan Napier', 'Danny Napier', 'D Napier', 'Daniel Work', 'Dan']
WHERE name = 'Daniel Napier';

-- David Carter - internal
UPDATE contacts 
SET aliases = ARRAY['David', 'Dave Carter', 'D Carter', 'Dave C', 'DC']
WHERE name = 'David Carter';

-- Edenilson Quevedo - internal
UPDATE contacts 
SET aliases = ARRAY['Edenilson', 'Eden', 'Edin', 'E Quevedo', 'Eden Q', 'Edin Work', 'Edi']
WHERE name = 'Edenilson Quevedo';

-- Randy Booth - internal
UPDATE contacts 
SET aliases = ARRAY['Randy', 'Randy B', 'R Booth', 'R. Booth']
WHERE name = 'Randy Booth';

-- Malcolm Hetzer - site supervisor
UPDATE contacts 
SET aliases = ARRAY['Malcolm', 'Mal Hetzer', 'M Hetzer', 'Hetzer Electric']
WHERE name = 'Malcolm Hetzer';

-- Alicia Cottrell - subcontractor (Crossed Chisels)
UPDATE contacts 
SET aliases = ARRAY['Alicia', 'A Cottrell', 'Crossed Chisels', 'Alicia Crossed Chisels']
WHERE name = 'Alicia Cottrell';

-- Anthony Cottrell - subcontractor
UPDATE contacts 
SET aliases = ARRAY['Anthony', 'A Cottrell', 'Tony Cottrell', 'Crossed Chisels LLC', 'Anthony Crossed Chisels']
WHERE name = 'Anthony Cottrell';

-- Taylor Messer - subcontractor (Hetzer Electric)
UPDATE contacts 
SET aliases = ARRAY['Taylor', 'T Messer', 'Taylor Hetzer', 'Hetzer Electric']
WHERE name = 'Taylor Messer';

-- Taylor Shannon - vendor (Grounded Siteworks)
UPDATE contacts 
SET aliases = ARRAY['Taylor', 'T Shannon', 'Grounded', 'Grounded Siteworks']
WHERE name = 'Taylor Shannon';

-- Randy Bryan - vendor
UPDATE contacts 
SET aliases = ARRAY['Randy', 'Randy B', 'R Bryan', 'Bryans Plumbing', 'Bryan Plumbing', 'Bryans Home Repair']
WHERE name = 'Randy Bryan';

-- Aleah Homer - client (personal)
UPDATE contacts 
SET aliases = ARRAY['Aleah', 'A Homer', 'Aleah H', 'Aleah Sexy Gorgeous Woman Love Of My Life']
WHERE name = 'Aleah Homer';

-- Kaylen Hurley - client  
UPDATE contacts 
SET aliases = ARRAY['Kaylen', 'K Hurley', 'Mrs. Hurley', 'Kaylen H']
WHERE name = 'Kaylen Hurley';

-- Shayelyn Woodbery - client
UPDATE contacts 
SET aliases = ARRAY['Shayelyn', 'S Woodbery', 'Shayelyn W', 'Mrs. Woodbery']
WHERE name = 'Shayelyn Woodbery';

-- Debbie Permar - client
UPDATE contacts 
SET aliases = ARRAY['Debbie', 'Deb Permar', 'D Permar', 'Mrs. Permar']
WHERE name = 'Debbie Permar';

-- Steven Permar - client
UPDATE contacts 
SET aliases = ARRAY['Steven', 'Steve Permar', 'S Permar']
WHERE name = 'Steven Permar';

-- Flynt Treadaway - vendor (Carter Lumber)
UPDATE contacts 
SET aliases = ARRAY['Flynt', 'Carter Lumber', 'Flynt Carter Lumber']
WHERE name = 'Flynt Treadaway';

-- Hector Ordonez - vendor (Carter Lumber)
UPDATE contacts 
SET aliases = ARRAY['Hector', 'Carter Lumber Sales', 'H Ordonez']
WHERE name = 'Hector Ordonez';

-- Brian Young - client
UPDATE contacts 
SET aliases = ARRAY['Brian', 'B Young']
WHERE name = 'Brian Young';

-- Norma Young - client
UPDATE contacts 
SET aliases = ARRAY['Norma', 'N Young', 'Mrs. Young']
WHERE name = 'Norma Young';

-- Gatlin (Peppers HVAC) - subcontractor
UPDATE contacts 
SET aliases = ARRAY['Gatlin Peppers', 'Peppers HVAC', 'Peppers Heating', 'Peppers Air']
WHERE name = 'Gatlin';

-- Joe Laboon III - vendor (Georgia Kitchens)
UPDATE contacts 
SET aliases = ARRAY['Joe', 'Joe Laboon', 'Georgia Kitchens', 'GK']
WHERE name = 'Joe Laboon III';

-- Austin Atkinson - vendor (Air Georgia)
UPDATE contacts 
SET aliases = ARRAY['Austin', 'Air Georgia', 'Air Georgia Heating']
WHERE name = 'Austin Atkinson';

-- Bill Mayne - vendor (Mayne Tile)
UPDATE contacts 
SET aliases = ARRAY['Bill', 'Mayne Tile', 'B Mayne']
WHERE name = 'Bill Mayne';

-- Brian Dove - vendor (Structuremen)
UPDATE contacts 
SET aliases = ARRAY['Brian', 'Structuremen', 'B Dove']
WHERE name = 'Brian Dove';

-- Calvin Taylor - vendor (Georgia Insulation)
UPDATE contacts 
SET aliases = ARRAY['Calvin', 'Georgia Insulation', 'C Taylor']
WHERE name = 'Calvin Taylor';

-- Chris Gaugler - vendor (Braswell Construction)
UPDATE contacts 
SET aliases = ARRAY['Chris', 'Braswell', 'Braswell Construction', 'C Gaugler']
WHERE name = 'Chris Gaugler';

-- Jose (Tony) Araujo - vendor (Jayco)
UPDATE contacts 
SET aliases = ARRAY['Tony', 'Tony Araujo', 'Jose Araujo', 'Jayco', 'Jayco Innovations']
WHERE name = 'Jose (Tony) Araujo';

-- Josh Mobley - vendor (Mobley Flooring)
UPDATE contacts 
SET aliases = ARRAY['Josh', 'Mobley Flooring', 'J Mobley']
WHERE name = 'Josh Mobley';

-- Luis Juarez - vendor (J&R Masonry)
UPDATE contacts 
SET aliases = ARRAY['Luis', 'J&R Masonry', 'JR Masonry', 'L Juarez']
WHERE name = 'Luis Juarez';

-- Michael Strickland - vendor (Southeastern Sitecast)
UPDATE contacts 
SET aliases = ARRAY['Michael', 'Mike Strickland', 'Southeastern Sitecast', 'M Strickland']
WHERE name = 'Michael Strickland';

-- Tracy Postin - vendor (T&J Vinyl)
UPDATE contacts 
SET aliases = ARRAY['Tracy', 'T&J Vinyl', 'TJ Vinyl', 'T Postin']
WHERE name = 'Tracy Postin';

-- Zach Givens - vendor (Givens Landscaping)
UPDATE contacts 
SET aliases = ARRAY['Zach', 'Givens Landscaping', 'Givens Irrigation', 'Z Givens']
WHERE name = 'Zach Givens';

-- Alexander Nasr - vendor (Select Floors)
UPDATE contacts 
SET aliases = ARRAY['Alexander', 'Alex Nasr', 'Select Floors', 'A Nasr']
WHERE name = 'Alexander Nasr';
;
