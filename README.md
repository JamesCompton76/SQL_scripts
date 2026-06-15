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

### Replication & Scale Notes
* **Replication-Safe Design:** While a standard `TRUNCATE` is significantly faster, SQL Server flatly blocks truncations on any table published via Transactional Replication because it bypasses row-level transaction logging. This batch script forces granular logging, allowing the Replication Log Reader Agent to stream deletions seamlessly down to subscribers without choking.
* **The DBA Infrastructure Alternative:** For massive enterprise tables where even chunked deletes degrade production I/O, the long-term solution shifts to the DBA domain via **Partition Switching**. By partitioning the table, an entire section of historical data can be swapped out into an un-replicated staging table via metadata pointers (`ALTER TABLE... SWITCH PARTITION`) in under 10 milliseconds, bypassing row logging entirely while remaining replication-compatible if publication flags are configured correctly.
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

### Replication & Scale Notes
* **Replication-Safe Design:** While a standard `TRUNCATE` is significantly faster, SQL Server flatly blocks truncations on any table published via Transactional Replication because it bypasses row-level transaction logging. This batch script forces granular logging, allowing the Replication Log Reader Agent to stream deletions seamlessly down to subscribers without choking.
* **The DBA Infrastructure Alternative:** For massive enterprise tables where even chunked deletes degrade production I/O, the long-term solution shifts to the DBA domain via **Partition Switching**. By partitioning the table, an entire section of historical data can be swapped out into an un-replicated staging table via metadata pointers (`ALTER TABLE... SWITCH PARTITION`) in under 10 milliseconds, bypassing row logging entirely while remaining replication-compatible if publication flags are configured correctly.
</details>

<details>
<summary>📂 <code>deduplicate_records.sql</code></summary>

### Technical Metadata **NEED TO TEST THESE**
* **Dialect:** T-SQL
* **Target Engine:** Microsoft SQL Server (2005+)
* **Core Features:** Common Table Expressions (CTEs), windowed sequence partitioning (`ROW_NUMBER()`), inline pointer modifications, execution plan sorting bypass (`SELECT NULL`).

### Functional Overview
A comprehensive de-duplication utility engine executing data purification directly in-place through a logical expression wrapper. Instead of implementing risky, high-overhead structural shifts—like migrating records to temporary tables, truncating sources, and rewriting datasets—this script exploits SQL Server's ability to map modifications through CTEs straight to physical disk addresses. It features hard-deletion routing, soft-delete tagging for warehouse lineage, and keyless heap table optimization.

### Technical Logic & Operational Variations

#### ⚡ Pattern A: Deterministic Surrogate Key Cleansing (Surgical Hard-Delete)
* **Logic:** Applied when records are duplicate mirror images based on business meaning, but hold distinct, auto-generated database primary keys (e.g., identity columns or hashes).
* **Mechanism:** Isolates data attributes within a `PARTITION BY` block, while forcing an explicit sequence sorting constraint inside the window configuration: `ORDER BY taxi_record_id ASC`. 
* **Outcome:** The earliest historical insert receives a sequence rank of `1`. All subsequent identical iterations are systematically assigned incremented sequence integers (`2`, `3`, etc.). Running a targeted `DELETE WHERE row_num > 1` purges the duplicate noise while safely preserving the original root record.

#### 🛡️ Pattern B: Audit-Safe Warehouse Tagging (The Update Pass)
* **Logic:** Tailored for corporate OBT architectures where destructive purges are banned in favor of preserving explicit data lineage and auditability.
* **Mechanism:** Captures row sequences identically to Pattern A, but shifts the modification footprint from a destructive `DELETE` statement to a passive inline `UPDATE`.
* **Guardrails & Execution:** Modifies a physical state tracking column (`SET is_duplicate = 1`) directly through the CTE interface `WHERE row_num > 1`. *Crucial Engine Rule:* While you can safely modify any native base column passed through the CTE layout, attempting to directly alter the virtual computed `row_num` column will cause an immediate engine compilation failure.

#### 🏎️ Pattern C: Keyless Heap / Flat OBT Processing (Performance Optimization)
* **Logic:** Deployed against staging tables, denormalized OBT layouts, or heaps that possess zero unique system constraints or key keys, and rows are complete mirror duplicates.
* **Mechanism:** To ensure true identity matching, it expands the window partition map to wrap **every single column** across the table structure.
* **CPU Optimization:** Because a windowing operation strictly mandates an internal sorting operation, this pattern leverages a performance-minded bypass trick: `ORDER BY (SELECT NULL)`. This tells the Query Optimizer to completely abandon the expensive physical resource-sorting processor phase, numbering the identical rows arbitrarily based on how they are encountered in the data blocks, significantly decreasing CPU utilization.
</details>

