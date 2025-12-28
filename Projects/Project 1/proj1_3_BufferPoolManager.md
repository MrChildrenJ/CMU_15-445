# BufferPoolManager Implementation Notes

## Project Overview
Implementation of CMU 15-445 (2025 Fall) Project 1 Task #3 - BufferPoolManager, managing page cache buffer pool and eviction policy.
![Project 0 Result](./2025fall_p1_complete.png)

### Performance
| Metric | QPS.1 | QPS.2 | QPS.3 | Summary |
|--------|-------|-------|-------|---------|
| Scan   | 39581 | 45949 | 3847  | -       |
| Get    | 3846  | 1231  | 201   | -       |
| **Total** | - | - | - | **4138.43** |

---

## Core Flow

### 1. NewPage() - ID Allocation Only
**Responsibilities:**
- Allocate unique page ID using `atomic::fetch_add()`
- Does **NOT** load page into memory, does **NOT** allocate frame
- Thread-safe without `bpm_latch_` (atomic operation guarantees safety)

**Design Pattern:**
```
NewPage() → allocate page_id
    ↓
CheckedWritePage(page_id) → allocate frame + load data
    ↓
return PageGuard
```

### 2. CheckedReadPage/WritePage - Three Cases

**Case 1: Page already in buffer pool**
- Lookup frame_id in `page_table_`
- `pin_count_.fetch_add(1)` + `SetEvictable(false)`
- `RecordAccess()` to update ARC
- Return PageGuard

**Case 2: Free frame available**
- Get frame from `free_frames_`
- `Reset()` to clear as all zeros
- **Perform disk read** (new pages return empty data, existing pages load correct data)
- Add to `page_table_`, register to replacer

**Case 3: Eviction needed**
- Call `replacer_->Evict()` to find victim
- If no evictable frame → return `std::nullopt`
- Remove old mapping from `page_table_`
- If `is_dirty_` → flush to disk
- `Reset()` + perform disk read
- Add to `page_table_`, register to replacer

### 3. Key Data Structures

| Structure | Purpose | Update Timing |
|------|------|---------|
| `page_table_` | page_id → frame_id mapping | When loading/evicting pages |
| `free_frames_` | Unused frames | Remove on first use |
| `frames_[fid]->page_id_` | Current page_id of frame | Set when loading new page |

---

## Thread-Safety Strategy

### 1. Two-Layer Latch Mechanism

| Latch | Protection Scope | When to Hold | Lifetime |
|---|---------|---------|---------|
| `bpm_latch_` | `page_table_`, `free_frames_`, replacer operations | Modifying shared data structures + **during I/O** | Until I/O completes |
| `frame->rwlatch_` | Frame data content + metadata (`is_dirty_`) | Reading/writing frame data | During usage |

**Key Principle:**
```cpp
bpm_latch_.lock();
// 1. Find/allocate frame
// 2. Update page_table_[page_id] = fid
// 3. RecordAccess() + SetEvictable()
// 4. Perform disk I/O (must hold bpm_latch_)
disk_scheduler_->Schedule(...);
future.wait();
bpm_latch_.unlock();  // ✅ Release after I/O completes
```

**Why must hold bpm_latch_ during I/O?**
- ❌ **Wrong**: Release before I/O → other threads may load same page_id to different frame
- ✅ **Correct**: Hold until I/O completes → prevent data race
- **Trade-off**: Lower QPS, but guarantees correctness

### 2. Pin Count and Eviction Protection

**Mechanism:**
```cpp
// BufferPoolManager increments pin_count
pin_count_.fetch_add(1);
SetEvictable(fid, false);  // ← Prevents eviction

// PageGuard::Drop() decrements pin_count
if (pin_count_.fetch_sub(1) == 1) {
  SetEvictable(fid, true);  // ← Allow eviction when pin_count reaches zero
}
```

**Why pin_count > 0 prevents eviction?**
- ArcReplacer::Evict() only selects from frames with `evictable = true`
- `SetEvictable(false)` removes frame from eviction candidates

### 3. State Before Returning PageGuard

