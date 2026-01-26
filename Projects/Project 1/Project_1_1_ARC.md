# ARC Replacer Implementation Notes
## Task 1 - Adaptive Replacement Cache (ARC) Replacement Policy

## Project Overview
Implementation of CMU 15-445 (2025 Fall) Project 1 - ARC (Adaptive Replacement Cache) replacer for buffer pool management.

![Project 0 Result](./leaderboard.png)
![Project 0 Result](./2025fall_p1_complete.png)
---

## Core Concepts

### 1. ARC Algorithm Structure

**Four Lists:**

| List | Name | Content | Identifier Type | Purpose |
|------|------|---------|----------------|---------|
| T1 | `mru_` | Recently used once | `frame_id_t` | Recency-based cache |
| T2 | `mfu_` | Recently used multiple times | `frame_id_t` | Frequency-based cache |
| B1 | `mru_ghost_` | Evicted from T1 | `page_id_t` | Ghost history for T1 |
| B2 | `mfu_ghost_` | Evicted from T2 | `page_id_t` | Ghost history for T2 |

**Key Parameters:**

- **p (mru\_target\_size_)**: Target size for T1, dynamically adjusted based on workload
- **c (capacity\_)**: Maximum number of frames in buffer pool

**Critical Distinction:**
- Alive lists (T1/T2): Use `frame_id_t` (frames exist in memory)
- Ghost lists (B1/B2): Use `page_id_t` (no frame allocation, only metadata)

### 2. RecordAccess Four Cases

| Case | Condition | Action | Target List | Update p? | curr_size_ |
|------|-----------|--------|-------------|-----------|------------|
| 1 | Hit T1 | Move to front | T2 (upgrade) | No | No change |
| 1 | Hit T2 | Move to front | T2 (refresh) | No | No change |
| 2 | Hit B1 | Add to front | T2 | `p = min(p + δ, c)` | ++ |
| 3 | Hit B2 | Add to front | T2 | `p = max(p - δ, 0)` | ++ |
| 4 | Miss all | Add to front | T1 | No | ++ |

**Delta Calculation:**
- Hit B1: `δ = max(1, |B2| / |B1|)`
- Hit B2: `δ = max(1, |B1| / |B2|)`

**Ghost List Eviction (Case 4):**
- If `|T1| + |B1| == c`: Evict from B1 (pop back)
- Else if `|T1| + |T2| + |B1| + |B2| == 2c`: Evict from B2 (pop back)

**Important:** RecordAccess does NOT call Evict() - it only manages ghost list size

### 3. Role of mru_target_size_ (p)

**Purpose:**
- Balances T1 and T2 sizes based on workload pattern
- Used in Evict() to decide eviction priority
- NOT used to control evictable status

**Eviction Logic:**
- If `|T1| > p`: Prefer evicting from T1
- Otherwise: Prefer evicting from T2
- Adapts dynamically via ghost list hits

### 4. Evictable vs Non-Evictable

**Key Understanding:**

| Concept | Reality |
|---------|---------|
| T1/T2 distinction | Access pattern (recency vs frequency) |
| Evictable status | Controlled by SetEvictable() (pin/unpin) |
| Moving T1→T2 | Does NOT change evictable status |

**curr_size_ Semantics:**
- Tracks "alive AND evictable" frames only
- Changes when:
  - Evictable status changes (SetEvictable)
  - Page moves between alive/ghost (RecordAccess, Evict, Remove)

### 5. Evict() vs Remove()

| Aspect | Evict() | Remove() |
|--------|---------|----------|
| Trigger | Buffer pool full, needs space | Page permanently deleted |
| Selection | ARC algorithm chooses victim | Caller specifies frame_id |
| Destination | Move to ghost list (preserve history) | Completely removed |
| Use Case | Normal eviction | DROP TABLE, etc. |

---

## Key Implementation Points

### 1. Performance Optimization: O(1) List Operations

**Problem:**
- Using `std::find()` to locate elements is O(n)
- Performance test exceeded 30 seconds

**Solution:**
- Store iterator in metadata structure
- Use `std::list<int>::iterator` for universal compatibility (works for both `frame_id_t` and `page_id_t`)

**Critical Details:**

| Operation | Method | Note |
|-----------|--------|------|
| Get first iterator | `list.begin()` | Returns iterator |
| Get last iterator | `std::prev(list.end())` | NOT `list.back()` (returns value) |
| Insert front | `list.push_front(id); it = list.begin();` | Update iterator after insert |
| Insert back | `list.push_back(id); it = std::prev(list.end());` | Update iterator after insert |
| Remove | `list.erase(stored_iterator);` | O(1) removal |

**Type Compatibility:**
- `std::list<frame_id_t>::iterator` ≠ `std::list<page_id_t>::iterator`
- Use `std::list<int>::iterator` for both alive and ghost lists

**Result:** Performance test passes in <3s (previously >30s)

### 2. Reverse Iterator Conversion

**Problem:**
- `std::list::erase()` doesn't accept `reverse_iterator`

