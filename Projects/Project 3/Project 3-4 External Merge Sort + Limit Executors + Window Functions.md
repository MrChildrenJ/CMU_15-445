# Task #4 - External Merge Sort + Limit Executors + Window Functions

![Project 0 Result](./2025fall_p3_complete.png)
![Project 0 Result](./2025fall_p3_leaderboard.png)

## External Merge Sort
### bound_order_by.h
- OrderBy = std::tuple<OrderByType, OrderByNullType, AbstractExpressionRef>
  - std::get<0>(order_by) 取得排序方向 (ASC/DESC/DEFAULT)
  - std::get<1>(order_by) 取得 NULL 處理方式 (NULLS_FIRST/NULLS_LAST/DEFAULT)
  - std::get<2>(order_by) 取得排序的表達式

### execution_common.h
**class TupleComparator**
- SortKey = std::vector<Value> - 排序用的鍵值
- SortEntry = std::pair<SortKey, Tuple> - 包含排序鍵和原始 tuple
- TupleComparator::operator() - 比較兩個 SortEntry
- GenerateSortKey() - 從 tuple 產生排序鍵

### TupleComparator 比較邏輯
- 依序比較每個排序欄位
- 先處理 NULL：NULLS_FIRST 時 NULL 排前面（回傳 true），NULLS_LAST 反之
- 兩個都是 NULL → 回傳 false（strict weak ordering）
- 非 NULL：ASC 時 a < b 回傳 true，DESC 反之
- 該欄位相等 → 繼續比較下一個欄位
- 全部相等 → 回傳 false
- DEFAULT 排序 = ASC；DEFAULT NULL = ASC 時 NULLS_FIRST，DESC 時 NULLS_LAST

### MergeSortRun 與 Iterator
- MergeSortRun：儲存一個 sorted run 的 page IDs (`std::vector<page_id_t>`)
- Iterator 成員：`page_idx_`（目前在第幾個 page）、`tuple_idx_`（page 中第幾個 tuple）
- Begin()：page_idx_ = 0, tuple_idx_ = 0
- End()：page_idx_ = pages_.size()（超過最後一個 page）
- operator++：tuple_idx_++，若超過該 page 的 tuple 數量則 page_idx_++, tuple_idx_ = 0
- operator*：從 bpm 讀取 page，用 GetTuple(tuple_idx_) 取得 tuple

### External Merge Sort 演算法流程
**Pass 0（建立初始 runs）：**
1. 從 child executor 讀取 tuples 到 vector
2. 追蹤總大小：tuple.GetLength() + 4 bytes (TupleInfo)
3. 接近 PAGE_SIZE 時，用 std::sort 排序 vector
4. 寫入新 page → 成為一個 run
5. 重複直到 child 無資料；處理最後剩餘的 tuples

**Pass 1+（合併階段）：**
1. 兩兩合併相鄰 runs（two-way merge）
2. 奇數個 runs 時，落單的直接保留到下一輪
3. 合併邏輯：比較兩個 iterator 指向的 tuple，較小的輸出並 ++
4. 舊 runs 的 pages 要 DeletePage()
5. 重複直到只剩 1 個 run

### ExternalMergeSortExecutor 私有成員
- `child_executor_`：讀取原始資料
- `bpm_`：指標，透過 exec_ctx_->GetBufferPoolManager() 取得
- `result_`：最終排序完成的 MergeSortRun
- `iterator_`：追蹤 Next() 目前讀到哪裡

## Window Functions

### 與 Aggregation 的差異
- Aggregation (GROUP BY)：每個 group 壓縮成一行
- Window Function：保留所有原始 rows，每行附加一個計算結果

### Window Frame 規則（不需實作自訂 frame）
- **有 ORDER BY**：計算範圍 = partition 內第一行到當前行（累積）
- **無 ORDER BY**：計算範圍 = 整個 partition（所有行結果相同）

### Plan 結構
- `columns_`：所有輸出欄位，window function 的位置用 placeholder 佔位
- `window_functions_`：`unordered_map<uint32_t, WindowFunction>`，key = column index
  - 每個 WindowFunction 包含：`function_`, `type_`, `partition_by_`, `order_by_`
- 判斷第 i 個欄位是普通欄位還是 window function：檢查 `window_functions_.count(i)`

### Init() 流程（B → D → A → C）
1. **B**：從 child 讀取所有 tuples
2. **D**：依 (partition_by + order_by) 排序 → 同 partition 的 tuples 自然相鄰
3. **A**：遍歷排序後的 tuples，計算 window function 值
   - 偵測新 partition 時，累積值歸零/重置
4. **C**：組合每行輸出（普通欄位用 `columns_[i]` 表達式計算，window function 位置填計算結果）

### 私有成員變數
- `std::vector<Tuple> tuples_`：存所有算好的結果
- `size_t cursor_`：追蹤 Next() 輸出位置

### RANK 規則
- 相同 ORDER BY 值 → 同排名（tie）
- 下一個不同值 → 排名 = 該 tuple 的實際位置（跳號）
- 例：a=1, b=2, b=2, c=4
- 需追蹤：**當前位置**（每 tuple +1）和**當前排名**（值改變時才更新為當前位置）

### 可重用的程式碼
- Sort Executor 的排序邏輯（步驟 D）
- Aggregation 的 `CombineAggregateValues` 計算邏輯（步驟 A），但不需要 hash table

## C++
### operator== / operator!= 實作注意事項
- **錯誤寫法（無限遞迴）：** `return *this == other;` ← 會呼叫自己，造成 stack overflow
- **正確寫法：** 比較實際成員變數，例如 `return a_ == other.a_ && b_ == other.b_;`
- `operator!=` 可以用 `return !(*this == other);`，前提是 `operator==` 已正確實作