<details>
<summary>📂 <code>sanitize_text_fields.sql</code></summary>

### Technical Metadata
* **Dialect:** T-SQL
* **Target Engine:** Microsoft SQL Server (2000+)
* **Core Features:** Dynamic string manipulation functions (`REPLACE`), character-code conversion engines (`CHAR`), text formatting injection mapping, procedural conditional loop structures (`WHILE`), programmatic transactional containment.

### Functional Overview
A high-performance data sanitation pipeline template engineered to strip hidden, non-printable formatting characters out of free-text descriptive fields. When workshop operators use multi-line text input fields on the shopfloor, the application layer frequently injects non-printable ASCII properties such as Carriage Returns (`CHAR(13)`), Line Feeds (`CHAR(10)`), and Horizontal Tabs (`CHAR(9)`). While SQL natively stores these characters, they corrupt downstream analytical workflows (e.g., throwing column alignment errors during CSV exports or breaking parquet file structures). This script safely replaces them with regular spaces while providing comprehensive diagnostic validation paths.

### Technical Logic & Operational Variations

#### 📊 Pattern A: Diagnostic & Visual Anatomy Scan (Pre-Flight Verification)
* **Logic:** Deployed prior to making database mutations to evaluate the scope of corruption and confirm that text modification wont alter semantic value.
* **Mechanism:** Rather than stripping characters immediately, it translates them into visible, printable bracketed tags: `CHAR(13) ➔ '[CR]'`, `CHAR(10) ➔ '[LF]'`, and `CHAR(9) ➔ '[TAB]'`.
* **Outcome:** Surfaces hidden formatting anomalies in standard SSMS grids alongside an adjacent side-by-side preview of the clean text string. This allows for scale metrics assessment (`@@ROWCOUNT`) before choosing an execution strategy.

#### ⚡ Pattern B: High-Velocity Direct Execution (Inline Update)
* **Logic:** Applied if the diagnostic scan confirms the total target row footprint falls well below a single transaction safety ceiling (e.g., < 5,000 records).
* **Mechanism:** Chains three nested `REPLACE()` operations together into a single atomic update pass, replacing formatting artifacts with white spaces.
* **Guardrails:** Restricts engine cost by applying wildcard string-matching parameters in the `WHERE` filter. This prevents the storage engine from running expensive writes on records that are already clean.

#### 🏎️ Pattern C: Scale-Protected Concurrency Safe Ingestion (Batched Loop Execution)
* **Logic:** Deployed if the diagnostic pre-flight pass detects systemic corruption affecting massive swaths of data (e.g., millions of records).
* **Mechanism:** Employs a procedural processing architecture that restricts operations to blocks of `TOP (4999)` rows wrapped inside explicit database transaction headers (`BEGIN TRANSACTION...COMMIT`).
* **Outcome:** Eliminates the risk of transaction log (`.ldf`) bloat and blocks SQL Server from escalating page-level row locks into an Exclusive Table Lock (`X`), allowing live shopfloor application reads and writes to execute unhindered while the cleanup job runs.
</details>

<details>
<summary>📂 <code>audit_and_cast_types.sql</code></summary>

### Technical Metadata **NOT TESTED AS YET**
* **Dialect:** T-SQL
* **Target Engine:** Microsoft SQL Server (2012+)
* **Core Features:** Safe serialization routing (`TRY_CAST`), anomaly scanning, data quality isolation filters.

### Functional Overview
A proactive data quality auditing utility designed to scan raw, loosely typed alphanumeric columns (`VARCHAR`/`NVARCHAR`) and pinpoint the exact rogue rows preventing structural migration to stricter, high-performance data types (like `NUMERIC` or `DATETIME2`). It serves as a vital diagnostic layer when flattening raw production logs into structured OBT layouts for downstream Python or Skywise ingestion pipelines.

