## <span id="query_transform">Query transformation</span>

VOPS is vectorized executor for Postgres. It is implemented as extension and can be used with any version of Postgres
and doesn't require any changes in Postgres core. Using vector (tile) types VOPS provides columnar format (like Apache Arrow)
on top of standard Postgres heap. And custom operators for VOPS types implement vector operations, minimizing interpretation overhead.
Comparing with other vertical solutions for Postgres: cstore_fwd and zedstore,
VOPS provides more than 10 times improvement of execution speed on some OLAP queries.

VOPS was developed more than three yeas ago and while main paradigm is not changed,
my vision of how it should be used was significantly changed.
My original indention was to define VOPS-specific tile types (i.e. vops_int4,...)
which provides the same operations as native scalar types and thanks to Postgres
user defined operators allow to write queries for VOPS tables almost in the same was as
for standard tables.

But very soon it becomes clear that although it is possible to redefine most of operators
and aggregates, for some of them it is not possible: AND, OR, BETWEEN, COUNT(*).
And my attempt to replace them with VOPS analogs, i.e. BETWIXT,&,|,...
require users to learn VOPS "dialect" of SQL. Also there are other cases,
when VOPS requires changing of standard queries, for example adding explicit type cast for
string literal.

Another my idea was to use foreign-data-wrappers (FDW) mechanism
to provide "normal" (row-based) access to VOPS table. vops_fdw should transpose columns into rows.
Unfortunately limitation of Postgres FDW mechanism, like not supporting parallel query execution,
devalue any advantages of columnar storage and performance is several times worse than for normal tables.

Finally I come to the conclusion that data should be kept in normal (horizontal)
table which is most efficient for OLTP operations and importing data.
And user should create one or more VOPS projections of this table,
where some subset of columns are "tiles": scalar types are replaced with VOPS types.
Grouping and ordering of rows in the project allows to store data in the format most efficient for
some particular subclass of queries. For example Q1 query of TPC-H benchmark performs group by
linestatus and returnflag, so we can create projection grouped by this columns.

Postgres planner hook tries to substitute query to main table with tranformed query to one of the available
VOPS projections. If it is possible (requirements for queries which can be executed on projections
will be listed below), then it transforms query using VOPS operators.
If it is not possible, then query is executed as usual on the original table.

So user writes query using standard SQL. If there is some existed application, then
it should not be changed. But if query can be executed on some of the available VOPS projections,
then it's speed can be increased several times (for example speedup on TPC-H Q1 is about ten times).

Synchronization of main table and VOPS projects is responsibly of user.
The straightforward solution is to use on-insert trigger to propagate changes to projection.
But it is actually bad idea: to efficiently pack records in vertical format we need to
perform bulk inserts. So we need to hold data in some buffer and then perform massive update.
Fortunately VOPS is useful for OLAP queries and such queries usually do not require most recent data.
So it is possible to periodically transfer data from main table to projects (for example at night
when system is idle). If projection is ordered by some monotonic key (i.e timestamp),
then VOPS is smart enough to append only most recent records which are not parent in the projection.
If there is no such key, then projections should be recreated from scratch.

As far as main table and projections may not be synchronized, but default
such implicit query transformation is disabled.
You should explicitly switch it on using `vops.auto_substitute_projections` parameter.
It can be done locally for the current session or for the whole Postgres instance.

## <span id="projection_creation">Creation of projections</span>

Now consider creation of partitions more precisely.

In future it may be added to SQL grammar, so that it is possible to write
`CREATE PROJECTION xxx OF TABLE yyy(column1, column2,...) GROUP BY (column1, column2, ...)`.
But right now it can be done using `create_projection(projection_name text, source_table regclass, vector_columns text[], scalar_columns text[] default null, order_by text default null)` function.
First argument of this function specifies name of the projection, second refers to existed Postgres table, `vector_columns` is array of
column names which should be stores as VOPS tiles, `scalar_columns`  is array of grouping columns which type is preserved and
optional `order_by` parameter specifies name of ordering attribute (explained below).
The `create_projection(PNAME,...)` functions does the following:

1. Creates projection table with specified name and attributes.
2. Creates PNAME_refresh() functions which can be used to update projection.
3. Creates functional BRIN indexes for `first()` and `last()` functions of ordering attribute (if any)
4. Creates BRIN index on grouping attributes (if any)
5. Insert information about created projection in `vops_projections` table. This table is used by optimizer to
    automatically substitute table with partition.

The `order_by` attribute is one of the VOPS projection vector columns by which data is sorted. Usually it is some kind of timestamp
used in *time series* (for example trade date). Presence of such column in projection allows to incrementally update projection.
Generated `PNAME_refresh()` method calls `populate` method with correspondent values of `predicate` and
`sort` parameters, selecting from original table only rows with `order_by` column value greater than maximal
value of this column in the projection. It assumes that `order_by` is unique or at least refresh is done at the moment when there is some gap
in collected events. In addition to `order_by`, sort list for `populate` includes all scalar (grouping) columns.
It allows to efficiently group imported data by scalar columns and fill VOPS tiles (vector columns) with data.

When `order_by` attribute is specified, VOPS creates two functional  BRIN indexes on `first()` and `last()`
functions of this attribute. Presence of such indexes allows to efficiently select time slices. If original query contains
predicate like `(trade_date between '01-01-2017' and '01-01-2018')` then VOPS projection substitution mechanism adds
`(first(trade_date) >= '01-01-2017' and last(trade_date) >= '01-01-2018')` conjuncts which allow Postgres optimizer to use BRIN
index to locate affected pages.

