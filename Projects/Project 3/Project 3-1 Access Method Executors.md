# Project 3 Notes

![Project 0 Result](./2025fall_p3_complete.png)
![Project 0 Result](./2025fall_p3_leaderboard.png)

## Explain
- **Binder**: Semantic analysis, parses SQL syntax tree, binds table names and column names to actual schema objects
- **Planner**: Logical execution plan, represented as a tree structure
- **Optimizer**: Optimized plan (reorder joins, push down filters, choose Index Scan vs Sequential Scan)

## EXPLAIN Reading Tips

| Symbol/Format | Meaning |
|---------------|---------|
| Indentation | Parent-child relationship (deeper indentation = executed first) |
| `{ ... }` | Node parameters |
| `\| (...)` | Output schema (column_name:type) |
| `#0.0` | 0th column from the 0th child node |

## Core Classes

**Execution Engine**
- abstract_executor.h - Base class for all executors, defines Init() and Next() interface (batch vectorization model)
- executor_context.h - Provides catalog, buffer pool manager, transaction and other resources
- executor_factory.cpp - Creates corresponding executor based on plan type

**Plans and Expressions**
- abstract_plan.h - Base class for all plan nodes
- abstract_expression.h - Defines Evaluate() and EvaluateJoin()

**Helper Classes**
- catalog.h - GetTable(table_oid) to get TableInfo, GetTableIndexes() to get indexes
- table_heap.h - MakeIterator() to create table iterator, InsertTuple() to insert data
- table_iterator.h - GetTuple(), GetRID(), IsEnd(), operator++()
- index.h - InsertEntry() / DeleteEntry() to manipulate indexes

## Relationship Between Plan, Executor, and Expression
- **Plan**: Tree structure describing "what to do" (pure data, no execution)
- **Executor**: Actually "executes" the plan logic (Init() to initialize, Next() to iterate and produce results)
- **Expression**: Describes "how to compute values" (used in projection, filter, join conditions, calls Evaluate() to compute Value)

Execution flow: Executor reads Plan → calls Expression.Evaluate() to compute values → produces results

## Task 1 - Access Method Executors

### Sequential Scan

**Data Source**: Get table from `table_oid_` in `SeqScanPlanNode`

**Traversal Method**: Use `TableIterator` to traverse all tuples (no need to manually handle pages)
- Path: exec_ctx → Catalog → TableInfo → TableHeap → MakeIterator()

**Easy to Miss: filter_predicate_**
- SeqScan's Next() must apply `plan_->filter_predicate_`, otherwise WHERE conditions won't work
- Call `Evaluate(&tuple, GetOutputSchema())` on each tuple, get boolean value
- If false, continue to skip that tuple

### Insert

**Difference from Projection**
- Projection: May reach batch_size midway, needs to pause and remember progress → child_tuples and child_rids are member variables
- Insert: One Next() consumes all child tuples, no need to pause → local variables are sufficient

**Execution Flow**
1. Get all tuples from child executor
2. For each tuple:
   - Use InsertTuple() to insert into table_heap, get RID
   - For all indexes: use KeyFromTuple() to create key, call InsertEntry() to insert into index
3. Return number of inserted rows

**Two Cases**
- `INSERT INTO t1 VALUES (...)` → child is ValuesExecutor
- `INSERT INTO t1 SELECT * FROM t2` → child is SeqScanExecutor or ProjectionExecutor

### Update

**Concept**: Update = Delete first, then Insert (implement Delete first, then merge)

**Common Mistake 1**: Must use `plan_->target_expressions_` to compute new tuple
- Call Evaluate() on each expression to produce new values
- Cannot directly insert old tuple

**Common Mistake 2**: When updating index, DeleteEntry uses old key, InsertEntry uses new key
- Because UPDATE might modify index key columns

### Delete

**Soft Delete**: table_heap has no DeleteEntry, instead marks `is_deleted_` as true

**Reasons**
- MVCC (Multi-Version Concurrency Control): Other transactions may still be reading old versions
- Simplify implementation: Physical deletion requires page reorganization, moving tuples, updating all RID references
- Real systems have Garbage Collection (PostgreSQL: VACUUM, MySQL InnoDB: Purge thread)

### Index Scan

**Purpose**: Use B+ Tree index to quickly find data, instead of scanning the entire table

**Two Modes**

| Mode | SQL Example | Description |
|------|-------------|-------------|
| Point Lookup | `WHERE v1 = 1` | Use index to directly locate |
| Ordered Scan | `ORDER BY v1` | Scan all data in order (utilizing B+ Tree ordering) |

**Init() Must Distinguish Between Two Modes**
- `pred_keys_.empty()` → Ordered Scan: Use GetBeginIterator() to traverse from start to end
- Otherwise → Point Lookup: Use ScanKey to lookup each pred_key

