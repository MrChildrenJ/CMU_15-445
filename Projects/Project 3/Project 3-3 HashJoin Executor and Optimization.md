# Task #3 - HashJoin Executor and Optimization

![Project 0 Result](./2025fall_p3_complete.png)
![Project 0 Result](./2025fall_p3_leaderboard.png)

## HashJoin Executor

### Basic Flow
- **Build Phase**: Build hash table on right table (in `Init()`)
- **Probe Phase**: Iterate through left table, lookup in hash table for matches (in `Next()`)
- Using right table for build and left table for probe naturally handles Left Outer Join:
  - Match found → Output `(left_tuple, right_tuple)`
  - No match → Output `(left_tuple, NULL...)`

### Grace Hash Join (When Memory Insufficient)

**Partition Phase:**
- Use hash function h1 to partition left table into k buckets: L0, L1, ..., L(k-1)
- Use **same** h1 to partition right table into k buckets: R0, R1, ..., R(k-1)
- Same join key → Must fall into same bucket number (key to correctness)
- Each partition (bucket) stores a `vector<page_id_t>` recording all page ids belonging to that partition

**Probe Phase:**
- For each pair (Li, Ri):
  - Read Ri, build hash table using h2
  - Use Li's tuples to probe
- **h1 and h2 must be different**: Avoid tuples with h1 collision also colliding in h2, which would degrade hash table to O(n) lookup

**Implementation:**
- **GHJ_Init()**: Read all tuples from child executors → Hash partition → Write to disk (record page_ids)
  - BPM APIs: `NewPage()` to create new page, `WritePage(page_id)` to get WritePageGuard
- **GHJ_Next()**: For each partition pair i:
  - Use `FetchPage()` to read right partition i from disk → Build in-memory hash table
  - Use `FetchPage()` to read left partition i tuples → Probe hash table → Output results
  - BPM APIs: `ReadPage(page_id)` to get ReadPageGuard, `DeletePage(page_id)` to delete page

### IntermediateResultPage Design

Used to store partition phase intermediate results, uses **slotted page** structure:
- One page stores only **one table's one bucket** tuples (same schema, easier management)
- Header: tuple count, free space offset, etc.
- Slot array: Grows downward from top, records each tuple's position
- Tuple data: Grows upward from page bottom
- Supports variable-length tuples (VARCHAR)
- Single tuple won't exceed page size, no need to handle cross-page storage

**Page Overlay:**
- Class only defines header members + zero-size array as boundary marker
- `sizeof(IntermediateResultPage)` only has header size
- Use `reinterpret_cast` to interpret 4KB buffer as this class
- Member access automatically maps to corresponding memory location

**⚠️ Important: TupleInfo must use plain struct, not std::tuple**
- `std::tuple` is not POD, memory layout decided by compiler
- May have extra padding or overhead
- `reinterpret_cast` on raw byte buffer causes data read/write corruption
- This causes **heap-buffer-overflow**
- Use plain struct to guarantee fixed memory layout

### Executor State Management

Required member variables:
- `bucket_idx_`: Current bucket number being processed
- `left_idx_`: Current tuple index in left bucket
- `right_match_idx_`: When one left tuple matches multiple right tuples, tracks which one being processed
- `matched_`: Tracks if current left tuple found a match (for Left Outer Join)

**⚠️ Must reset `matched_tuples_` when switching partitions**
- `matched_tuples_` is a pointer to a vector in `ht_`
- Calling `ht_.clear()` destroys those vectors
- If not reset first, `matched_tuples_` becomes dangling pointer
- Next access to `matched_tuples_->size()` causes **use-after-free**
- Must reset to `nullptr` before calling `ht_.clear()`

## In-memory Hash Join Implementation

### hash_join_plan.h

**JoinKey struct:**
- `operator==`: Compare keys_ one by one, NULL == NULL treated as equal (special handling)

**⚠️ NULL Handling SQL Semantics Issue:**
- In SQL standard, JOIN's ON condition (e.g., `t1.a = t2.a`) should return FALSE if both sides are NULL
- Current implementation treats `NULL == NULL` as TRUE, may cause incorrect matches
- Strictly speaking, keys containing NULL shouldn't be inserted into hash table, and shouldn't match when probing

**std::hash<JoinKey> specialization (must be in namespace std):**
- Allows `std::unordered_map<JoinKey, ...>` to work correctly

### hash_join_executor.h

**Member Variables:**
- `ht_`: `std::unordered_map<JoinKey, std::vector<Tuple>>` - Right table's hash table
- `left_tuples_`: Current batch read from left child
- `left_tuple_idx_`: Current tuple index in batch
- `matched_tuples_`: Pointer to right table tuples matching current left tuple
- `right_match_idx_`: Current match index for current left tuple
- `has_match_`: Whether current left tuple found any match (for LEFT JOIN)
- `no_matches_`: **Static empty vector**, used to distinguish "not yet looked up" from "looked up but no match"