**Solution:**
```cpp
// Convert reverse_iterator to forward_iterator
auto forward_it = std::next(reverse_it).base();
list.erase(forward_it);
```

**Why `std::next(it).base()`?**
- `reverse_iterator::base()` points to element AFTER the reverse_iterator
- Need `std::next()` first to compensate offset

### 3. Heap-Use-After-Free: Dangling References

**Common Patterns:**

| Problem Pattern | Fix |
|----------------|-----|
| `auto& ref = map[key]; map.erase(key);` | Copy value before erase: `auto val = map[key]; map.erase(key);` |
| `const T& ref = list.back(); list.pop_back();` | Use value not reference: `T val = list.back(); list.pop_back();` |

**Detection:**
- Use AddressSanitizer (ASan) for detailed stack traces
- Compile with `-fsanitize=address`

### 4. Common Misconceptions

| Misconception | Reality |
|---------------|---------|
| RecordAccess calls Evict() | RecordAccess only manages ghost lists |
| T1/T2 = evictable/non-evictable | T1/T2 = recency/frequency (both can be evictable) |
| Ghost lists use frame_id | Ghost lists use page_id (no frame allocation) |
| Moving T1→T2 changes evictability | Evictable status independent of T1/T2 membership |

### 5. Algorithm Flow

```
1. RecordAccess(frame_id, page_id, access_type)
   - Maintain list structure
   - Adjust mru_target_size_ based on ghost hits
   - Manage ghost list size

2. Evict() → frame_id
   - Select victim based on mru_target_size_
   - Move victim to appropriate ghost list
   - Return evicted frame_id

3. SetEvictable(frame_id, evictable)
   - Update evictable status
   - Update curr_size_ accordingly

4. Remove(frame_id)
   - Permanent deletion (no ghost list)
   - Used for DROP TABLE, etc.
```

---

## Common Pitfalls

1. Forgetting to update `curr_size_` when page moves between alive/ghost
2. Using `frame_id` instead of `page_id` for ghost lists
3. Calling Evict() from RecordAccess
4. Not handling case where all frames are pinned (Evict returns nullopt)
5. Using reference to element before erasing container

---
---

# ARC Replacer 實作筆記 (中文版)
## 任務 1 - 自適應替換快取 (ARC) 替換策略

## 專案概述
實作 CMU 15-445 (2025 Fall) Project 1 - ARC (Adaptive Replacement Cache) replacer，用於 buffer pool 管理。

---

## 核心概念

### 1. ARC 演算法結構

**四個列表：**

| 列表 | 名稱 | 內容 | 識別符型別 | 用途 |
|------|------|------|-----------|------|
| T1 | `mru_` | 最近使用過一次 | `frame_id_t` | 基於 recency 的快取 |
| T2 | `mfu_` | 最近使用過多次 | `frame_id_t` | 基於 frequency 的快取 |
| B1 | `mru_ghost_` | 從 T1 被淘汰 | `page_id_t` | T1 的幽靈歷史 |
| B2 | `mfu_ghost_` | 從 T2 被淘汰 | `page_id_t` | T2 的幽靈歷史 |

**關鍵參數：**

- **p (mru\_target\_size_)**：T1 的目標大小，根據工作負載動態調整
- **c (capacity\_)**：Buffer pool 中的最大 frame 數量

**關鍵區別：**
- Alive lists (T1/T2)：使用 `frame_id_t`（frame 存在於記憶體中）
- Ghost lists (B1/B2)：使用 `page_id_t`（無 frame 分配，僅 metadata）

### 2. RecordAccess 四種情況

| 情況 | 條件 | 動作 | 目標列表 | 更新 p？ | curr_size_ |
|------|------|------|---------|---------|------------|
| 1 | 命中 T1 | 移到最前面 | T2（升級） | 否 | 不變 |
| 1 | 命中 T2 | 移到最前面 | T2（刷新） | 否 | 不變 |
| 2 | 命中 B1 | 加到最前面 | T2 | `p = min(p + δ, c)` | ++ |
| 3 | 命中 B2 | 加到最前面 | T2 | `p = max(p - δ, 0)` | ++ |
| 4 | 全部未命中 | 加到最前面 | T1 | 否 | ++ |

**Delta 計算：**
- 命中 B1：`δ = max(1, |B2| / |B1|)`
- 命中 B2：`δ = max(1, |B1| / |B2|)`

**Ghost List 淘汰（Case 4）：**
- 若 `|T1| + |B1| == c`：從 B1 淘汰（pop back）
- 否則若 `|T1| + |T2| + |B1| + |B2| == 2c`：從 B2 淘汰（pop back）

**重要：** RecordAccess 不會呼叫 Evict() - 只管理 ghost list 大小

### 3. mru\_target\_size_ (p) 的作用

**目的：**
- 根據工作負載模式平衡 T1 和 T2 大小
- 在 Evict() 中用來決定淘汰優先順序
- 不用來控制 evictable 狀態

