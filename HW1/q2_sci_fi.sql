Select primary_title, premiered, runtime_minutes || ' (mins)' as runtime  
From titles 
Where genres Like '%Sci-Fi%'  
Order By runtime_minutes Desc 
Limit 10;

/*
Cicak-Man 2: Planet Hitam|2008|999 (mins)
Project Hail Mary|2021|970 (mins)
Wholy|2018|660 (mins)
Tales from the Void|2016|600 (mins)
Blade Runner: Czy androidy marza o elektrycznych owcach? (Audioplay)|2012|403 (mins)
Cold Lazarus|1996|300 (mins)
Phantom Gear|2021|300 (mins)
The Halt|2019|279 (mins)
V: The Final Battle|1984|272 (mins)
Atom Man vs. Superman|1950|252 (mins)
*/