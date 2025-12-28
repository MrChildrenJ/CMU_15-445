# PageGuard Implementation Notes

## Project Overview
Implementation of CMU 15-445 (2025 Fall) Project 1 Task #3 - PageGuard
![Project 0 Result](./2025fall_p1_complete.png)
---

## Core Concepts

### 1. PageGuard Architecture
**Purpose:**
- RAII wrapper providing thread-safe read/write page access
- Automatically manages two resources: **Pin Count** and **Page Latch**
- Prevents manual lock/unlock errors

**Two Types:**
- `ReadPageGuard`: Multiple concurrent readers (uses `RLatch()`)
- `WritePageGuard`: Single writer (uses `WLatch()`)

**Resource Ownership Flow:**
```
BufferPoolManager::CheckedReadPage/WritePage
    ↓
Create PageGuard (already pinned + latched)
    ↓
User holds PageGuard (RAII protection)
    ↓
PageGuard destructor/Drop() (unpin + unlatch)
```

### 2. Pin Count Management

**Responsibilities:**
- **Increment**: BufferPoolManager (when creating PageGuard)
- **Decrement**: PageGuard destructor/Drop() (`frame_->pin_count_.fetch_sub(1)`)
- PageGuard is friend class of FrameHeader, can access private `pin_count_`

**Why Pin Count?**
- Prevents eviction while thread accesses page
- `pin_count > 0` → frame cannot be evicted
- Each PageGuard represents one "pin" on the frame

**Synchronization with ArcReplacer:**
| Component | Role |
|-----------|------|
| `FrameHeader::pin_count_` | Tracks active accessor count |
| `ArcReplacer::SetEvictable()` | Controls if frame can be evicted |
| PageGuard::Drop() | Calls `SetEvictable(true)` when pin_count reaches 0 |

### 3. Latch Management

**Ownership:**
- **FrameHeader** owns latch (`std::shared_mutex rwlatch_`)
- PageGuard accesses via `frame_->rwlatch_`

| PageGuard Type | Constructor | Destructor | Concurrency |
|----------------|-------------|------------|-------------|
| ReadPageGuard | `lock_shared()` | `unlock_shared()` | Multiple readers |
| WritePageGuard | `lock()` | `unlock()` | Single writer |

### 4. RAII Resource Management

**Constructor:**
- Acquire latch (read/write lock)
- Set `is_valid_ = true`
- Note: Pin count already incremented by BPM before construction

**Destructor:**
- Simply calls `Drop()`

**Drop() Method Steps:**
1. Check `is_valid_` flag, return if false
2. Lock `bpm_latch_` (prevents eviction thread from accessing frame)
3. Release frame's `rwlatch_` (allows other threads to acquire latch)
4. Atomically decrement `pin_count` using `fetch_sub(1)` (returns old value)
5. Call `SetEvictable(true)` only when pin_count reaches 0
6. Unlock `bpm_latch_` (allows eviction to proceed)
7. Set `is_valid_ = false`

### 5. Move Semantics

**Why Move?**
- Pages/frames should not be copied (unique ownership)
- Similar to `std::unique_ptr` - exclusive ownership model

**Move Constructor Steps:**
1. Transfer all members from source to destination
2. Copy `is_valid_` from source
3. Set source's `is_valid_ = false` (invalidate source)

**Move Assignment Steps:**
1. Check for self-assignment
2. Call `Drop()` on current object (release current resources)
3. Transfer all members from source (same as move constructor)
4. Set source's `is_valid_ = false` (invalidate source)
5. Return `*this`

**Key:** Source object's `is_valid_` becomes `false`, preventing double-free in destructor

### 6. `is_valid_` Flag

**Purpose:**
- Prevent double-free in moved-from object's destructor
- Allow safe default construction (for stack allocation before move assignment)

**States:**
- `true`: PageGuard holds valid resources (must release in destructor)
- `false`: PageGuard has no resources (moved-from or default constructed)

**Usage Pattern:**
1. Default construct guard → `is_valid_ = false`
2. Move assign from BPM call → `is_valid_ = true`
3. When guard goes out of scope → destructor checks `is_valid_` before releasing

---

## Key Implementation Points

### 1. Atomic Pin Count Operations

**Wrong Approach (Race Condition):**
- Decrement pin_count with `--`
- Then check if equals 0
- Problem: Non-atomic read after write

