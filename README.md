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
* **Bidirectional SQL text Extraction:** Utilizes a dual execution mapping pattern with `CROSS APPLY` and `OUTER APPLY` over the system handles (`sql_handle`). It surfaces the exact T-SQL text segment being executed by the blocked session *simultaneously* alongside the query text running inside the blocking session.
* **Administrative Telemetry:** Exposes active connection variables including client machine roots (`host_name`), software application contexts (`program_name`), corporate logins (`login_name`), wait thresholds (`wait_time` mapped to seconds), and structural lock categories (`wait_type`).
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
