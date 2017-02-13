/* contrib/vops/vops.sql */

-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "create extension vops" to load this file. \quit

create type vops_bool;
create type vops_char;
create type vops_int2;
create type vops_int4;
create type vops_int8;
create type vops_date;
create type vops_float4;
create type vops_float8;
create type vops_timestamp;


create function vops_bool_input(cstring) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_bool_output(vops_bool) returns cstring as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_input(cstring) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_output(vops_char) returns cstring as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_input(cstring) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_output(vops_int2) returns cstring as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_input(cstring) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_output(vops_int4) returns cstring as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_input(cstring) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_output(vops_int8) returns cstring as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_input(cstring) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_output(vops_float4) returns cstring as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_input(cstring) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_output(vops_float8) returns cstring as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_date_input(cstring) returns vops_date as 'MODULE_PATHNAME','vops_int4_input' language C parallel safe immutable strict;
create function vops_date_output(vops_date) returns cstring as 'MODULE_PATHNAME','vops_int4_output' language C parallel safe immutable strict;
create function vops_timestamp_input(cstring) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_input' language C parallel safe immutable strict;
create function vops_timestamp_output(vops_timestamp) returns cstring as 'MODULE_PATHNAME','vops_int8_output' language C parallel safe immutable strict;

create type vops_bool (
	input = vops_bool_input, 
	output = vops_bool_output, 
	alignment = double,
    internallength = 16
);

create type vops_char (
	input = vops_char_input, 
	output = vops_char_output, 
	alignment = double,
    internallength = 72 -- 8+64
);


create type vops_int2 (
	input = vops_int2_input, 
	output = vops_int2_output, 
	alignment = double,
    internallength = 136 -- 8+64*2
);


create type vops_int4 (
	input = vops_int4_input, 
	output = vops_int4_output, 
	alignment = double,
    internallength = 264 -- 8 + 64*4
);

create type vops_date (
	input = vops_date_input, 
	output = vops_date_output, 
	alignment = double,
    internallength = 264 -- 8 + 64*4
);


create type vops_int8 (
	input = vops_int8_input, 
	output = vops_int8_output, 
	alignment = double,
    internallength = 520 -- 8 + 64*8
);


create type vops_float4 (
	input = vops_float4_input, 
	output = vops_float4_output, 
	alignment = double,
    internallength = 264 -- 8 + 64*4
);

create type vops_float8 (
	input = vops_float8_input, 
	output = vops_float8_output, 
	alignment = double,
    internallength = 520 -- 8 + 64*8
);

create type vops_timestamp (
	input = vops_timestamp_input, 
	output = vops_timestamp_output, 
	alignment = double,
    internallength = 520 -- 8 + 64*8
);

-- char tile

create function vops_char_concat(left vops_char, right vops_char) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator || (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_concat);

create function vops_char_group_by(state internal, group_by vops_char, aggregates cstring, variadic anyarray) returns internal as 'MODULE_PATHNAME' language C parallel safe immutable;
create function vops_agg_combine(state1 internal, state2 internal) returns internal as 'MODULE_PATHNAME' language C parallel safe immutable;
create function vops_agg_serial(internal) returns bytea as 'MODULE_PATHNAME' language C parallel safe strict;
create function vops_agg_deserial(bytea,internal) returns internal as 'MODULE_PATHNAME' language C parallel safe strict;
create function vops_agg_final(internal) returns bigint as 'MODULE_PATHNAME' language C parallel safe strict;
create aggregate map(group_by vops_char, aggregates cstring, variadic anyarray) (
	   sfunc = vops_char_group_by, 
	   stype = internal,
	   finalfunc=vops_agg_final,
	   combinefunc = vops_agg_combine,
	   serialfunc = vops_agg_serial,
	   deserialfunc = vops_agg_deserial,	   
	   parallel = safe);