### Technical Logic & Guardrails
* **Explosion Prevention:** Rather than using a standard `CAST` or `CONVERT` which halts query processing and drops connection links upon hitting an invalid string, this script utilizes `TRY_CAST()`. This function forces the evaluation engine to elegantly output a standard `NULL` whenever formatting constraints are broken.
* **Targeted Anomaly Isolation:** By restricting data collection to instances where `TRY_CAST(column) IS NULL AND column IS NOT NULL`, the script eliminates clean records and native missing data values, outputting an unmasked registry of structural corruptions (e.g., text artifacts like "N/A" hidden inside a numerical field).
</details>

### 📊 System Administration & Monitoring

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

<details>
<summary>📂 <code>table_size_rows.sql</code></summary>

### Technical Metadata
* **Dialect:** T-SQL
* **Target Engine:** Microsoft SQL Server (2008+) / Linked Server Instance Layer
* **Core Features:** Dynamic Management Views (DMVs), data page aggregation, precision numeric casting, partition stat tracking.

### Functional Overview
A database administration and capacity monitoring utility that calculates real-time row counts and disk storage footprints across user-defined tables on a targeted instance (`DBWV2J9900`). It serves as a diagnostic tool for storage analysis, tracking table inflation anomalies, monitoring indexing footprints, and mapping baseline data volumes prior to planning data engineering migrations or ETL pipelines.

### Technical Logic & Guardrails
* **Duplication Prevention:** Filters partition statistics strictly using `ps.index_id IN (0, 1)`. Isolating only Heaps (ID `0`) and Clustered Indexes (ID `1`) forces the engine to aggregate the base data pages exactly once, eliminating row-count inflation or capacity distortion caused by reading secondary non-clustered index pages.
* **Storage Allocation Calculations:** Converts low-level 8KB database pages into human-readable Megabyte (MB) valuations using a precise calculation grid:
  * Computes total reserved and used space via the formula: `(Page Count * 8 KB) / 1024.00 = Megabytes`.
  * Forces numerical conformity and prevents trailing decimal truncation by wrapping the calculations in an explicit precision cast: `CAST(ROUND(..., 2) AS NUMERIC(36, 2))`.
* **System Filters:** Integrates `t.is_ms_shipped = 0` to automatically drop native Microsoft SQL Server internal objects, ensuring the resulting dataset represents only active application tables.
* **Surfaced Administration Metrics:**
  * `ActualRowCounts`: The true scalar cardinality of rows residing in the base data partitions.
  * `TotalReservedSpaceMB`: Total disk space allocated by the operating system for the table data and structures.
  * `UsedSpaceMB`: The actual disk volume consumed by active records and index roots.
</details>

<details>
<summary>📂 <code>blocking_detection.sql</code></summary>

### Technical Metadata
* **Dialect:** T-SQL
* **Target Engine:** Microsoft SQL Server (2005+)
* **Core Features:** Active request monitoring (`sys.dm_exec_requests`), connection session properties (`sys.dm_exec_sessions`), inline text extraction vectors (`sys.dm_exec_sql_text`).

### Functional Overview
A live concurrency diagnostics utility engineered to detect, isolate, and trace active blocking lock loops across the database instance. When a production table freezes or an application hangs, this script targets the engine's scheduling layers to pinpoint the exact root Session ID (SPID) causing the bottleneck, isolating the "head blocker" from the downstream wait conditions.

### Technical Logic & Guardrails
* **Lock Contention Filtering:** Isolates records using an active boundary criteria where `r.blocking_session_id <> 0`. This cleanly filters out healthy, executing, or idle transactions to focus exclusively on active transaction blockages.
* **Bidirectional SQL Text Extraction:** Utilizes a dual execution mapping pattern with `CROSS APPLY` and `OUTER APPLY` over the system handles (`sql_handle`). It surfaces the exact T-SQL text segment being executed by the blocked session *simultaneously* alongside the query text running inline inside the blocking session.
* **Administrative Telemetry:** Exposes active connection variables including client machine roots (`host_name`), software application contexts (`program_name`), corporate logins (`login_name`), wait thresholds (`wait_time` mapped to seconds), and structural lock categories (`wait_type`).
* **Query vs. Mutation Identification:** The script surfaces `Blocking_SQL_Text` to allow engineers to visually scan for write operations (`UPDATE`, `DELETE`, `INSERT`). Programmatically, the underlying `sys.dm_exec_requests` table exposes a `.command` property which explicitly states the execution type (e.g., `SELECT` vs. `DELETE`), allowing instant identification of data-modifying workloads.

