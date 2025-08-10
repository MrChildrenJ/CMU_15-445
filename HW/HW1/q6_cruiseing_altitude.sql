/*
Determine the most popular works with a person who has "Cruise" in their name and is born in 1962.

Details: Get the works with the most votes that have a person in the crew with "Cruise" in their 
name who was born in 1962. Return both the name of the work and the number of votes and only list 
the top 10 results in order from most to least votes. 

Make sure your output is formatted as follows: Top Gun|408389

ratings: title_id, votes
titles: title_id, primary_title
people: person_id, name, born
crew: title_id, person_id
*/

-- person_id with name "Cruise"
-- Select Distinct(p.person_id) From people p
-- Join crew c On c.person_id = p.person_id
-- Where p.name Like '%Cruise%' And p.born = 1962;

Select t.primary_title, r.votes From titles t 
Join ratings r On r.title_id = t.title_id
Join crew c On c.title_id = r.title_id
Where c.person_id In (Select Distinct(p.person_id) From people p
Join crew c On c.person_id = p.person_id
Where p.name Like '%Cruise%' And p.born = 1962)
Order By r.votes Desc
Limit 10;

/*
Oblivion|520383
Mission: Impossible|423228
Top Gun|408389
Magnolia|311030
Born on the Fourth of July|106667
Days of Thunder|88698
Lions for Lambs|50257
Without Limits|7127
Space Station 3D|1693
Nickelodeon Kids' Choice Awards 2012|212
