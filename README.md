Vectorized Operations extension for PostgreSQL.

This extensions allows to increase more than 10 times speed of OLAP queries with filter and aggregation
by storing data in tiles: group of column values. It allows to reduce deform tuple and executor overhead.
Please look at tpch.sql example which shows how VOPS can be used to increase speed of TPC-H Q1/Q6 queries 
more than ten times.

How to use VOPS? First of all you need to somehow load data in VOPS.
It can be done in two ways:
1. Load data from existed table. In this case you just need to create VOPS projection of this table (using VOPS types instead
of original scalar types) and copy data to it using VOPS populate(...) function.
2. If you data is not yet loaded in the database, you can import it directly from CSV file into VOPS table using VOPS import(...) function.

Ok, now you have data in VOPS format. What you can do with it? VOPS manual (vops.html) explains many different ways of running
VOPS queries. VOPS provides set of overloaded operators which allows you to write queries in more or less standard SQL.
Operators which can not be overloaded (and, or, not, between) are handled by VOPS executor hook.

VOPS is able to efficiently execute filter and aggregation queries. What about other kinds of queries? For examples queries with
joins? There are once again two choices:
1. You can use original table (if any) for such queries.
2. You can use VOPS foreign data wrapper (FDW) to present VOPS table to PostgreSQL as normal table (with scalar column types).
The parts of query which can be efficiently executed by VOPS (filtering and aggregation) will be pushed by Postgres query optimizer
to VOPS FDW and will be executed using VOPS operators. Other query nodes will fetch data from VOPS as standard tuples
and process them in the same way as in case of normal tables. VOPS FDW provides statistic (you need to do ANALYZE for FDW table)
so query execution plan should be almost the same as for normal tables. The only exception is parallel processing: 
parallel processing is not currently supported by VOPS FDW.

So what finally you get? By creating of VOPS projection of existed data or storing data in VOPS table you can speed-up execution
of some queries more than ten times (mostly analytic queries with aggregation and without joins). And still be able to execute 
all other queries using VOPS FDW.

Chinces version of VOPS documantation can be found here:
https://github.com/digoal/blog/blob/master/201702/20170225_01.md