**MakeJoinKey() needs three parameters (unlike MakeAggregateKey):**
- Hash Join has two children, left and right table schemas are different
- Left table tuple uses `LeftJoinKeyExpressions()` + left table schema
- Right table tuple uses `RightJoinKeyExpressions()` + right table schema

### hash_join_executor.cpp

**Init() - Build Phase:**
- Clear hash table
- Reset all state
- Build: Read all right table tuples, build hash table

**Next() - Probe Phase (loop with three cases):**
- Case 1: Still have matches to output
- Case 2: Current left tuple processed, handle LEFT JOIN null
- Case 3: Move to next left tuple, do hash lookup for new left tuple

**Key Design: `no_matches_` Three-State Semantics**
- `nullptr`: Initial state, no hash lookup done yet
- `&no_matches_` (empty vector): Lookup done but no match found
- `&it->second` (non-empty vector): Lookup done and match found

**Why both Case 1 and Case 2 use `!= nullptr` instead of `!= &no_matches_`:**
- **Case 1**: `matched_tuples_ != nullptr && right_match_idx_ < matched_tuples_->size()`
  - Use `!= nullptr` because the `size()` check naturally filters out `&no_matches_` (size=0)
  - Using `!= nullptr` is safer (avoids calling `size()` on nullptr)
- **Case 2**: `matched_tuples_ != nullptr && !has_match_ && LEFT_JOIN`
  - Must use `!= nullptr` because we **want** `&no_matches_` to enter this case
  - `&no_matches_` represents "looked up but no match", exactly when LEFT JOIN should output NULL
  - Using `!= &no_matches_` would **incorrectly exclude** this case

## Optimizer: NLJ → HashJoin

### Applicable Conditions
- Hash Join can only handle **equi-join** (equality join)
- `t1.a = t2.b` ✅ Can use Hash Join
- `t1.a > t2.b` ❌ Cannot

### Recursively Extract Join Keys

Predicate is an expression tree, e.g., `(t1.a = t2.a) AND (t1.b = t2.c)` forms an AND tree with equality comparisons.

Recursive logic:
- **AND (Logic Expression)**: Recursively process left and right operands
- **= (Comparison Expression)**: Base case, extract left/right key

### Note Column Ownership

Equality might be written as `t2.b = t1.a` (right table column on left side), use `ColumnValueExpression::GetTupleIdx()` to determine:
- `GetTupleIdx() == 0` → Left table → Add to left_keys
- `GetTupleIdx() == 1` → Right table → Add to right_keys

## Common Mistakes and Debugging

### 1. heap-buffer-overflow in IntermediateResultPage
**Symptom**: Overflow in `SerializeTo()` or `memcpy()`, write position at page boundary
**Cause**: Using `std::tuple<uint16_t, uint16_t>` as TupleInfo - not POD, memory layout not fixed
**Solution**: Use plain struct with fixed layout

### 2. use-after-free in HashJoinExecutor::Next()
**Symptom**: Crash when accessing `matched_tuples_->size()`
**Cause**: `matched_tuples_` points to vector in `ht_`, but `ht_.clear()` called when switching partition
**Solution**: Reset pointer to `nullptr` before `ht_.clear()`

### 3. Type Conversion Issue
**Symptom**: Offset calculation error, writing to wrong position
**Cause**: `free_space_pointer` (uint16_t) mixed with `tuple.GetLength()` (uint32_t)
**Solution**: Use explicit local variables and explicit casting

### 4. Gradescope Compilation Error: JoinKey Undefined
**Symptom**: Compiles locally but Gradescope reports `unknown type name 'JoinKey'`
**Cause**: `make submit-p3` doesn't include `hash_join_plan.h` - only includes `hash_join_executor.h` and `.cpp`
**Solution**: Move `JoinKey` struct and `std::hash<JoinKey>` specialization to `hash_join_executor.h`
- Note: `std::hash<JoinKey>` must be defined before `HashJoinExecutor` class (since class uses `std::unordered_map<JoinKey, ...>`)
- Need to temporarily close `namespace bustub`, define `std::hash`, then reopen

---

# Task #3 - HashJoin Executor and Optimization

## HashJoin Executor

### 基本流程
- **Build Phase**: 對右表建立 hash table（放在 `Init()`）
- **Probe Phase**: 遍歷左表，去 hash table 查找匹配（放在 `Next()`）
- 用右表 build、左表 probe 的方式，在遍歷左表時就能自然地處理 Left Outer Join：
  - 找到匹配 → 輸出 `(left_tuple, right_tuple)`
  - 沒找到匹配 → 輸出 `(left_tuple, NULL...)`

### Grace Hash Join（記憶體不夠時）

