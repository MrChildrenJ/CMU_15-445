/*
For all people born in 1955, get their name and average rating on all movies they have been part of 
through their careers. Output the 9th decile of individuals as measured by their average career 
movie rating.

Details: Calculate average ratings for each individual born in 1955 across only the movies they 
         have been part of. 
         Compute the quantiles for each individual's average rating using NTILE(10).
         Make sure your output is formatted as follows 
         (round average rating to the nearest hundredth, 
         results should be ordered by a compound value of their ratings descending and 
         secondly their name in alphabetical order): 
         Stanley Nelson|7.13

Note: You should take quantiles after processing the average career movie rating of individuals. 
      In other words, find the individuals who have an average career movie rating in the 9th decile 
      of all individuals.

people: person_id, born
crew: title_id, person_id
ratings: title_id, rating

-- people born at 1955
Select distinct(person_id) From people Where born = 1955;



*/

With avg_rating As (
    Select p.name As name, Round(Avg(r.rating), 2) As av From people p
    Join crew c On c.person_id = p.person_id
    Join ratings r On c.title_id = r.title_id
    Join titles t On t.title_id = r.title_id
    Where c.person_id In (
        Select distinct(person_id) From people Where born = 1955) And t.type = 'movie'
    Group By c.person_id),
decile_ranking As (Select name, av, Ntile(10) Over (Order By av, name) As avg_bucket From avg_rating)
Select name, av From decile_ranking Where avg_bucket = 9 Order By av Desc, name;