### Remediation & Operational Notes
* **Targeted Session Termination:** If a blocking chain must be broken manually, the root `Blocking_SPID` can be passed to the T-SQL termination engine: `KILL <SPID>`. This requires `sysadmin`, `processadmin`, or server-level `ALTER ANY CONNECTION` privileges.
* **The Rollback Insurance Valve:** Issuing a `KILL` command on an active data mutation forces the engine to roll back transactional state row-by-row to guarantee database atomicity. During heavy write rollbacks, the session remains in a temporary `KILLED/ROLLBACK` state and continues holding exclusive locks.
* **Rollback Telemetry tracking:** If a killed session continues to block downstream requests, the real-time rollback completion trajectory and estimated time remaining can be checked securely without resetting the query thread by executing: `KILL <SPID> WITH STATUSONLY`.
</details>

<details>
<summary>📂 <code>fragmentation_detection.sql</code></summary>

### Technical Metadata
* **Dialect:** T-SQL
* **Target Engine:** Microsoft SQL Server (2005+)
* **Core Features:** Storage layout statistics (`sys.dm_db_index_physical_stats`), master index mappings (`sys.indexes`), programmatic syntax assembly via conditional `CASE` grids.

### Functional Overview
An automated storage infrastructure audit utility that monitors the physical page fragmentation metrics of database table indexes. Deleting or updating large sets of records inevitably leaves gaps across physical disk pages. This script identifies degraded index nodes and programmatically generates the required remediation scripts (`REBUILD` or `REORGANIZE`) to eliminate unnecessary storage read/write overhead.

### Technical Logic & Guardrails
* **Performance-Minded Ingestion Scope:** Instructs the physical parsing engine to use a `'LIMITED'` scanning mode parameter. This samples root-level pages rather than traversing full index b-trees, ensuring the audit runs at lightning speed without stalling production I/O channels.
* **Significance Threshold Filtering:** Implements a protective criteria filter:
  * Restricts evaluation to indexes where `avg_fragmentation_in_percent > 10` to ignore baseline storage noise.
  * Filters for tables where `page_count > 1000`, bypassing small tables where logical page layout fragmentation has a zero-net impact on query optimization plans.
* **Programmatic Action Assignment:** Evaluates the page layout state against standard Microsoft database health thresholds using an inline conditional `CASE` block:
  * *Fragmentation > 30%:* Assembles an immediate `REBUILD` DDL string to reconstruct the index framework.
  * *Fragmentation 10% - 30%:* Assembles a low-overhead `REORGANIZE` DDL query to defragment existing data leaves.
</details>

<details>
<summary>📂 <code>plan_cache_top_10_expensive.sql</code></summary>

### Technical Metadata
* **Dialect:** T-SQL
* **Target Engine:** Microsoft SQL Server (2005+)
* **Core Features:** Query cache diagnostics (`sys.dm_exec_query_stats`), query plan extraction (`sys.dm_exec_query_plan`), precise script text offset parsing.

### Functional Overview
A performance tuning and monitoring tool that interrogates SQL Server's internal memory plan cache to expose the top 10 most expensive queries currently impacting the system. It ranks cached query footprints based on total CPU execution overhead (`total_worker_time`), tracking down unindexed queries, bad analytical joins, or system-stretching processes authored by downstream BI users.

### Technical Logic & Guardrails
* **Resource Cost Metric Ranking:** Implements a strict `ORDER BY total_worker_time DESC` constraint to force the database engine to rank its entire active cached execution registry by total processor consumption time before outputting the top 10 records.
* **Granular Text Segment Slicing:** Because multiple individual statements can reside inside a single procedure or transactional batch, the script uses a sophisticated text-offset calculation pattern: `SUBSTRING(st.text, (qs.statement_start_offset/2)+1, ...)`. This isolates and displays the precise line-item statement causing the high resource draw rather than dumping the whole parent script.
* **XML Execution Plan Extraction:** Deploys a `CROSS APPLY` operation out to `sys.dm_exec_query_plan(qs.plan_handle)`, outputting the full, graphical, interactive query optimization map (`query_plan`) directly into the SSMS result field for immediate index analysis.
</details>

---

## 🐘 PostgreSQL (PL/pgSQL)

*This section is a placeholder for future utility scripts written for the PostgreSQL dialect.*

---

## ❄️ Snowflake SQL

*This section is a placeholder for future analytical warehouse optimization and cloning scripts.*
