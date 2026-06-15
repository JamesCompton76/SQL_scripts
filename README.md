# SQL-Utility-Scripts

A curated collection of performant, high-concurrency T-SQL scripts and data mitigation patterns for Microsoft SQL Server. These templates are engineered to handle heavy data-cleansing operations on large production tables without triggering lock escalation, blocking shopfloor users, or exhausting transaction log resources.

---

## 🛠️ SQL Flavor & Compatibility
* **Primary Dialect:** **T-SQL (Transact-SQL)**
* **Target Engine:** Microsoft SQL Server (2012+)
* **Core Language Features Utilized:** Procedural `WHILE` execution loops, dynamic `TOP (@Variable)` expressions, `TRY...CATCH` structured exception handling, local indexing architectures, and explicit ACID transactional boundaries.

---

## 💾 Script Inventory & Deep Dive

### ⚡ 1. Inline Capped Pruning

<details>
<summary>📂 <code>batch_delete.sql</code></summary>

### Functional Overview
Executes an inline, iterative data purge directly against a live table (`yellow_taxi`) based on a specific criteria timeline. It bypasses the common risks of massive data deletions by chipping away at the dataset in tightly controlled increments. This script is ideal for sequential maintenance tasks on production systems where active write operations must continue completely uninterrupted.

### Technical Metadata & Logic
* **Lock Escalation Guardrail:** Uses a hardcoded micro-batch limit of `4,999` rows per transaction. Capping the operation strictly under the default SQL Server `5,000` threshold prevents the engine from escalating granular row locks into a full Exclusive Table Lock (`X`), ensuring high concurrency for other active workshop connections.
* **ACID Transaction Management:** Encapsulates each independent delete action inside a standalone `BEGIN TRANSACTION` and `COMMIT` block. This approach allows the database engine to continually reuse Virtual Log Files (VLFs) in the transaction log (`.ldf`), keeping the server's storage footprint lean.
* **Defensive Exception Architecture:** Implements a robust `TRY...CATCH` framework. If a specific batch gets caught in a deadlock chain, the script rolls back *only* that individual 4,999-row pass and terminates gracefully, leaving all previous historically committed batches permanently written to disk.
* **Real-Time Instrumentation:** Deploys `RAISERROR...WITH NOWAIT` execution notifications every 10 iterations. This bypasses standard SQL Server output buffering to stream live progress telemetry directly to the SSMS Messages tab.
</details>

### 🛡️ 2. Read-Isolated Two-Phase Pruning

<details>
<summary>📂 <code>batch_delete_type_2.sql</code></summary>

### Functional Overview
Implements a highly sophisticated data purge strategy by completely decoupling the "Read/Scan" phase of a deletion from the actual "Write/Delete" phase. It isolates the primary lookup logic from the main production dataset up front, transforming a potentially heavy index-scanning query into a series of highly efficient, indexed key-seek operations.

### Technical Metadata & Logic
* **Horizontal Read-Isolation:** Phase 1 uses a `SELECT INTO` operation paired with a `WITH (NOLOCK)` hint to extract target primary keys into a local temporary table (`#TargetsToPurge`). This ensures the initially massive index scan reads data without issuing shared locks, preventing the script from blocking live database writers.
* **Temporary Local Indexing:** Dynamically builds a local clustered index (`IX_Temp_ID`) straight onto the populated temporary key table. This converts the downstream lookups from expensive table scans into ultra-fast, index-seek operations.
* **Dual-Pruning Synchronization Loop:** Phase 2 executes a synchronized loop that applies the `TOP (4999)` limit to *both* sides of the operation:
  * It deletes 4,999 rows from the live production table (`yellow_taxi`) using an optimized `WHERE id IN (SELECT id FROM #TargetsToPurge)` subquery seek.
  * It immediately shreds the corresponding 4,999 key records out of the temporary table (`#TargetsToPurge`). This double-cleanup ensures that subsequent subquery iterations evaluate a continually shrinking dataset, preventing performance degradation as the script nears completion.
</details>
