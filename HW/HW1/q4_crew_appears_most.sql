/*
Find the people who appear most frequently as crew members.
Details: Print the names and number of appearances of the 20 people with the most crew appearances ordered by their number of appearances in a descending fashion.
Your output should look like this: NAME|NUM_APPEARANCES

crew - person_id
people - person_id, name
*/

Select p.name, Count(c.title_id) As cnt, c.person_id From crew c
Join people p On p.person_id = c.person_id
Group By c.person_id
Order By cnt Desc
Limit 20;