### Optimization (seqscan_as_indexscan.cpp)

**Goal**: Convert `SeqScan` + `WHERE column = constant` to `IndexScan` (recommended to do optimization first)

**Conversion Example**: `SeqScan { filter=(v1=1) }` → `IndexScan { pred_keys_=[1] }`

**Cases to Handle**

| Case | SQL Example | How to Handle |
|------|-------------|---------------|
| Basic | `WHERE v1 = 1` | column = constant |
| Reversed order | `WHERE 1 = v1` | Check both left and right sides |
| Multiple ORs | `WHERE v1 = 1 OR v1 = 4` | Parse LogicExpression, collect multiple pred_keys |
| **Do not handle** | `WHERE v1 = 1 AND v2 = 2` | Keep as SeqScan, don't split predicate |

**Conversion Conditions (all must be satisfied)**
1. Plan type is SeqScan
2. filter_predicate_ is not null
3. predicate is ComparisonExpression(Equal) or LogicExpression(OR + multiple Equals)
4. One side is ColumnValueExpression, the other side is ConstantValueExpression
5. The column has a corresponding index

**Optimizer Rule Fixed Flow**
1. Recursively process children, use CloneWithChildren() to copy plan (PlanNode is immutable)
2. Check if it's SeqScan, use dynamic_cast to cast
3. Check if it has filter_predicate_
4. Check if it's in the form of column = constant (try both left and right sides)
5. Check if the column has an index (use GetTableIndexes() to get all indexes, compare GetKeyAttrs())
6. Create IndexScanPlanNode

**OR Condition Handling**
- 2 ORs: `WHERE v1 = 1 OR v1 = 4` → Single-layer LogicExpression
- 3+ ORs: `WHERE v1 = 1 OR v1 = 2 OR v1 = 3` → Nested (left-leaning) LogicExpression

**Common Mistake**: Only handling single-layer OR → Cannot convert when 3+ OR conditions

**Solution**: Write recursive helper function `CollectOrPredicates`
- When encountering LogicExpression(Or) → Recursively process left and right children
- When encountering ComparisonExpression(Equal) → Parse column/constant, check same column, add to pred_keys
- Other cases → Return false

---

## Explain
- **Binder**: 語意分析，解析 SQL 語法樹，將表名、列名綁定到實際的 schema 物件上
- **Planner**: 邏輯執行計劃，用樹狀結構表示
- **Optimizer**: 優化後的計劃（重排 Join 順序、將 Filter 下推、選擇使用 Index Scan vs Sequential Scan）

## EXPLAIN 閱讀技巧

| 符號/格式 | 含義 |
|-----------|------|
| 縮排 | 表示父子關係（縮排越深 = 越先執行） |
| `{ ... }` | 節點的參數 |
| `\| (...)` | 輸出的 schema（列名:類型） |
| `#0.0` | 第 0 個子節點的第 0 欄位 |

## 核心類別

**執行引擎**
- abstract_executor.h - 所有 executor 的基類，定義 Init() 和 Next() 介面（batch vectorization 模型）
- executor_context.h - 提供 catalog、buffer pool manager、transaction 等資源
- executor_factory.cpp - 根據 plan type 建立對應的 executor

**計劃與表達式**
- abstract_plan.h - 所有 plan node 的基類
- abstract_expression.h - 定義 Evaluate() 和 EvaluateJoin()

**輔助類別**
- catalog.h - GetTable(table_oid) 取得 TableInfo，GetTableIndexes() 取得索引
- table_heap.h - MakeIterator() 建立 table iterator，InsertTuple() 插入資料
- table_iterator.h - GetTuple(), GetRID(), IsEnd(), operator++()
- index.h - InsertEntry() / DeleteEntry() 操作索引

## Plan, Executor, Expression 三者關係
- **Plan**：描述「要做什麼」的樹狀結構（純資料，不執行）
- **Executor**：實際「執行」plan 的邏輯（Init() 初始化、Next() 迭代產生結果）
- **Expression**：描述如何「計算值」（用於 projection、filter、join 條件，呼叫 Evaluate() 計算出 Value）

執行流程：Executor 讀取 Plan → 呼叫 Expression.Evaluate() 計算值 → 產生結果

## Task 1 - Access Method Executors

### Sequential Scan

**資料來源**：從 `SeqScanPlanNode` 的 `table_oid_` 取得 table

**遍歷方式**：使用 `TableIterator` 遍歷所有 tuple（不需手動處理 page）
- 路徑：exec_ctx → Catalog → TableInfo → TableHeap → MakeIterator()

**易漏：filter_predicate_**
- SeqScan 的 Next() 必須套用 `plan_->filter_predicate_`，否則 WHERE 條件無效
- 對每個 tuple 呼叫 `Evaluate(&tuple, GetOutputSchema())`，取出布林值
- 若為 false 則 continue 跳過該 tuple