| Item | State | Reason |
|------|------|------|
| `bpm_latch_` | ✅ Released | PageGuard lifetime doesn't need global latch |
| `frame->rwlatch_` | ✅ Unlocked | PageGuard constructor will acquire it, deadlock if already locked |
| `pin_count_` | ✅ Incremented | Prevent eviction during usage |
| Frame data | ✅ Ready | Reset/loaded complete |

### 4. PageGuard::Drop() Latch Order
**Avoid deadlock:** Must acquire `bpm_latch_` before releasing `rwlatch_`
```cpp
// ✅ Correct order
bpm_->bpm_latch_.lock();
// Update SetEvictable
rwlatch_.unlock();
bpm_->bpm_latch_.unlock();
```

---

## Key Problems and Solutions

### 1. RecordAccess Must Come Before SetEvictable
**Problem:** Free frame never tracked, calling `SetEvictable()` directly causes assertion failure

**Correct Order:**
```cpp
// ✅ Register first, then set
page_table_[page_id] = fid;
replacer_->RecordAccess(fid, page_id, access_type);
replacer_->SetEvictable(fid, false);
```

### 2. GetDataMut() Must Set is_dirty_
**Problem:** User modifies data, but eviction doesn't flush → data loss

**Fix:**
```cpp
auto GetDataMut() -> char * {
  is_dirty_ = true;  // ← Critical!
  return GetData();
}
```

**Flow:**
1. `strcpy(guard.GetDataMut(), "data")` → `is_dirty_ = true`
2. `guard.Drop()` → unpin
3. On eviction check `is_dirty_` → perform flush ✅

### 3. FlushPage vs FlushPageUnsafe

| Method | Acquires rwlatch | Use Case |
|------|----------------|---------|
| `FlushPage` | ✅ Acquires read lock | BufferPoolManager calls |
| `FlushPageUnsafe` | ❌ No lock | Eviction flow (already holds bpm_latch_) |

**Why does FlushPage use read lock?**
- Flush only reads frame data to write to disk
- `is_dirty_` is metadata, doesn't need write lock

### 4. Unified Disk Read Strategy

**Conclusion: Always perform disk read**

| Frame Source | Perform disk read | Result |
|-----------|-----------|------|
| Free frame (new page) | ✅ Read | DiskManager returns empty data (all zeros) |
| Free frame (existing page) | ✅ Read | Load correct data |
| Evicted frame | ✅ Read | Load new page data |

**Advantages:**
- Simple: No need to track which pages exist on disk
- Safe: Reading new pages returns empty data (expected behavior)
- Correct: Reading existing pages returns correct data

### 5. ARC Unsigned Underflow
**Problem:** `size_t` subtraction underflows to huge value

**Wrong:**
```cpp
// ❌ std::max executes after subtraction, already underflowed
mru_target_size_ = std::max(mru_target_size_ - delta, 0);
```

**Correct:**
```cpp
// ✅ Compare first, then subtract
mru_target_size_ = (mru_target_size_ >= delta) ? (mru_target_size_ - delta) : 0;
```

---

## Complete Eviction Flow (Case 3)

**Steps (all while holding bpm_latch_):**

1. **Evict old page**
   - Call `replacer_->Evict()` to get victim frame
   - Get old page_id from victim frame
   - Remove old mapping from page_table_

2. **Flush if dirty**
   - Check victim frame's is_dirty_ flag
   - If dirty: schedule write, wait for completion
   - Must hold bpm_latch_ during I/O

3. **Reuse frame**
   - Reset frame data
   - Set frame's page_id to new page_id
   - Add new mapping to page_table_

4. **Load new page**
   - Call RecordAccess() to register with replacer
   - Call SetEvictable(false) (frame is pinned)
   - Increment pin_count atomically

5. **Disk I/O**
   - Schedule read request
   - Wait for completion
   - Still holding bpm_latch_

6. **Release and return**
   - Unlock bpm_latch_
   - Return PageGuard to caller

**Critical: Hold `bpm_latch_` throughout entire flow until new page loading completes**

---
---

# BufferPoolManager Implementation Notes (中文版)

## 專案概述
實作 CMU 15-445 (2025 Fall) Project 1 Task #3 - BufferPoolManager，管理頁面快取的緩衝池與驅逐策略。

