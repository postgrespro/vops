create extension vops;
create table s(x real);
create table v(x vops_float4);
insert into s values(1.0),(2.0),(null),(3.0),(null),(4.0);
select populate(destination:='v'::regclass, source:='s'::regclass);
select unnest(v.*) from v where x > 1;
select countall(*) from v where x is not null;
select count(*) from v where x is null;
select count(*) from v where x is not null;
select count(*),count(x),sum(x),avg(x),min(x),max(x),variance(x),var_pop(x),var_samp(x),stddev(x),stddev_pop(x),stddev_samp(x) from v where x >= 0.0;
select count(*),count(x),sum(x),avg(x),min(x),max(x),variance(x),var_pop(x),var_samp(x),stddev(x),stddev_pop(x),stddev_samp(x) from s where x >= 0.0;
select count(*),count(x),sum(x),avg(x),min(x),max(x),variance(x),var_pop(x),var_samp(x),stddev(x),stddev_pop(x),stddev_samp(x) from v where x > 1.0;
select count(*),count(x),sum(x),avg(x),min(x),max(x),variance(x),var_pop(x),var_samp(x),stddev(x),stddev_pop(x),stddev_samp(x) from s where x > 1.0;
select count(*) from v where ifnull(x, 0) >= 0;
select count(*) from v where coalesce(x, 0.0::float8::vops_float4) >= 0;
select unnest(t.*) from (select mcount(*) over w,mcount(x) over w,msum(x) over w,mavg(x) over w,mmin(x) over w,mmax(x) over w,x - lag(x) over w from v window w as (rows between unbounded preceding and current row)) t;
 
create table s2(x float8, id serial);
insert into  s2(select generate_series(1,100));
create table v2(x vops_float8, id vops_int4);
select populate(destination:='v2'::regclass, source:='s2'::regclass,sort:='id');

select unnest(t.*) from (select msum(x,10) over (order by first(id)) from v2) t;
select sum(x) over (order by id rows between 9 preceding and current row) from s2;

