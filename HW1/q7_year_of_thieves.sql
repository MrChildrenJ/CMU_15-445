/*
List the number of works that premiered in the same year that "Army of Thieves" premiered.
Details: Print only the total number of works. The answer should include "Army of Thieves" itself. 
For this question, determine distinct works by their title_id, not their names.

titles: title_id, primary_title, premiered
*/

-- the year
-- Select premiered From titles
-- Where primary_title Like 'Army of Thieves';

Select Count(title_id) From titles
Where premiered In (Select premiered From titles
                    Where primary_title Like 'Army of Thieves');

-- 63843