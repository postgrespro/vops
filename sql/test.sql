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
 