**淘汰邏輯：**
- 若 `|T1| > p`：優先從 T1 淘汰
- 否則：優先從 T2 淘汰
- 透過 ghost list 命中動態適應

### 4. Evictable vs Non-Evictable

**關鍵理解：**

| 概念 | 實際情況 |
|------|---------|
| T1/T2 區別 | 存取模式（recency vs frequency） |
| Evictable 狀態 | 由 SetEvictable() 控制（pin/unpin） |
| 移動 T1→T2 | 不會改變 evictable 狀態 |

**curr_size_ 語意：**
- 僅追蹤「alive 且 evictable」的 frame
- 在以下情況改變：
  - Evictable 狀態改變（SetEvictable）
  - 頁面在 alive/ghost 之間移動（RecordAccess, Evict, Remove）

### 5. Evict() vs Remove()

| 面向 | Evict() | Remove() |
|------|---------|----------|
| 觸發時機 | Buffer pool 滿了，需要空間 | 頁面被永久刪除 |
| 選擇方式 | ARC 演算法選擇 victim | 呼叫者指定 frame_id |
| 目的地 | 移到 ghost list（保留歷史） | 完全移除 |
| 使用場景 | 正常淘汰 | DROP TABLE 等 |

---

## 關鍵實作要點

### 1. 效能優化：O(1) List 操作

**問題：**
- 使用 `std::find()` 定位元素是 O(n)
- Performance test 超過 30 秒

**解決方案：**
- 在 metadata 結構中儲存 iterator
- 使用 `std::list<int>::iterator` 達到通用相容性（同時支援 `frame_id_t` 和 `page_id_t`）

**關鍵細節：**

| 操作 | 方法 | 注意 |
|------|------|------|
| 取得第一個 iterator | `list.begin()` | 返回 iterator |
| 取得最後一個 iterator | `std::prev(list.end())` | 不是 `list.back()`（返回值） |
| 插入最前面 | `list.push_front(id); it = list.begin();` | 插入後更新 iterator |
| 插入最後面 | `list.push_back(id); it = std::prev(list.end());` | 插入後更新 iterator |
| 移除 | `list.erase(stored_iterator);` | O(1) 移除 |

**型別相容性：**
- `std::list<frame_id_t>::iterator` ≠ `std::list<page_id_t>::iterator`
- 對 alive 和 ghost lists 都使用 `std::list<int>::iterator`

**結果：** Performance test 在 <3 秒內通過（原本 >30 秒）

### 2. Reverse Iterator 轉換

**問題：**
- `std::list::erase()` 不接受 `reverse_iterator`

**解決方案：**
```cpp
// 將 reverse_iterator 轉換為 forward_iterator
auto forward_it = std::next(reverse_it).base();
list.erase(forward_it);
```

**為什麼是 `std::next(it).base()`？**
- `reverse_iterator::base()` 指向 reverse_iterator 之後的元素
- 需要先 `std::next()` 來補償偏移

### 3. Heap-Use-After-Free：懸空參照

**常見模式：**

| 問題模式 | 修正 |
|---------|------|
| `auto& ref = map[key]; map.erase(key);` | 在 erase 前複製值：`auto val = map[key]; map.erase(key);` |
| `const T& ref = list.back(); list.pop_back();` | 使用值而非參照：`T val = list.back(); list.pop_back();` |

**偵測工具：**
- 使用 AddressSanitizer (ASan) 取得詳細 stack trace
- 編譯時加上 `-fsanitize=address`

### 4. 常見誤解

| 誤解 | 實際情況 |
|------|---------|
| RecordAccess 呼叫 Evict() | RecordAccess 只管理 ghost lists |
| T1/T2 = evictable/non-evictable | T1/T2 = recency/frequency（兩者都可以是 evictable） |
| Ghost lists 使用 frame_id | Ghost lists 使用 page_id（無 frame 分配） |
| 移動 T1→T2 會改變可淘汰性 | Evictable 狀態與 T1/T2 成員資格無關 |

### 5. 演算法流程

```
1. RecordAccess(frame_id, page_id, access_type)
   - 維護列表結構
   - 根據 ghost 命中調整 mru_target_size_
   - 管理 ghost list 大小

2. Evict() → frame_id
   - 根據 mru_target_size_ 選擇 victim
   - 將 victim 移到適當的 ghost list
   - 返回被淘汰的 frame_id

3. SetEvictable(frame_id, evictable)
   - 更新 evictable 狀態
   - 相應更新 curr_size_

4. Remove(frame_id)
   - 永久刪除（不進入 ghost list）
   - 用於 DROP TABLE 等
```

---

## 常見陷阱

1. 忘記在頁面於 alive/ghost 之間移動時更新 `curr_size_`
2. 對 ghost lists 使用 `frame_id` 而非 `page_id`
3. 從 RecordAccess 呼叫 Evict()
4. 未處理所有 frame 都被 pin 的情況（Evict 返回 nullopt）
5. 在 erase container 前使用元素的參照
