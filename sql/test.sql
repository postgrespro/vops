create extension vops;
set extra_float_digits=0;
create table s(x real);
create table v(x vops_float4);
insert into s values(1.0),(2.0),(null),(3.0),(null),(4.0);
select populate(destination:='v'::regclass, source:='s'::regclass);
select vops_unnest(v.*) from v where x > 1;
select countall(*) from v where x is not null;
select count(*) from v where x is null;
select count(*) from v where x is not null;
select count(*),count(x),sum(x),avg(x),min(x),max(x),variance(x),var_pop(x),var_samp(x),stddev(x),stddev_pop(x),stddev_samp(x) from v where x >= 0.0;
select count(*),count(x),sum(x),avg(x),min(x),max(x),variance(x),var_pop(x),var_samp(x),stddev(x),stddev_pop(x),stddev_samp(x) from s where x >= 0.0;
select count(*),count(x),sum(x),avg(x),min(x),max(x),variance(x),var_pop(x),var_samp(x),stddev(x),stddev_pop(x),stddev_samp(x) from v where x > 1.0;
select count(*),count(x),sum(x),avg(x),min(x),max(x),variance(x),var_pop(x),var_samp(x),stddev(x),stddev_pop(x),stddev_samp(x) from s where x > 1.0;
select count(*) from v where ifnull(x, 0) >= 0;
select count(*) from v where coalesce(x, 0.0::float8::vops_float4) >= 0;
select vops_unnest(t.*) from (select mcount(*) over w,mcount(x) over w,msum(x) over w,mavg(x) over w,mmin(x) over w,mmax(x) over w,x - lag(x) over w from v window w as (rows between unbounded preceding and current row)) t;
 
create table s2(x float8, id serial);
insert into  s2(select generate_series(1,100));
create table v2(x vops_float8, id vops_int4);
select populate(destination:='v2'::regclass, source:='s2'::regclass,sort:='id');

select vops_unnest(t.*) from (select msum(x,10) over (order by first(id)) from v2) t;
select sum(x) over (order by id rows between 9 preceding and current row) from s2;

set vops.auto_substitute_projections=on;
create table it(i interval, t varchar(4));
insert into it values ('1 second','sec'), ('1 minute','min'), ('1 hour','hour');
select create_projection('vit','it',array['i','t']);
select vit_refresh();

select * from vit;
select count(*) from vit where t='min'::text;
select count(*) from vit where i>='1 minute'::interval;

create table stock(symbol char(5), day date, low real, high real, open real, close real);
insert into stock values
('AAA', '01-11-2018', 10.0, 11.0, 10.1, 10.8),
('AAA', '02-11-2018', 11.0, 12.0, 11.2, 11.5),
('AAA', '03-11-2018', 10.4, 10.6, 10.5, 10.4),
('AAA', '04-11-2018', 11.1, 11.5, 11.2, 11.4),
('AAA', '05-11-2018', 11.0, 11.3, 11.4, 11.1);
select create_projection('vstock','stock',array['day','low','high','open','close'],array['symbol'],'day');

select vstock_refresh();
select avg((open+close)/2),max(high-low) from stock group by symbol;
set vops.auto_substitute_projections=on;
explain (costs off) select avg((open+close)/2),max(high-low) from stock group by symbol;
select avg((open+close)/2),max(high-low) from stock group by symbol;

insert into stock values
('AAA', '06-11-2018', 10.1, 10.8, 10.3, 10.2),
('AAA', '07-11-2018', 11.1, 11.8, 10.2, 11.4),
('AAA', '08-11-2018', 11.2, 11.6, 11.4, 11.3),
('AAA', '09-11-2018', 10.6, 11.1, 11.3, 10.8),
('AAA', '10-11-2018', 10.7, 11.3, 10.8, 11.1);
select vstock_refresh();

select avg((open+close)/2),max(high-low) from stock group by symbol;
set vops.auto_substitute_projections=off;
select avg((open+close)/2),max(high-low) from stock group by symbol;

create table wiki_data(
   cat_id bigint,
   page_id bigint,
   requests int,
   size bigint,
   dyear int,
   dmonth int,
   dday int,
   dhour int
);

create table wiki_cat
(   cat_id bigint primary key,
    category varchar(20))
;

insert into wiki_data values
(101,1001,123,456),
(101,1002,789,123),
(101,1003,456,789),
(102,2001,123,456),
(102,2002,789,123),
(103,3001,456,789);

insert into wiki_cat values
(101, 'cat 101'),
(102, 'cat 102'),
(103, 'cat 103');

select create_projection('wiki_data_prj', 'wiki_data', array['page_id','requests','size'],array['cat_id']);

select wiki_data_prj_refresh();

SELECT
	category,
	sum( requests ),
	sum( size )
FROM
	wiki_data
	INNER JOIN wiki_cat
	 ON wiki_data.cat_id = wiki_cat.cat_id
GROUP BY
	category
ORDER BY 3 DESC limit 5;

set vops.auto_substitute_projections=on;

SELECT
	category,
	sum( requests ),
	sum( size )
FROM
	wiki_data
	INNER JOIN wiki_cat
	 ON wiki_data.cat_id = wiki_cat.cat_id
GROUP BY
	category
ORDER BY 3 DESC limit 5;

explain (costs off) SELECT
	category,
	sum( requests ),
	sum( size )
FROM
	wiki_data
	INNER JOIN wiki_cat
	 ON wiki_data.cat_id = wiki_cat.cat_id
GROUP BY
	category
ORDER BY 3 DESC limit 5;

create table quote(symbol char(5), ts timestamp, ask_price real, ask_size integer, bid_price real, bid_size integer);
insert into quote values
('AAA', '03-12-2018 10:00', 10.0, 100, 10.1, 202),
('AAA', '03-12-2018 10:01', 11.0, 120, 11.2, 200),
('AAA', '03-12-2018 10:02', 10.4, 110, 10.5, 204),
('AAA', '03-12-2018 10:03', 11.1, 125, 11.2, 201),
('AAA', '03-12-2018 10:04', 11.0, 105, 11.4, 205);

select create_projection('vquote','quote',array['ts','ask_price','ask_size','bid_price','bid_size'],array['symbol'],'ts');
select vquote_refresh();

select first(bid_price,ts),last(ask_size,ts) from vquote group by symbol;
select symbol,time_bucket('2 minutes',ts) from vquote;
