## <span id="motivation">Motivation</span>

PostgreSQL looks very competitive with other mainstream databases on
OLTP workload (execution of large number of simple queries). But on OLAP
queries, requiring processing of larger volumes of data, DBMS-es
oriented on analytic queries processing can provide an order of
magnitude better speed. Let's investigate why it happen and can we do
something to make PostgreSQL efficient also for OLAP
queries.

## <span id="profiling">Where DBMS spent most of the time during processing OLAP queries?</span>

Profiling execution of queries shows several main factors, limiting
Postgres performance:

1.  Unpacking tuple overhead (tuple\_deform). To be able to access
    column values, Postgres needs to deform the tuple. Values can be
    compressed, stored at some other page (TOAST), ... Also, as far as
    size of column can be varying, to extract N-th column we need to
    unpack preceding N-1 columns. So deforming tuple is quite expensive
    operation, especially for tables with large number of attributes. In
    some cases rearranging columns in the table allows to significantly
    reduce query execution time. Another universal approach is to split
    table into two: one small with frequently accessed scalar columns
    and another with rarely used large columns. Certainly in this case
    we need to perform extra join but it allows to several times reduce
    amount of fetched data. In queries like TPC-H Q6, tuple deform takes
    about 40% of total query execution time.
2.  Interpretation overhead. Postgres compiler and optimizer build tree
    representing query execution plan. So query executor performs
    recursive invocation of evaluate functions for nodes of this tree.
    Implementation of some nodes also contain switches used to select
    requested action. So query plan is interpreted by Postgres query
    executor rather than directly executed. Usually interpreter is about
    10 times slower than native code. This is why elimination of
    interpretation overhead allows to several times increase query
    speed, especially for queries with complex predicates where most
    time is spent in expression evaluation.
3.  Abstraction penalty. Support of abstract (user defined) types and
    operations is one of the key features of Postgres. It's executor is
    able to deal not only with built-in set of scalar types (like
    integer, real, ...) but with any types defined by user (for example
    complex, point,...). But the price of such flexibility is that each
    operations requires function call. Instead of adding to integers
    directly, Postgres executor invokes function which performs addition
    of two integers. Certainly in this case function call overhead is
    much larger then performed operation itself. Function call overhead
    is also increased because of Postgres function call convention
    requiring passing parameter values through memory (not using
    register call convention).
4.  Pull model overhead. Postgres executor is implementing classical
    Volcano-style query execution model - pull model. Operand's values
    are pulled by operator. It simplifies executor and operators
    implementation. But it has negative impact on performance, because
    leave nodes (fetching tuple from heap or index page) have to do a
    lot of extra work saving and restoring their context.
5.  MVCC overhead. Postgres provides multiversion concurrency control,
    which allows multiple transactions to concurrently work with the
    same record without blocking each other. It is goods for frequently
    updated data (OLTP), but for read-only or append-only data in OLAP
    scenarios it adds just extra overhead. Both space overhead (about 20
    extra bytes per tuple) and CPU overhead (checking visibility of each
    tuple).

There are many different ways of addressing this issues. For example we
can use JIT (Just-In-Time) compiler to generate native code for query
and eliminate interpretation overhead and increase heap deform speed. We
can rewrite optimizer from pull to push model. We can try to optimize
tuple format to make heap deforming more efficient. Or we can generate
byte code for query execution plan which interpretation is more
efficient than recursive invocation of evaluate function for each node
because of better access locality. But all this approaches require
significant rewriting of Postgres executor and some of them also require
changes of all Postgres architecture.

But there is an approach which allows to address most of this issues
without radical changes of executor. It is vector operations. It is
explained in next section.

## <span id="vertical">Vertical storage</span>

Traditional query executor (like Postgres executor) deals with single
row of data at each moment of time. If it has to evaluate expression
(x+y) then it fetches value of "x", then value of "y", performs
operation "+" and returns the result value to the upper node. In
contrast vectorized executor is able to process in one operation
multiple values. In this case "x" and "y" represent not just a single
scalar value, but vector of values and result is also a vector of
values. In vector execution model interpretation and function call
overhead is divided by size of vector. The price of performing function
call is the same, but as far as function proceeds N values instead of
just one, this overhead become less critical.

What is the optimal size for the vector? From the explanation above it
is clear that the larger vector is, the less per-row overhead we have.
So we can form vector from all values of the correspondent table
attribute. It is so called vertical data model or columnar store. Unlike
classical "horizontal" data model where the unit of storing data is row
(tuple), here we have vertical columns. Columnar store has the following
main advantages:

  - Reduce size of fetched data: only columns used in query need to be
    fetched
  - Better compression: storing all values of the same attribute
    together makes it possible to much better and faster compress them,
    for example using delta encoding.
  - Minimize interpretation overhead: each operation is perform not for
    single value, but for set of values
  - Use CPU vector instruction (SIMD) to process data

