Vectorized Operations extension for PostgreSQL.

This extensions allows to increase more than 10 times speed of OLAP queries with filter and aggregation
by storing data in tiles: group of column values. It allows to reduce deform tuple and executor overhead.
Please look at tpch.sql example which shows how VOPS can be used to increase speed of TPC-H Q1/Q6 queries 
more than ten times.

Chinces version of VOPS documantation can be found here:
https://github.com/digoal/blog/blob/master/201702/20170225_01.md