**Partition Phase:**
- 用 hash function h1 把左表分成 k 個 bucket: L0, L1, ..., L(k-1)
- 用**同一個** h1 把右表分成 k 個 bucket: R0, R1, ..., R(k-1)
- 相同 join key → 一定落在相同編號的 bucket（這是正確性的關鍵）
- 每個 partition (bucket) 存一個 `vector<page_id_t>`，記錄屬於該 partition 的所有 page ids

**Probe Phase:**
- 對每一對 (Li, Ri)：
  - 讀入 Ri，用 h2 建立 hash table
  - 用 Li 的 tuple 來 probe
- **h1 和 h2 必須不同**：避免 h1 collision 的 tuple 在 h2 也 collision，導致 hash table 退化成 O(n) 查詢

**實作：**
- **GHJ_Init()**: 從 child executors 讀取所有 tuples → Hash partition → 寫到磁碟（記錄 page_ids）
  - BPM APIs: `NewPage()` 建立新 page，`WritePage(page_id)` 取得 WritePageGuard
- **GHJ_Next()**: 對於 partition pair i：
  - 用 `FetchPage()` 從磁碟讀回 right partition i → 建立 in-memory hash table
  - 用 `FetchPage()` 從磁碟讀回 left partition i tuples → Probe hash table → 輸出結果
  - BPM APIs: `ReadPage(page_id)` 取得 ReadPageGuard，`DeletePage(page_id)` 刪除 page

### IntermediateResultPage 設計

用於存放 partition phase 的中間結果，採用 **slotted page** 結構：
- 一個 page 只存**一個表的一個 bucket** 的 tuple（相同 schema，方便管理）
- Header: tuple count、free space offset 等
- Slot array: 從上往下長，記錄每個 tuple 的位置
- Tuple data: 從 page 底部往上長
- 支援變長 tuple（VARCHAR）
- 單個 tuple 不會超過 page size，不需處理跨頁存儲

**Page Overlay：**
- Class 只定義 header 成員 + 零大小數組作為邊界標記
- `sizeof(IntermediateResultPage)` 只有 header 大小
- 使用 `reinterpret_cast` 將 4KB buffer 解讀為此 class
- 存取成員時自動映射到對應的記憶體位置

**⚠️ 重要：TupleInfo 必須使用 plain struct，不能用 std::tuple**
- `std::tuple` 不是 POD，記憶體佈局由編譯器決定
- 可能有額外 padding 或 overhead
- 對 raw byte buffer 做 `reinterpret_cast` 時會導致資料讀寫錯亂
- 這會造成 **heap-buffer-overflow**
- 使用 plain struct 保證固定的記憶體佈局

### Executor 狀態管理

需要的 member variables：
- `bucket_idx_`: 目前處理的 bucket 編號
- `left_idx_`: 目前左表 bucket 處理到第幾個 tuple
- `right_match_idx_`: 當一個左表 tuple 匹配多個右表 tuple 時，追蹤處理到第幾個
- `matched_`: 追蹤當前左表 tuple 是否找到匹配（用於 Left Outer Join）

**⚠️ 切換 partition 時必須重置 `matched_tuples_`**
- `matched_tuples_` 是指向 `ht_` 中 vector 的指標
- 呼叫 `ht_.clear()` 會銷毀那些 vector
- 如果不先重置，`matched_tuples_` 會變成 dangling pointer
- 下次存取 `matched_tuples_->size()` 時會造成 **use-after-free**
- 必須在呼叫 `ht_.clear()` 之前重置為 `nullptr`

## In-memory Hash Join 實作

### hash_join_plan.h

**JoinKey struct:**
- `operator==`: 逐一比較 keys_，NULL == NULL 視為相等（特殊處理）

**⚠️ NULL 處理的 SQL 語意問題：**
- SQL 標準中，JOIN 的 ON 條件（如 `t1.a = t2.a`）若兩邊都是 NULL，結果應為 FALSE
- 目前實作將 `NULL == NULL` 視為 TRUE，可能導致錯誤匹配
- 嚴格來說，包含 NULL 的 key 不應插入 hash table，probe 時也不應匹配

**std::hash<JoinKey> 特化（必須在 namespace std 裡）:**
- 讓 `std::unordered_map<JoinKey, ...>` 能正確運作

### hash_join_executor.h

**成員變數：**
- `ht_`: `std::unordered_map<JoinKey, std::vector<Tuple>>` - 右表的 hash table
- `left_tuples_`: 當前從 left child 讀取的 batch
- `left_tuple_idx_`: 目前處理到 batch 中的哪個 tuple
- `matched_tuples_`: 指向當前 left tuple 匹配的右表 tuples
- `right_match_idx_`: 當前 left tuple 處理到第幾個 match
- `has_match_`: 當前 left tuple 是否找到過匹配（用於 LEFT JOIN）
- `no_matches_`: **靜態空 vector**，用於區分「還沒 lookup」和「lookup 了但沒匹配」