### Performance
| Metric | QPS.1 | QPS.2 | QPS.3 | Summary |
|--------|-------|-------|-------|---------|
| Scan   | 39581 | 45949 | 3847  | -       |
| Get    | 3846  | 1231  | 201   | -       |
| **Total** | - | - | - | **4138.43** |

---

## 核心流程

### 1. NewPage() - 僅分配 ID
**職責：**
- 使用 `atomic::fetch_add()` 分配唯一 page ID
- **不**載入頁面到記憶體，**不**分配 frame
- Thread-safe 無需 `bpm_latch_`（atomic 操作本身保證）

**設計模式：**
```
NewPage() → 分配 page_id
    ↓
CheckedWritePage(page_id) → 分配 frame + 載入資料
    ↓
返回 PageGuard
```

### 2. CheckedReadPage/WritePage - 三種情況

**Case 1: 頁面已在 buffer pool**
- 在 `page_table_` 查找 frame_id
- `pin_count_.fetch_add(1)` + `SetEvictable(false)`
- `RecordAccess()` 更新 ARC
- 返回 PageGuard

**Case 2: 有空閒 frame**
- 從 `free_frames_` 取得 frame
- `Reset()` 清空為全 0
- **執行 disk read**（新頁面會返回空資料，已存在頁面會載入正確資料）
- 加入 `page_table_`，註冊到 replacer

**Case 3: 需要驅逐**
- 呼叫 `replacer_->Evict()` 尋找 victim
- 若無可驅逐 frame → 返回 `std::nullopt`
- 從 `page_table_` 移除舊映射
- 若 `is_dirty_` → flush 到 disk
- `Reset()` + 執行 disk read
- 加入 `page_table_`，註冊到 replacer

### 3. 關鍵資料結構

| 結構 | 用途 | 更新時機 |
|------|------|---------|
| `page_table_` | page_id → frame_id 映射 | 載入/驅逐頁面時 |
| `free_frames_` | 未使用過的 frames | frame 首次使用時移除 |
| `frames_[fid]->page_id_` | frame 當前的 page_id | 載入新頁面時設定 |

---

## Thread-Safety 策略

### 1. 兩層鎖機制

| 鎖 | 保護範圍 | 何時持有 | 生命週期 |
|---|---------|---------|---------|
| `bpm_latch_` | `page_table_`, `free_frames_`, replacer 操作 | 修改共享資料結構 + **I/O 期間** | 直到 I/O 完成 |
| `frame->rwlatch_` | frame 資料內容 + metadata (`is_dirty_`) | 讀寫 frame 資料 | 使用期間 |

**關鍵原則：**
```cpp
bpm_latch_.lock();
// 1. 查找/分配 frame
// 2. 更新 page_table_[page_id] = fid
// 3. RecordAccess() + SetEvictable()
// 4. 執行 disk I/O（必須持有 bpm_latch_）
disk_scheduler_->Schedule(...);
future.wait();
bpm_latch_.unlock();  // ✅ I/O 完成後才釋放
```

**為何必須持有 bpm_latch_ 做 I/O？**
- ❌ **錯誤**：I/O 前釋放 → 其他 thread 可能重複載入同一 page_id 到不同 frame
- ✅ **正確**：持有到 I/O 完成 → 防止 data race
- **Trade-off**：降低 QPS，但保證正確性

### 2. Pin Count 與驅逐保護

**機制：**
```cpp
// BufferPoolManager 增加 pin_count
pin_count_.fetch_add(1);
SetEvictable(fid, false);  // ← 這會防止被驅逐

// PageGuard::Drop() 減少 pin_count
if (pin_count_.fetch_sub(1) == 1) {
  SetEvictable(fid, true);  // ← pin_count 歸零才允許驅逐
}
```

**為何 pin_count > 0 不會被驅逐？**
- ArcReplacer::Evict() 只從 `evictable = true` 的 frame 中選擇
- `SetEvictable(false)` 會將 frame 從驅逐候選中移除

### 3. 返回 PageGuard 前的狀態

| 項目 | 狀態 | 原因 |
|------|------|------|
| `bpm_latch_` | ✅ 已釋放 | PageGuard 生命週期不需全域鎖 |
| `frame->rwlatch_` | ✅ 未上鎖 | PageGuard constructor 會獲取，若已鎖會死鎖 |
| `pin_count_` | ✅ 已遞增 | 防止使用期間被驅逐 |
| Frame 資料 | ✅ 已就緒 | Reset/載入完成 |

