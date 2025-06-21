# MySQL vs SQLite 指令對照表

## 啟動和連接

| 功能 | MySQL | SQLite |
|------|-------|---------|
| 啟動 | `mysql -u username -p` | `sqlite3` |
| 連接特定資料庫 | `mysql -u username -p database_name` | `sqlite3 database.db` |
| 連接到伺服器 | `mysql -h hostname -u username -p` | N/A (檔案型資料庫) |

## 資料庫操作

| 功能 | MySQL | SQLite |
|------|-------|---------|
| 顯示所有資料庫 | `SHOW DATABASES;` | `.databases` |
| 創建資料庫 | `CREATE DATABASE db_name;` | N/A (建立檔案即可) |
| 使用資料庫 | `USE database_name;` | `.open database.db` |
| 刪除資料庫 | `DROP DATABASE db_name;` | 刪除 .db 檔案 |
| 顯示目前資料庫 | `SELECT DATABASE();` | `.databases` |

## 表格操作

| 功能 | MySQL | SQLite |
|------|-------|---------|
| 顯示所有表格 | `SHOW TABLES;` | `.tables` |
| 顯示表格結構 | `DESCRIBE table_name;`<br>`SHOW COLUMNS FROM table_name;` | `.schema table_name`<br>`.describe table_name` |
| 顯示建表語句 | `SHOW CREATE TABLE table_name;` | `.schema table_name` |
| 重新命名表格 | `RENAME TABLE old_name TO new_name;` | `ALTER TABLE old_name RENAME TO new_name;` |

## 資料型別主要差異

| MySQL | SQLite | 說明 |
|-------|---------|------|
| `INT`, `INTEGER` | `INTEGER` | 整數 |
| `VARCHAR(n)`, `CHAR(n)` | `TEXT` | 字串 |
| `FLOAT`, `DOUBLE` | `REAL` | 浮點數 |
| `DECIMAL` | `NUMERIC` | 精確小數 |
| `BLOB` | `BLOB` | 二進位資料 |
| `DATETIME`, `TIMESTAMP` | `TEXT`, `INTEGER`, `REAL` | 日期時間 |

## 查詢和資料操作

| 功能 | MySQL | SQLite |
|------|-------|---------|
| 基本 SELECT | `SELECT * FROM table;` | `SELECT * FROM table;` |
| 限制結果數量 | `SELECT * FROM table LIMIT 10;` | `SELECT * FROM table LIMIT 10;` |
| 分頁查詢 | `SELECT * FROM table LIMIT 10 OFFSET 20;` | `SELECT * FROM table LIMIT 10 OFFSET 20;` |
| 自增主鍵 | `AUTO_INCREMENT` | `AUTOINCREMENT` |

## 索引操作

| 功能 | MySQL | SQLite |
|------|-------|---------|
| 顯示索引 | `SHOW INDEX FROM table_name;` | `.indices table_name` |
| 創建索引 | `CREATE INDEX idx_name ON table(column);` | `CREATE INDEX idx_name ON table(column);` |
| 刪除索引 | `DROP INDEX idx_name ON table_name;` | `DROP INDEX idx_name;` |

## 系統和元資料

| 功能 | MySQL | SQLite |
|------|-------|---------|
| 顯示版本 | `SELECT VERSION();` | `SELECT sqlite_version();` |
| 顯示目前時間 | `SELECT NOW();` | `SELECT datetime('now');` |
| 顯示使用者 | `SELECT USER();` | N/A |
| 顯示程序 | `SHOW PROCESSLIST;` | N/A |

## 匯入匯出

| 功能 | MySQL | SQLite |
|------|-------|---------|
| 匯出資料庫 | `mysqldump -u user -p db_name > backup.sql` | `.dump > backup.sql` |
| 匯入資料庫 | `mysql -u user -p db_name < backup.sql` | `.read backup.sql` |
| 匯出表格 | `mysqldump -u user -p db_name table_name` | `.dump table_name` |
| 匯出為 CSV | `SELECT * INTO OUTFILE 'file.csv'` | `.mode csv`<br>`.output file.csv`<br>`SELECT * FROM table;` |

## 控制台指令

| 功能 | MySQL | SQLite |
|------|-------|---------|
| 顯示幫助 | `HELP;` 或 `\h` | `.help` |
| 退出 | `EXIT;` 或 `QUIT;` 或 `\q` | `.quit` 或 `.exit` |
| 清除螢幕 | `SYSTEM clear;` (Linux/Mac) | 使用系統 `clear` |
| 執行 SQL 檔案 | `SOURCE filename.sql;` | `.read filename.sql` |
| 顯示執行時間 | `SET profiling = 1;` | `.timer on` |

## 事務控制

| 功能 | MySQL | SQLite |
|------|-------|---------|
| 開始事務 | `START TRANSACTION;` 或 `BEGIN;` | `BEGIN;` |
| 提交事務 | `COMMIT;` | `COMMIT;` |
| 回滾事務 | `ROLLBACK;` | `ROLLBACK;` |
| 自動提交 | `SET AUTOCOMMIT = 0;` (關閉) | 預設關閉 |

## 使用者和權限 (僅 MySQL)

| 功能 | MySQL | SQLite |
|------|-------|---------|
| 顯示使用者 | `SELECT User FROM mysql.user;` | N/A (無使用者系統) |
| 創建使用者 | `CREATE USER 'username'@'host';` | N/A |
| 授予權限 | `GRANT ALL ON db.* TO 'user'@'host';` | N/A |
| 刷新權限 | `FLUSH PRIVILEGES;` | N/A |

## 特殊功能

| 功能 | MySQL | SQLite |
|------|-------|---------|
| 顯示最後插入ID | `SELECT LAST_INSERT_ID();` | `SELECT last_insert_rowid();` |
| 檢查表格 | `CHECK TABLE table_name;` | `PRAGMA integrity_check;` |
| 優化表格 | `OPTIMIZE TABLE table_name;` | `VACUUM;` |
| 修復表格 | `REPAIR TABLE table_name;` | N/A |

## 實用的 SQLite 特有指令

| 指令 | 說明 |
|------|------|
| `.mode column` | 以欄位對齊方式顯示 |
| `.headers on` | 顯示欄位標題 |
| `.width 10 20 15` | 設定欄位寬度 |
| `.output filename` | 將輸出重定向到檔案 |
| `.backup backup.db` | 備份資料庫 |
| `.restore backup.db` | 還原資料庫 |

## 注意事項

1. **SQLite 是檔案型資料庫**：不需要伺服器，直接操作檔案
2. **型別系統差異**：SQLite 的型別系統較為寬鬆
3. **並發處理**：MySQL 支援更好的並發，SQLite 適合單使用者或低並發
4. **功能豐富度**：MySQL 功能更豐富，SQLite 更輕量
5. **SQL 標準**：大部分基本 SQL 語法兩者都支援

這個對照表涵蓋了日常開發中最常用的指令，希望對你的學習有幫助！