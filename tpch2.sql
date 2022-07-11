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

create table orders(
    o_orderkey integer,
    o_custkey integer,
    o_orderstatus "char",
    o_totalprice real,
    o_orderdate date,
    o_orderpriority varchar,
    o_clerk varchar,
    o_shippriority integer,
    o_comment varchar,
    o_dummy char(1));

create table customer(
    c_custkey integer,
    c_name varchar,
    c_address varchar,
    c_nationkey integer,
    c_phone varchar,
    c_acctbal real,
    c_mktsegment varchar,
    c_comment varchar,
    c_dummy char(1));

create table nation(
    n_nationkey integer,
    n_name varchar,
    n_regionkey integer,
    n_comment varchar,
    c_dummy char(1));

CREATE TABLE region(
    r_regionkey INTEGER,
    r_name varchar,
    r_comment varchar,
    r_dummy char);

CREATE TABLE supplier(
    s_suppkey INTEGER,
    s_name varchar,
    s_address varchar,
    s_nationkey integer,
    s_phone varchar,
    s_acctbal real,
    s_comment varchar,
    s_dummy char);

create table vlineitem(
   l_suppkey vops_int4 not null,
   l_orderkey vops_int4 not null,
   l_partkey vops_int4 not null,
   l_shipdate vops_date not null,
   l_quantity vops_float4 not null,
   l_extendedprice vops_float4 not null,
   l_discount vops_float4 not null,
   l_tax vops_float4 not null,
   l_returnflag vops_char not null,
   l_linestatus vops_char not null
);


create table vorders(
    o_orderkey vops_int4,
    o_custkey vops_int4,
    o_orderstatus vops_char,
    o_totalprice vops_float4,
    o_orderdate vops_date,
    o_shippriority vops_int4
);

create table vcustomer(
    c_custkey vops_int4,
    c_nationkey vops_int4,
    c_acctbal vops_float4
);
 

CREATE TABLE vsupplier(
    s_suppkey vops_int4,
    s_nationkey vops_int4,
    s_acctbal vops_float4
);

copy lineitem from '/mnt/data/lineitem.tbl' delimiter '|' csv;
copy orders from '/mnt/data/orders.tbl' delimiter '|' csv;
copy supplier from '/mnt/data/supplier.tbl' delimiter '|' csv;
copy customer from '/mnt/data/customer.tbl' delimiter '|' csv;
copy region from '/mnt/data/region.tbl' delimiter '|' csv;
copy nation from '/mnt/data/nation.tbl' delimiter '|' csv;

select populate(destination := 'vlineitem'::regclass, source := 'lineitem'::regclass);
select populate(destination := 'vorders'::regclass, source := 'orders'::regclass);
select populate(destination := 'vsupplier'::regclass, source := 'supplier'::regclass);
select populate(destination := 'vcustomer'::regclass, source := 'customer'::regclass);

select
    n_name,
    count(*),
    sum(l_extendedprice * (1-l_discount)) as revenue
from
    (select c.* from vcustomer vc, vops_unnest(vc.*) c(c_custkey int4,c_nationkey int4,c_acctbal real)) c1
	 join 
	(select o.* from vorders vo,vops_unnest(vo.*) o(o_orderkey int4,o_custkey int4,o_orderstatus "char",
	  o_totalprice real,o_orderdate date,o_shippriority int4)
	 where vo.o_orderdate >= '1996-01-01'::date and vo.o_orderdate < '1997-01-01'::date) o1
     on c_custkey = o_custkey
     join
    (select l.* from vlineitem vl, vops_unnest(vl.*) l(l_suppkey int4,l_orderkey int4,l_partkey int4,l_shipdate date,l_quantity float4,
         l_extendedprice float4,l_discount float4,l_tax float4,l_returnflag "char",l_linestatus "char")) l1 on l_orderkey = o_orderkey
     join 
	(select s.* from vsupplier vs,vops_unnest(vs.*) s(s_suppkey int4,s_nationkey int4,s_acctbal real)) s1 on l_suppkey = s_suppkey
    join nation on c_nationkey = n_nationkey
    join region on n_regionkey = r_regionkey