### 4. PageGuard::Drop() 鎖順序
**避免死鎖：** 必須先獲取 `bpm_latch_`，再釋放 `rwlatch_`
```cpp
// ✅ 正確順序
bpm_->bpm_latch_.lock();
// 更新 SetEvictable
rwlatch_.unlock();
bpm_->bpm_latch_.unlock();
```

---

## 關鍵問題與解決

### 1. RecordAccess 必須在 SetEvictable 之前
**問題：** Free frame 從未被追蹤，直接 `SetEvictable()` 會 assertion 失敗

**正確順序：**
```cpp
// ✅ 先註冊再設定
page_table_[page_id] = fid;
replacer_->RecordAccess(fid, page_id, access_type);
replacer_->SetEvictable(fid, false);
```

### 2. GetDataMut() 必須設定 is_dirty_
**問題：** 用戶修改資料後，驅逐時不 flush → 資料遺失

**修正：**
```cpp
auto GetDataMut() -> char * {
  is_dirty_ = true;  // ← 關鍵！
  return GetData();
}
```

**流程：**
1. `strcpy(guard.GetDataMut(), "data")` → `is_dirty_ = true`
2. `guard.Drop()` → unpin
3. 驅逐時檢查 `is_dirty_` → 執行 flush ✅

### 3. FlushPage vs FlushPageUnsafe

| 方法 | 是否取得 rwlatch | 使用場景 |
|------|----------------|---------|
| `FlushPage` | ✅ 取得讀鎖 | BufferPoolManager 呼叫 |
| `FlushPageUnsafe` | ❌ 不取鎖 | 驅逐流程（已持有 bpm_latch_） |

**為何 FlushPage 用讀鎖？**
- Flush 只讀取 frame 資料寫到磁碟
- `is_dirty_` 是 metadata，不需寫鎖保護

### 4. 統一 Disk Read 策略

**結論：總是執行 disk read**

| Frame 來源 | 是否讀 disk | 結果 |
|-----------|-----------|------|
| Free frame（新頁面） | ✅ 讀 | DiskManager 返回空資料（全 0） |
| Free frame（已存在頁面） | ✅ 讀 | 載入正確資料 |
| Evicted frame | ✅ 讀 | 載入新頁面資料 |

**優點：**
- 簡單：不需追蹤頁面是否存在於 disk
- 安全：新頁面讀取返回空資料（符合預期）
- 正確：已存在頁面返回正確資料

### 5. ARC Unsigned Underflow
**問題：** `size_t` 減法 underflow 成極大值

**錯誤：**
```cpp
// ❌ std::max 在減法後才執行，已經 underflow
mru_target_size_ = std::max(mru_target_size_ - delta, 0);
```

**正確：**
```cpp
// ✅ 先比較再減法
mru_target_size_ = (mru_target_size_ >= delta) ? (mru_target_size_ - delta) : 0;
```

---

## 驅逐流程完整步驟（Case 3）

**步驟（全程持有 bpm_latch_）：**

1. **驅逐舊頁面**
   - 呼叫 `replacer_->Evict()` 取得 victim frame
   - 從 victim frame 取得舊 page_id
   - 從 page_table_ 移除舊映射

2. **Flush（若 dirty）**
   - 檢查 victim frame 的 is_dirty_ flag
   - 若 dirty：排程寫入，等待完成
   - 必須持有 bpm_latch_ 執行 I/O

3. **重用 frame**
   - Reset frame 資料
   - 設定 frame 的 page_id 為新 page_id
   - 加入新映射到 page_table_

4. **載入新頁面**
   - 呼叫 RecordAccess() 註冊到 replacer
   - 呼叫 SetEvictable(false)（frame 被 pin）
   - 原子遞增 pin_count

5. **Disk I/O**
   - 排程讀取 request
   - 等待完成
   - 仍持有 bpm_latch_

6. **釋放並返回**
   - Unlock bpm_latch_
   - 返回 PageGuard 給呼叫者

**關鍵：整個流程持有 `bpm_latch_`，直到新頁面載入完成**
