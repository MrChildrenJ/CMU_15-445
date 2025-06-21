/*
List the all the different actors and actresses who have starred in a work with 
Nicole Kidman (born in 1967).

Details: Print only the names of the actors and actresses in alphabetical order. 
         The answer should include Nicole Kidman herself. 
         Each name should only appear once in the output.

Note: As mentioned in the schema, when considering the role of an individual on 
      the crew, refer to the field category. The roles "actor" and "actress" are 
      different and should be accounted for as such.

people: person_id, name, born
crew: title_id, person_id, category

-- Real Nicole
Select person_id From people Where name Like '%Nicole Kidman%';

-- title_id has crew as Nicole Kidman
Select Distinct(title_id) From crew Where person_id = 
(Select person_id From people Where name Like '%Nicole Kidman%');

-- person_id of actor/actress with Nicole
Select Distinct(person_id) From crew c
Where c.title_id In (Select Distinct(title_id) From crew 
                     Where person_id = (Select person_id From people p
                                        Where p.name Like '%Nicole Kidman%')) And
        (c.category Like 'actor' Or c.category Like 'actress');

*/

Select p.name From people p
Join (Select Distinct(person_id) From crew c
      Where c.title_id In (Select Distinct(title_id) From crew 
                           Where person_id = (Select person_id From people p
                                              Where p.name Like '%Nicole Kidman%')) And
        (c.category Like 'actor' Or c.category Like 'actress')) colleagues_id On colleagues_id.person_id = p.person_id
Order By p.name

/*
Betty Gilpin
Casey Affleck
Colin Farrell
Crista Flanagan
Danny Huston
Dennis Miller
Donald Sutherland
Ed Mantell
Fionnula Flanagan
Flora Cross
Fredrik Skavlan
Gus Mercurio
Halle Berry
Harris Yulin
J.K. Simmons
Jackson Bond
James Corden
Jason Bateman
Javier Bardem
Jesper Christensen
John Lithgow
Julianne Moore
Kai Lewins
Kyle Mooney
Lisa Flanagan
Liz Burch
Mahershala Ali
Maria Tran
Mark Strong
Nicholas Eadie
Nicole Kidman
Paul Bettany
Pauline Chan
Robert Pattinson
Russell Crowe
Sam Neill
Shailene Woodley
Sherie Graham
Simon Baker
Stellan Skarsgård
Tom Cruise
Valerie Yu
Veronica Lang
Will Ferrell

