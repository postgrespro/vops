/* contrib/vops/vops--1.0--1.1.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "ALTER EXTENSION vops UPDATE TO '1.1'" to load this file. \quit

create or replace aggregate msum(vops_char) (
	sfunc = vops_char_sum_extend,
	stype = vops_int8,
	mstype = vops_int8,
	msfunc = vops_char_sum_extend,
	minvfunc = vops_char_sum_reduce,
	parallel = safe
);
drop function vops_char_sum_stub(vops_int8, vops_char);

create or replace aggregate msum(vops_char, winsize integer) (
	sfunc = vops_char_msum_extend,
	stype = internal,
	finalfunc = vops_char_msum_final,
	mstype = internal,
	msfunc = vops_char_msum_extend,
	minvfunc = vops_char_msum_reduce,
	mfinalfunc = vops_char_msum_final,
	parallel = safe
);
drop function vops_char_msum_stub(internal, vops_char, integer);

create or replace aggregate mavg(vops_char) (
	sfunc = vops_char_avg_extend,
	stype = internal,
	finalfunc = vops_mavg_final,
	mstype = internal,
	msfunc = vops_char_avg_extend,
	minvfunc = vops_char_avg_reduce,
	mfinalfunc = vops_mavg_final,
	parallel = safe
);
drop function vops_char_avg_stub(internal, vops_char);

create or replace aggregate mmax(vops_char) (
	sfunc = vops_char_max_extend,
	stype = vops_char,
	mstype = vops_char,
	msfunc = vops_char_max_extend,
	minvfunc = vops_char_max_reduce,
	parallel = safe
);
drop function vops_char_max_stub(vops_char, vops_char);

create or replace aggregate mmin(vops_char) (
	sfunc = vops_char_min_extend,
	stype = vops_char,
	mstype = vops_char,
	msfunc = vops_char_min_extend,
	minvfunc = vops_char_min_reduce,
	parallel = safe
);
drop function vops_char_min_stub(vops_char, vops_char);

create or replace aggregate lag(vops_char) (
	sfunc = vops_char_lag_extend,
	stype = internal,
	finalfunc = vops_win_char_final,
	mstype = internal,
	msfunc = vops_char_lag_extend,
	minvfunc = vops_char_lag_reduce,
	mfinalfunc = vops_win_char_final,
	parallel = safe
);
drop function vops_char_lag_accumulate(state internal, val vops_char);

create or replace aggregate mcount(vops_char) (
	sfunc = vops_char_count_extend,
	stype = vops_int8,
	initcond = '0',
	mstype = vops_int8,
	msfunc = vops_char_count_extend,
	minvfunc = vops_char_count_reduce,
	minitcond = '0',
	parallel = safe
);
drop function vops_char_count_stub(vops_int8, vops_char);

create or replace aggregate msum(vops_int2) (
	sfunc = vops_int2_sum_extend,
	stype = vops_int8,
	mstype = vops_int8,
	msfunc = vops_int2_sum_extend,
	minvfunc = vops_int2_sum_reduce,
	parallel = safe
);
drop function vops_int2_sum_stub(vops_int8, vops_int2);

create or replace aggregate msum(vops_int2, winsize integer) (
	sfunc = vops_int2_msum_extend,
	stype = internal,
	finalfunc = vops_int2_msum_final,
	mstype = internal,
	msfunc = vops_int2_msum_extend,
	minvfunc = vops_int2_msum_reduce,
	mfinalfunc = vops_int2_msum_final,
	parallel = safe
);
drop function vops_int2_msum_stub(internal, vops_int2, integer);

create or replace aggregate mavg(vops_int2) (
	sfunc = vops_int2_avg_extend,
	finalfunc = vops_mavg_final,
	stype = internal,
	mstype = internal,
	msfunc = vops_int2_avg_extend,
	minvfunc = vops_int2_avg_reduce,
	mfinalfunc = vops_mavg_final,
	parallel = safe
);
drop function vops_int2_avg_stub(internal, vops_int2);

create or replace aggregate mmax(vops_int2) (
	sfunc = vops_int2_max_extend,
	stype = vops_int2,
	mstype = vops_int2,
	msfunc = vops_int2_max_extend,
	minvfunc = vops_int2_max_reduce,
	parallel = safe
);
drop function vops_int2_max_stub(vops_int2, vops_int2);

create or replace aggregate mmin(vops_int2) (
	sfunc = vops_int2_min_extend,
	stype = vops_int2,
	mstype = vops_int2,
	msfunc = vops_int2_min_extend,
	minvfunc = vops_int2_min_reduce,
	parallel = safe
);
drop function vops_int2_min_stub(vops_int2, vops_int2);

create or replace aggregate lag(vops_int2) (
	sfunc = vops_int2_lag_extend,
	stype = internal,
	finalfunc = vops_int2_lag_final,
	mstype = internal,
	msfunc = vops_int2_lag_extend,
	minvfunc = vops_int2_lag_reduce,
	mfinalfunc = vops_int2_lag_final,
	parallel = safe
);
drop function vops_int2_lag_accumulate(state internal, val vops_int2);

create or replace aggregate mcount(vops_int2) (
	sfunc = vops_int2_count_extend,
	stype = vops_int8,
	initcond = '0',
	mstype = vops_int8,
	msfunc = vops_int2_count_extend,
	minvfunc = vops_int2_count_reduce,
	minitcond = '0',
	parallel = safe
);
drop function vops_int2_count_stub(vops_int8, vops_int2);

create or replace aggregate msum(vops_int4) (
	sfunc = vops_int4_sum_extend,
	stype = vops_int8,
	mstype = vops_int8,
	msfunc = vops_int4_sum_extend,
	minvfunc = vops_int4_sum_reduce,
	parallel = safe
);
drop function vops_int4_sum_stub(vops_int8, vops_int4);

create or replace aggregate msum(vops_int4, winsize integer) (
	sfunc = vops_int4_msum_extend,
	stype = internal,
	finalfunc = vops_int4_msum_final,
	mstype = internal,
	msfunc = vops_int4_msum_extend,
	minvfunc = vops_int4_msum_reduce,
	mfinalfunc = vops_int4_msum_final,
	parallel = safe
);
drop function vops_int4_msum_stub(internal, vops_int4, integer);

create or replace aggregate mavg(vops_int4) (
	sfunc = vops_int4_avg_extend,
	stype = internal,
	finalfunc = vops_mavg_final,
	mstype = internal,
	msfunc = vops_int4_avg_extend,
	minvfunc = vops_int4_avg_reduce,
	mfinalfunc = vops_mavg_final,
	parallel = safe
);
drop function vops_int4_avg_stub(internal, vops_int4);

create or replace aggregate mmax(vops_int4) (
	sfunc = vops_int4_max_extend,
	stype = vops_int4,
	mstype = vops_int4,
	msfunc = vops_int4_max_extend,
	minvfunc = vops_int4_max_reduce,
	parallel = safe
);
drop function vops_int4_max_stub(vops_int4, vops_int4);

create or replace aggregate mmin(vops_int4) (
	sfunc = vops_int4_min_extend,
	stype = vops_int4,
	mstype = vops_int4,
	msfunc = vops_int4_min_extend,
	minvfunc = vops_int4_min_reduce,
	parallel = safe
);
drop function vops_int4_min_stub(vops_int4, vops_int4);

create or replace aggregate lag(vops_int4) (
	sfunc = vops_int4_lag_extend,
	stype = internal,
	finalfunc = vops_int4_lag_final,
	mstype = internal,
	msfunc = vops_int4_lag_extend,
	minvfunc = vops_int4_lag_reduce,
	mfinalfunc = vops_int4_lag_final,
	parallel = safe
);
drop function vops_int4_lag_accumulate(state internal, val vops_int4);

create or replace aggregate mcount(vops_int4) (
	sfunc = vops_int4_count_extend,
	stype = vops_int8,
	initcond = '0',
	mstype = vops_int8,
	msfunc = vops_int4_count_extend,
	minvfunc = vops_int4_count_reduce,
	minitcond = '0',
	parallel = safe
);
drop function vops_int4_count_stub(vops_int8, vops_int4);

create or replace aggregate msum(vops_date) (
	sfunc = vops_date_sum_extend,
	stype = vops_int8,
	mstype = vops_int8,
	msfunc = vops_date_sum_extend,
	minvfunc = vops_date_sum_reduce,
	parallel = safe
);
drop function vops_date_sum_stub(vops_int8, vops_date);

create or replace aggregate msum(vops_date, winsize integer) (
	sfunc = vops_date_msum_extend,
	stype = internal,
	finalfunc = vops_date_msum_final,
	mstype = internal,
	msfunc = vops_date_msum_extend,
	minvfunc = vops_date_msum_reduce,
	mfinalfunc = vops_date_msum_final,
	parallel = safe
);
drop function vops_date_msum_stub(internal, vops_date, integer);

create or replace aggregate mavg(vops_date) (
	sfunc = vops_date_avg_extend,
	stype = internal,
	finalfunc = vops_mavg_final,
	mstype = internal,
	msfunc = vops_date_avg_extend,
	minvfunc = vops_date_avg_reduce,
	mfinalfunc = vops_mavg_final,
	parallel = safe
);
drop function vops_date_avg_stub(internal, vops_date);

create or replace aggregate mmax(vops_date) (
	sfunc = vops_date_max_extend,
	stype = vops_date,
	mstype = vops_date,
	msfunc = vops_date_max_extend,
	minvfunc = vops_date_max_reduce,
	parallel = safe
);
drop function vops_date_max_stub(vops_date, vops_date);

create or replace aggregate mmin(vops_date) (
	sfunc = vops_date_min_extend,
	stype = vops_date,
	mstype = vops_date,
	msfunc = vops_date_min_extend,
	minvfunc = vops_date_min_reduce,
	parallel = safe
);
drop function vops_date_min_stub(vops_date, vops_date);

create or replace aggregate lag(vops_date) (
	sfunc = vops_date_lag_extend,
	stype = internal,
	finalfunc = vops_date_lag_final,
	mstype = internal,
	msfunc = vops_date_lag_extend,
	minvfunc = vops_date_lag_reduce,
	mfinalfunc = vops_date_lag_final,
	parallel = safe
);
drop function vops_date_lag_accumulate(state internal, val vops_date);

create or replace aggregate mcount(vops_date) (
	sfunc = vops_date_count_extend,
	stype = vops_int8,
	initcond = '0',
	mstype = vops_int8,
	msfunc = vops_date_count_extend,
	minvfunc = vops_date_count_reduce,
	minitcond = '0',
	parallel = safe
);
drop function vops_date_count_stub(vops_int8, vops_date);

create or replace aggregate msum(vops_timestamp) (
	sfunc = vops_timestamp_sum_extend,
	stype = vops_int8,
	mstype = vops_int8,
	msfunc = vops_timestamp_sum_extend,
	minvfunc = vops_timestamp_sum_reduce,
	parallel = safe
);
drop function vops_timestamp_sum_stub(vops_int8, vops_timestamp);

create or replace aggregate msum(vops_timestamp, winsize integer) (
	sfunc = vops_timestamp_msum_extend,
	stype = internal,
	finalfunc = vops_timestamp_msum_final,
	mstype = internal,
	msfunc = vops_timestamp_msum_extend,
	minvfunc = vops_timestamp_msum_reduce,
	mfinalfunc = vops_timestamp_msum_final,
	parallel = safe
);
drop function vops_timestamp_msum_stub(internal, vops_timestamp, integer);

create or replace aggregate mavg(vops_timestamp) (
	sfunc = vops_timestamp_avg_extend,
	stype = internal,
	finalfunc = vops_mavg_final,
	mstype = internal,
	msfunc = vops_timestamp_avg_extend,
	minvfunc = vops_timestamp_avg_reduce,
	mfinalfunc = vops_mavg_final,
	parallel = safe
);
drop function vops_timestamp_avg_stub(internal, vops_timestamp);

create or replace aggregate mmax(vops_timestamp) (
	sfunc = vops_timestamp_max_extend,
	stype = vops_timestamp,
	mstype = vops_timestamp,
	msfunc = vops_timestamp_max_extend,
	minvfunc = vops_timestamp_max_reduce,
	parallel = safe
);
drop function vops_timestamp_max_stub(vops_timestamp, vops_timestamp);

create or replace aggregate mmin(vops_timestamp) (
	sfunc = vops_timestamp_min_extend,
	stype = vops_timestamp,
	mstype = vops_timestamp,
	msfunc = vops_timestamp_min_extend,
	minvfunc = vops_timestamp_min_reduce,
	parallel = safe
);
drop function vops_timestamp_min_stub(vops_timestamp, vops_timestamp);

create or replace aggregate lag(vops_timestamp) (
	sfunc = vops_timestamp_lag_extend,
	stype = internal,
	finalfunc = vops_timestamp_lag_final,
	mstype = internal,
	msfunc = vops_timestamp_lag_extend,
	minvfunc = vops_timestamp_lag_reduce,
	mfinalfunc = vops_timestamp_lag_final,
	parallel = safe
);
drop function vops_timestamp_lag_accumulate(state internal, val vops_timestamp);

create or replace aggregate mcount(vops_timestamp) (
	sfunc = vops_timestamp_count_extend,
	stype = vops_int8,
	initcond = '0',
	mstype = vops_int8,
	msfunc = vops_timestamp_count_extend,
	minvfunc = vops_timestamp_count_reduce,
	minitcond = '0',
	parallel = safe
);
drop function vops_timestamp_count_stub(vops_int8, vops_timestamp);

create or replace aggregate msum(vops_interval) (
	sfunc = vops_interval_sum_extend,
	stype = vops_int8,
	mstype = vops_int8,
	msfunc = vops_interval_sum_extend,
	minvfunc = vops_interval_sum_reduce,
	parallel = safe
);
drop function vops_interval_sum_stub(vops_int8, vops_interval);

create or replace aggregate msum(vops_interval, winsize integer) (
	sfunc = vops_interval_msum_extend,
	stype = internal,
	finalfunc = vops_interval_msum_final,
	mstype = internal,
	msfunc = vops_interval_msum_extend,
	minvfunc = vops_interval_msum_reduce,
	mfinalfunc = vops_interval_msum_final,
	parallel = safe
);
drop function vops_interval_msum_stub(internal, vops_interval, integer);

create or replace aggregate mavg(vops_interval) (
	sfunc = vops_interval_avg_extend,
	stype = internal,
	finalfunc = vops_mavg_final,
	mstype = internal,
	msfunc = vops_interval_avg_extend,
	minvfunc = vops_interval_avg_reduce,
	mfinalfunc = vops_mavg_final,
	parallel = safe
);
drop function vops_interval_avg_stub(internal, vops_interval);

create or replace aggregate mmax(vops_interval) (
	sfunc = vops_interval_max_extend,
	stype = vops_interval,
	mstype = vops_interval,
	msfunc = vops_interval_max_extend,
	minvfunc = vops_interval_max_reduce,
	parallel = safe
);
drop function vops_interval_max_stub(vops_interval, vops_interval);

create or replace aggregate mmin(vops_interval) (
	sfunc = vops_interval_min_extend,
	stype = vops_interval,
	mstype = vops_interval,
	msfunc = vops_interval_min_extend,
	minvfunc = vops_interval_min_reduce,
	parallel = safe
);
drop function vops_interval_min_stub(vops_interval, vops_interval);

create or replace aggregate lag(vops_interval) (
	sfunc = vops_interval_lag_extend,
	stype = internal,
	finalfunc = vops_interval_lag_final,
	mstype = internal,
	msfunc = vops_interval_lag_extend,
	minvfunc = vops_interval_lag_reduce,
	mfinalfunc = vops_interval_lag_final,
	parallel = safe
);
drop function vops_interval_lag_accumulate(state internal, val vops_interval);

create or replace aggregate mcount(vops_interval) (
	sfunc = vops_interval_count_extend,
	stype = vops_int8,
	initcond = '0',
	mstype = vops_int8,
	msfunc = vops_interval_count_extend,
	minvfunc = vops_interval_count_reduce,
	minitcond = '0',
	parallel = safe
);
drop function vops_interval_count_stub(vops_int8, vops_interval);

create or replace aggregate msum(vops_int8) (
	sfunc = vops_int8_sum_extend,
	stype = vops_int8,
	mstype = vops_int8,
	msfunc = vops_int8_sum_extend,
	minvfunc = vops_int8_sum_reduce,
	parallel = safe
);
drop function vops_int8_sum_stub(vops_int8, vops_int8);

create or replace aggregate msum(vops_int8, winsize integer) (
	sfunc = vops_int8_msum_extend,
	stype = internal,
	finalfunc = vops_int8_msum_final,
	mstype = internal,
	msfunc = vops_int8_msum_extend,
	minvfunc = vops_int8_msum_reduce,
	mfinalfunc = vops_int8_msum_final,
	parallel = safe
);
drop function vops_int8_msum_stub(internal, vops_int8, integer);

create or replace aggregate mavg(vops_int8) (
	sfunc = vops_int8_avg_extend,
	stype = internal,
	finalfunc = vops_mavg_final,
	mstype = internal,
	msfunc = vops_int8_avg_extend,
	minvfunc = vops_int8_avg_reduce,
	mfinalfunc = vops_mavg_final,
	parallel = safe
);
drop function vops_int8_avg_stub(internal, vops_int8);

create or replace aggregate mmax(vops_int8) (
	sfunc = vops_int8_max_extend,
	stype = vops_int8,
	mstype = vops_int8,
	msfunc = vops_int8_max_extend,
	minvfunc = vops_int8_max_reduce,
	parallel = safe
);
drop function vops_int8_max_stub(vops_int8, vops_int8);

create or replace aggregate mmin(vops_int8) (
	sfunc = vops_int8_min_extend,
	stype = vops_int8,
	mstype = vops_int8,
	msfunc = vops_int8_min_extend,
	minvfunc = vops_int8_min_reduce,
	parallel = safe
);
drop function vops_int8_min_stub(vops_int8, vops_int8);

create or replace aggregate lag(vops_int8) (
	sfunc = vops_int8_lag_extend,
	stype = internal,
	finalfunc = vops_int8_lag_final,
	mstype = internal,
	msfunc = vops_int8_lag_extend,
	minvfunc = vops_int8_lag_reduce,
	mfinalfunc = vops_int8_lag_final,
	parallel = safe
);
drop function vops_int8_lag_accumulate(state internal, val vops_int8);

create or replace aggregate mcount(vops_int8) (
	sfunc = vops_int8_count_extend,
	stype = vops_int8,
	initcond = '0',
	mstype = vops_int8,
	msfunc = vops_int8_count_extend,
	minvfunc = vops_int8_count_reduce,
	minitcond = '0',
	parallel = safe
);
drop function vops_int8_count_stub(vops_int8, vops_int8);

create or replace aggregate msum(vops_float4) (
	sfunc = vops_float4_sum_extend,
	stype = vops_float8,
	mstype = vops_float8,
	msfunc = vops_float4_sum_extend,
	minvfunc = vops_float4_sum_reduce,
	parallel = safe
);
drop function vops_float4_sum_stub(vops_float8, vops_float4);

create or replace aggregate msum(vops_float4, winsize integer) (
	sfunc = vops_float4_msum_extend,
	stype = internal,
	finalfunc = vops_float4_msum_final,
	mstype = internal,
	msfunc = vops_float4_msum_extend,
	minvfunc = vops_float4_msum_reduce,
	mfinalfunc = vops_float4_msum_final,
	parallel = safe
);
drop function vops_float4_msum_stub(internal, vops_float4, integer);

create or replace aggregate mavg(vops_float4) (
	sfunc = vops_float4_avg_extend,
	stype = internal,
	finalfunc = vops_mavg_final,
	mstype = internal,
	msfunc = vops_float4_avg_extend,
	minvfunc = vops_float4_avg_reduce,
	mfinalfunc = vops_mavg_final,
	parallel = safe
);
drop function vops_float4_avg_stub(internal, vops_float4);

create or replace aggregate mmax(vops_float4) (
	sfunc = vops_float4_max_extend,
	stype = vops_float4,
	mstype = vops_float4,
	msfunc = vops_float4_max_extend,
	minvfunc = vops_float4_max_reduce,
	parallel = safe
);
drop function vops_float4_max_stub(vops_float4, vops_float4);

create or replace aggregate mmin(vops_float4) (
	sfunc = vops_float4_min_extend,
	stype = vops_float4,
	mstype = vops_float4,
	msfunc = vops_float4_min_extend,
	minvfunc = vops_float4_min_reduce,
	parallel = safe
);
drop function vops_float4_min_stub(vops_float4, vops_float4);

create or replace aggregate lag(vops_float4) (
	sfunc = vops_float4_lag_extend,
	stype = internal,
	finalfunc = vops_float4_lag_final,
	mstype = internal,
	msfunc = vops_float4_lag_extend,
	minvfunc = vops_float4_lag_reduce,
	mfinalfunc = vops_float4_lag_final,
	parallel = safe
);
drop function vops_float4_lag_accumulate(state internal, val vops_float4);

create or replace aggregate mcount(vops_float4) (
	sfunc = vops_float4_count_extend,
	stype = vops_int8,
	initcond = '0',
	mstype = vops_int8,
	msfunc = vops_float4_count_extend,
	minvfunc = vops_float4_count_reduce,
	minitcond = '0',
	parallel = safe
);
drop function vops_float4_count_stub(vops_int8, vops_float4);

create or replace aggregate msum(vops_float8) (
	sfunc = vops_float8_sum_extend,
	stype = vops_float8,
	mstype = vops_float8,
	msfunc = vops_float8_sum_extend,
	minvfunc = vops_float8_sum_reduce,
	parallel = safe
);
drop function vops_float8_sum_stub(vops_float8, vops_float8);

create or replace aggregate msum(vops_float8, winsize integer) (
	sfunc = vops_float8_msum_extend,
	stype = internal,
	finalfunc = vops_float8_msum_final,
	mstype = internal,
	msfunc = vops_float8_msum_extend,
	minvfunc = vops_float8_msum_reduce,
	mfinalfunc = vops_float8_msum_final,
	parallel = safe
);
drop function vops_float8_msum_stub(internal, vops_float8, integer);

create or replace aggregate mavg(vops_float8) (
	sfunc = vops_float8_avg_extend,
	stype = internal,
	finalfunc = vops_mavg_final,
	mstype = internal,
	msfunc = vops_float8_avg_extend,
	minvfunc = vops_float8_avg_reduce,
	mfinalfunc = vops_mavg_final,
	parallel = safe
);
drop function vops_float8_avg_stub(internal, vops_float8);

create or replace aggregate mmax(vops_float8) (
	sfunc = vops_float8_max_extend,
	stype = vops_float8,
	mstype = vops_float8,
	msfunc = vops_float8_max_extend,
	minvfunc = vops_float8_max_reduce,
	parallel = safe
);
drop function vops_float8_max_stub(vops_float8, vops_float8);

create or replace aggregate mmin(vops_float8) (
	sfunc = vops_float8_min_extend,
	stype = vops_float8,
	mstype = vops_float8,
	msfunc = vops_float8_min_extend,
	minvfunc = vops_float8_min_reduce,
	parallel = safe
);
drop function vops_float8_min_stub(vops_float8, vops_float8);

create or replace aggregate lag(vops_float8) (
	sfunc = vops_float8_lag_extend,
	stype = internal,
	finalfunc = vops_float8_lag_final,
	mstype = internal,
	msfunc = vops_float8_lag_extend,
	minvfunc = vops_float8_lag_reduce,
	mfinalfunc = vops_float8_lag_final,
	parallel = safe
);
drop function vops_float8_lag_accumulate(state internal, val vops_float8);

create or replace aggregate mcount(vops_float8) (
	sfunc = vops_float8_count_extend,
	stype = vops_int8,
	initcond = '0',
	mstype = vops_int8,
	msfunc = vops_float8_count_extend,
	minvfunc = vops_float8_count_reduce,
	minitcond = '0',
	parallel = safe
);
drop function vops_float8_count_stub(vops_int8, vops_float8);

create or replace aggregate mcount(*) (
	sfunc = vops_count_extend,
	stype = vops_int8,
	initcond = '0',
	mstype = vops_int8,
	msfunc = vops_count_extend,
	minvfunc = vops_count_reduce,
	minitcond = '0',
	parallel = safe
);
drop function vops_count_stub(vops_int8);

-- create_projection is actually the same function as it was in 1.0, but with code style corrected
create or replace function create_projection(projection_name text, source_table regclass, vector_columns text[], scalar_columns text[] default null, order_by text default null) returns void as $create$
declare
	create_table text;
	create_func  text;
	create_index text;
	vector_attno integer[];
	scalar_attno integer[];
	att_num      integer;
	att_name     text;
	att_typname  text;
	att_typid    integer;
	sep          text := '';
	key_type     text;
	min_value    text;
	i            integer;
	att_typmod   integer;
 begin
	create_table := 'create table '||projection_name||'(';
	create_func := 'create function '||projection_name||'_refresh() returns bigint as $$ select populate(source:='''||source_table::text||''', destination:='''||projection_name||''', sort:=''';
	if scalar_columns is not null
	then
		create_index := 'create index on '||projection_name||' using brin(';
		foreach att_name IN ARRAY scalar_columns
		loop
			select atttypid, attnum, typname into att_typid, att_num, att_typname from pg_attribute, pg_type where attrelid=source_table::oid and attname=att_name and atttypid=pg_type.oid;
		if att_typid is null
			then
				raise exception 'No attribute % in table %', att_name, source_table;
			end if;
			scalar_attno := scalar_attno||att_num;
			if att_typname='char'
			then
				att_typname:='"char"';
			end if;
			create_table := create_table||sep||att_name||' '||att_typname;
			create_func := create_func||sep||att_name;
			create_index := create_index||sep||att_name;
			sep := ',';
		end loop;
	end if;

	if order_by is not null
	then
		create_func := create_func||sep||order_by;
	end if;
	create_func := create_func||''''; -- end of sort list

	foreach att_name in array vector_columns
	loop
		select atttypid, attnum, typname, atttypmod into att_typid, att_num, att_typname, att_typmod from pg_attribute, pg_type where attrelid=source_table::oid and attname=att_name and atttypid=pg_type.oid;
		if att_typid is null
		then
			raise exception 'No attribute % in table %', att_name, source_table;
		end if;
		if att_typname='bpchar' or att_typname='varchar'
		then
			att_typname:='text('||(att_typmod-4)||')';
		end if;
		vector_attno := vector_attno||att_num;
		create_table := create_table||sep||att_name||' vops_'||att_typname;
		sep := ',';
		if att_name=order_by
		then
			key_type := att_typname;
		end if;
	end loop;

	create_table := create_table||')';
	execute create_table;

	if create_index is not null
	then
		create_index := create_index||')';
		execute create_index;
	end if;

	if order_by is not null
	then
		if key_type is null
		then
			raise exception 'Invalid order column % for projection %', order_by, projection_name;
		end if;
		create_index := 'create index on '||projection_name||' using brin(first('||order_by||'))';
		execute create_index;
		create_index := 'create index on '||projection_name||' using brin(last('||order_by||'))';
		execute create_index;
		if key_type='timestamp' or key_type='date'
		then
			min_value := '''''-infinity''''::'||key_type;
		else
			min_value := '-1'; -- assume that key have only non-negative values
		end if;
		create_func := create_func||', predicate:='''||order_by||'>(select coalesce(max(last('||order_by||')),'||min_value||') from '||projection_name||')''';
	end if;
	create_func := create_func||'); $$ language sql';
	execute create_func;

	insert into vops_projections values (projection_name, source_table, vector_attno, scalar_attno, order_by);
end;
$create$ language plpgsql;
