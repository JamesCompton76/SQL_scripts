# SQL-Utility-Scripts

A curated collection of performant, high-concurrency database utility scripts, administrative templates, and data mitigation patterns spanning multiple SQL dialects. These scripts are engineered to execute heavy data operations safely, protect system resources, and optimize storage engines across different database platforms.

---

## 🟧 Microsoft SQL Server (T-SQL)

Optimized routines specifically engineered for the T-SQL dialect and the SQL Server database engine.

### ⚡ Data Cleansing & Maintenance

<details>
<summary>📂 <code>batch_delete.sql</code></summary>

### Technical Metadata
* **Dialect:** T-SQL
* **Target Engine:** Microsoft SQL Server (2012+)
* **Core Features:** Procedural `WHILE` loops, dynamic `TOP` expressions, explicit ACID transactions, `TRY...CATCH` exception blocks.

### Functional Overview
Executes an inline, iterative data purge directly against a live table (`yellow_taxi`) based on a specific criteria timeline. It bypasses the common risks of massive data deletions by chipping away at the dataset in tightly controlled increments. This script is ideal for sequential maintenance tasks on production systems where active write operations must continue completely uninterrupted.

### Technical Logic & Guardrails
* **Lock Escalation Limit:** Uses a micro-batch limit of `4,999` rows per transaction pass. Capping the operation strictly under the default SQL Server `5,000` lock threshold prevents the engine from escalating granular row locks into a full Exclusive Table Lock (`X`), ensuring high concurrency for other active system users.
* **ACID Transaction Management:** Encapsulates each independent delete action inside a standalone `BEGIN TRANSACTION` and `COMMIT` block. This approach allows the engine to continually reuse Virtual Log Files (VLFs) in the transaction log (`.ldf`), keeping the server's storage footprint lean.
* **Defensive Exception Architecture:** Implements a robust `TRY...CATCH` framework. If a specific batch gets caught in a deadlock chain, the script rolls back *only* that individual 4,999-row pass and terminates gracefully, leaving all previous historically committed batches permanently written to disk.
* **Real-Time Instrumentation:** Deploys `RAISERROR...WITH NOWAIT` execution notifications every 10 iterations. This bypasses standard SQL Server output buffering to stream live progress telemetry directly to the SSMS Messages tab.
</details>

<details>
<summary>📂 <code>batch_delete_type_2.sql</code></summary>

### Technical Metadata
* **Dialect:** T-SQL
* **Target Engine:** Microsoft SQL Server (2008+)
* **Core Features:** Read-isolation hints (`NOLOCK`), local temp tables (`#`), clustered index generation, keyed subquery seeks.

### Functional Overview
Implements a highly sophisticated data purge strategy by completely decoupling the "Read/Scan" phase of a deletion from the actual "Write/Delete" phase. It isolates the primary lookup logic from the main production dataset up front, transforming a potentially heavy index-scanning query into a series of highly efficient, indexed key-seek operations.

### Technical Logic & Guardrails
* **Horizontal Read-Isolation:** Phase 1 uses a `SELECT INTO` operation paired with a `WITH (NOLOCK)` hint to extract target primary keys into a local temporary table (`#TargetsToPurge`). This ensures the initially massive index scan reads data without issuing shared locks, preventing the script from blocking live database writers.
* **Temporary Local Indexing:** Dynamically builds a local clustered index (`IX_Temp_ID`) straight onto the populated temporary key table. This converts the downstream lookups from expensive table scans into ultra-fast, index-seek operations.
* **Dual-Pruning Synchronization Loop:** Phase 2 executes a synchronized loop that applies the `TOP (4999)` limit to *both* sides of the operation:
  * It deletes 4,999 rows from the live production table (`yellow_taxi`) using an optimized `WHERE id IN (SELECT id FROM #TargetsToPurge)` subquery seek.
  * It immediately shreds the corresponding 4,999 key records out of the temporary table (`#TargetsToPurge`). This double-cleanup ensures that subsequent subquery iterations evaluate a continually shrinking dataset, preventing performance degradation as the script nears completion.
</details>

<details>
<summary>📂 <code>restore_history.sql</code></summary>

### Technical Metadata
* **Dialect:** T-SQL
* **Target Engine:** Microsoft SQL Server (2012+) / System Instance Layer
* **Core Features:** Dynamic system catalog querying (`msdb`), analytic lookahead windowing (`LEAD()`), timeline partitioning.

### Functional Overview
A system administration and data governance script designed to audit the transactional database restoration history across a SQL Server instance. It tracks database snapshot deployments, monitors disaster recovery synchronization schedules, and evaluates configuration safety flags. Rather than returning a static log, it calculates exact point-in-time chronological validity windows to show precisely how long any given database restoration remained the active state of the environment.

### Technical Logic & Guardrails
* **Analytic Timeline Segmentation:** Employs a `LEAD(restore_date) OVER (PARTITION BY destination_database_name ORDER BY restore_date ASC)` window map. This records the exact timestamp of the *subsequent* restoration checkpoint as `next_date`. 
* **Environment Validity Windows:** By pairing the actual event execution date (`restore_date`) with the captured lookahead timestamp (`next_date`), the query constructs discrete, bounded time intervals. This allows data engineers to instantly evaluate the lifespan of an active database snapshot before it was overwritten by a subsequent restore loop.
* **System Instance Scope:** Queries directly out of the application database context into the Microsoft SQL Server system instance catalog: `[msdb].[dbo].[restorehistory]`. 
* **Infrastructure Security Note:** Because this script references the native `msdb` system table, the executing user context requires explicit database-level permissions (such as membership in the `db_datareader` role within `msdb` or membership in the `sysadmin` fixed server role).
* **Surfaced Administration Metrics:**
  * `user_name`: Tracks the infrastructure operator or automated pipeline service account that triggered the execution.
  * `restore_type`: Identifies the backup restore style applied (e.g., Database, File, or Log).
  * `replace` / `recovery` / `restart`: Exposes the boolean state safety configurations passed during the DDL operation (crucial for troubleshooting interrupted recovery loops).
</details>

---

## 🐘 PostgreSQL (PL/pgSQL)

*This section is a placeholder for future utility scripts written for the PostgreSQL dialect.*

---

## ❄️ Snowflake SQL

*This section is a placeholder for future analytical warehouse optimization and cloning scripts.*