There are several DBMS-es implementing columnar store model. Most
popular are [Vertica](https://vertica.com/),
[MonetDB](https://www.monetdb.org/Home). But actually performing
operation on the whole column is not so good idea. Table can be very
large (OLAP queries are used to work with large data sets), so vector
can also be very big and even doesn't fit in memory. But even if it fits
in memory, working with such larger vectors prevent efficient
utilization of CPU caches (L1, L2,...). Consider expression
(x+y)\*(x-y). Vector executor performs addition of two vectors : "x" and
"y" and produces result vector "r1". But when last element of vector "r"
is produced, first elements of vector "r1" are already thrown from CPU
cache, as well as first elements of "x" and "y" vectors. So when we need
to calculate (x-y) we once again have to load data for "x" and "y" from
slow memory to fast cache. Then we produce "r2" and perform
multiplication of "r1" and "r2". But here we also need first to load
data for this vectors into the CPU cache.

So it is more efficient to split column into relatively small *chunks*
(or *tiles* - there is no single notion for it accepted by everyone).
This chunk is a unit of processing by vectorized executor. Size of such
chunk is chosen to keep all operands of vector operations in cache even
for complex expressions. Typical size of chunk is from 100 to 1000
elements. So in case of (x+y)\*(x-y) expression, we calculate it not for
the whole column but only for 100 values (assume that size of the chunk
is 100). Splitting columns into chunks in successors of MonetDB x100 and
HyPer allows to increase speed up to ten times.

## <span id="vops">VOPS</span>

<span id="overview">Overview</span>

There are several attempts to integrate columnar store in PostgreSQL.
The most known is [CStore FDW](https://github.com/citusdata/cstore_fdw)
by CitusDB. It is implemented as foreign data wrapper (FDW) and is
efficient for queries fetching relatively small fraction of columns. But
it is using standard Postgres raw-based executor and so is not able to
take advantages of vector processing. There is interesting
[project](https://github.com/citusdata/postgres_vectorization_test) done
by CitusDB intern. He implements vector operations on top of CStore
using executors hooks for some nodes. IT reports 4-6 times speedup for
grand aggregates and 3 times speedup for aggregation with group by.

Another project is [IMCS](https://github.com/knizhnik/imcs): In-Memory
Columnar Store. Here columnar store is implemented in memory and is
accessed using special functions. So you can not use standard SQL query
to work with this storage - you have to rewrite it using IMCS functions.
IMCS provides vector operations (using tiles) and parallel execution.

Both CStore and IMCS are keeping data outside Postgres. But what if we
want to use vector operations for data kept in standard Postgres tables?
Definitely, the best approach is to impalement alternative heap format.
Or even further: eliminate notion of heap at all - treat heap just as
yet another access method, similar with other indexes.

But such radical changes requires deep redesign of all Postgres
architecture. It will be better to estimate first possible advantages we
can expect from usage of vector vector operations. Vector executor is
widely discussed in Postgres forums, but efficient vector executor is
not possible without underlying support at storage layer. Advantages of
vector processing will be annihilated if vectors are formed from
attributes of rows extracted from existed Postgres heap page.

The idea of VOPS extension is to implement vector operations for tiles
represented as special Postgres types. Tiles should be used as table
column types instead of scalar types. For example instead of "real" we
should use "vops\_float4" which is tile representing up to 64 values of
the correspondent column. Why 64? There are several reasons for choosing
this number:

1.  We provide efficient access to tiles, we need that
    size\_of\_tile\*size\_of\_attribute\*number\_of\_attributes is
    smaller than page size. Typical record contains about 10 attributes,
    default size of Postgres page is 8kb.
2.  64 is number of bits in large word. We need to maintain bitmask to
    mark null values. Certainly it is possible to store bitmask in array
    with arbitrary size, but manipulation with single 64-bit integer is
    more efficient.
3.  Due to the arguments above, to efficiently utilize cache, size of
    tile should be in range 100..1000.

VOPS is implemented as Postgres extension. It doesn't change anything in
Postgres executor and page format. It also doesn't setup any executors
hooks or alter query execution plan. The main idea of this project was
to measure speedup which can be reached by using vector operation with
existed executor and heap manager. VOPS provides set of standard
operators for tile types, allowing to write SQL queries in the way
similar with normal SQL queries. Right now vector operators can be used
inside predicates and aggregate expressions. Joins are not currently
supported. Details of VOPS architecture are described below.

### <span id="types">Types</span>

VOPS supports all basic Postgres numeric types: 1,2,4,8 byte integers
and 4,8 bytes floats. Also it supports `date` and `timestamp` types but
them are using the same implementation as `int4` and `int8`
correspondingly.

| SQL type                | C type    | VOPS tile type  |
| ----------------------- | --------- | --------------- |
| bool                    | bool      | vops\_bool      |
| "char"                  | char      | vops\_char      |
| int2                    | int16     | vops\_int2      |
| int4                    | int32     | vops\_int4      |
| int8                    | int64     | vops\_int8      |
| float4                  | float4    | vops\_float4    |
| float8                  | float8    | vops\_float8    |
| date                    | DateADT   | vops\_date      |
| timestamp               | Timestamp | vops\_timestamp |
| char(N), varchar(N)     | text      | vops\_text      |

VOPS doesn't support work with strings (char or varchar types), except
case of single character. If strings are used as identifiers, in most
cases it is preferable to place them in some dictionary and use integer
identifiers instead of original strings.

### <span id="operators">Vector operators</span>

VOPS provides implementation of all built-in SQL arithmetic operations
for numeric types: **+ - / \*** Certainly it also implements all
comparison operators: **= \<\> \> \>= \< \<=**. Operands of such
operators can be either tiles, either scalar constants: `x=y` or `x=1`.

Boolean operators `and`, `or`, `not` can not be overloaded. This is why
VOPS provides instead of them operators **& | \!**. Please notice that
precedence of this operators is different from `and`, `or`, `not`
operators. So you can not write predicate as `x=1 | x=2` - it will cause
syntax error. To solve this problem please use parenthesis: `(x=1) |
(x=2)`.

Also VOPS provides analog of between operator. In SQL expression `(x
BETWEEN a AND b)` is equivalent to `(x >= a AND x <= b)`. But as far as
AND operator can not be overloaded, such substitution will not work for
VOPS tiles. This is why VOPS provides special function for range check.
Unfortunately `BETWEEN` is reserved keyword, so no function with such
name can be defined. This is why synonym `BETWIXT` is used.

.

Postgres requires predicate expression to have boolean type. But result
of vector boolean operators is `vops_bool`, not `bool`. This is why
compiler doesn't allow to use it in predicate. The problem can be solved
by introducing special `filter` function. This function is given
arbitrary vector boolean expression and returns normal boolean which ...
is always true. So from Postgres executor point of view predicate value
is always true. But `filter` function sets `filter_mask` which is
actually used in subsequent operators to determine selected records. So
query in VOPS looks something like this:

``` 
  select sum(price) from trades where filter(day >= '2017-01-01'::date);
```

Please notice one more difference from normal sequence: we have to use
explicit cast of string constant to appreciate data type (`date` type in
this example). For `betwixt` function it is not
needed:

``` 
  select sum(price) from trades where filter(betwixt(day, '2017-01-01', '2017-02-01'));
```

For `char`, `int2` and `int4` types VOPS provides concatenation operator
**||** which produces doubled integer type: `(char || char) -> int2`,
`(int2 || int2) -> int4`, `(int4 || int4) -> int8`. Them can be used for
grouping by several columns (see below).

| Operator              | Description                          |
| --------------------- | ------------------------------------ |
| `+`                   | Addition                             |
| `-`                   | Binary subtraction or unary negation |
| `*`                   | Multiplication                       |
| `/`                   | Division                             |
| `=`                   | Equals                               |
| `<>`                  | Not equals                           |
| `<`                   | Less than                            |
| `<=`                  | Less than or Equals                  |
| `>`                   | Greater than                         |
| `>=`                  | Greater than or equals               |
| `&`                   | Boolean AND                          |
| `\|`                  | Boolean OR                           |
| `!`                   | Boolean NOT                          |
| `bitwixt(x,low,high)` | Analog of BETWEEN                    |
| `is_null(x)`          | Analog of IS NULL                    |
| `is_not_null(x)`      | Analog of IS NOT NULL                |
| `ifnull(x,subst)`     | Analog of COALESCE                   |

### <span id="aggregates">Vector aggregates</span>

OLAP queries usually perform some kind of aggregation of large volumes
of data. These includes `grand` aggregates which are calculated for the
whole table or aggregates with `group by` which are calculated for each
group. VOPS implements all standard SQL aggregates: `count, min, max,
sum, avg, var_pop, var_sampl, variance, stddev_pop, stddev_samp,
stddev`. Them can be used exactly in the same way as in normal SQL
queries:

    select sum(l_extendedprice*l_discount) as revenue
    from vops_lineitem
    where filter(betwixt(l_shipdate, '1996-01-01', '1997-01-01')
            & betwixt(l_discount, 0.08, 0.1)
            & (l_quantity < 24));

Also VOPS provides weighted average aggregate VWAP which can be used to
calculate volume-weighted average price:

    select wavg(l_extendedprice,l_quantity) from vops_lineitem;

Using aggregation with group by is more complex. VOPS provides two
functions for it: `map` and `reduce`. The work is actually done by
**map**(*group\_by\_expression*, *aggregate\_list*, *expr* {, *expr* })
VOPS implements aggregation using hash table, which entries collect
aggregate states for all groups. And set returning function `reduce`
just iterates through the hash table consrtucted by `map`. `reduce`
function is needed because result of aggregate in Postgres can not be a
set. So aggregate query with group by looks something like
    this:

    select reduce(map(l_returnflag||l_linestatus, 'sum,sum,sum,sum,avg,avg,avg',
        l_quantity,
        l_extendedprice,
        l_extendedprice*(1-l_discount),
        l_extendedprice*(1-l_discount)*(1+l_tax),
        l_quantity,
        l_extendedprice,
        l_discount)) from vops_lineitem where filter(l_shipdate <= '1998-12-01'::date);

Here we use concatenation operator to perform grouping by two columns.
Right now VOPS supports grouping only by integer type. Another serious
restriction is that all aggregated expressions should have the same
type, for example `vops_float4`. It is not possible to calculate
aggregates for `vops_float4` and `vopd_int8` columns in one call of
`map` function, because it accepts aggregation arguments as variadic
array, so all elements of this array should have the same type.

Aggregate string in `map` function should contain list of requested
aggregate functions, separated by colon. Standard lowercase names should
be used: `count, sum, agg, min, max`. Count is executed for the
particular column: `count(x)`. There is no need to explicitly specify
`count(*)` because number of records in each group is returned by
`reduce` function in any case.

`reduce` function returns set of `vops_aggregate` type. It contains
three components: value of group by expression, number of records in the
group and array of floats with aggregate values. Please notice that
values of all aggregates, including `count` and `min/max`, are returned
as
    floats.

    create type vops_aggregates as(group_by int8, count int8, aggs float8[]);
    create function reduce(bigint) returns setof vops_aggregates;

But there is much simple and straightforward way of performing group
aggregates using VOPS. We need to partition table by *group by* fields.
In this case grouping keys will be stored in normal way and other fields
- inside tiles. Now Postgres executor will execute VOPS aggregates for
each group:

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
        countall(*) as count_order
    from
        vops_lineitem_projection
    where
        filter(l_shipdate <= '1998-12-01'::date)
    group by
        l_returnflag,
        l_linestatus
    order by
        l_returnflag,
        l_linestatus;

In this example `l_returnflag` and `l_linestatus` fields of table
vops\_lineitem\_projection have `"char"` type while all other used
fields - tile types (`l_shipdate` has type `vops_date` and other fields
- `vops_float4`). The query above is executed even faster than query
with `reduce(map(...))`. The main problem with this approach is that you
have to create projection for each combination of group by keys you want
to use in queries.

### <span id="window">Vector window functions</span>

VOPS provides limited support of Postgres window functions. It
implements `count, sum, min, max, avg` and `lag` functions. But
unfortunately Postgres requires aggregates to have to similar final type
for moving (window) and plain implementations. This is why VOPS has to
choose define this aggregate under different names: `mcount, msum, mmin,
mmax, mavg`.

There are also two important restrictions:

1.  Filtering, grouping and sorting can be done only by scalar
    (non-tile) attributes
2.  Only `rows between unbounded preceding and current row` frame is
    supported (but there is special version of `msum` which accepts
    extra window size parameter)

Example of using window functions with
    VOPS:

    select unnest(t.*) from (select mcount(*) over w,mcount(x) over w,msum(x) over w,mavg(x) over w,mmin(x) over w,mmax(x) over w,x - lag(x) over w 
    from v window w as (rows between unbounded preceding and current row)) t;

### <span id="indexes">Using indexes</span>

Analytic queries are usually performed on the data for which no indexes
are defined. And columnar store vector operations are most efficient in
this case. But it is still possible to use indexes with VOPS.

As far as each VOPS tile represents multiple values, index can be used
only for some preliminary, non-precise filtering of data. It is
something similar with BRIN indexes. VOPS provides four functions:
`first, last, high, low` which can be used to obtain high/low boundary
of values stored in the tile. First two functions `first` and `last`
should be used for sorted data set. In this case first value is the
smallest value in the tile and last value is the largest value in the
tile. If data is not sorted, then `low`high functions should be used,
which are more expensive, because them need to inspect all tile values.
Using this four function it is possible to construct functional indexes
for VOPS table. BRIN index seems to be the best choice for VOPS
    table:

    create index low_boundary on trades using brin(first(day)); -- trades table is ordered by day
    create index high_boundary on trades using brin(last(day)); -- trades table is ordered by day

Now it is possible to use this indexes in query. Please notice that we
have to recheck precise condition because index gives only approximate
result:

    select sum(price) from trades where first(day) >= '2015-01-01' and last(day) <= '2016-01-01'
                                                   and filter(betwixt(day, '2015-01-01', '2016-01-01'));

### <span id="populating">Preparing data for VOPS</span>

Now the most interesting question (from which may be we should start) -
how we managed to prepare data for VOPS queries? Who and how will
combine attribute values of several rows inside one VOPS tile? It is
done by `populate` functions, provided by VOPS extension.

First of all you need to create table with columns having VOPS tile
types. It can map all columns of the original table or just some most
frequently used subset of them. This table can be treated as
`projection` of original table (this concept of projections is taken
from Vertica). Projection should include columns which are most
frequently used together in queries.

Original table from TPC-H benchmark:

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
       l_comment char(44));

VOPS projection of this table:

    create table vops_lineitem(
       l_shipdate vops_date not null,
       l_quantity vops_float4 not null,
       l_extendedprice vops_float4 not null,
       l_discount vops_float4 not null,
       l_tax vops_float4 not null,
       l_returnflag vops_char not null,
       l_linestatus vops_char not null
    );

Original table can be treated as write optimized storage (WOS). If it
has not indexes, then Postgres is able to provide very fast insertion
speed, comparable with raw disk write speed. Projection in VOPS format
can be treated as read-optimized storage (ROS), most efficient for
execution of OLAP queries.

Data can be transferred from original to projected table using VOPS
`populate` function:

    create function populate(destination regclass, 
                            source regclass, 
                            predicate cstring default null, 
                            sort cstring default null) returns bigint;

Two first mandatory arguments of this function specify target and source
tables. Optional predicate and sort clauses allow to restrict amount of
imported data and enforce requested order. By specifying predicate it is
possible to update VOPS table using only most recently received records.
This functions returns number of loaded records. Example of populate
function
    invocation:

    select populate(destination := 'vops_lineitem'::regclass, source := 'lineitem'::regclass);

You can use populated table in queries performing sequential scan. VOPS
operators can speed up filtering of records and calculation of
aggregates. Aggregation with `group by` requires use of `reduce + map`
functions. But as it was mentioned above in the section describing
aggregates, it is possible to populate table in such way, that standard
Postgres grouping algorithm will be used.

We need to choose partitioning keys and sort original table by this
keys. Combination of partitioning keys expected to be NOT unique -
otherwise tiles can only increase used space and lead to performance
degradation. But if there are a lot of duplicates, then "collapsing"
them and storing other fields in tiles will help to reduce space and
speed up queries. Let's create the following projection of `lineitems`
table:

    create table vops_lineitem_projection(                                                                                    
       l_shipdate vops_date not null,
       l_quantity vops_float4 not null,
       l_extendedprice vops_float4 not null,
       l_discount vops_float4 not null,
       l_tax vops_float4 not null,
       l_returnflag "char" not null,
       l_linestatus "char" not null
    );

As you can see, in this table `l_returnflag` and `l_linestatus` fields
are scalars, and other fields - tiles. This projection can be populated
using the following
    command:

    select populate(destination := 'vops_lineitem_projection'::regclass, source := 'lineitem_projection'::regclass, sort := 'l_returnflag,l_linestatus');

Now we can create normal index on partitioning keys, define standard
predicates for them and use them in `group by` and `order by` clauses.

Sometimes it is not possible or not desirable to store two copies of the
same dataset. VOPS allows to load data directly from CSV file into VOPS
table with tiles, bypassing creation of normal (plain) table. It can be
done using `import`
    function:

    select import(destination := 'vops_lineitem'::regclass, csv_path := '/mnt/data/lineitem.csv', separator := '|');

`import` function is defined in this way:

    create function import(destination regclass, 
                           csv_path cstring, 
                           separator cstring default ',', 
                           skip integer default 0) returns bigint;

It accepts name of target VOPS table, path to CSV file, optional
separator (default is ',') and number of lines in CSV header (no header
by default). The function returns number of imported rows.

### <span id="unnest">Back to normal tuples</span>

A query from VOPS projection returns set of tiles. Output function of
tile type is able to print content of the tile. But in some cases it is
preferable to transfer result to normal (horizontal) format where each
tuple represents one record. It can be done using `unnest`
    function:

    postgres=# select unnest(l.*) from vops_lineitem l where filter(l_shipdate <= '1998-12-01'::date) limit 3;
                    unnest                 
    ---------------------------------------
     (1996-03-13,17,33078.9,0.04,0.02,N,O)
     (1996-04-12,36,38306.2,0.09,0.06,N,O)
     (1996-01-29,8,15479.7,0.1,0.02,N,O)
    (3 rows)

### <span id="fdw">Back to normal tables</span>

As it was mentioned in previous section, `unnest` function can scatter
records with VOPS types into normal records with scalar types. So it is
possible to use this records in arbitrary SQL queries. But there are two
problems with unnest function:

1.  It is not convenient to use. This function has no static knowledge
    about the format of output record and this is why programmer has to
    specify it manually, if here wants to decompose this record.
2.  PostgreSQL optimizer has completely no knowledge on result of
    transformation performed by unnest() function. This is why it is not
    able to choose optimal query execution plan for data retrieved from
    VOPS table.

Fortunately Postgres provides solution for both of this problem: foreign
data wrappers (FDW). In our case data is not really "foreign": it is
stored inside our own database. But in alternatives (VOPS) format. VOPS
FDW allows to "hide" specific of VOPS format and run normal SQL queries
on VOPS tables. FDW allows the following:

1.  Extract data from VOPS table in normal (horizontal) format so that
    it can be proceeded by upper nodes in query execution plan.
2.  Pushdown to VOPS operations that can be efficiently executed using
    vectorized operations on VOPS types: filtering and aggregation.
3.  Provide statistic for underlying table which can be used by query
    optimizer.

So, by placing VOPS projection under FDW, we can efficiently perform
sequential scan and aggregation queries as if them will be explicitly
written for VOPS table and at the same time be able to execute any other
queries on this data, including joins, CTEs,... Query can be written in
standard SQL without usage of any VOPS specific functions.

Below is an example of creating VOPS FDW and running some queries on it:

    create foreign table lineitem_fdw  (
       l_suppkey int4 not null,
       l_orderkey int4 not null,
       l_partkey int4 not null,
       l_shipdate date not null,
       l_quantity float4 not null,
       l_extendedprice float4 not null,
       l_discount float4 not null,
       l_tax      float4 not null,
       l_returnflag "char" not null,
       l_linestatus "char" not null
    ) server vops_server options (table_name 'vops_lineitem');
    
    explain select
       sum(l_extendedprice*l_discount) as revenue
    from
       lineitem_fdw
    where
       l_shipdate between '1996-01-01' and '1997-01-01'
       and l_discount between 0.08 and 0.1
       and l_quantity < 24;
                           QUERY PLAN                        
    ---------------------------------------------------------
     Foreign Scan  (cost=1903.26..1664020.23 rows=1 width=4)
    (1 row)
    
    -- Filter was pushed down to FDW
    
    explain select
        n_name,
        count(*),
        sum(l_extendedprice * (1-l_discount)) as revenue
    from
        customer_fdw join orders_fdw on c_custkey = o_custkey
        join lineitem_fdw on l_orderkey = o_orderkey
        join supplier_fdw on l_suppkey = s_suppkey
        join nation on c_nationkey = n_nationkey
        join region on n_regionkey = r_regionkey
    where
        c_nationkey = s_nationkey
        and r_name = 'ASIA'
        and o_orderdate >= '1996-01-01'
        and o_orderdate < '1997-01-01'
    group by
        n_name
    order by
        revenue desc;
                                                                  QUERY PLAN                                                              
    --------------------------------------------------------------------------------------------------------------------------------------
     Sort  (cost=2337312.28..2337312.78 rows=200 width=48)
       Sort Key: (sum((lineitem_fdw.l_extendedprice * ('1'::double precision - lineitem_fdw.l_discount)))) DESC
       ->  GroupAggregate  (cost=2336881.54..2337304.64 rows=200 width=48)
             Group Key: nation.n_name
             ->  Sort  (cost=2336881.54..2336951.73 rows=28073 width=40)
                   Sort Key: nation.n_name
                   ->  Hash Join  (cost=396050.65..2334807.39 rows=28073 width=40)
                         Hash Cond: ((orders_fdw.o_custkey = customer_fdw.c_custkey) AND (nation.n_nationkey = customer_fdw.c_nationkey))
                         ->  Hash Join  (cost=335084.53..2247223.46 rows=701672 width=52)
                               Hash Cond: (lineitem_fdw.l_orderkey = orders_fdw.o_orderkey)
                               ->  Hash Join  (cost=2887.07..1786058.18 rows=4607421 width=52)
                                     Hash Cond: (lineitem_fdw.l_suppkey = supplier_fdw.s_suppkey)
                                     ->  Foreign Scan on lineitem_fdw  (cost=0.00..1512151.52 rows=59986176 width=16)
                                     ->  Hash  (cost=2790.80..2790.80 rows=7702 width=44)
                                           ->  Hash Join  (cost=40.97..2790.80 rows=7702 width=44)
                                                 Hash Cond: (supplier_fdw.s_nationkey = nation.n_nationkey)
                                                 ->  Foreign Scan on supplier_fdw  (cost=0.00..2174.64 rows=100032 width=8)
                                                 ->  Hash  (cost=40.79..40.79 rows=15 width=36)
                                                       ->  Hash Join  (cost=20.05..40.79 rows=15 width=36)
                                                             Hash Cond: (nation.n_regionkey = region.r_regionkey)
                                                             ->  Seq Scan on nation  (cost=0.00..17.70 rows=770 width=40)
                                                             ->  Hash  (cost=20.00..20.00 rows=4 width=4)
                                                                   ->  Seq Scan on region  (cost=0.00..20.00 rows=4 width=4)
                                                                         Filter: ((r_name)::text = 'ASIA'::text)
                               ->  Hash  (cost=294718.76..294718.76 rows=2284376 width=8)
                                     ->  Foreign Scan on orders_fdw  (cost=0.00..294718.76 rows=2284376 width=8)
                         ->  Hash  (cost=32605.64..32605.64 rows=1500032 width=8)
                               ->  Foreign Scan on customer_fdw  (cost=0.00..32605.64 rows=1500032 width=8)
    
    -- filter on orders range is pushed to FDW

## <span id="transform">Standard SQL query transformation</span>

Previous section describes VOPS specific types, operators, functions,...
Good news\! You do not need to learn them. You can use normal SQL. Well,
it is still responsibility of programmer or database administrator to
create proper projections of original table. This projections need to
use tiles types for some attributes (vops\_float4,...). Then you can
query this table using standard SQL. And this query will be executed
using vector operations\!

How it works? There are absolutely no magic here. There are four main
components of the puzzle:

1.  User defined types
2.  User defined operator
3.  User defined implicit type casts
4.  Post parse analyze hook which performs query transformation

So VOPS defines tile types and standard SQL operators for this types.
Then it defines implicit type cast from `vops_bool` (result of boolean
operation with tiles) to boolean type. Now programmer do not have to
wrap vectorized boolean operations in `filter()` function call. And the
final transformation is done by post parse analyze hook, defined by VOPS
extension. It replaces scalar boolean operations with vector boolean
operations:

| Original expression         | Result of transformation        |
| --------------------------- | ------------------------------- |
| `NOT filter(o1)`            | `filter(vops_bool_not(o1))`     |
| `filter(o1) AND filter(o2)` | `filter(vops_bool_and(o1, o2))` |
| `filter(o1) OR filter(o2)`  | `filter(vops_bool_or(o1, o2))`  |

Now there is no need to use VOPS specific `BETIXT` operator: standard
SQL `BETWEEN` operator will work (but still using `BETIXT` is slightly
more efficient, because it performs both comparions in one function).
Also there are no problems with operators precedence and extra
parenthesis are not needed. If query includes vectorized aggregates,
then `count(*)` is transformed to `countall(*)`.

There is only one difference left between standard SQL and its
vectorized extension. You still have to perform explicit type cast in
case of using string literal, for example `l_shipdate <= '1998-12-01'`
will not work for `l_shipdate` column with tile type. Postgres have two
overloaded versions of \<= operator which can be applied here:

1.  `vops_date` **\<=** `vops_date`
2.  `vops_date` **\<=** `date`

And it decides that it is better to convert string to the tile type
`vops_date`. In principle, it is possible to provide such conversion
operator. But it is not good idea, because we have to generate dummy
tile with all components equal to the specified constant and perform
(*vector* **OP** *vector*) operation instead of more efficient (*vector*
**OP** *scalar*).

There is one pitfall with post parse analyze hook: it is initialized in
the extension `_PG_init` function. But if extension was not registered
in `shared_preload_libraries` list, then it will be loaded on demand
when any function of this extension is requested. Unfortunately it
happens **after** parse analyze is done. So first time you execute VOPS
query, it will not be transformed. You can get wrong result in this
case. Either take it in account, either add `vops` to
`shared_preload_libraries` configuration string. VOPS extension provides
special function `vops_initialize()` which can be invoked to force
initialization of VOPS extension. After invocation of this function,
extension will be loaded and all subsequent queries will be normally
transformed and produce expected results.

## <span id="projections">VOPS projections and automatic table sustitution</span>

VOPS provides some functions simplifying creation and usage of projections.
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

Like materialized views, VOPS projections are not updated automatically. It is responsibility of programmer to periodically refresh them.
Certainly it is possible to define trigger or rule which will automatically insert data in projection table when original table is updated.
But such approach will be extremely inefficient and slow. To take advantage of vector processing, VOPS has to group data in tiles.
It can be done only if there is some batch of data which can be grouped by scalar attributes. If you insert records in projection table on-by-one,
then most of VOPS tiles will contain just one element.
The most convenient way is to use generated `PNAME_refresh()` function.
If `order_by` attribute is specified, this function imports from original table only the new data (not present in projection).

The main advantage of VOPS projection mechanism is that it allows to automatically substitute queries on original tables with projections.
There is `vops.auto_substitute_projections` configuration parameter which allows to switch on such substitution.
By default it is switched off, because VOPS projects may be not synchronized with original table and query on projection may return different result.
Right now projections can be automatically substituted only if:

1. Query doesn't contain joins.
2. Query performs aggregation of vector (tile) columns.
3. All other expressions in target list, `ORDER BY` / `GROUP BY` clauses refer only to scalar attributes of projection.

Projection can be removed using `drop_projection(projection_name text)` function.
It not only drops the correspondent table, but also removes information about it from `vops_partitions` table
and drops generated refresh function.

Example of using projections:
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

select create_projection('vops_lineitem','lineitem',array['l_shipdate','l_quantity','l_extendedprice','l_discount','l_tax'],array['l_returnflag','l_linestatus']);

\timing

copy lineitem from '/mnt/data/lineitem.tbl' delimiter '|' csv;

select vops_lineitem_refresh();

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

set vops.auto_substitute_projections TO  on;

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


## <span id="example">Example</span>

The most popular benchmark for OLAP is [TPC-H](http://www.tpc.org/tpch).
It contains 21 different queries. We adopted for VOPS only two of them:
Q1 and Q6 which are not using joins. Most of fragments of this code are
already mentioned above, but here we collect it together:

``` 
-- Standard way of creating extension
create extension vops; 

-- Original TPC-H table
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
   l_dummy char(1)); -- this table is needed because of terminator after last column in generated data 

-- Import data to it
copy lineitem from '/mnt/data/lineitem.tbl' delimiter '|' csv;

-- Create VOPS projection
create table vops_lineitem(
   l_shipdate vops_date not null,
   l_quantity vops_float4 not null,
   l_extendedprice vops_float4 not null,
   l_discount vops_float4 not null,
   l_tax vops_float4 not null,
   l_returnflag vops_char not null,
   l_linestatus vops_char not null
);

-- Copy data to the projection table
select populate(destination := 'vops_lineitem'::regclass, source := 'lineitem'::regclass);

-- For honest comparison creates the same projection without VOPS types
create table lineitem_projection as (select l_shipdate,l_quantity,l_extendedprice,l_discount,l_tax,l_returnflag::"char",l_linestatus::"char" from lineitem);

-- Now create mixed projection with partitioning keys:
create table vops_lineitem_projection(                                                                                    
   l_shipdate vops_date not null,
   l_quantity vops_float4 not null,
   l_extendedprice vops_float4 not null,
   l_discount vops_float4 not null,
   l_tax vops_float4 not null,
   l_returnflag "char" not null,
   l_linestatus "char" not null
);

-- And populate it with data sorted by partitioning key:
select populate(destination := 'vops_lineitem_projection'::regclass, source := 'lineitem_projection'::regclass, sort := 'l_returnflag,l_linestatus');


-- Let's measure time
\timing

-- Original Q6 query performing filtering with calculation of grand aggregate
select
    sum(l_extendedprice*l_discount) as revenue
from
    lineitem
where
    l_shipdate between '1996-01-01' and '1997-01-01'
    and l_discount between 0.08 and 0.1
    and l_quantity < 24;

-- VOPS version of Q6 using VOPS specific operators
select sum(l_extendedprice*l_discount) as revenue
from vops_lineitem
where filter(betwixt(l_shipdate, '1996-01-01', '1997-01-01')
        & betwixt(l_discount, 0.08, 0.1)
        & (l_quantity < 24));

-- Yet another vectorized version of Q6, but now in stadnard SQL:
select sum(l_extendedprice*l_discount) as revenue
from vops_lineitem
where l_shipdate between '1996-01-01'::date AND '1997-01-01'::date
   and l_discount between 0.08 and 0.1
   and l_quantity < 24;



-- Original version of Q1: filter + group by + aggregation
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

-- VOPS version of Q1, sorry - no final sorting
select reduce(map(l_returnflag||l_linestatus, 'sum,sum,sum,sum,avg,avg,avg',
    l_quantity,
    l_extendedprice,
    l_extendedprice*(1-l_discount),
    l_extendedprice*(1-l_discount)*(1+l_tax),
    l_quantity,
    l_extendedprice,
    l_discount)) from vops_lineitem where filter(l_shipdate <= '1998-12-01'::date);
       
-- Mixed mode: let's Postgres does group by and calculates VOPS aggregates for each group
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
    vops_lineitem_projection
where
    l_shipdate <= '1998-12-01'::date
group by
    l_returnflag,
    l_linestatus
order by
    l_returnflag,
    l_linestatus;


```

## <span id="performance">Performance evaluation</span>

Now most interesting thing: compare performance results on original
table and using vector operations on VOPS projection. All measurements
were performed at desktop with 16Gb of RAM and quad-core i7-4770 CPU @
3.40GHz processor with enabled hyper-threading. Data set for benchmark
was generated by dbgen utility included in TPC-H benchmark. Scale factor
is 10 which corresponds to about 8Gb database. It can completely fit in
memory, so we are measuring best query execution time for *warm* data.
Postgres was configured with shared buffer size equal to 8Gb. For each
query we measured time of sequential and parallel execution with 8
parallel
workers.

| Query                                   | Sequential execution (msec) | Parallel execution (msec) |
| --------------------------------------- | --------------------------: | ------------------------: |
| Original Q1 for lineitem                |                       38028 |                     10997 |
| Original Q1 for lineitem\_projection    |                       33872 |                      9656 |
| Vectorized Q1 for vops\_lineitem        |                        3372 |                       951 |
| Mixed Q1 for vops\_lineitem\_projection |                        1490 |                       396 |
| Original Q6 for lineitem                |                       16796 |                      4110 |
| Original Q6 for lineitem\_projection    |                        4279 |                      1171 |
| Vectorized Q6 for vops\_lineitem        |                         875 |                       284 |

## <span id="conclusion">Conclusion</span>

As you can see in performance results, VOPS can provide more than 10
times improvement of query speed. And this result is achieved without
changing something in query planner and executor. It is better than any
of existed attempt to speed up execution of OLAP queries using JIT (4
times for Q1, 3 times for Q6): [Speeding up query execution in
PostgreSQL using LLVM JIT
compiler](http://llvm.org/devmtg/2016-09/slides/Melnik-PostgreSQLLLVM.pdf).

Definitely VOPS extension is just a prototype which main role is to
demonstrate potential of vectorized executor. But I hope that it also
can be useful in practice to speedup execution of OLAP aggregation
queries for existed databases. And in future we should think about the
best approach of integrating vectorized executor in Postgres core.

ALL sources of VOPS project can be obtained from this [GIT
repository](https://github.com/postgrespro/vops). Chinese version of
documentation is available
[here](https://github.com/digoal/blog/blob/master/201702/20170225_01.md).
Please send any feedbacks, complaints, bug reports, change requests to
[Konstantin Knizhnik](mailto:k.knizhnik@postgrespro.ru).
