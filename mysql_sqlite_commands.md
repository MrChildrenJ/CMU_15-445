# MySQL vs SQLite Commands Reference

## Startup and Connection

| Function | MySQL | SQLite |
|----------|-------|---------|
| Startup | `mysql -u username -p` | `sqlite3` |
| Connect to specific database | `mysql -u username -p database_name` | `sqlite3 database.db` |
| Connect to server | `mysql -h hostname -u username -p` | N/A (file-based database) |

## Database Operations

| Function | MySQL | SQLite |
|----------|-------|---------|
| Show all databases | `SHOW DATABASES;` | `.databases` |
| Create database | `CREATE DATABASE db_name;` | N/A (create file directly) |
| Use database | `USE database_name;` | `.open database.db` |
| Drop database | `DROP DATABASE db_name;` | Delete .db file |
| Show current database | `SELECT DATABASE();` | `.databases` |

## Table Operations

| Function | MySQL | SQLite |
|----------|-------|---------|
| Show all tables | `SHOW TABLES;` | `.tables` |
| Show table structure | `DESCRIBE table_name;`<br>`SHOW COLUMNS FROM table_name;` | `.schema table_name`<br>`.describe table_name` |
| Show create table statement | `SHOW CREATE TABLE table_name;` | `.schema table_name` |
| Rename table | `RENAME TABLE old_name TO new_name;` | `ALTER TABLE old_name RENAME TO new_name;` |

## Main Data Type Differences

| MySQL | SQLite | Description |
|-------|---------|-------------|
| `INT`, `INTEGER` | `INTEGER` | Integer |
| `VARCHAR(n)`, `CHAR(n)` | `TEXT` | String |
| `FLOAT`, `DOUBLE` | `REAL` | Floating point |
| `DECIMAL` | `NUMERIC` | Exact decimal |
| `BLOB` | `BLOB` | Binary data |
| `DATETIME`, `TIMESTAMP` | `TEXT`, `INTEGER`, `REAL` | Date and time |

## Queries and Data Operations

| Function | MySQL | SQLite |
|----------|-------|---------|
| Basic SELECT | `SELECT * FROM table;` | `SELECT * FROM table;` |
| Limit results | `SELECT * FROM table LIMIT 10;` | `SELECT * FROM table LIMIT 10;` |
| Pagination | `SELECT * FROM table LIMIT 10 OFFSET 20;` | `SELECT * FROM table LIMIT 10 OFFSET 20;` |
| Auto-increment primary key | `AUTO_INCREMENT` | `AUTOINCREMENT` |

## Index Operations

| Function | MySQL | SQLite |
|----------|-------|---------|
| Show indexes | `SHOW INDEX FROM table_name;` | `.indices table_name` |
| Create index | `CREATE INDEX idx_name ON table(column);` | `CREATE INDEX idx_name ON table(column);` |
| Drop index | `DROP INDEX idx_name ON table_name;` | `DROP INDEX idx_name;` |

## System and Metadata

| Function | MySQL | SQLite |
|----------|-------|---------|
| Show version | `SELECT VERSION();` | `SELECT sqlite_version();` |
| Show current time | `SELECT NOW();` | `SELECT datetime('now');` |
| Show user | `SELECT USER();` | N/A |
| Show processes | `SHOW PROCESSLIST;` | N/A |

## Import/Export

| Function | MySQL | SQLite |
|----------|-------|---------|
| Export database | `mysqldump -u user -p db_name > backup.sql` | `.dump > backup.sql` |
| Import database | `mysql -u user -p db_name < backup.sql` | `.read backup.sql` |
| Export table | `mysqldump -u user -p db_name table_name` | `.dump table_name` |
| Export as CSV | `SELECT * INTO OUTFILE 'file.csv'` | `.mode csv`<br>`.output file.csv`<br>`SELECT * FROM table;` |

## Console Commands

| Function | MySQL | SQLite |
|----------|-------|---------|
| Show help | `HELP;` or `\h` | `.help` |
| Exit | `EXIT;` or `QUIT;` or `\q` | `.quit` or `.exit` |
| Clear screen | `SYSTEM clear;` (Linux/Mac) | Use system `clear` |
| Execute SQL file | `SOURCE filename.sql;` | `.read filename.sql` |
| Show execution time | `SET profiling = 1;` | `.timer on` |

## Transaction Control

| Function | MySQL | SQLite |
|----------|-------|---------|
| Begin transaction | `START TRANSACTION;` or `BEGIN;` | `BEGIN;` |
| Commit transaction | `COMMIT;` | `COMMIT;` |
| Rollback transaction | `ROLLBACK;` | `ROLLBACK;` |
| Auto-commit | `SET AUTOCOMMIT = 0;` (disable) | Disabled by default |

## Users and Permissions (MySQL only)

| Function | MySQL | SQLite |
|----------|-------|---------|
| Show users | `SELECT User FROM mysql.user;` | N/A (no user system) |
| Create user | `CREATE USER 'username'@'host';` | N/A |
| Grant permissions | `GRANT ALL ON db.* TO 'user'@'host';` | N/A |
| Flush privileges | `FLUSH PRIVILEGES;` | N/A |

## Special Functions

| Function | MySQL | SQLite |
|----------|-------|---------|
| Show last insert ID | `SELECT LAST_INSERT_ID();` | `SELECT last_insert_rowid();` |
| Check table | `CHECK TABLE table_name;` | `PRAGMA integrity_check;` |
| Optimize table | `OPTIMIZE TABLE table_name;` | `VACUUM;` |
| Repair table | `REPAIR TABLE table_name;` | N/A |

## SQLite-Specific Useful Commands

| Command | Description |
|---------|-------------|
| `.mode column` | Display in column-aligned format |
| `.headers on` | Show column headers |
| `.width 10 20 15` | Set column widths |
| `.output filename` | Redirect output to file |
| `.backup backup.db` | Backup database |
| `.restore backup.db` | Restore database |

## Important Notes

1. **SQLite is file-based**: No server required, operates directly on files
2. **Type system differences**: SQLite has a more flexible type system
3. **Concurrency handling**: MySQL supports better concurrency, SQLite is suitable for single-user or low-concurrency scenarios
4. **Feature richness**: MySQL has more features, SQLite is more lightweight
5. **SQL standards**: Both support most basic SQL syntax

This reference covers the most commonly used commands in daily development. Hope it helps with your learning!