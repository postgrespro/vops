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
   l_returnflag char,
   l_linestatus char,
   l_shipdate date,
   l_commitdate date,
   l_receiptdate date,
   l_shipinstruct char(25),
   l_shipmode char(10),
   l_comment char(44),
   l_dummy char(1));

copy lineitem from '/mnt/data/lineitem.tbl' delimiter '|' csv;

create table vops_lineitem(
   l_shipdate vops_date not null,
   l_quantity vops_float4 not null,
   l_extendedprice vops_float4 not null,
   l_discount vops_float4 not null,
   l_tax vops_float4 not null,
   l_returnflag vops_char not null,
   l_linestatus vops_char not null
);

create table vops_lineitem_projection(                                                                                    
   l_shipdate vops_date not null,
   l_quantity vops_float4 not null,
   l_extendedprice vops_float4 not null,
   l_discount vops_float4 not null,
   l_tax vops_float4 not null,
   l_returnflag "char" not null,
   l_linestatus "char" not null
);

-- create index lineitem_shipdate on vops_lineitem using brin(first(l_shipdate)); 
-- select populate(destination := 'vops_lineitem'::regclass, source := 'lineitem'::regclass, sort := 'l_shipdate');

select populate(destination := 'vops_lineitem'::regclass, source := 'lineitem'::regclass);

create table lineitem_projection as (select l_shipdate,l_quantity,l_extendedprice,l_discount,l_tax,l_returnflag::"char",l_linestatus::"char" from lineitem);

select populate(destination := 'vops_lineitem_projection'::regclass, source := 'lineitem_projection'::regclass, sort := 'l_returnflag,l_linestatus');

\timing on

-- Q6
select
    sum(l_extendedprice*l_discount) as revenue
from
    lineitem
where
    l_shipdate between '1996-01-01' and '1997-01-01'
    and l_discount between 0.08 and 0.1
    and l_quantity < 24;
-- Seq time: 16796.237 ms
-- Par time:  4110.401 ms

select
    sum(l_extendedprice*l_discount) as revenue
from
    lineitem_projection
where
    l_shipdate between '1996-01-01' and '1997-01-01'
    and l_discount between 0.08 and 0.1
    and l_quantity < 24;
-- Seq time:  4279.043 ms
-- Par time:  1171.193 ms

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
-- Seq time: 38028.345 ms
-- Par time: 10996.792 ms

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
    lineitem_projection
where
    l_shipdate <= '1998-12-01'
group by
    l_returnflag,
    l_linestatus
order by
    l_returnflag,
    l_linestatus;
-- Seq time: 33872.223 ms
-- Par time:  7502.620 ms
                                                                                                                                 
--
-- VOPS
-- 

-- Q6 using VOPS special operators
select countall(*),sum(l_extendedprice*l_discount) as revenue
from vops_lineitem
where filter((l_shipdate >= '1996-01-01'::date) 
		& (l_shipdate <= '1997-01-01'::date)
		& (l_discount >= 0.08)
		& (l_discount <= 0.1)
		& (l_quantity < 24));

-- Q6 with BETIXT
select sum(l_extendedprice*l_discount) as revenue
from vops_lineitem
where filter(betwixt(l_shipdate, '1996-01-01', '1997-01-01')
		& betwixt(l_discount, 0.08, 0.1)
		& (l_quantity < 24));
-- Seq time: 875.045 ms
-- Par time: 283.966 ms

-- Q6 using standard SQL
select
    sum(l_extendedprice*l_discount) as revenue
from
    vops_lineitem_projection
where
    l_shipdate between '1996-01-01'::date and '1997-01-01'::date
    and l_discount between 0.08 and 0.1
    and l_quantity < 24;

-- Q1 using VOPS group by
select reduce(map(l_returnflag||l_linestatus, 'sum,sum,sum,sum,avg,avg,avg',
    l_quantity,
    l_extendedprice,
    l_extendedprice*(1-l_discount),
    l_extendedprice*(1-l_discount)*(1+l_tax),
    l_quantity,
    l_extendedprice,
    l_discount)) from vops_lineitem where filter(l_shipdate <= '1998-12-01'::date);
-- Seq time: 3372.416 ms
-- Par time: 951.031 ms
	   
-- Q1 in standard SQL
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
-- Seq time: 1490.143 ms
-- Par time: 396.329 ms