where
    c_nationkey = s_nationkey
    and r_name = 'ASIA'
group by
    n_name
order by
    revenue desc;
-- Time: 44950.530 ms (00:44.951)

select
    n_name,
    count(*),
    sum(l_extendedprice * (1-l_discount)) as revenue
from                                       
    customer join orders on c_custkey = o_custkey
    join lineitem on l_orderkey = o_orderkey
    join supplier on l_suppkey = s_suppkey
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
-- Seq: Time: 30186.833 ms (00:30.187)
-- Par: Time: 15492.048 ms (00:15.492)




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
) server vops_server options (table_name 'vlineitem');

create foreign table orders_fdw  (                                          
    o_orderkey int4 not null,
    o_custkey int4 not null,
    o_orderstatus "char" not null,
    o_totalprice float4 not null,
    o_orderdate date not null,
    o_shippriority int4 not null
) server vops_server options (table_name 'vorders');

create foreign table customer_fdw  (                                          
    c_custkey int4 not null,
    c_nationkey int4 not null,
    c_acctbal float4 not null
) server vops_server options (table_name 'vcustomer');

create foreign table supplier_fdw  (                                          
    s_suppkey int4 not null,
    s_nationkey int4 not null,
    s_acctbal float4 not null
) server vops_server options (table_name 'vsupplier');

analyze lineitem_fdw;
analyze customer_fdw;
analyze supplier_fdw;
analyze orders_fdw;

select
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
-- Time: 41108.297 ms (00:41.108)


create table hlineitem(
   l_suppkey int4 not null,
   l_orderkey int4 not null,
   l_partkey int4 not null,
   l_shipdate date not null,
   l_quantity float4 not null,
   l_extendedprice float4 not null,
   l_discount float4 not null,
   l_tax float4 not null,
   l_returnflag "char" not null,
   l_linestatus "char" not null
);


create table horders(
    o_orderkey int4,
    o_custkey int4,
    o_orderstatus "char",
    o_totalprice float4,
    o_orderdate date,
    o_shippriority int4
);

create table hcustomer(
    c_custkey int4,
    c_nationkey int4,
    c_acctbal float4
);
 

CREATE TABLE hsupplier(
    s_suppkey int4,
    s_nationkey int4,
    s_acctbal float4
);

create function unnest_customer(vcustomer) returns setof hcustomer as 'vops','vops_unnest' language C parallel safe immutable strict;
create function unnest_supplier(vsupplier) returns setof hsupplier as 'vops','vops_unnest' language C parallel safe immutable strict;
create function unnest_lineitem(vlineitem) returns setof hlineitem as 'vops','vops_unnest' language C parallel safe immutable strict;
create function unnest_orders(vorders) returns setof horders as 'vops','vops_unnest' language C parallel safe immutable strict;

select
    n_name,
    count(*),
    sum(l_extendedprice * (1-l_discount)) as revenue
from
    (select (c).* from (select unnest_customer(vc.*) c from vcustomer vc offset 0) s1) s2
	 join 
	(select (o).* from (select unnest_orders(vo.*) o from vorders vo 
	 where o_orderdate >= '1996-01-01'::date and o_orderdate < '1997-01-01'::date offset 0) s3) s4
     on c_custkey = o_custkey
     join
    (select (l).* from (select unnest_lineitem(vl.*) l from vlineitem vl offset 0) s5) s6
	 on l_orderkey = o_orderkey
     join 
    (select (s).* from (select unnest_supplier(vs.*) s from vsupplier vs offset 0) s7) s8 
	 on l_suppkey = s_suppkey
    join nation on c_nationkey = n_nationkey
    join region on n_regionkey = r_regionkey
where
    c_nationkey = s_nationkey
    and r_name = 'ASIA'
group by
    n_name
order by
    revenue desc;