In in addition to BRIN indexes for `order_by` attribute, VOPS also creates BRIN index for grouping (scalar) columns.
Such index allows to efficiently select groups and perform index join.

Presence of scalar columns in VOPS projections allows to used them in index search, grouping or ordering.
Please notice, that if you are importing data in VOPS projection with scalar columns,
then input data should be sorted by these columns. And number of duplicated combinations of this columns should be large enough (greater than hundreds).
Only in this case tiles will be efficiently filled with data. Otherwise you will only loose disk space without any positive effect on performance.


Right now projections can be automatically substituted only if:

1. Query doesn't contain joins.
2. Query performs aggregation of vector (tile) columns.
3. All other expressions in target list, `ORDER BY` / `GROUP BY` clauses refer only to scalar attributes of projection.

Projection can be removed using `drop_projection(projection_name text)` function.
It not only drops the correspondent table, but also removes information about it from `vops_partitions` table
and drops generated refresh function.

## <span id="example">Example of using projections</span>


```
create extension vops;

create table lineitem(
   l_orderkey integer,
   l_partkey integer,
   l_suppkey integer,
   l_linenumber integer,
   l_quantity real,
   l_extendedprice real,
   l_discount real,
   l_tax real,
   l_returnflag "char",
   l_linestatus "char",
   l_shipdate date,
   l_commitdate date,
   l_receiptdate date,
   l_shipinstruct char(25),
   l_shipmode char(10),
   l_comment char(44),
   l_dummy char(1));

-- Create VOPS projection
select create_projection('vops_lineitem','lineitem',array['l_shipdate','l_quantity','l_extendedprice','l_discount','l_tax'],array['l_returnflag','l_linestatus']);

\timing

-- Load data in main table
copy lineitem from '/mnt/data/lineitem.tbl' delimiter '|' csv;

-- Transfer data from main table to projections.
select vops_lineitem_refresh();

-- Allow query substition
set vops.auto_substitute_projections TO  on;

-- Now let VOPS planner hook to use VOPS projections instead of main table
select
    l_returnflag,
    l_linestatus,
    sum(l_quantity) as sum_qty,
    sum(l_extendedprice) as sum_base_price,
    sum(l_extendedprice*(1-l_discount)) as sum_disc_price,
    sum(l_extendedprice*(1-l_discount)*(1+l_tax)) as sum_charge,
    avg(l_quantity) as avg_qty,
    avg(l_extendedprice) as avg_price,
    avg(l_discount) as avg_disc,
    count(*) as count_order
from
    lineitem
where
    l_shipdate <= '1998-12-01'
group by
    l_returnflag,
    l_linestatus
order by
    l_returnflag,
    l_linestatus;
```

## <span id="vops_rules">Three rules of using VOPS</span>

Now lets formulate 1-2-3 rules of using VOPS.

1. Consider whether VOPS can help to speed-up your application. VOPS will be useful if
your applications runs OLAP queries on large volumes of data and these queries mostly do some
filtering and aggregation (may be with grouping). If queries contain joins, then VOPS can not help you
unless you perform join on foreign key which was left as scalar in projections.
But even in the last case automatic substations of query will not work and you have to write query manually.

2. Find out whether your queries perform some particular grouping. Size of each group should be large enough
(thousands) and number of different grouping combination should be small (because maintaining more than few projections
will be too expensive). Create projection for each group.

3. Define projection refresh policy. If original table contains some monotonic key (like timestamp or
auto-generated column), then specify it as ordering field during projection creation. It will allow to incrementally update projection,
appending only new records. VOPS is mostly oriented on work with append-only tables. There is no way to efficiently handle updates.
To make transformation from horizontal to vertical format as efficient as possible, you should perform bulk update,
adding relatively large number of records.
Adding records to projection one-by-one leads to very bad space utilization, because VOPS is not able to append data to existed tiles.

Once you created projections and populated them with data, you can try to run queries.
Please use `EXPLAIN` to check whether plan for projection was chosen.

## <span id="vops_pros_and_contras">VOPS pros and contras</span>

Advantages of VOPS:
1. Significant (several times) increase of execution speed on some OLAP queries.
VOPS provides speed comparable with Yandex Clickhouse, preserving all power of Postgres relational model.
2. Can be used with any version of Postgres: no need to install Postgres forks and migrate data to them
(unlike CitusDB/GreenPlum)
3. Fully transnational, data can be managed using standard Postgres utilities, like basebackup, pg_dump...
4. VOPS doesn't affect original table, so presence of VOPS doesn't somehow affect data consistency/durability,
as well as performance of OLTP operations on original table, for example data insertion speed.
5. Doesn't require rewriting queries and changing your application  (in case of using automatic query substitution).

Certainly VOPS approach has some limitations and disadvantages:
1. Extra space needed for VOPS projections: maintaining N projections requires N times more storage space.
2. Original table and projections are not synchronized, so online analytic is not possible
(OLAP queries are not working with most recent data).
3. Transferring data from main table to projection may take significant amount of time and right now this operation can not be done in parallel.
4. Only small subset of OLAP queries can be efficiently handled by VOPS (joins, subqueries, window functions and many other things are not supported).
5. No columnar specific compression is performed (VOPS relies on standard Postgres compression mechanism which is not so efficient).
6. Some query plans may return incorrect results (for example VOPS correctly works for hash aggregate, but not for sort aggregate).

I hope that this small document can help you to understand whether VOPS may be useful in your case.