**MakeJoinKey() 需要三個參數（不同於 MakeAggregateKey）：**
- Hash Join 有兩個 child，左右表 schema 不同
- 左表 tuple 用 `LeftJoinKeyExpressions()` + 左表 schema
- 右表 tuple 用 `RightJoinKeyExpressions()` + 右表 schema

### hash_join_executor.cpp

**Init() - Build Phase:**
- 清空 hash table
- 重設所有狀態
- Build: 讀取右表所有 tuples，建立 hash table

**Next() - Probe Phase（三種情況的迴圈）：**
- Case 1: 還有 match 要輸出
- Case 2: 當前 left tuple 處理完了，處理 LEFT JOIN null
- Case 3: 移動到下一個 left tuple，對新的 left tuple 做 hash lookup

**關鍵設計：`no_matches_` 的三狀態語意**
- `nullptr`: 初始狀態，還沒做過任何 hash lookup
- `&no_matches_`（空 vector）: 做過 lookup 但沒找到匹配
- `&it->second`（非空 vector）: 做過 lookup 且有匹配

**為什麼 Case 1 和 Case 2 都用 `!= nullptr` 而非 `!= &no_matches_`：**
- **Case 1**: `matched_tuples_ != nullptr && right_match_idx_ < matched_tuples_->size()`
  - 用 `!= nullptr` 是因為後面的 `size()` 檢查會自然過濾掉 `&no_matches_`（其 size=0）
  - 用 `!= nullptr` 更安全（避免對 nullptr 呼叫 `size()`）
- **Case 2**: `matched_tuples_ != nullptr && !has_match_ && LEFT_JOIN`
  - 必須用 `!= nullptr`，因為我們**希望** `&no_matches_` 進入這個 case
  - `&no_matches_` 代表「做過 lookup 但沒匹配」，正是 LEFT JOIN 要輸出 NULL 的情況
  - 如果用 `!= &no_matches_`，會**錯誤地排除**這種情況

## Optimizer: NLJ → HashJoin

### 適用條件
- Hash Join 只能處理 **equi-join**（等值連接）
- `t1.a = t2.b` ✅ 可以用 Hash Join
- `t1.a > t2.b` ❌ 不行

### 遞迴提取 Join Keys

Predicate 是一個 expression tree，例如 `(t1.a = t2.a) AND (t1.b = t2.c)` 形成 AND 樹與等值比較。

遞迴邏輯：
- **AND (Logic Expression)**: 遞迴處理左右 operand
- **= (Comparison Expression)**: base case，提取 left/right key

### 注意 Column 歸屬

等式可能寫成 `t2.b = t1.a`（右表 column 在左邊），需要用 `ColumnValueExpression::GetTupleIdx()` 判斷：
- `GetTupleIdx() == 0` → 左表 → 放入 left_keys
- `GetTupleIdx() == 1` → 右表 → 放入 right_keys

## 常見錯誤與除錯經驗

### 1. heap-buffer-overflow in IntermediateResultPage
**症狀**: `SerializeTo()` 或 `memcpy()` 時發生 overflow，寫入位置剛好在 page 邊界
**原因**: 使用 `std::tuple<uint16_t, uint16_t>` 作為 TupleInfo - 不是 POD，記憶體佈局不固定
**解決**: 改用 plain struct 保證固定佈局

### 2. use-after-free in HashJoinExecutor::Next()
**症狀**: 存取 `matched_tuples_->size()` 時 crash
**原因**: `matched_tuples_` 指向 `ht_` 中的 vector，但切換 partition 時呼叫了 `ht_.clear()`
**解決**: 在 `ht_.clear()` 之前重置指標為 `nullptr`

### 3. 型別轉換問題
**症狀**: offset 計算錯誤，導致寫入錯誤位置
**原因**: `free_space_pointer` (uint16_t) 與 `tuple.GetLength()` (uint32_t) 混合運算
**解決**: 使用明確的 local variable 和顯式轉型

### 4. Gradescope 編譯錯誤：JoinKey 未定義
**症狀**: 本地編譯通過，但 Gradescope 報錯 `unknown type name 'JoinKey'`
**原因**: `make submit-p3` 打包的檔案不包含 `hash_join_plan.h` - 只包含 `hash_join_executor.h` 和 `.cpp`
**解決**: 將 `JoinKey` struct 和 `std::hash<JoinKey>` 特化移到 `hash_join_executor.h`
- 注意：`std::hash<JoinKey>` 必須在 `HashJoinExecutor` class 之前定義（因為 class 內使用了 `std::unordered_map<JoinKey, ...>`）
- 需要暫時關閉 `namespace bustub`，定義 `std::hash` 後再重新開啟