**Correct Approach:**
- Use `fetch_sub(1)` which atomically decrements and returns old value
- Check if returned value equals 1 (meaning it's now 0)
- Call `SetEvictable(true)` only when pin_count reaches 0

**Why atomic even with bpm_latch_?**
- `pin_count_` accessed outside Drop() (e.g., `GetPinCount()`)
- Provides extra safety guarantee
- Clear semantics: "atomically decrement and check old value"

### 2. Common Misconceptions

| Misconception | Reality |
|---------------|---------|
| PageGuard owns the latch | FrameHeader owns latch, PageGuard manages **lifecycle** via RAII |
| Call `bpm_->UnpinPage()` | PageGuard has no `bpm_` pointer, directly manipulates `frame_->pin_count_` as friend class |
| PageGuard increments pin_count | BPM increments **before** creating PageGuard; PageGuard only **decrements** in Drop() |
| Check `frame_ == nullptr` | Use `is_valid_` flag instead; `frame_` is `shared_ptr`, null check isn't the right pattern |
| ReadPageGuard pages are clean | `is_dirty_` is frame state, not guard state; frame may have been modified by previous WritePageGuard |

### 3. Flush() Implementation

**Key Challenges:**
1. `DiskScheduler::Schedule()` takes non-const lvalue reference → cannot pass initializer list
2. `std::promise` is move-only → must use `std::move()` or `emplace_back()`
3. Must synchronously wait for write completion

**Implementation Steps:**
1. Check if frame is dirty, return early if clean
2. Create vector of DiskRequest
3. Use `emplace_back()` to construct request with move-only promise
4. Get future from request's promise
5. Schedule write request
6. Wait for future (blocks until write completes)
7. Clear `is_dirty_` flag

**Promise/Future Mechanism:**
- `std::promise<T>`: Promise to provide a value in the future
- `std::future<T>`: Wait for that value
- Worker thread sets promise value after completing write
- `future.wait()` blocks until promise is fulfilled

### 4. Friend Class Access

PageGuard is friend of FrameHeader, can directly access:
- `frame_->pin_count_` (private `std::atomic<size_t>`)
- `frame_->rwlatch_` (private `std::shared_mutex`)
- `frame_->frame_id_` (private `const frame_id_t`)
- `frame_->is_dirty_` (private `bool`)

### 5. Implementation Order

1. ReadPageGuard Move Constructor → transfer members + invalidate source
2. ReadPageGuard Move Assignment → Drop() + transfer + invalidate
3. ReadPageGuard Drop() → check is_valid_ + release latch + unpin
4. ReadPageGuard Destructor → call Drop()
5. ReadPageGuard Flush() → create DiskRequest + schedule + wait
6. WritePageGuard (same pattern, use `lock()/unlock()` instead of `lock_shared()/unlock_shared()`)

---
---

# PageGuard Implementation Notes (中文版)

## 專案概述
實作 CMU 15-445 (2025 Fall) Project 1 Task #3 - PageGuard

---

## 核心概念

### 1. PageGuard 架構
**目的：**
- RAII 物件，提供執行緒安全的讀/寫頁面存取
- 自動管理兩種資源：**Pin Count** 和 **Page Latch**
- 防止手動上鎖/解鎖錯誤

**兩種類型：**
- `ReadPageGuard`：允許多個並行 readers（使用 `RLatch()`）
- `WritePageGuard`：只允許一個 writer（使用 `WLatch()`）

**資源所有權流程：**
```
BufferPoolManager::CheckedReadPage/WritePage
    ↓
建立 PageGuard（已經 pinned + latched）
    ↓
使用者持有 PageGuard（RAII 保護）
    ↓
PageGuard destructor/Drop()（unpin + unlatch）
```

### 2. Pin Count 管理

**職責：**
- **增加**: BufferPoolManager（建立 PageGuard 時）
- **減少**: PageGuard destructor/Drop()（`frame_->pin_count_.fetch_sub(1)`）
- PageGuard 是 FrameHeader 的 friend class，可存取私有 `pin_count_`

**為何需要 Pin Count？**
- 防止 thread 存取頁面時被驅逐
- `pin_count > 0` → frame 不能被驅逐
- 每個 PageGuard 代表 frame 上的一個 "pin"

**與 ArcReplacer 同步：**
| 元件 | 角色 |
|------|------|
| `FrameHeader::pin_count_` | 追蹤活躍存取者數量 |
| `ArcReplacer::SetEvictable()` | 控制 frame 是否可被驅逐 |
| PageGuard::Drop() | pin_count 歸零時呼叫 `SetEvictable(true)` |

### 3. Latch 管理

**所有權：**
- **FrameHeader** 持有 latch（`std::shared_mutex rwlatch_`）
- PageGuard 透過 `frame_->rwlatch_` 存取

| PageGuard 類型 | Constructor | Destructor | 並發性 |
|----------------|-------------|------------|--------|
| ReadPageGuard | `lock_shared()` | `unlock_shared()` | 多個 readers |
| WritePageGuard | `lock()` | `unlock()` | 單一 writer |

### 4. RAII 資源管理

**Constructor：**
- 取得 latch（讀/寫鎖）
- 設定 `is_valid_ = true`
- 注意：Pin count 在建構前已由 BPM 增加

**Destructor：**
- 單純呼叫 `Drop()`

**Drop() 方法步驟：**
1. 檢查 `is_valid_` flag，若為 false 則返回
2. Lock `bpm_latch_`（防止 eviction thread 存取 frame）
3. 釋放 frame 的 `rwlatch_`（讓其他 threads 可以取得 latch）
4. 使用 `fetch_sub(1)` 原子遞減 `pin_count`（返回舊值）
5. 只有在 pin_count 到達 0 時才呼叫 `SetEvictable(true)`
6. Unlock `bpm_latch_`（允許 eviction 繼續）
7. 設定 `is_valid_ = false`

### 5. Move 語意

**為何 Move？**
- Pages/frames 不應被複製（獨占所有權）
- 類似 `std::unique_ptr` - 獨占所有權模型

**Move Constructor 步驟：**
1. 從來源轉移所有成員到目的地
2. 複製來源的 `is_valid_`
3. 設定來源的 `is_valid_ = false`（使來源無效）

**Move Assignment 步驟：**
1. 檢查自我賦值
2. 在當前物件上呼叫 `Drop()`（釋放當前資源）
3. 從來源轉移所有成員（同 move constructor）
4. 設定來源的 `is_valid_ = false`（使來源無效）
5. 返回 `*this`

**關鍵：** 來源物件的 `is_valid_` 變為 `false`，防止 destructor 雙重釋放

### 6. `is_valid_` Flag

**目的：**
- 防止已移動物件的 destructor 雙重釋放
- 允許安全的預設建構（用於堆疊分配後的 move assignment）

**狀態：**
- `true`：PageGuard 持有有效資源（destructor 中必須釋放）
- `false`：PageGuard 沒有資源（已移動或預設建構）

**使用模式：**
1. 預設建構 guard → `is_valid_ = false`
2. 從 BPM 呼叫 move assign → `is_valid_ = true`
3. guard 離開作用域時 → destructor 檢查 `is_valid_` 才釋放

---

## 關鍵實作要點

### 1. 原子 Pin Count 操作

**錯誤做法（Race Condition）：**
- 用 `--` 遞減 pin_count
- 然後檢查是否等於 0
- 問題：讀寫非原子

**正確做法：**
- 使用 `fetch_sub(1)` 原子遞減並返回舊值
- 檢查返回值是否等於 1（意味著現在為 0）
- 只有在 pin_count 到達 0 時才呼叫 `SetEvictable(true)`

**為何有 bpm_latch_ 還需要原子操作？**
- `pin_count_` 在 Drop() 外也被存取（例如 `GetPinCount()`）
- 提供額外安全保證
- 清晰語意：「原子地遞減並檢查舊值」

### 2. 常見誤解

| 誤解 | 實際情況 |
|------|---------|
| PageGuard 持有 latch | FrameHeader 持有 latch，PageGuard 透過 RAII 管理**生命週期** |
| 呼叫 `bpm_->UnpinPage()` | PageGuard 沒有 `bpm_` 指標，作為 friend class 直接操作 `frame_->pin_count_` |
| PageGuard 增加 pin_count | BPM 在建立 PageGuard **之前**增加；PageGuard 只**減少** |
| 檢查 `frame_ == nullptr` | 使用 `is_valid_` flag；`frame_` 是 `shared_ptr`，null 檢查不是正確模式 |
| ReadPageGuard 的頁面是乾淨的 | `is_dirty_` 是 frame 狀態，非 guard 狀態；frame 可能被先前的 WritePageGuard 修改過 |

### 3. Flush() 實作

**關鍵挑戰：**
1. `DiskScheduler::Schedule()` 接受非 const lvalue reference → 不能傳遞 initializer list
2. `std::promise` 是 move-only → 必須用 `std::move()` 或 `emplace_back()`
3. 必須同步等待寫入完成

**實作步驟：**
1. 檢查 frame 是否 dirty，若乾淨則提前返回
2. 建立 DiskRequest 的 vector
3. 使用 `emplace_back()` 建構包含 move-only promise 的 request
4. 從 request 的 promise 取得 future
5. 排程寫入 request
6. 等待 future（阻塞直到寫入完成）
7. 清除 `is_dirty_` flag

**Promise/Future 機制：**
- `std::promise<T>`：承諾在未來提供一個值
- `std::future<T>`：等待那個值
- Worker thread 完成寫入後設定 promise 值
- `future.wait()` 阻塞直到 promise 被滿足

### 4. Friend Class 存取

PageGuard 是 FrameHeader 的 friend，可直接存取：
- `frame_->pin_count_`（private `std::atomic<size_t>`）
- `frame_->rwlatch_`（private `std::shared_mutex`）
- `frame_->frame_id_`（private `const frame_id_t`）
- `frame_->is_dirty_`（private `bool`）

### 5. 實作順序

1. ReadPageGuard Move Constructor → 轉移成員 + 使來源無效
2. ReadPageGuard Move Assignment → Drop() + 轉移 + 使來源無效
3. ReadPageGuard Drop() → 檢查 is_valid_ + 釋放 latch + unpin
4. ReadPageGuard Destructor → 呼叫 Drop()
5. ReadPageGuard Flush() → 建立 DiskRequest + 排程 + 等待
6. WritePageGuard（相同模式，用 `lock()/unlock()` 代替 `lock_shared()/unlock_shared()`）