create function vops_char_sub(left vops_char, right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_sub_rconst(left vops_char, right int4) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_sub_lconst(left int4, right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_sub);
create operator - (leftarg=vops_char, rightarg=int4, procedure=vops_char_sub_rconst);
create operator - (leftarg=int4, rightarg=vops_char, procedure=vops_char_sub_lconst);

create function vops_char_add(left vops_char, right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_add_rconst(left vops_char, right int4) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_add_lconst(left int4, right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator + (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_add);
create operator + (leftarg=vops_char, rightarg=int4, procedure=vops_char_add_rconst);
create operator + (leftarg=int4, rightarg=vops_char, procedure=vops_char_add_lconst);

create function vops_char_mul(left vops_char, right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_mul_rconst(left vops_char, right int4) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_mul_lconst(left int4, right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator * (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_mul);
create operator * (leftarg=vops_char, rightarg=int4, procedure=vops_char_mul_rconst);
create operator * (leftarg=int4, rightarg=vops_char, procedure=vops_char_mul_lconst);

create function vops_char_div(left vops_char, right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_div_rconst(left vops_char, right int4) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_div_lconst(left int4, right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator / (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_div);
create operator / (leftarg=vops_char, rightarg=int4, procedure=vops_char_div_rconst);
create operator / (leftarg=int4, rightarg=vops_char, procedure=vops_char_div_lconst);

create function vops_char_eq(left vops_char, right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_eq_rconst(left vops_char, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_eq_lconst(left int4, right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator = (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_eq);
create operator = (leftarg=vops_char, rightarg=int4, procedure=vops_char_eq_rconst);
create operator = (leftarg=int4, rightarg=vops_char, procedure=vops_char_eq_lconst);

create function vops_char_ne(left vops_char, right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_ne_rconst(left vops_char, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_ne_lconst(left int4, right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <> (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_ne);
create operator <> (leftarg=vops_char, rightarg=int4, procedure=vops_char_ne_rconst);
create operator <> (leftarg=int4, rightarg=vops_char, procedure=vops_char_ne_lconst);

create function vops_char_gt(left vops_char, right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_gt_rconst(left vops_char, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_gt_lconst(left int4, right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator > (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_gt);
create operator > (leftarg=vops_char, rightarg=int4, procedure=vops_char_gt_rconst);
create operator > (leftarg=int4, rightarg=vops_char, procedure=vops_char_gt_lconst);

create function vops_char_lt(left vops_char, right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_lt_rconst(left vops_char, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_lt_lconst(left int4, right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator < (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_lt);
create operator < (leftarg=vops_char, rightarg=int4, procedure=vops_char_lt_rconst);
create operator < (leftarg=int4, rightarg=vops_char, procedure=vops_char_lt_lconst);

create function vops_char_ge(left vops_char, right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_ge_rconst(left vops_char, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_ge_lconst(left int4, right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator >= (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_ge);
create operator >= (leftarg=vops_char, rightarg=int4, procedure=vops_char_ge_rconst);
create operator >= (leftarg=int4, rightarg=vops_char, procedure=vops_char_ge_lconst);

create function vops_char_le(left vops_char, right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_le_rconst(left vops_char, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_le_lconst(left int4, right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <= (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_le);
create operator <= (leftarg=vops_char, rightarg=int4, procedure=vops_char_le_rconst);
create operator <= (leftarg=int4, rightarg=vops_char, procedure=vops_char_le_lconst);

create function betwixt(opd vops_char, low int4, high int4) returns vops_bool as 'MODULE_PATHNAME','vops_betwixt_char' language C parallel safe immutable strict;

create function vops_char_neg(right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (rightarg=vops_char, procedure=vops_char_neg);

create function vops_char_sum_accumulate(state int8, val vops_char) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE sum(vops_char) (
	SFUNC = vops_char_sum_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	PARALLEL = SAFE
);

create function vops_avg_final(state internal) returns float8 as 'MODULE_PATHNAME' language C parallel safe strict;
create function vops_avg_combine(internal,internal) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_avg_serial(internal) returns bytea as 'MODULE_PATHNAME' language C parallel safe strict;
create function vops_avg_deserial(bytea,internal) returns internal as 'MODULE_PATHNAME' language C parallel safe strict;

create function vops_char_avg_accumulate(state internal, val vops_char) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE avg(vops_char) (
	SFUNC = vops_char_avg_accumulate,
	STYPE = internal,
	FINALFUNC = vops_avg_final,
	COMBINEFUNC = vops_avg_combine,
	SERIALFUNC = vops_avg_serial,
	DESERIALFUNC = vops_avg_deserial,
	PARALLEL = SAFE
);

create function vops_char_max_accumulate(state char, val vops_char) returns char as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE max(vops_char) (
	SFUNC = vops_char_max_accumulate,
	STYPE = char,
	PARALLEL = SAFE
);

create function vops_char_min_accumulate(state char, val vops_char) returns char as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE min(vops_char) (
	SFUNC = vops_char_min_accumulate,
	STYPE = char,
	PARALLEL = SAFE
);

create function vops_char_count_accumulate(state int8, val vops_char) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE count(vops_char) (
	SFUNC = vops_char_count_accumulate,
	STYPE = int8,
	COMBINEFUNC = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);

create function first(tile vops_char) returns char as 'MODULE_PATHNAME','vops_char_first' language C parallel safe immutable strict;
create function last(tile vops_char) returns char as 'MODULE_PATHNAME','vops_char_last' language C parallel safe immutable strict;
create function low(tile vops_char) returns char as 'MODULE_PATHNAME','vops_char_low' language C parallel safe immutable strict;
create function high(tile vops_char) returns char as 'MODULE_PATHNAME','vops_char_high' language C parallel safe immutable strict;

-- int2 tile

create function vops_int2_concat(left vops_int2, right vops_int2) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator || (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_concat);

create function vops_int2_group_by(state internal, group_by vops_int2, aggregates cstring, variadic anyarray) returns internal as 'MODULE_PATHNAME' language C parallel safe immutable;
create aggregate map(group_by vops_int2, aggregates cstring, variadic anyarray) (
	   sfunc = vops_int2_group_by, 
	   stype = internal,
	   finalfunc=vops_agg_final,
	   combinefunc = vops_agg_combine,
	   serialfunc = vops_agg_serial,
	   deserialfunc = vops_agg_deserial,
	   parallel = safe);

create function vops_int2_sub(left vops_int2, right vops_int2) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_sub_rconst(left vops_int2, right int4) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_sub_lconst(left int4, right vops_int2) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_sub);
create operator - (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_sub_rconst);
create operator - (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_sub_lconst);

create function vops_int2_add(left vops_int2, right vops_int2) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_add_rconst(left vops_int2, right int4) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_add_lconst(left int4, right vops_int2) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator + (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_add);
create operator + (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_add_rconst);
create operator + (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_add_lconst);

create function vops_int2_mul(left vops_int2, right vops_int2) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_mul_rconst(left vops_int2, right int4) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_mul_lconst(left int4, right vops_int2) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator * (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_mul);
create operator * (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_mul_rconst);
create operator * (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_mul_lconst);

create function vops_int2_div(left vops_int2, right vops_int2) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_div_rconst(left vops_int2, right int4) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_div_lconst(left int4, right vops_int2) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator / (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_div);
create operator / (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_div_rconst);
create operator / (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_div_lconst);

create function vops_int2_eq(left vops_int2, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_eq_rconst(left vops_int2, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_eq_lconst(left int4, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator = (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_eq);
create operator = (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_eq_rconst);
create operator = (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_eq_lconst);

create function vops_int2_ne(left vops_int2, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_ne_rconst(left vops_int2, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_ne_lconst(left int4, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <> (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_ne);
create operator <> (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_ne_rconst);
create operator <> (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_ne_lconst);

create function vops_int2_gt(left vops_int2, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_gt_rconst(left vops_int2, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_gt_lconst(left int4, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator > (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_gt);
create operator > (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_gt_rconst);
create operator > (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_gt_lconst);

create function vops_int2_lt(left vops_int2, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_lt_rconst(left vops_int2, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_lt_lconst(left int4, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator < (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_lt);
create operator < (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_lt_rconst);
create operator < (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_lt_lconst);

create function vops_int2_ge(left vops_int2, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_ge_rconst(left vops_int2, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_ge_lconst(left int4, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator >= (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_ge);
create operator >= (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_ge_rconst);
create operator >= (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_ge_lconst);

create function vops_int2_le(left vops_int2, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_le_rconst(left vops_int2, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_le_lconst(left int4, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <= (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_le);
create operator <= (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_le_rconst);
create operator <= (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_le_lconst);

create function betwixt(opd vops_int2, low int4, high int4) returns vops_bool as 'MODULE_PATHNAME','vops_betwixt_int2' language C parallel safe immutable strict;

create function vops_int2_neg(right vops_int2) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (rightarg=vops_int2, procedure=vops_int2_neg);

create function vops_int2_sum_accumulate(state int8, val vops_int2) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE sum(vops_int2) (
	SFUNC = vops_int2_sum_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	PARALLEL = SAFE
);

create function vops_int2_avg_accumulate(state internal, val vops_int2) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE avg(vops_int2) (
	SFUNC = vops_int2_avg_accumulate,
	STYPE = internal,
	FINALFUNC = vops_avg_final,
	COMBINEFUNC = vops_avg_combine,
	SERIALFUNC = vops_avg_serial,
	DESERIALFUNC = vops_avg_deserial,
	PARALLEL = SAFE
);

create function vops_int2_max_accumulate(state int2, val vops_int2) returns int2 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE max(vops_int2) (
	SFUNC = vops_int2_max_accumulate,
	STYPE = int2,
    COMBINEFUNC = int2larger,
	PARALLEL = SAFE
);

create function vops_int2_min_accumulate(state int2, val vops_int2) returns int2 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE min(vops_int2) (
	SFUNC = vops_int2_min_accumulate,
	STYPE = int2,
    COMBINEFUNC = int2smaller,
	PARALLEL = SAFE
);

create function vops_int2_count_accumulate(state int8, val vops_int2) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE count(vops_int2) (
	SFUNC = vops_int2_count_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);

create function first(tile vops_int2) returns int2 as 'MODULE_PATHNAME','vops_int2_first' language C parallel safe immutable strict;
create function last(tile vops_int2) returns int2 as 'MODULE_PATHNAME','vops_int2_last' language C parallel safe immutable strict;
create function low(tile vops_int2) returns int2 as 'MODULE_PATHNAME','vops_int2_low' language C parallel safe immutable strict;
create function high(tile vops_int2) returns int2 as 'MODULE_PATHNAME','vops_int2_high' language C parallel safe immutable strict;

-- int4 tile

create function vops_int4_concat(left vops_int4, right vops_int4) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator || (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_concat);

create function vops_int4_group_by(state internal, group_by vops_int4, aggregates cstring, variadic anyarray) returns internal as 'MODULE_PATHNAME' language C parallel safe immutable;
create aggregate map(group_by vops_int4, aggregates cstring, variadic anyarray) (
	   sfunc = vops_int4_group_by, 
	   stype = internal,
	   finalfunc=vops_agg_final,
	   combinefunc = vops_agg_combine,
	   serialfunc = vops_agg_serial,
	   deserialfunc = vops_agg_deserial,
	   parallel = safe);

create function vops_int4_sub(left vops_int4, right vops_int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_sub_rconst(left vops_int4, right int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_sub_lconst(left int4, right vops_int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_sub);
create operator - (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_sub_rconst);
create operator - (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_sub_lconst);

create function vops_int4_add(left vops_int4, right vops_int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_add_rconst(left vops_int4, right int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_add_lconst(left int4, right vops_int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator + (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_add);
create operator + (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_add_rconst);
create operator + (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_add_lconst);

create function vops_int4_mul(left vops_int4, right vops_int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_mul_rconst(left vops_int4, right int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_mul_lconst(left int4, right vops_int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator * (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_mul);
create operator * (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_mul_rconst);
create operator * (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_mul_lconst);

create function vops_int4_div(left vops_int4, right vops_int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_div_rconst(left vops_int4, right int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_div_lconst(left int4, right vops_int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator / (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_div);
create operator / (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_div_rconst);
create operator / (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_div_lconst);

create function vops_int4_eq(left vops_int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_eq_rconst(left vops_int4, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_eq_lconst(left int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator = (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_eq);
create operator = (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_eq_rconst);
create operator = (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_eq_lconst);

create function vops_int4_ne(left vops_int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_ne_rconst(left vops_int4, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_ne_lconst(left int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <> (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_ne);
create operator <> (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_ne_rconst);
create operator <> (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_ne_lconst);

create function vops_int4_gt(left vops_int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_gt_rconst(left vops_int4, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_gt_lconst(left int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator > (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_gt);
create operator > (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_gt_rconst);
create operator > (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_gt_lconst);

create function vops_int4_lt(left vops_int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_lt_rconst(left vops_int4, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_lt_lconst(left int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator < (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_lt);
create operator < (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_lt_rconst);
create operator < (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_lt_lconst);

create function vops_int4_ge(left vops_int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_ge_rconst(left vops_int4, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_ge_lconst(left int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator >= (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_ge);
create operator >= (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_ge_rconst);
create operator >= (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_ge_lconst);

create function vops_int4_le(left vops_int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_le_rconst(left vops_int4, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_le_lconst(left int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <= (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_le);
create operator <= (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_le_rconst);
create operator <= (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_le_lconst);

create function betwixt(opd vops_int4, low int4, high int4) returns vops_bool as 'MODULE_PATHNAME','vops_betwixt_int4' language C parallel safe immutable strict;

create function vops_int4_neg(right vops_int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (rightarg=vops_int4, procedure=vops_int4_neg);

create function vops_int4_sum_accumulate(state int8, val vops_int4) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE sum(vops_int4) (
	SFUNC = vops_int4_sum_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	PARALLEL = SAFE
);

create function vops_int4_avg_accumulate(state internal, val vops_int4) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE avg(vops_int4) (
	SFUNC = vops_int4_avg_accumulate,
	STYPE = internal,
	FINALFUNC = vops_avg_final,
	COMBINEFUNC = vops_avg_combine,
	SERIALFUNC = vops_avg_serial,
	DESERIALFUNC = vops_avg_deserial,
	PARALLEL = SAFE
);

create function vops_int4_max_accumulate(state int4, val vops_int4) returns int4 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE max(vops_int4) (
	SFUNC = vops_int4_max_accumulate,
	STYPE = int4,
    COMBINEFUNC = int4larger,
	PARALLEL = SAFE
);

create function vops_int4_min_accumulate(state int4, val vops_int4) returns int4 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE min(vops_int4) (
	SFUNC = vops_int4_min_accumulate,
	STYPE = int4,
    COMBINEFUNC = int4smaller,
	PARALLEL = SAFE
);

create function vops_int4_count_accumulate(state int8, val vops_int4) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE count(vops_int4) (
	SFUNC = vops_int4_count_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);

create function first(tile vops_int4) returns int4 as 'MODULE_PATHNAME','vops_int4_first' language C parallel safe immutable strict;
create function last(tile vops_int4) returns int4 as 'MODULE_PATHNAME','vops_int4_last' language C parallel safe immutable strict;
create function low(tile vops_int4) returns int4 as 'MODULE_PATHNAME','vops_int4_low' language C parallel safe immutable strict;
create function high(tile vops_int4) returns int4 as 'MODULE_PATHNAME','vops_int4_high' language C parallel safe immutable strict;

-- date tile

create function vops_date_group_by(state internal, group_by vops_date, aggregates cstring, variadic anyarray) returns internal as 'MODULE_PATHNAME','vops_int4_group_by' language C parallel safe immutable;
create aggregate map(group_by vops_date, aggregates cstring, variadic anyarray) (
	   sfunc = vops_date_group_by, 
	   stype = internal,
	   finalfunc=vops_agg_final,
	   combinefunc = vops_agg_combine,
	   serialfunc = vops_agg_serial,
	   deserialfunc = vops_agg_deserial,
	   parallel = safe);

create function vops_date_sub(left vops_date, right vops_date) returns vops_date as 'MODULE_PATHNAME','vops_int4_sub' language C parallel safe immutable strict;
create function vops_date_sub_rconst(left vops_date, right date) returns vops_date as 'MODULE_PATHNAME','vops_int4_sub_rconst' language C parallel safe immutable strict;
create function vops_date_sub_lconst(left date, right vops_date) returns vops_date as 'MODULE_PATHNAME','vops_int4_sub_lconst' language C parallel safe immutable strict;
create operator - (leftarg=vops_date, rightarg=vops_date, procedure=vops_date_sub);
create operator - (leftarg=vops_date, rightarg=date, procedure=vops_date_sub_rconst);
create operator - (leftarg=date, rightarg=vops_date, procedure=vops_date_sub_lconst);

create function vops_date_add(left vops_date, right vops_date) returns vops_date as 'MODULE_PATHNAME','vops_int4_add' language C parallel safe immutable strict;
create function vops_date_add_rconst(left vops_date, right date) returns vops_date as 'MODULE_PATHNAME','vops_int4_add_rconst' language C parallel safe immutable strict;
create function vops_date_add_lconst(left date, right vops_date) returns vops_date as 'MODULE_PATHNAME','vops_int4_add_lconst' language C parallel safe immutable strict;
create operator + (leftarg=vops_date, rightarg=vops_date, procedure=vops_date_add);
create operator + (leftarg=vops_date, rightarg=date, procedure=vops_date_add_rconst);
create operator + (leftarg=date, rightarg=vops_date, procedure=vops_date_add_lconst);

create function vops_date_mul(left vops_date, right vops_date) returns vops_date as 'MODULE_PATHNAME','vops_int4_mul' language C parallel safe immutable strict;
create function vops_date_mul_rconst(left vops_date, right date) returns vops_date as 'MODULE_PATHNAME','vops_int4_mul_rconst' language C parallel safe immutable strict;
create function vops_date_mul_lconst(left date, right vops_date) returns vops_date as 'MODULE_PATHNAME','vops_int4_mul_lconst' language C parallel safe immutable strict;
create operator * (leftarg=vops_date, rightarg=vops_date, procedure=vops_date_mul);
create operator * (leftarg=vops_date, rightarg=date, procedure=vops_date_mul_rconst);
create operator * (leftarg=date, rightarg=vops_date, procedure=vops_date_mul_lconst);

create function vops_date_div(left vops_date, right vops_date) returns vops_date as 'MODULE_PATHNAME','vops_int4_div' language C parallel safe immutable strict;
create function vops_date_div_rconst(left vops_date, right date) returns vops_date as 'MODULE_PATHNAME','vops_int4_div_rconst' language C parallel safe immutable strict;
create function vops_date_div_lconst(left date, right vops_date) returns vops_date as 'MODULE_PATHNAME','vops_int4_div_lconst' language C parallel safe immutable strict;
create operator / (leftarg=vops_date, rightarg=vops_date, procedure=vops_date_div);
create operator / (leftarg=vops_date, rightarg=date, procedure=vops_date_div_rconst);
create operator / (leftarg=date, rightarg=vops_date, procedure=vops_date_div_lconst);

create function vops_date_eq(left vops_date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_eq' language C parallel safe immutable strict;
create function vops_date_eq_rconst(left vops_date, right date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_eq_rconst' language C parallel safe immutable strict;
create function vops_date_eq_lconst(left date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_eq_lconst' language C parallel safe immutable strict;
create operator = (leftarg=vops_date, rightarg=vops_date, procedure=vops_date_eq);
create operator = (leftarg=vops_date, rightarg=date, procedure=vops_date_eq_rconst);
create operator = (leftarg=date, rightarg=vops_date, procedure=vops_date_eq_lconst);

create function vops_date_ne(left vops_date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_ne' language C parallel safe immutable strict;
create function vops_date_ne_rconst(left vops_date, right date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_ne_rconst' language C parallel safe immutable strict;
create function vops_date_ne_lconst(left date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_ne_lconst' language C parallel safe immutable strict;
create operator <> (leftarg=vops_date, rightarg=vops_date, procedure=vops_date_ne);
create operator <> (leftarg=vops_date, rightarg=date, procedure=vops_date_ne_rconst);
create operator <> (leftarg=date, rightarg=vops_date, procedure=vops_date_ne_lconst);

create function vops_date_gt(left vops_date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_gt' language C parallel safe immutable strict;
create function vops_date_gt_rconst(left vops_date, right date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_gt_rconst' language C parallel safe immutable strict;
create function vops_date_gt_lconst(left date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_gt_lconst' language C parallel safe immutable strict;
create operator > (leftarg=vops_date, rightarg=vops_date, procedure=vops_date_gt);
create operator > (leftarg=vops_date, rightarg=date, procedure=vops_date_gt_rconst);
create operator > (leftarg=date, rightarg=vops_date, procedure=vops_date_gt_lconst);

create function vops_date_lt(left vops_date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_lt' language C parallel safe immutable strict;
create function vops_date_lt_rconst(left vops_date, right date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_lt_rconst' language C parallel safe immutable strict;
create function vops_date_lt_lconst(left date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_lt_lconst' language C parallel safe immutable strict;
create operator < (leftarg=vops_date, rightarg=vops_date, procedure=vops_date_lt);
create operator < (leftarg=vops_date, rightarg=date, procedure=vops_date_lt_rconst);
create operator < (leftarg=date, rightarg=vops_date, procedure=vops_date_lt_lconst);

create function vops_date_ge(left vops_date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_ge' language C parallel safe immutable strict;
create function vops_date_ge_rconst(left vops_date, right date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_ge_rconst' language C parallel safe immutable strict;
create function vops_date_ge_lconst(left date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_ge_lconst' language C parallel safe immutable strict;
create operator >= (leftarg=vops_date, rightarg=vops_date, procedure=vops_date_ge);
create operator >= (leftarg=vops_date, rightarg=date, procedure=vops_date_ge_rconst);
create operator >= (leftarg=date, rightarg=vops_date, procedure=vops_date_ge_lconst);

create function vops_date_le(left vops_date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_le' language C parallel safe immutable strict;
create function vops_date_le_rconst(left vops_date, right date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_le_rconst' language C parallel safe immutable strict;
create function vops_date_le_lconst(left date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_le_lconst' language C parallel safe immutable strict;
create operator <= (leftarg=vops_date, rightarg=vops_date, procedure=vops_date_le);
create operator <= (leftarg=vops_date, rightarg=date, procedure=vops_date_le_rconst);
create operator <= (leftarg=date, rightarg=vops_date, procedure=vops_date_le_lconst);

create function betwixt(opd vops_date, low date, high date) returns vops_bool as 'MODULE_PATHNAME','vops_betwixt_int4' language C parallel safe immutable strict;

create function vops_date_neg(right vops_date) returns vops_date as 'MODULE_PATHNAME','vops_int4_neg' language C parallel safe immutable strict;
create operator - (rightarg=vops_date, procedure=vops_date_neg);

create function vops_date_sum_accumulate(state int8, val vops_date) returns int8 as 'MODULE_PATHNAME','vops_int4_sum_accumulate' language C parallel safe;
CREATE AGGREGATE sum(vops_date) (
	SFUNC = vops_date_sum_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	PARALLEL = SAFE
);

create function vops_date_avg_accumulate(state internal, val vops_date) returns internal as 'MODULE_PATHNAME','vops_int4_avg_accumulate' language C parallel safe;
CREATE AGGREGATE avg(vops_date) (
	SFUNC = vops_date_avg_accumulate,
	STYPE = internal,
	FINALFUNC = vops_avg_final,
	COMBINEFUNC = vops_avg_combine,
	SERIALFUNC = vops_avg_serial,
	DESERIALFUNC = vops_avg_deserial,
	PARALLEL = SAFE
);

create function vops_date_max_accumulate(state date, val vops_date) returns date as 'MODULE_PATHNAME','vops_int4_max_accumulate' language C parallel safe;
CREATE AGGREGATE max(vops_date) (
	SFUNC = vops_date_max_accumulate,
	STYPE = date,
    COMBINEFUNC = date_larger,
	PARALLEL = SAFE
);

create function vops_date_min_accumulate(state date, val vops_date) returns date as 'MODULE_PATHNAME','vops_int4_min_accumulate' language C parallel safe;
CREATE AGGREGATE min(vops_date) (
	SFUNC = vops_date_min_accumulate,
	STYPE = date,
    COMBINEFUNC = date_smaller,
	PARALLEL = SAFE
);

create function vops_date_count_accumulate(state int8, val vops_date) returns int8 as 'MODULE_PATHNAME','vops_int4_count_accumulate' language C parallel safe;
CREATE AGGREGATE count(vops_date) (
	SFUNC = vops_date_count_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);

create function first(tile vops_date) returns date as 'MODULE_PATHNAME','vops_int4_first' language C parallel safe immutable strict;
create function last(tile vops_date) returns date as 'MODULE_PATHNAME','vops_int4_last' language C parallel safe immutable strict;
create function low(tile vops_date) returns date as 'MODULE_PATHNAME','vops_int4_low' language C parallel safe immutable strict;
create function high(tile vops_date) returns date as 'MODULE_PATHNAME','vops_int4_high' language C parallel safe immutable strict;

-- timestamp tile

create function vops_timestamp_group_by(state internal, group_by vops_timestamp, aggregates cstring, variadic anyarray) returns internal as 'MODULE_PATHNAME','vops_int8_group_by' language C immutable;
create aggregate map(group_by vops_timestamp, aggregates cstring, variadic anyarray) (
	   sfunc = vops_timestamp_group_by, 
	   stype = internal,
	   finalfunc=vops_agg_final,
	   combinefunc = vops_agg_combine,
	   serialfunc = vops_agg_serial,
	   deserialfunc = vops_agg_deserial,
	   parallel = safe);

create function vops_timestamp_sub(left vops_timestamp, right vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_sub' language C parallel safe immutable strict;
create function vops_timestamp_sub_rconst(left vops_timestamp, right timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_sub_rconst' language C parallel safe immutable strict;
create function vops_timestamp_sub_lconst(left timestamp, right vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_sub_lconst' language C parallel safe immutable strict;
create operator - (leftarg=vops_timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_sub);
create operator - (leftarg=vops_timestamp, rightarg=timestamp, procedure=vops_timestamp_sub_rconst);
create operator - (leftarg=timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_sub_lconst);

create function vops_timestamp_add(left vops_timestamp, right vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_add' language C parallel safe immutable strict;
create function vops_timestamp_add_rconst(left vops_timestamp, right timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_add_rconst' language C parallel safe immutable strict;
create function vops_timestamp_add_lconst(left timestamp, right vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_add_lconst' language C parallel safe immutable strict;
create operator + (leftarg=vops_timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_add);
create operator + (leftarg=vops_timestamp, rightarg=timestamp, procedure=vops_timestamp_add_rconst);
create operator + (leftarg=timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_add_lconst);

create function vops_timestamp_mul(left vops_timestamp, right vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_mul' language C parallel safe immutable strict;
create function vops_timestamp_mul_rconst(left vops_timestamp, right timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_mul_rconst' language C parallel safe immutable strict;
create function vops_timestamp_mul_lconst(left timestamp, right vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_mul_lconst' language C parallel safe immutable strict;
create operator * (leftarg=vops_timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_mul);
create operator * (leftarg=vops_timestamp, rightarg=timestamp, procedure=vops_timestamp_mul_rconst);
create operator * (leftarg=timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_mul_lconst);

create function vops_timestamp_div(left vops_timestamp, right vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_div' language C parallel safe immutable strict;
create function vops_timestamp_div_rconst(left vops_timestamp, right timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_div_rconst' language C parallel safe immutable strict;
create function vops_timestamp_div_lconst(left timestamp, right vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_div_lconst' language C parallel safe immutable strict;
create operator / (leftarg=vops_timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_div);
create operator / (leftarg=vops_timestamp, rightarg=timestamp, procedure=vops_timestamp_div_rconst);
create operator / (leftarg=timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_div_lconst);

create function vops_timestamp_eq(left vops_timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_eq' language C parallel safe immutable strict;
create function vops_timestamp_eq_rconst(left vops_timestamp, right timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_eq_rconst' language C parallel safe immutable strict;
create function vops_timestamp_eq_lconst(left timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_eq_lconst' language C parallel safe immutable strict;
create operator = (leftarg=vops_timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_eq);
create operator = (leftarg=vops_timestamp, rightarg=timestamp, procedure=vops_timestamp_eq_rconst);
create operator = (leftarg=timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_eq_lconst);

create function vops_timestamp_ne(left vops_timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_ne' language C parallel safe immutable strict;
create function vops_timestamp_ne_rconst(left vops_timestamp, right timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_ne_rconst' language C parallel safe immutable strict;
create function vops_timestamp_ne_lconst(left timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_ne_lconst' language C parallel safe immutable strict;
create operator <> (leftarg=vops_timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_ne);
create operator <> (leftarg=vops_timestamp, rightarg=timestamp, procedure=vops_timestamp_ne_rconst);
create operator <> (leftarg=timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_ne_lconst);

create function vops_timestamp_gt(left vops_timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_gt' language C parallel safe immutable strict;
create function vops_timestamp_gt_rconst(left vops_timestamp, right timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_gt_rconst' language C parallel safe immutable strict;
create function vops_timestamp_gt_lconst(left timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_gt_lconst' language C parallel safe immutable strict;
create operator > (leftarg=vops_timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_gt);
create operator > (leftarg=vops_timestamp, rightarg=timestamp, procedure=vops_timestamp_gt_rconst);
create operator > (leftarg=timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_gt_lconst);

create function vops_timestamp_lt(left vops_timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_lt' language C parallel safe immutable strict;
create function vops_timestamp_lt_rconst(left vops_timestamp, right timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_lt_rconst' language C parallel safe immutable strict;
create function vops_timestamp_lt_lconst(left timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_lt_lconst' language C parallel safe immutable strict;
create operator < (leftarg=vops_timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_lt);
create operator < (leftarg=vops_timestamp, rightarg=timestamp, procedure=vops_timestamp_lt_rconst);
create operator < (leftarg=timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_lt_lconst);

create function vops_timestamp_ge(left vops_timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_ge' language C parallel safe immutable strict;
create function vops_timestamp_ge_rconst(left vops_timestamp, right timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_ge_rconst' language C parallel safe immutable strict;
create function vops_timestamp_ge_lconst(left timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_ge_lconst' language C parallel safe immutable strict;
create operator >= (leftarg=vops_timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_ge);
create operator >= (leftarg=vops_timestamp, rightarg=timestamp, procedure=vops_timestamp_ge_rconst);
create operator >= (leftarg=timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_ge_lconst);

create function vops_timestamp_le(left vops_timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_le' language C parallel safe immutable strict;
create function vops_timestamp_le_rconst(left vops_timestamp, right timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_le_rconst' language C parallel safe immutable strict;
create function vops_timestamp_le_lconst(left timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_le_lconst' language C parallel safe immutable strict;
create operator <= (leftarg=vops_timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_le);
create operator <= (leftarg=vops_timestamp, rightarg=timestamp, procedure=vops_timestamp_le_rconst);
create operator <= (leftarg=timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_le_lconst);

create function betwixt(opd vops_timestamp, low timestamp, high timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_betwixt_int8' language C parallel safe immutable strict;

create function vops_timestamp_neg(right vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_neg' language C parallel safe immutable strict;
create operator - (rightarg=vops_timestamp, procedure=vops_timestamp_neg);

create function vops_timestamp_sum_accumulate(state int8, val vops_timestamp) returns int8 as 'MODULE_PATHNAME','vops_int8_sum_accumulate' language C parallel safe;
CREATE AGGREGATE sum(vops_timestamp) (
	SFUNC = vops_timestamp_sum_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	PARALLEL = SAFE
);

create function vops_timestamp_avg_accumulate(state internal, val vops_timestamp) returns internal as 'MODULE_PATHNAME','vops_int8_avg_accumulate' language C parallel safe;
CREATE AGGREGATE avg(vops_timestamp) (
	SFUNC = vops_timestamp_avg_accumulate,
	STYPE = internal,
	FINALFUNC = vops_avg_final,
	COMBINEFUNC = vops_avg_combine,
	SERIALFUNC = vops_avg_serial,
	DESERIALFUNC = vops_avg_deserial,
	PARALLEL = SAFE
);

create function vops_timestamp_max_accumulate(state timestamp, val vops_timestamp) returns timestamp as 'MODULE_PATHNAME','vops_int8_max_accumulate' language C parallel safe;
CREATE AGGREGATE max(vops_timestamp) (
	SFUNC = vops_timestamp_max_accumulate,
	STYPE = timestamp,
    COMBINEFUNC = timestamp_larger,
	PARALLEL = SAFE
);

create function vops_timestamp_min_accumulate(state timestamp, val vops_timestamp) returns timestamp as 'MODULE_PATHNAME','vops_int8_min_accumulate' language C parallel safe;
CREATE AGGREGATE min(vops_timestamp) (
	SFUNC = vops_timestamp_min_accumulate,
	STYPE = timestamp,
    COMBINEFUNC = timestamp_smaller,
	PARALLEL = SAFE
);

create function vops_timestamp_count_accumulate(state int8, val vops_timestamp) returns int8 as 'MODULE_PATHNAME','vops_int8_count_accumulate' language C parallel safe;
CREATE AGGREGATE count(vops_timestamp) (
	SFUNC = vops_timestamp_count_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);

create function first(tile vops_timestamp) returns timestamp as 'MODULE_PATHNAME','vops_int8_first' language C parallel safe immutable strict;
create function last(tile vops_timestamp) returns timestamp as 'MODULE_PATHNAME','vops_int8_last' language C parallel safe immutable strict;
create function low(tile vops_timestamp) returns timestamp as 'MODULE_PATHNAME','vops_int8_low' language C parallel safe immutable strict;
create function high(tile vops_timestamp) returns timestamp as 'MODULE_PATHNAME','vops_int8_high' language C parallel safe immutable strict;

-- int8 tile

create function vops_int8_group_by(state internal, group_by vops_int8, aggregates cstring, variadic anyarray) returns internal as 'MODULE_PATHNAME' language C parallel safe immutable;
create aggregate map(group_by vops_int8, aggregates cstring, variadic anyarray) (
	   sfunc = vops_int8_group_by, 
	   stype = internal,
	   finalfunc=vops_agg_final,
	   combinefunc = vops_agg_combine,
	   serialfunc = vops_agg_serial,
	   deserialfunc = vops_agg_deserial,
	   parallel = safe);

create function vops_int8_sub(left vops_int8, right vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_sub_rconst(left vops_int8, right int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_sub_lconst(left int8, right vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_sub);
create operator - (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_sub_rconst);
create operator - (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_sub_lconst);

create function vops_int8_add(left vops_int8, right vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_add_rconst(left vops_int8, right int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_add_lconst(left int8, right vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator + (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_add);
create operator + (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_add_rconst);
create operator + (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_add_lconst);

create function vops_int8_mul(left vops_int8, right vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_mul_rconst(left vops_int8, right int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_mul_lconst(left int8, right vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator * (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_mul);
create operator * (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_mul_rconst);
create operator * (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_mul_lconst);

create function vops_int8_div(left vops_int8, right vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_div_rconst(left vops_int8, right int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_div_lconst(left int8, right vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator / (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_div);
create operator / (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_div_rconst);
create operator / (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_div_lconst);

create function vops_int8_eq(left vops_int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_eq_rconst(left vops_int8, right int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_eq_lconst(left int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator = (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_eq);
create operator = (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_eq_rconst);
create operator = (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_eq_lconst);

create function vops_int8_ne(left vops_int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_ne_rconst(left vops_int8, right int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_ne_lconst(left int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <> (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_ne);
create operator <> (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_ne_rconst);
create operator <> (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_ne_lconst);

create function vops_int8_gt(left vops_int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_gt_rconst(left vops_int8, right int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_gt_lconst(left int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator > (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_gt);
create operator > (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_gt_rconst);
create operator > (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_gt_lconst);

create function vops_int8_lt(left vops_int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_lt_rconst(left vops_int8, right int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_lt_lconst(left int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator < (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_lt);
create operator < (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_lt_rconst);
create operator < (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_lt_lconst);

create function vops_int8_ge(left vops_int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_ge_rconst(left vops_int8, right int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_ge_lconst(left int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator >= (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_ge);
create operator >= (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_ge_rconst);
create operator >= (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_ge_lconst);

create function vops_int8_le(left vops_int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_le_rconst(left vops_int8, right int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_le_lconst(left int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <= (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_le);
create operator <= (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_le_rconst);
create operator <= (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_le_lconst);

create function betwixt(opd vops_int8, low int8, high int8) returns vops_bool as 'MODULE_PATHNAME','vops_betwixt_int8' language C parallel safe immutable strict;

create function vops_int8_neg(right vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (rightarg=vops_int8, procedure=vops_int8_neg);


create function vops_int8_sum_accumulate(state int8, val vops_int8) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE sum(vops_int8) (
	SFUNC = vops_int8_sum_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	PARALLEL = SAFE
);

create function vops_int8_avg_accumulate(state internal, val vops_int8) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE avg(vops_int8) (
	SFUNC = vops_int8_avg_accumulate,
	STYPE = internal,
	FINALFUNC = vops_avg_final,
	COMBINEFUNC = vops_avg_combine,
	SERIALFUNC = vops_avg_serial,
	DESERIALFUNC = vops_avg_deserial,
	PARALLEL = SAFE
);

create function vops_int8_max_accumulate(state int8, val vops_int8) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE max(vops_int8) (
	SFUNC = vops_int8_max_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8larger,
	PARALLEL = SAFE
);

create function vops_int8_min_accumulate(state int8, val vops_int8) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE min(vops_int8) (
	SFUNC = vops_int8_min_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8smaller,
	PARALLEL = SAFE
);

create function vops_int8_count_accumulate(state int8, val vops_int8) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE count(vops_int8) (
	SFUNC = vops_int8_count_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);

create function first(tile vops_int8) returns int8 as 'MODULE_PATHNAME','vops_int8_first' language C parallel safe immutable strict;
create function last(tile vops_int8) returns int8 as 'MODULE_PATHNAME','vops_int8_last' language C parallel safe immutable strict;
create function low(tile vops_int8) returns int8 as 'MODULE_PATHNAME','vops_int8_low' language C parallel safe immutable strict;
create function high(tile vops_int8) returns int8 as 'MODULE_PATHNAME','vops_int8_high' language C parallel safe immutable strict;

-- float4 tile

create function vops_float4_sub(left vops_float4, right vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_sub_rconst(left vops_float4, right float8) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_sub_lconst(left float8, right vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_sub);
create operator - (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_sub_rconst);
create operator - (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_sub_lconst);

create function vops_float4_add(left vops_float4, right vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_add_rconst(left vops_float4, right float8) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_add_lconst(left float8, right vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator + (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_add);
create operator + (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_add_rconst);
create operator + (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_add_lconst);

create function vops_float4_mul(left vops_float4, right vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_mul_rconst(left vops_float4, right float8) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_mul_lconst(left float8, right vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator * (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_mul);
create operator * (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_mul_rconst);
create operator * (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_mul_lconst);

create function vops_float4_div(left vops_float4, right vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_div_rconst(left vops_float4, right float8) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_div_lconst(left float8, right vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator / (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_div);
create operator / (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_div_rconst);
create operator / (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_div_lconst);

create function vops_float4_eq(left vops_float4, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_eq_rconst(left vops_float4, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_eq_lconst(left float8, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator = (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_eq);
create operator = (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_eq_rconst);
create operator = (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_eq_lconst);

create function vops_float4_ne(left vops_float4, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_ne_rconst(left vops_float4, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_ne_lconst(left float8, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <> (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_ne);
create operator <> (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_ne_rconst);
create operator <> (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_ne_lconst);

create function vops_float4_gt(left vops_float4, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_gt_rconst(left vops_float4, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_gt_lconst(left float8, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator > (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_gt);
create operator > (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_gt_rconst);
create operator > (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_gt_lconst);

create function vops_float4_lt(left vops_float4, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_lt_rconst(left vops_float4, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_lt_lconst(left float8, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator < (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_lt);
create operator < (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_lt_rconst);
create operator < (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_lt_lconst);

create function vops_float4_ge(left vops_float4, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_ge_rconst(left vops_float4, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_ge_lconst(left float8, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator >= (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_ge);
create operator >= (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_ge_rconst);
create operator >= (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_ge_lconst);

create function vops_float4_le(left vops_float4, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_le_rconst(left vops_float4, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_le_lconst(left float8, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <= (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_le);
create operator <= (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_le_rconst);
create operator <= (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_le_lconst);

create function betwixt(opd vops_float4, low float8, high float8) returns vops_bool as 'MODULE_PATHNAME','vops_betwixt_float4' language C parallel safe immutable strict;

create function vops_float4_neg(right vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (rightarg=vops_float4, procedure=vops_float4_neg);

create function vops_float4_sum_accumulate(state float8, val vops_float4) returns float8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE sum(vops_float4) (
	SFUNC = vops_float4_sum_accumulate,
	STYPE = float8,
    COMBINEFUNC = float8pl,
	PARALLEL = SAFE
);

create function vops_float4_avg_accumulate(state internal, val vops_float4) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE avg(vops_float4) (
	SFUNC = vops_float4_avg_accumulate,
	STYPE = internal,
	FINALFUNC = vops_avg_final,
	COMBINEFUNC = vops_avg_combine,
	SERIALFUNC = vops_avg_serial,
	DESERIALFUNC = vops_avg_deserial,
	PARALLEL = SAFE
);

create function vops_float4_max_accumulate(state float4, val vops_float4) returns float4 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE max(vops_float4) (
	SFUNC = vops_float4_max_accumulate,
	STYPE = float4,
    COMBINEFUNC = float4larger,	
	PARALLEL = SAFE
);

create function vops_float4_min_accumulate(state float4, val vops_float4) returns float4 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE min(vops_float4) (
	SFUNC = vops_float4_min_accumulate,
	STYPE = float4,
    COMBINEFUNC = float4smaller,
	PARALLEL = SAFE
);

create function vops_float4_count_accumulate(state int8, val vops_float4) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE count(vops_float4) (
	SFUNC = vops_float4_count_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);

create function first(tile vops_float4) returns float4 as 'MODULE_PATHNAME','vops_float4_first' language C parallel safe immutable strict;
create function last(tile vops_float4) returns float4 as 'MODULE_PATHNAME','vops_float4_last' language C parallel safe immutable strict;
create function low(tile vops_float4) returns float4 as 'MODULE_PATHNAME','vops_float4_low' language C parallel safe immutable strict;
create function high(tile vops_float4) returns float4 as 'MODULE_PATHNAME','vops_float4_high' language C parallel safe immutable strict;

-- float8 tile

create function vops_float8_sub(left vops_float8, right vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_sub_rconst(left vops_float8, right float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_sub_lconst(left float8, right vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_sub);
create operator - (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_sub_rconst);
create operator - (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_sub_lconst);

create function vops_float8_add(left vops_float8, right vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_add_rconst(left vops_float8, right float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_add_lconst(left float8, right vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator + (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_add);
create operator + (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_add_rconst);
create operator + (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_add_lconst);

create function vops_float8_mul(left vops_float8, right vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_mul_rconst(left vops_float8, right float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_mul_lconst(left float8, right vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator * (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_mul);
create operator * (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_mul_rconst);
create operator * (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_mul_lconst);

create function vops_float8_div(left vops_float8, right vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_div_rconst(left vops_float8, right float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_div_lconst(left float8, right vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator / (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_div);
create operator / (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_div_rconst);
create operator / (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_div_lconst);

create function vops_float8_eq(left vops_float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_eq_rconst(left vops_float8, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_eq_lconst(left float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator = (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_eq);
create operator = (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_eq_rconst);
create operator = (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_eq_lconst);

create function vops_float8_ne(left vops_float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_ne_rconst(left vops_float8, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_ne_lconst(left float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <> (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_ne);
create operator <> (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_ne_rconst);
create operator <> (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_ne_lconst);

create function vops_float8_gt(left vops_float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_gt_rconst(left vops_float8, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_gt_lconst(left float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator > (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_gt);
create operator > (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_gt_rconst);
create operator > (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_gt_lconst);

create function vops_float8_lt(left vops_float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_lt_rconst(left vops_float8, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_lt_lconst(left float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator < (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_lt);
create operator < (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_lt_rconst);
create operator < (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_lt_lconst);

create function vops_float8_ge(left vops_float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_ge_rconst(left vops_float8, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_ge_lconst(left float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator >= (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_ge);
create operator >= (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_ge_rconst);
create operator >= (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_ge_lconst);

create function vops_float8_le(left vops_float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_le_rconst(left vops_float8, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_le_lconst(left float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <= (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_le);
create operator <= (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_le_rconst);
create operator <= (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_le_lconst);

create function betwixt(opd vops_float8, low float8, high float8) returns vops_bool as 'MODULE_PATHNAME','vops_betwixt_float8' language C parallel safe immutable strict;

create function vops_float8_neg(right vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (rightarg=vops_float8, procedure=vops_float8_neg);

create function vops_float8_sum_accumulate(state float8, val vops_float8) returns float8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE sum(vops_float8) (
	SFUNC = vops_float8_sum_accumulate,
	STYPE = float8,
    COMBINEFUNC = float8pl,
	PARALLEL = SAFE
);

create function vops_float8_avg_accumulate(state internal, val vops_float8) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE avg(vops_float8) (
	SFUNC = vops_float8_avg_accumulate,
	STYPE = internal,
	FINALFUNC = vops_avg_final,
	COMBINEFUNC = vops_avg_combine,
	SERIALFUNC = vops_avg_serial,
	DESERIALFUNC = vops_avg_deserial,
	PARALLEL = SAFE
);

create function vops_float8_max_accumulate(state float8, val vops_float8) returns float8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE max(vops_float8) (
	SFUNC = vops_float8_max_accumulate,
	STYPE = float8,
	COMBINEFUNC  = float8larger,
	PARALLEL = SAFE
);

create function vops_float8_min_accumulate(state float8, val vops_float8) returns float8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE min(vops_float8) (
	SFUNC = vops_float8_min_accumulate,
	STYPE = float8,
	COMBINEFUNC  = float8smaller,
	PARALLEL = SAFE
);

create function vops_float8_count_accumulate(state int8, val vops_float8) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE count(vops_float8) (
	SFUNC = vops_float8_count_accumulate,
	STYPE = int8,
	COMBINEFUNC  = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);

create function first(tile vops_float8) returns float8 as 'MODULE_PATHNAME','vops_float8_first' language C parallel safe immutable strict;
create function last(tile vops_float8) returns float8 as 'MODULE_PATHNAME','vops_float8_last' language C parallel safe immutable strict;
create function low(tile vops_float8) returns float8 as 'MODULE_PATHNAME','vops_float8_low' language C parallel safe immutable strict;
create function high(tile vops_float8) returns float8 as 'MODULE_PATHNAME','vops_float8_high' language C parallel safe immutable strict;

-- bool tile

create function vops_bool_not(vops_bool) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator ! (rightarg=vops_bool, procedure=vops_bool_not);

create function vops_bool_or(left vops_bool, right vops_bool) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator | (leftarg=vops_bool, rightarg=vops_bool, procedure=vops_bool_or, commutator= |);

create function vops_bool_and(left vops_bool, right vops_bool) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator & (leftarg=vops_bool, rightarg=vops_bool, procedure=vops_bool_and, commutator= &);


create function vops_count_accumulate(state int8) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE countall(*) (
	SFUNC = vops_count_accumulate,
	STYPE = int8,
	COMBINEFUNC = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);


-- Generic functions

create function filter(condition vops_bool) returns bool as 'MODULE_PATHNAME','vops_filter' language C parallel safe;

create function populate(destination regclass, source regclass, predicate cstring default null, sort cstring default null) returns void as 'MODULE_PATHNAME','vops_populate' language C;

create type vops_aggregates as(group_by int8, count int8, aggs float8[]);
create function reduce(bigint) returns setof vops_aggregates as 'MODULE_PATHNAME','vops_reduce' language C parallel safe strict immutable;

create function unnest(anyelement) returns setof record as 'MODULE_PATHNAME','vops_unnest' language C parallel safe strict immutable;