### Insert

**和 Projection 的區別**
- Projection: 可能處理到一半就達到 batch_size，要暫停並記住進度 → child_tuples 和 child_rids 是 member variable
- Insert: 一次 Next() 把所有 child tuples 都消耗完，不需暫停 → local variable 即可

**執行流程**
1. 從 child executor 取得所有 tuples
2. 對每個 tuple：
   - 用 InsertTuple() 插入 table_heap，取得 RID
   - 對所有 index：用 KeyFromTuple() 建立 key，呼叫 InsertEntry() 插入索引
3. 回傳插入筆數

**兩種情況**
- `INSERT INTO t1 VALUES (...)` → child 是 ValuesExecutor
- `INSERT INTO t1 SELECT * FROM t2` → child 是 SeqScanExecutor 或 ProjectionExecutor

### Update

**概念**：Update = 先 Delete 再 Insert（先實作 Delete 再融合）

**易錯點 1**：必須用 `plan_->target_expressions_` 計算新 tuple
- 對每個 expression 呼叫 Evaluate() 產生新的 values
- 不能直接插入舊 tuple

**易錯點 2**：索引更新時，DeleteEntry 用舊 key，InsertEntry 用新 key
- 因為 UPDATE 可能改到 index key 欄位

### Delete

**軟性刪除**：table_heap 沒有 DeleteEntry，而是標記 `is_deleted_` 為 true

**原因**
- MVCC 多版本並發控制：其他 transaction 可能還在讀取舊版本
- 簡化實作：物理刪除需要頁面整理、移動 tuple、更新所有 RID 引用
- 實際系統有 Garbage Collection（PostgreSQL: VACUUM, MySQL InnoDB: Purge thread）

### Index Scan

**目的**：用 B+ Tree 索引來快速找資料，而不是掃描整張表

**兩種模式**

| 模式 | SQL 範例 | 說明 |
|------|----------|------|
| Point Lookup | `WHERE v1 = 1` | 用索引直接定位 |
| Ordered Scan | `ORDER BY v1` | 按順序掃描所有資料（利用 B+ Tree 有序性） |

**Init() 要區分兩種模式**
- `pred_keys_.empty()` → Ordered Scan：用 GetBeginIterator() 從頭到尾遍歷
- 否則 → Point Lookup：用 ScanKey 查找每個 pred_key

### Optimization (seqscan_as_indexscan.cpp)

**目標**：將 `SeqScan` + `WHERE column = constant` 轉換為 `IndexScan`（建議先做 optimization）

**轉換範例**：`SeqScan { filter=(v1=1) }` → `IndexScan { pred_keys_=[1] }`

**需要處理的情況**

| 情況 | SQL 範例 | 處理方式 |
|------|----------|----------|
| 基本 | `WHERE v1 = 1` | column = constant |
| 順序對調 | `WHERE 1 = v1` | 檢查左右兩邊都要試 |
| 多個 OR | `WHERE v1 = 1 OR v1 = 4` | 解析 LogicExpression，收集多個 pred_keys |
| **不處理** | `WHERE v1 = 1 AND v2 = 2` | 維持 SeqScan，不拆分 predicate |

**轉換條件（全部滿足）**
1. Plan 類型是 SeqScan
2. filter_predicate_ 不為 null
3. predicate 是 ComparisonExpression(Equal) 或 LogicExpression(OR + 多個 Equal)
4. 一邊是 ColumnValueExpression，另一邊是 ConstantValueExpression
5. 該欄位有對應的 index

**Optimizer Rule 固定流程**
1. 遞迴處理 children，用 CloneWithChildren() 複製 plan（PlanNode 是 immutable）
2. 檢查是否為 SeqScan，用 dynamic_cast 轉型
3. 檢查是否有 filter_predicate_
4. 檢查是否為 column = constant 形式（左右兩邊都要試）
5. 檢查該欄位是否有 index（用 GetTableIndexes() 取得所有 index，比對 GetKeyAttrs()）
6. 建立 IndexScanPlanNode

**OR 條件處理**
- 2 個 OR：`WHERE v1 = 1 OR v1 = 4` → 單層 LogicExpression
- 3+ 個 OR：`WHERE v1 = 1 OR v1 = 2 OR v1 = 3` → nested（左偏）LogicExpression

**易錯點**：只處理單層 OR → 3+ 個 OR 條件時無法轉換

**解決方式**：寫遞迴 helper function `CollectOrPredicates`
- 遇到 LogicExpression(Or) → 遞迴處理左右子節點
- 遇到 ComparisonExpression(Equal) → 解析 column/constant，檢查同一 column，加入 pred_keys
- 其他情況 → 回傳 false
