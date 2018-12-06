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
create type vops_interval;
create type vops_text;
create type deltatime;

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
create function vops_interval_input(cstring) returns vops_interval as 'MODULE_PATHNAME','vops_int8_input' language C parallel safe immutable strict;
create function vops_interval_output(vops_interval) returns cstring as 'MODULE_PATHNAME','vops_int8_output' language C parallel safe immutable strict;
create function vops_text_input(cstring,oid,integer) returns vops_text as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_text_output(vops_text) returns cstring as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_text_typmod_in(cstring[]) returns integer as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_deltatime_input(cstring) returns deltatime as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_deltatime_output(deltatime) returns cstring as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_time_interval(interval) returns deltatime as 'MODULE_PATHNAME' language C parallel safe immutable strict;

create type vops_bool (
	input = vops_bool_input, 
	output = vops_bool_output, 
	alignment = double,
    internallength = 24
);

create type vops_char (
	input = vops_char_input, 
	output = vops_char_output, 
	alignment = double,
    internallength = 80 -- 16+64
);


create type vops_int2 (
	input = vops_int2_input, 
	output = vops_int2_output, 
	alignment = double,
    internallength = 144 -- 16+64*2
);


create type vops_int4 (
	input = vops_int4_input, 
	output = vops_int4_output, 
	alignment = double,
    internallength = 272 -- 16 + 64*4
);

create type vops_date (
	input = vops_date_input, 
	output = vops_date_output, 
	alignment = double,
    internallength = 272 -- 16 + 64*4
);


create type vops_int8 (
	input = vops_int8_input, 
	output = vops_int8_output, 
	alignment = double,
    internallength = 528 -- 16 + 64*8
);


create type vops_float4 (
	input = vops_float4_input, 
	output = vops_float4_output, 
	alignment = double,
    internallength = 272 -- 16 + 64*4
);

create type vops_float8 (
	input = vops_float8_input, 
	output = vops_float8_output, 
	alignment = double,
    internallength = 528 -- 16 + 64*8
);

create type vops_timestamp (
	input = vops_timestamp_input, 
	output = vops_timestamp_output, 
	alignment = double,
    internallength = 528 -- 16 + 64*8
);

create type vops_interval (
	input = vops_interval_input, 
	output = vops_interval_output, 
	alignment = double,
    internallength = 528 -- 16 + 64*8
);

create type vops_text (
	input = vops_text_input,
	output = vops_text_output,
	typmod_in = vops_text_typmod_in,
	alignment = double
);

create type deltatime (input=vops_deltatime_input, output=vops_deltatime_output, like=int8);
create cast (interval as deltatime) with function vops_time_interval(interval) AS IMPLICIT;

-- text tile

create function vops_text_const(opd text, width integer) returns vops_text as 'MODULE_PATHNAME' language C parallel safe immutable strict;

create function vops_text_concat(left vops_text, right vops_text) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator || (leftarg=vops_text, rightarg=vops_text, procedure=vops_text_concat);

create function vops_text_eq(left vops_text, right vops_text) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_text_eq_rconst(left vops_text, right text) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_text_eq_lconst(left text, right vops_text) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator = (leftarg=vops_text, rightarg=vops_text, procedure=vops_text_eq, commutator= =);
create operator = (leftarg=vops_text, rightarg=text, procedure=vops_text_eq_rconst, commutator= =);
create operator = (leftarg=text, rightarg=vops_text, procedure=vops_text_eq_lconst, commutator= =);

create function vops_text_ne(left vops_text, right vops_text) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_text_ne_rconst(left vops_text, right text) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_text_ne_lconst(left text, right vops_text) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <> (leftarg=vops_text, rightarg=vops_text, procedure=vops_text_ne, commutator= <>);
create operator <> (leftarg=vops_text, rightarg=text, procedure=vops_text_ne_rconst, commutator= <>);
create operator <> (leftarg=text, rightarg=vops_text, procedure=vops_text_ne_lconst, commutator= <>);

create function vops_text_gt(left vops_text, right vops_text) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_text_gt_rconst(left vops_text, right text) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_text_gt_lconst(left text, right vops_text) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator > (leftarg=vops_text, rightarg=vops_text, procedure=vops_text_gt, commutator= <);
create operator > (leftarg=vops_text, rightarg=text, procedure=vops_text_gt_rconst, commutator= <);
create operator > (leftarg=text, rightarg=vops_text, procedure=vops_text_gt_lconst, commutator= <);

create function vops_text_lt(left vops_text, right vops_text) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_text_lt_rconst(left vops_text, right text) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_text_lt_lconst(left text, right vops_text) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator < (leftarg=vops_text, rightarg=vops_text, procedure=vops_text_lt, commutator= >);
create operator < (leftarg=vops_text, rightarg=text, procedure=vops_text_lt_rconst, commutator= >);
create operator < (leftarg=text, rightarg=vops_text, procedure=vops_text_lt_lconst, commutator= >);

create function vops_text_ge(left vops_text, right vops_text) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_text_ge_rconst(left vops_text, right text) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_text_ge_lconst(left text, right vops_text) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator >= (leftarg=vops_text, rightarg=vops_text, procedure=vops_text_ge, commutator= <=);
create operator >= (leftarg=vops_text, rightarg=text, procedure=vops_text_ge_rconst, commutator= <=);
create operator >= (leftarg=text, rightarg=vops_text, procedure=vops_text_ge_lconst, commutator= <=);

create function vops_text_le(left vops_text, right vops_text) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_text_le_rconst(left vops_text, right text) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_text_le_lconst(left text, right vops_text) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <= (leftarg=vops_text, rightarg=vops_text, procedure=vops_text_le, commutator= >=);
create operator <= (leftarg=vops_text, rightarg=text, procedure=vops_text_le_rconst, commutator= >=);
create operator <= (leftarg=text, rightarg=vops_text, procedure=vops_text_le_lconst, commutator= >=);

create function betwixt(opd vops_text, low text, high text) returns vops_bool as 'MODULE_PATHNAME','vops_betwixt_text' language C parallel safe immutable strict;

create function ifnull(opd vops_text, subst text) returns vops_text as 'MODULE_PATHNAME','vops_ifnull_text' language C parallel safe immutable strict;
create function ifnull(opd vops_text, subst vops_text) returns vops_text as 'MODULE_PATHNAME','vops_coalesce_text' language C parallel safe immutable strict;

create function vops_text_first_accumulate(state internal, val vops_text, ts vops_timestamp) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_text_first_final(state internal) returns text as 'MODULE_PATHNAME','vops_first_final' language C parallel safe strict;
create function vops_first_combine(internal,internal) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE first(vops_text,vops_timestamp) (
	SFUNC = vops_text_first_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_text_first_final,
 	COMBINEFUNC = vops_first_combine,
	PARALLEL = SAFE
);

create function vops_text_last_accumulate(state internal, val vops_text, ts vops_timestamp) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_last_combine(internal,internal) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE last(vops_text,vops_timestamp) (
	SFUNC = vops_text_last_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_text_first_final,
 	COMBINEFUNC = vops_last_combine,
	PARALLEL = SAFE
);

create function first(tile vops_text) returns text as 'MODULE_PATHNAME','vops_text_first' language C parallel safe immutable strict;
create function last(tile vops_text) returns text as 'MODULE_PATHNAME','vops_text_last' language C parallel safe immutable strict;
create function low(tile vops_text) returns text as 'MODULE_PATHNAME','vops_text_low' language C parallel safe immutable strict;
create function high(tile vops_text) returns text as 'MODULE_PATHNAME','vops_text_high' language C parallel safe immutable strict;

-- char tile

create function vops_char_const(opd "char") returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create cast ("char" as vops_char) with function vops_char_const("char") AS IMPLICIT;

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
create function vops_char_sub_rconst(left vops_char, right "char") returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_sub_lconst(left "char", right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_sub);
create operator - (leftarg=vops_char, rightarg="char", procedure=vops_char_sub_rconst);
create operator - (leftarg="char", rightarg=vops_char, procedure=vops_char_sub_lconst);

create function vops_char_add(left vops_char, right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_add_rconst(left vops_char, right "char") returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_add_lconst(left "char", right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator + (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_add, commutator= +);
create operator + (leftarg=vops_char, rightarg="char", procedure=vops_char_add_rconst, commutator= +);
create operator + (leftarg="char", rightarg=vops_char, procedure=vops_char_add_lconst, commutator= +);

create function vops_char_mul(left vops_char, right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_mul_rconst(left vops_char, right "char") returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_mul_lconst(left "char", right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator * (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_mul, commutator= *);
create operator * (leftarg=vops_char, rightarg="char", procedure=vops_char_mul_rconst, commutator= *);
create operator * (leftarg="char", rightarg=vops_char, procedure=vops_char_mul_lconst, commutator= *);

create function vops_char_div(left vops_char, right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_div_rconst(left vops_char, right "char") returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_div_lconst(left "char", right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator / (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_div);
create operator / (leftarg=vops_char, rightarg="char", procedure=vops_char_div_rconst);
create operator / (leftarg="char", rightarg=vops_char, procedure=vops_char_div_lconst);

create function vops_char_rem(left vops_char, right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_rem_rconst(left vops_char, right "char") returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_rem_lconst(left "char", right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator % (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_rem);
create operator % (leftarg=vops_char, rightarg="char", procedure=vops_char_rem_rconst);
create operator % (leftarg="char", rightarg=vops_char, procedure=vops_char_rem_lconst);

create function vops_char_eq(left vops_char, right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_eq_rconst(left vops_char, right "char") returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_eq_lconst(left "char", right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator = (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_eq, commutator= =);
create operator = (leftarg=vops_char, rightarg="char", procedure=vops_char_eq_rconst, commutator= =);
create operator = (leftarg="char", rightarg=vops_char, procedure=vops_char_eq_lconst, commutator= =);

create function vops_char_ne(left vops_char, right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_ne_rconst(left vops_char, right "char") returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_ne_lconst(left "char", right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <> (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_ne, commutator= <>);
create operator <> (leftarg=vops_char, rightarg="char", procedure=vops_char_ne_rconst, commutator= <>);
create operator <> (leftarg="char", rightarg=vops_char, procedure=vops_char_ne_lconst, commutator= <>);

create function vops_char_gt(left vops_char, right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_gt_rconst(left vops_char, right "char") returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_gt_lconst(left "char", right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator > (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_gt, commutator= <);
create operator > (leftarg=vops_char, rightarg="char", procedure=vops_char_gt_rconst, commutator= <);
create operator > (leftarg="char", rightarg=vops_char, procedure=vops_char_gt_lconst, commutator= <);

create function vops_char_lt(left vops_char, right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_lt_rconst(left vops_char, right "char") returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_lt_lconst(left "char", right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator < (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_lt, commutator= >);
create operator < (leftarg=vops_char, rightarg="char", procedure=vops_char_lt_rconst, commutator= >);
create operator < (leftarg="char", rightarg=vops_char, procedure=vops_char_lt_lconst, commutator= >);

create function vops_char_ge(left vops_char, right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_ge_rconst(left vops_char, right "char") returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_ge_lconst(left "char", right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator >= (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_ge, commutator= <=);
create operator >= (leftarg=vops_char, rightarg="char", procedure=vops_char_ge_rconst, commutator= <=);
create operator >= (leftarg="char", rightarg=vops_char, procedure=vops_char_ge_lconst, commutator= <=);

create function vops_char_le(left vops_char, right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_le_rconst(left vops_char, right "char") returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_char_le_lconst(left "char", right vops_char) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <= (leftarg=vops_char, rightarg=vops_char, procedure=vops_char_le, commutator= >=);
create operator <= (leftarg=vops_char, rightarg="char", procedure=vops_char_le_rconst, commutator= >=);
create operator <= (leftarg="char", rightarg=vops_char, procedure=vops_char_le_lconst, commutator= >=);

create function betwixt(opd vops_char, low "char", high "char") returns vops_bool as 'MODULE_PATHNAME','vops_betwixt_char' language C parallel safe immutable strict;

create function ifnull(opd vops_char, subst "char") returns vops_char as 'MODULE_PATHNAME','vops_ifnull_char' language C parallel safe immutable strict;
create function ifnull(opd vops_char, subst vops_char) returns vops_char as 'MODULE_PATHNAME','vops_coalesce_char' language C parallel safe immutable strict;

create function vops_char_neg(right vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (rightarg=vops_char, procedure=vops_char_neg);

create function vops_char_sum_accumulate(state int8, val vops_char) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE sum(vops_char) (
	SFUNC = vops_char_sum_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	PARALLEL = SAFE
);
create function vops_char_sum_stub(state vops_int8, val vops_char) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_char_sum_extend(state vops_int8, val vops_char) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe;
create function vops_char_sum_reduce(state vops_int8, val vops_char) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE msum(vops_char) (
	SFUNC = vops_char_sum_stub,
	STYPE = vops_int8,
    mstype = vops_int8,
	msfunc = vops_char_sum_extend,
	minvfunc = vops_char_sum_reduce,
	PARALLEL = SAFE
);

create function vops_char_msum_stub(state internal, val vops_char, winsize integer) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_char_msum_extend(state internal, val vops_char, winsize integer) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_char_msum_reduce(state internal, val vops_char, winsize integer) returns internal as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
create function vops_char_msum_final(state internal) returns vops_int8 as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE msum(vops_char,winsize integer) (
	SFUNC = vops_char_msum_stub,
	STYPE = internal,
	finalfunc = vops_char_msum_final,
    mstype = internal,
	msfunc = vops_char_msum_extend,
	minvfunc = vops_char_msum_reduce,
	mfinalfunc = vops_char_msum_final,
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
	SSPACE = 16,
	FINALFUNC = vops_avg_final,
	COMBINEFUNC = vops_avg_combine,
	SERIALFUNC = vops_avg_serial,
	DESERIALFUNC = vops_avg_deserial,
	PARALLEL = SAFE
);
create function vops_char_avg_stub(state internal, val vops_char) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_char_avg_extend(state internal, val vops_char) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_char_avg_reduce(state internal, val vops_char) returns internal as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
create function vops_mavg_final(state internal) returns vops_float8 as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE mavg(vops_char) (
	SFUNC = vops_char_avg_stub,
	STYPE = internal,
	FINALFUNC = vops_mavg_final,
    mstype = internal,
    msfunc = vops_char_avg_extend,
    minvfunc = vops_char_avg_reduce,
	mfinalfunc = vops_mavg_final
);

create function vops_var_combine(internal,internal) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_var_serial(internal) returns bytea as 'MODULE_PATHNAME' language C parallel safe strict;
create function vops_var_deserial(bytea,internal) returns internal as 'MODULE_PATHNAME' language C parallel safe strict;
create function vops_var_pop_final(state internal) returns float8 as 'MODULE_PATHNAME' language C parallel safe strict;
create function vops_var_samp_final(state internal) returns float8 as 'MODULE_PATHNAME' language C parallel safe strict;
create function vops_stddev_pop_final(state internal) returns float8 as 'MODULE_PATHNAME' language C parallel safe strict;
create function vops_stddev_samp_final(state internal) returns float8 as 'MODULE_PATHNAME' language C parallel safe strict;
create function vops_wavg_final(state internal) returns float8 as 'MODULE_PATHNAME' language C parallel safe;

create function vops_char_var_accumulate(state internal, val vops_char) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE var_pop(vops_char) (
	SFUNC = vops_char_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_pop_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE var_samp(vops_char) (
	SFUNC = vops_char_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE variance(vops_char) (
	SFUNC = vops_char_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev_pop(vops_char) (
	SFUNC = vops_char_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_pop_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev_samp(vops_char) (
	SFUNC = vops_char_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev(vops_char) (
	SFUNC = vops_char_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

create function vops_char_wavg_accumulate(state internal, x vops_char, y vops_char) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE wavg(vops_char, vops_char) (
	SFUNC = vops_char_wavg_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_wavg_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

create function vops_char_max_accumulate(state char, val vops_char) returns char as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE max(vops_char) (
	SFUNC = vops_char_max_accumulate,
	STYPE = char,
	PARALLEL = SAFE
);
create function vops_char_max_stub(state vops_char, val vops_char) returns vops_char as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_char_max_extend(state vops_char, val vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe;
create function vops_char_max_reduce(state vops_char, val vops_char) returns vops_char as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mmax(vops_char) (
	SFUNC = vops_char_max_stub,
	STYPE = vops_char,
    mstype = vops_char,
    msfunc = vops_char_max_extend,
    minvfunc = vops_char_max_reduce, 
	PARALLEL = SAFE
);

create function vops_char_min_accumulate(state char, val vops_char) returns char as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE min(vops_char) (
	SFUNC = vops_char_min_accumulate,
	STYPE = char,
	PARALLEL = SAFE
);
create function vops_char_min_stub(state vops_char, val vops_char) returns vops_char as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_char_min_extend(state vops_char, val vops_char) returns vops_char as 'MODULE_PATHNAME' language C parallel safe;
create function vops_char_min_reduce(state vops_char, val vops_char) returns vops_char as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mmin(vops_char) (
	SFUNC = vops_char_min_stub,
	STYPE = vops_char,
	mstype = vops_char,
    msfunc = vops_char_min_extend,
    minvfunc = vops_char_min_reduce, 
	PARALLEL = SAFE
);

create function vops_char_lag_accumulate(state internal, val vops_char) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_char_lag_extend(state internal, val vops_char) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_char_lag_reduce(state internal, val vops_char) returns internal as 'MODULE_PATHNAME','vops_lag_reduce' language C parallel safe;
create function vops_win_char_final(state internal) returns vops_char as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE lag(vops_char) (
	SFUNC = vops_char_lag_accumulate,
	STYPE = internal,
	finalfunc = vops_win_char_final,
	mstype = internal,
    msfunc = vops_char_lag_extend,
    minvfunc = vops_char_lag_reduce,
	mfinalfunc = vops_win_char_final,
	PARALLEL = SAFE
);

create function vops_char_count_accumulate(state int8, val vops_char) returns int8 as 'MODULE_PATHNAME','vops_count_any_accumulate' language C parallel safe strict;
CREATE AGGREGATE count(vops_char) (
	SFUNC = vops_char_count_accumulate,
	STYPE = int8,
	COMBINEFUNC = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);
create function vops_char_count_stub(state vops_int8, val vops_char) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe strict;
create function vops_char_count_extend(state vops_int8, val vops_char) returns vops_int8 as 'MODULE_PATHNAME','vops_count_any_extend' language C parallel safe strict;
create function vops_char_count_reduce(state vops_int8, val vops_char) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe strict;
CREATE AGGREGATE mcount(vops_char) (
	SFUNC = vops_char_count_stub,
	STYPE = vops_int8,
	initcond = '0', 
    mstype = vops_int8,
	msfunc = vops_char_count_extend,
	minvfunc = vops_char_count_reduce,
	minitcond = '0', 
	PARALLEL = SAFE
);

create function vops_char_first_accumulate(state internal, val vops_char, ts vops_timestamp) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_char_first_final(state internal) returns "char" as 'MODULE_PATHNAME','vops_first_final' language C parallel safe;
CREATE AGGREGATE first(vops_char,vops_timestamp) (
	SFUNC = vops_char_first_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_char_first_final,
 	COMBINEFUNC = vops_first_combine,
	PARALLEL = SAFE
);

create function vops_char_last_accumulate(state internal, val vops_char, ts vops_timestamp) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE last(vops_char,vops_timestamp) (
	SFUNC = vops_char_last_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_char_first_final,
 	COMBINEFUNC = vops_last_combine,
	PARALLEL = SAFE
);

create function first(tile vops_char) returns "char" as 'MODULE_PATHNAME','vops_char_first' language C parallel safe immutable strict;
create function last(tile vops_char) returns "char" as 'MODULE_PATHNAME','vops_char_last' language C parallel safe immutable strict;
create function low(tile vops_char) returns "char" as 'MODULE_PATHNAME','vops_char_low' language C parallel safe immutable strict;
create function high(tile vops_char) returns "char" as 'MODULE_PATHNAME','vops_char_high' language C parallel safe immutable strict;

-- int2 tile

create function vops_int2_const(opd int4) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create cast (int4 as vops_int2) with function vops_int2_const(int4) AS IMPLICIT;

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
create operator + (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_add, commutator= +);
create operator + (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_add_rconst, commutator= +);
create operator + (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_add_lconst, commutator= +);

create function vops_int2_mul(left vops_int2, right vops_int2) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_mul_rconst(left vops_int2, right int4) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_mul_lconst(left int4, right vops_int2) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator * (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_mul, commutator= *);
create operator * (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_mul_rconst, commutator= *);
create operator * (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_mul_lconst, commutator= *);

create function vops_int2_div(left vops_int2, right vops_int2) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_div_rconst(left vops_int2, right int4) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_div_lconst(left int4, right vops_int2) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator / (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_div);
create operator / (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_div_rconst);
create operator / (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_div_lconst);

create function vops_int2_rem(left vops_int2, right vops_int2) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_rem_rconst(left vops_int2, right int4) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_rem_lconst(left int4, right vops_int2) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator % (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_rem);
create operator % (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_rem_rconst);
create operator % (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_rem_lconst);

create function vops_int2_eq(left vops_int2, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_eq_rconst(left vops_int2, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_eq_lconst(left int4, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator = (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_eq, commutator= =);
create operator = (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_eq_rconst, commutator= =);
create operator = (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_eq_lconst, commutator= =);

create function vops_int2_ne(left vops_int2, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_ne_rconst(left vops_int2, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_ne_lconst(left int4, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <> (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_ne, commutator= <>);
create operator <> (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_ne_rconst, commutator= <>);
create operator <> (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_ne_lconst, commutator= <>);

create function vops_int2_gt(left vops_int2, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_gt_rconst(left vops_int2, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_gt_lconst(left int4, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator > (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_gt, commutator= <);
create operator > (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_gt_rconst, commutator= <);
create operator > (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_gt_lconst, commutator= <);

create function vops_int2_lt(left vops_int2, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_lt_rconst(left vops_int2, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_lt_lconst(left int4, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator < (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_lt, commutator= >);
create operator < (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_lt_rconst, commutator= >);
create operator < (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_lt_lconst, commutator= >);

create function vops_int2_ge(left vops_int2, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_ge_rconst(left vops_int2, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_ge_lconst(left int4, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator >= (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_ge, commutator= <=);
create operator >= (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_ge_rconst, commutator= <=);
create operator >= (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_ge_lconst, commutator= <=);

create function vops_int2_le(left vops_int2, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_le_rconst(left vops_int2, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int2_le_lconst(left int4, right vops_int2) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <= (leftarg=vops_int2, rightarg=vops_int2, procedure=vops_int2_le, commutator= >=);
create operator <= (leftarg=vops_int2, rightarg=int4, procedure=vops_int2_le_rconst, commutator= >=);
create operator <= (leftarg=int4, rightarg=vops_int2, procedure=vops_int2_le_lconst, commutator= >=);

create function betwixt(opd vops_int2, low int4, high int4) returns vops_bool as 'MODULE_PATHNAME','vops_betwixt_int2' language C parallel safe immutable strict;

create function ifnull(opd vops_int2, subst int4) returns vops_int2 as 'MODULE_PATHNAME','vops_ifnull_int2' language C parallel safe immutable strict;
create function ifnull(opd vops_int2, subst vops_int2) returns vops_int2 as 'MODULE_PATHNAME','vops_coalesce_int2' language C parallel safe immutable strict;

create function vops_int2_neg(right vops_int2) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (rightarg=vops_int2, procedure=vops_int2_neg);

create function vops_int2_sum_accumulate(state int8, val vops_int2) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE sum(vops_int2) (
	SFUNC = vops_int2_sum_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	PARALLEL = SAFE
);
create function vops_int2_sum_stub(state vops_int8, val vops_int2) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_int2_sum_extend(state vops_int8, val vops_int2) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int2_sum_reduce(state vops_int8, val vops_int2) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE msum(vops_int2) (
	SFUNC = vops_int2_sum_stub,
	STYPE = vops_int8,
    mstype = vops_int8,
	msfunc = vops_int2_sum_extend,
	minvfunc = vops_int2_sum_reduce,
	PARALLEL = SAFE
);

create function vops_int2_msum_stub(state internal, val vops_int2, winsize integer) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_int2_msum_extend(state internal, val vops_int2, winsize integer) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int2_msum_reduce(state internal, val vops_int2, winsize integer) returns internal as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
create function vops_int2_msum_final(state internal) returns vops_int8 as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE msum(vops_int2,winsize integer) (
	SFUNC = vops_int2_msum_stub,
	STYPE = internal,
	finalfunc = vops_int2_msum_final,
    mstype = internal,
	msfunc = vops_int2_msum_extend,
	minvfunc = vops_int2_msum_reduce,
	mfinalfunc = vops_int2_msum_final,
	PARALLEL = SAFE
);

create function vops_int2_var_accumulate(state internal, val vops_int2) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE var_pop(vops_int2) (
	SFUNC = vops_int2_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_pop_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE var_samp(vops_int2) (
	SFUNC = vops_int2_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE variance(vops_int2) (
	SFUNC = vops_int2_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev_pop(vops_int2) (
	SFUNC = vops_int2_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_pop_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev_samp(vops_int2) (
	SFUNC = vops_int2_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev(vops_int2) (
	SFUNC = vops_int2_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

create function vops_int2_wavg_accumulate(state internal, x vops_int2, y vops_int2) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE wavg(vops_int2, vops_int2) (
	SFUNC = vops_int2_wavg_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_wavg_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

create function vops_int2_avg_accumulate(state internal, val vops_int2) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE avg(vops_int2) (
	SFUNC = vops_int2_avg_accumulate,
	STYPE = internal,
	SSPACE = 16,
	FINALFUNC = vops_avg_final,
	COMBINEFUNC = vops_avg_combine,
	SERIALFUNC = vops_avg_serial,
	DESERIALFUNC = vops_avg_deserial,
	PARALLEL = SAFE
);
create function vops_int2_avg_stub(state internal, val vops_int2) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_int2_avg_extend(state internal, val vops_int2) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int2_avg_reduce(state internal, val vops_int2) returns internal as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mavg(vops_int2) (
	SFUNC = vops_int2_avg_stub,
	FINALFUNC = vops_mavg_final,
	STYPE = internal,
    mstype = internal,
    msfunc = vops_int2_avg_extend,
    minvfunc = vops_int2_avg_reduce,
	mfinalfunc = vops_mavg_final,
	PARALLEL = SAFE
);

create function vops_int2_max_accumulate(state int2, val vops_int2) returns int2 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE max(vops_int2) (
	SFUNC = vops_int2_max_accumulate,
	STYPE = int2,
    COMBINEFUNC = int2larger,
	PARALLEL = SAFE
);
create function vops_int2_max_stub(state vops_int2, val vops_int2) returns vops_int2 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_int2_max_extend(state vops_int2, val vops_int2) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int2_max_reduce(state vops_int2, val vops_int2) returns vops_int2 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mmax(vops_int2) (
	SFUNC = vops_int2_max_stub,
	STYPE = vops_int2,
    mstype = vops_int2,
    msfunc = vops_int2_max_extend,
    minvfunc = vops_int2_max_reduce
);

create function vops_int2_min_accumulate(state int2, val vops_int2) returns int2 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE min(vops_int2) (
	SFUNC = vops_int2_min_accumulate,
	STYPE = int2,
    COMBINEFUNC = int2smaller,
	PARALLEL = SAFE
);
create function vops_int2_min_stub(state vops_int2, val vops_int2) returns vops_int2 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_int2_min_extend(state vops_int2, val vops_int2) returns vops_int2 as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int2_min_reduce(state vops_int2, val vops_int2) returns vops_int2 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mmin(vops_int2) (
	SFUNC = vops_int2_min_stub,
	STYPE = vops_int2,
    mstype = vops_int2,
    msfunc = vops_int2_min_extend,
    minvfunc = vops_int2_min_reduce
);

create function vops_int2_lag_accumulate(state internal, val vops_int2) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_int2_lag_extend(state internal, val vops_int2) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int2_lag_reduce(state internal, val vops_int2) returns internal as 'MODULE_PATHNAME','vops_lag_reduce' language C parallel safe;
create function vops_int2_lag_final(state internal) returns vops_int2 as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE lag(vops_int2) (
	SFUNC = vops_int2_lag_accumulate,
	STYPE = internal,
	finalfunc = vops_int2_lag_final,
    mstype = internal,
    msfunc = vops_int2_lag_extend,
    minvfunc = vops_int2_lag_reduce,
	mfinalfunc = vops_int2_lag_final,
	PARALLEL = SAFE
);

create function vops_int2_count_accumulate(state int8, val vops_int2) returns int8 as 'MODULE_PATHNAME','vops_count_any_accumulate' language C parallel safe strict;
CREATE AGGREGATE count(vops_int2) (
	SFUNC = vops_int2_count_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);
create function vops_int2_count_stub(state vops_int8, val vops_int2) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate'  language C parallel safe strict;
create function vops_int2_count_extend(state vops_int8, val vops_int2) returns vops_int8 as 'MODULE_PATHNAME','vops_count_any_extend' language C parallel safe strict;
create function vops_int2_count_reduce(state vops_int8, val vops_int2) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe strict;
CREATE AGGREGATE mcount(vops_int2) (
	SFUNC = vops_int2_count_stub,
	STYPE = vops_int8,
	initcond = '0', 
    mstype = vops_int8,
	msfunc = vops_int2_count_extend,
	minvfunc = vops_int2_count_reduce,
	minitcond = '0', 
	PARALLEL = SAFE
);

create function vops_int2_first_accumulate(state internal, val vops_int2, ts vops_timestamp) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int2_first_final(state internal) returns int2 as 'MODULE_PATHNAME','vops_first_final' language C parallel safe;
CREATE AGGREGATE first(vops_int2,vops_timestamp) (
	SFUNC = vops_int2_first_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_int2_first_final,
 	COMBINEFUNC = vops_first_combine,
	PARALLEL = SAFE
);

create function vops_int2_last_accumulate(state internal, val vops_int2, ts vops_timestamp) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE last(vops_int2,vops_timestamp) (
	SFUNC = vops_int2_last_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_int2_first_final,
 	COMBINEFUNC = vops_last_combine,
	PARALLEL = SAFE
);

create function first(tile vops_int2) returns int2 as 'MODULE_PATHNAME','vops_int2_first' language C parallel safe immutable strict;
create function last(tile vops_int2) returns int2 as 'MODULE_PATHNAME','vops_int2_last' language C parallel safe immutable strict;
create function low(tile vops_int2) returns int2 as 'MODULE_PATHNAME','vops_int2_low' language C parallel safe immutable strict;
create function high(tile vops_int2) returns int2 as 'MODULE_PATHNAME','vops_int2_high' language C parallel safe immutable strict;

-- int4 tile

create function vops_int4_const(opd int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create cast (int4 as vops_int4) with function vops_int4_const(int4) AS IMPLICIT;

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
create operator + (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_add, commutator= +);
create operator + (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_add_rconst, commutator= +);
create operator + (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_add_lconst, commutator= +);

create function vops_int4_mul(left vops_int4, right vops_int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_mul_rconst(left vops_int4, right int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_mul_lconst(left int4, right vops_int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator * (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_mul, commutator= *);
create operator * (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_mul_rconst, commutator= *);
create operator * (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_mul_lconst, commutator= *);

create function vops_int4_div(left vops_int4, right vops_int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_div_rconst(left vops_int4, right int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_div_lconst(left int4, right vops_int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator / (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_div);
create operator / (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_div_rconst);
create operator / (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_div_lconst);

create function vops_int4_rem(left vops_int4, right vops_int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_rem_rconst(left vops_int4, right int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_rem_lconst(left int4, right vops_int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator % (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_rem);
create operator % (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_rem_rconst);
create operator % (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_rem_lconst);

create function vops_int4_eq(left vops_int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_eq_rconst(left vops_int4, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_eq_lconst(left int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator = (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_eq, commutator= =);
create operator = (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_eq_rconst, commutator= =);
create operator = (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_eq_lconst, commutator= =);

create function vops_int4_ne(left vops_int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_ne_rconst(left vops_int4, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_ne_lconst(left int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <> (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_ne, commutator= <>);
create operator <> (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_ne_rconst, commutator= <>);
create operator <> (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_ne_lconst, commutator= <>);

create function vops_int4_gt(left vops_int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_gt_rconst(left vops_int4, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_gt_lconst(left int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator > (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_gt, commutator= <);
create operator > (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_gt_rconst, commutator= <);
create operator > (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_gt_lconst, commutator= <);

create function vops_int4_lt(left vops_int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_lt_rconst(left vops_int4, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_lt_lconst(left int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator < (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_lt, commutator= >);
create operator < (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_lt_rconst, commutator= >);
create operator < (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_lt_lconst, commutator= >);

create function vops_int4_ge(left vops_int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_ge_rconst(left vops_int4, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_ge_lconst(left int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator >= (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_ge, commutator= <=);
create operator >= (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_ge_rconst, commutator= <=);
create operator >= (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_ge_lconst, commutator= <=);

create function vops_int4_le(left vops_int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_le_rconst(left vops_int4, right int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int4_le_lconst(left int4, right vops_int4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <= (leftarg=vops_int4, rightarg=vops_int4, procedure=vops_int4_le, commutator= >=);
create operator <= (leftarg=vops_int4, rightarg=int4, procedure=vops_int4_le_rconst, commutator= >=);
create operator <= (leftarg=int4, rightarg=vops_int4, procedure=vops_int4_le_lconst, commutator= >=);

create function betwixt(opd vops_int4, low int4, high int4) returns vops_bool as 'MODULE_PATHNAME','vops_betwixt_int4' language C parallel safe immutable strict;

create function ifnull(opd vops_int4, subst int4) returns vops_int4 as 'MODULE_PATHNAME','vops_ifnull_int4' language C parallel safe immutable strict;
create function ifnull(opd vops_int4, subst vops_int4) returns vops_int4 as 'MODULE_PATHNAME','vops_coalesce_int4' language C parallel safe immutable strict;

create function vops_int4_neg(right vops_int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (rightarg=vops_int4, procedure=vops_int4_neg);

create function vops_int4_sum_accumulate(state int8, val vops_int4) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE sum(vops_int4) (
	SFUNC = vops_int4_sum_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	PARALLEL = SAFE
);
create function vops_int4_sum_stub(state vops_int8, val vops_int4) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_int4_sum_extend(state vops_int8, val vops_int4) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int4_sum_reduce(state vops_int8, val vops_int4) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE msum(vops_int4) (
	SFUNC = vops_int4_sum_stub,
	STYPE = vops_int8,
    mstype = vops_int8,
	msfunc = vops_int4_sum_extend,
	minvfunc = vops_int4_sum_reduce,
	PARALLEL = SAFE
);

create function vops_int4_msum_stub(state internal, val vops_int4, winsize integer) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_int4_msum_extend(state internal, val vops_int4, winsize integer) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int4_msum_reduce(state internal, val vops_int4, winsize integer) returns internal as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
create function vops_int4_msum_final(state internal) returns vops_int8 as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE msum(vops_int4,winsize integer) (
	SFUNC = vops_int4_msum_stub,
	STYPE = internal,
	finalfunc = vops_int4_msum_final,
    mstype = internal,
	msfunc = vops_int4_msum_extend,
	minvfunc = vops_int4_msum_reduce,
	mfinalfunc = vops_int4_msum_final,
	PARALLEL = SAFE
);

create function vops_int4_var_accumulate(state internal, val vops_int4) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE var_pop(vops_int4) (
	SFUNC = vops_int4_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_pop_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE var_samp(vops_int4) (
	SFUNC = vops_int4_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE variance(vops_int4) (
	SFUNC = vops_int4_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev_pop(vops_int4) (
	SFUNC = vops_int4_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_pop_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev_samp(vops_int4) (
	SFUNC = vops_int4_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev(vops_int4) (
	SFUNC = vops_int4_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

create function vops_int4_wavg_accumulate(state internal, x vops_int4, y vops_int4) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE wavg(vops_int4, vops_int4) (
	SFUNC = vops_int4_wavg_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_wavg_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

create function vops_int4_avg_accumulate(state internal, val vops_int4) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE avg(vops_int4) (
	SFUNC = vops_int4_avg_accumulate,
	STYPE = internal,
	SSPACE = 16,
	FINALFUNC = vops_avg_final,
	COMBINEFUNC = vops_avg_combine,
	SERIALFUNC = vops_avg_serial,
	DESERIALFUNC = vops_avg_deserial,
	PARALLEL = SAFE
);
create function vops_int4_avg_stub(state internal, val vops_int4) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_int4_avg_extend(state internal, val vops_int4) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int4_avg_reduce(state internal, val vops_int4) returns internal as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mavg(vops_int4) (
	SFUNC = vops_int4_avg_stub,
	STYPE = internal,
	finalfunc = vops_mavg_final,
    mstype = internal,
    msfunc = vops_int4_avg_extend,
    minvfunc = vops_int4_avg_reduce,
	mfinalfunc = vops_mavg_final
);

create function vops_int4_max_accumulate(state int4, val vops_int4) returns int4 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE max(vops_int4) (
	SFUNC = vops_int4_max_accumulate,
	STYPE = int4,
    COMBINEFUNC = int4larger,
	PARALLEL = SAFE
);
create function vops_int4_max_stub(state vops_int4, val vops_int4) returns vops_int4 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_int4_max_extend(state vops_int4, val vops_int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int4_max_reduce(state vops_int4, val vops_int4) returns vops_int4 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mmax(vops_int4) (
	SFUNC = vops_int4_max_stub,
	STYPE = vops_int4,
    mstype = vops_int4,
    msfunc = vops_int4_max_extend,
    minvfunc = vops_int4_max_reduce
);

create function vops_int4_min_accumulate(state int4, val vops_int4) returns int4 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE min(vops_int4) (
	SFUNC = vops_int4_min_accumulate,
	STYPE = int4,
    COMBINEFUNC = int4smaller,
	PARALLEL = SAFE
);
create function vops_int4_min_stub(state vops_int4, val vops_int4) returns vops_int4 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_int4_min_extend(state vops_int4, val vops_int4) returns vops_int4 as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int4_min_reduce(state vops_int4, val vops_int4) returns vops_int4 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mmin(vops_int4) (
	SFUNC = vops_int4_min_stub,
	STYPE = vops_int4,
    mstype = vops_int4,
    msfunc = vops_int4_min_extend,
    minvfunc = vops_int4_min_reduce,
	PARALLEL = SAFE
);

create function vops_int4_lag_accumulate(state internal, val vops_int4) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_int4_lag_extend(state internal, val vops_int4) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int4_lag_reduce(state internal, val vops_int4) returns internal as 'MODULE_PATHNAME','vops_lag_reduce' language C parallel safe;
create function vops_int4_lag_final(state internal) returns vops_int4 as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE lag(vops_int4) (
	SFUNC = vops_int4_lag_accumulate,
	STYPE = internal,
	finalfunc = vops_int4_lag_final,
    mstype = internal,
    msfunc = vops_int4_lag_extend,
    minvfunc = vops_int4_lag_reduce,
    mfinalfunc = vops_int4_lag_final,
	PARALLEL = SAFE
);

create function vops_int4_count_accumulate(state int8, val vops_int4) returns int8 as 'MODULE_PATHNAME','vops_count_any_accumulate' language C parallel safe strict;
CREATE AGGREGATE count(vops_int4) (
	SFUNC = vops_int4_count_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);
create function vops_int4_count_stub(state vops_int8, val vops_int4) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate'  language C parallel safe strict;
create function vops_int4_count_extend(state vops_int8, val vops_int4) returns vops_int8 as 'MODULE_PATHNAME','vops_count_any_extend' language C parallel safe strict;
create function vops_int4_count_reduce(state vops_int8, val vops_int4) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe strict;
CREATE AGGREGATE mcount(vops_int4) (
	SFUNC = vops_int4_count_stub,
	STYPE = vops_int8,
	initcond = '0', 
    mstype = vops_int8,
	msfunc = vops_int4_count_extend,
	minvfunc = vops_int4_count_reduce,
	minitcond = '0', 
	PARALLEL = SAFE
);

create function vops_int4_first_accumulate(state internal, val vops_int4, ts vops_timestamp) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int4_first_final(state internal) returns int4 as 'MODULE_PATHNAME','vops_first_final' language C parallel safe;
CREATE AGGREGATE first(vops_int4,vops_timestamp) (
	SFUNC = vops_int4_first_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_int4_first_final,
 	COMBINEFUNC = vops_first_combine,
	PARALLEL = SAFE
);

create function vops_int4_last_accumulate(state internal, val vops_int4, ts vops_timestamp) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE last(vops_int4,vops_timestamp) (
	SFUNC = vops_int4_last_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_int4_first_final,
 	COMBINEFUNC = vops_last_combine,
	PARALLEL = SAFE
);

create function first(tile vops_int4) returns int4 as 'MODULE_PATHNAME','vops_int4_first' language C parallel safe immutable strict;
create function last(tile vops_int4) returns int4 as 'MODULE_PATHNAME','vops_int4_last' language C parallel safe immutable strict;
create function low(tile vops_int4) returns int4 as 'MODULE_PATHNAME','vops_int4_low' language C parallel safe immutable strict;
create function high(tile vops_int4) returns int4 as 'MODULE_PATHNAME','vops_int4_high' language C parallel safe immutable strict;

-- date tile

create function date_bucket(interval, vops_date) returns vops_date  as 'MODULE_PATHNAME','vops_date_bucket' language C parallel safe immutable strict;

create function vops_date_const(opd date) returns vops_date as 'MODULE_PATHNAME','vops_int4_const' language C parallel safe immutable strict;
create cast (date as vops_date) with function vops_date_const(date) AS IMPLICIT;

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
create operator + (leftarg=vops_date, rightarg=vops_date, procedure=vops_date_add, commutator= +);
create operator + (leftarg=vops_date, rightarg=date, procedure=vops_date_add_rconst, commutator= +);
create operator + (leftarg=date, rightarg=vops_date, procedure=vops_date_add_lconst, commutator= +);

create function vops_date_mul(left vops_date, right vops_date) returns vops_date as 'MODULE_PATHNAME','vops_int4_mul' language C parallel safe immutable strict;
create function vops_date_mul_rconst(left vops_date, right date) returns vops_date as 'MODULE_PATHNAME','vops_int4_mul_rconst' language C parallel safe immutable strict;
create function vops_date_mul_lconst(left date, right vops_date) returns vops_date as 'MODULE_PATHNAME','vops_int4_mul_lconst' language C parallel safe immutable strict;
create operator * (leftarg=vops_date, rightarg=vops_date, procedure=vops_date_mul, commutator= *);
create operator * (leftarg=vops_date, rightarg=date, procedure=vops_date_mul_rconst, commutator= *);
create operator * (leftarg=date, rightarg=vops_date, procedure=vops_date_mul_lconst, commutator= *);

create function vops_date_div(left vops_date, right vops_int4) returns vops_int4 as 'MODULE_PATHNAME','vops_int4_div' language C parallel safe immutable strict;
create function vops_date_div_rconst(left vops_date, right int4) returns vops_int4 as 'MODULE_PATHNAME','vops_int4_div_rconst' language C parallel safe immutable strict;
create operator / (leftarg=vops_date, rightarg=vops_int4, procedure=vops_date_div);
create operator / (leftarg=vops_date, rightarg=int4, procedure=vops_date_div_rconst);

create function vops_date_rem(left vops_date, right vops_int4) returns vops_int4 as 'MODULE_PATHNAME','vops_int4_rem' language C parallel safe immutable strict;
create function vops_date_rem_rconst(left vops_date, right int4) returns vops_int4 as 'MODULE_PATHNAME','vops_int4_rem_rconst' language C parallel safe immutable strict;
create operator % (leftarg=vops_date, rightarg=vops_int4, procedure=vops_date_rem);
create operator % (leftarg=vops_date, rightarg=int4, procedure=vops_date_rem_rconst);

create function vops_date_eq(left vops_date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_eq' language C parallel safe immutable strict;
create function vops_date_eq_rconst(left vops_date, right date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_eq_rconst' language C parallel safe immutable strict;
create function vops_date_eq_lconst(left date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_eq_lconst' language C parallel safe immutable strict;
create operator = (leftarg=vops_date, rightarg=vops_date, procedure=vops_date_eq, commutator= =);
create operator = (leftarg=vops_date, rightarg=date, procedure=vops_date_eq_rconst, commutator= =);
create operator = (leftarg=date, rightarg=vops_date, procedure=vops_date_eq_lconst, commutator= =);

create function vops_date_ne(left vops_date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_ne' language C parallel safe immutable strict;
create function vops_date_ne_rconst(left vops_date, right date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_ne_rconst' language C parallel safe immutable strict;
create function vops_date_ne_lconst(left date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_ne_lconst' language C parallel safe immutable strict;
create operator <> (leftarg=vops_date, rightarg=vops_date, procedure=vops_date_ne, commutator= <>);
create operator <> (leftarg=vops_date, rightarg=date, procedure=vops_date_ne_rconst, commutator= <>);
create operator <> (leftarg=date, rightarg=vops_date, procedure=vops_date_ne_lconst, commutator= <>);

create function vops_date_gt(left vops_date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_gt' language C parallel safe immutable strict;
create function vops_date_gt_rconst(left vops_date, right date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_gt_rconst' language C parallel safe immutable strict;
create function vops_date_gt_lconst(left date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_gt_lconst' language C parallel safe immutable strict;
create operator > (leftarg=vops_date, rightarg=vops_date, procedure=vops_date_gt, commutator= <);
create operator > (leftarg=vops_date, rightarg=date, procedure=vops_date_gt_rconst, commutator= <);
create operator > (leftarg=date, rightarg=vops_date, procedure=vops_date_gt_lconst, commutator= <);

create function vops_date_lt(left vops_date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_lt' language C parallel safe immutable strict;
create function vops_date_lt_rconst(left vops_date, right date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_lt_rconst' language C parallel safe immutable strict;
create function vops_date_lt_lconst(left date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_lt_lconst' language C parallel safe immutable strict;
create operator < (leftarg=vops_date, rightarg=vops_date, procedure=vops_date_lt, commutator= >);
create operator < (leftarg=vops_date, rightarg=date, procedure=vops_date_lt_rconst, commutator= >);
create operator < (leftarg=date, rightarg=vops_date, procedure=vops_date_lt_lconst, commutator= >);

create function vops_date_ge(left vops_date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_ge' language C parallel safe immutable strict;
create function vops_date_ge_rconst(left vops_date, right date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_ge_rconst' language C parallel safe immutable strict;
create function vops_date_ge_lconst(left date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_ge_lconst' language C parallel safe immutable strict;
create operator >= (leftarg=vops_date, rightarg=vops_date, procedure=vops_date_ge, commutator= <=);
create operator >= (leftarg=vops_date, rightarg=date, procedure=vops_date_ge_rconst, commutator= <=);
create operator >= (leftarg=date, rightarg=vops_date, procedure=vops_date_ge_lconst, commutator= <=);

create function vops_date_le(left vops_date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_le' language C parallel safe immutable strict;
create function vops_date_le_rconst(left vops_date, right date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_le_rconst' language C parallel safe immutable strict;
create function vops_date_le_lconst(left date, right vops_date) returns vops_bool as 'MODULE_PATHNAME','vops_int4_le_lconst' language C parallel safe immutable strict;
create operator <= (leftarg=vops_date, rightarg=vops_date, procedure=vops_date_le, commutator= >=);
create operator <= (leftarg=vops_date, rightarg=date, procedure=vops_date_le_rconst, commutator= >=);
create operator <= (leftarg=date, rightarg=vops_date, procedure=vops_date_le_lconst, commutator= >=);

create function betwixt(opd vops_date, low date, high date) returns vops_bool as 'MODULE_PATHNAME','vops_betwixt_int4' language C parallel safe immutable strict;

create function ifnull(opd vops_date, subst date) returns vops_date as 'MODULE_PATHNAME','vops_ifnull_int4' language C parallel safe immutable strict;
create function ifnull(opd vops_date, subst vops_date) returns vops_date as 'MODULE_PATHNAME','vops_coalesce_int4' language C parallel safe immutable strict;

create function vops_date_neg(right vops_date) returns vops_date as 'MODULE_PATHNAME','vops_int4_neg' language C parallel safe immutable strict;
create operator - (rightarg=vops_date, procedure=vops_date_neg);

create function vops_date_sum_accumulate(state int8, val vops_date) returns int8 as 'MODULE_PATHNAME','vops_int4_sum_accumulate' language C parallel safe;
CREATE AGGREGATE sum(vops_date) (
	SFUNC = vops_date_sum_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	PARALLEL = SAFE
);
create function vops_date_sum_stub(state vops_int8, val vops_date) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_date_sum_extend(state vops_int8, val vops_date) returns vops_int8 as 'MODULE_PATHNAME','vops_int4_sum_extend' language C parallel safe;
create function vops_date_sum_reduce(state vops_int8, val vops_date) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE msum(vops_date) (
	SFUNC = vops_date_sum_stub,
	STYPE = vops_int8,
    mstype = vops_int8,
	msfunc = vops_date_sum_extend,
	minvfunc = vops_date_sum_reduce,
	PARALLEL = SAFE
);

create function vops_date_msum_stub(state internal, val vops_date, winsize integer) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_date_msum_extend(state internal, val vops_date, winsize integer) returns internal as 'MODULE_PATHNAME','vops_int4_msum_extend' language C parallel safe;
create function vops_date_msum_reduce(state internal, val vops_date, winsize integer) returns internal as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
create function vops_date_msum_final(state internal) returns vops_int8 as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE msum(vops_date,winsize integer) (
	SFUNC = vops_date_msum_stub,
	STYPE = internal,
	finalfunc = vops_date_msum_final,
    mstype = internal,
	msfunc = vops_date_msum_extend,
	minvfunc = vops_date_msum_reduce,
	mfinalfunc = vops_date_msum_final,
	PARALLEL = SAFE
);

create function vops_date_var_accumulate(state internal, val vops_date) returns internal as 'MODULE_PATHNAME','vops_int4_var_accumulate' language C parallel safe;
CREATE AGGREGATE var_pop(vops_date) (
	SFUNC = vops_date_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_pop_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE var_samp(vops_date) (
	SFUNC = vops_date_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE variance(vops_date) (
	SFUNC = vops_date_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev_pop(vops_date) (
	SFUNC = vops_date_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_pop_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev_samp(vops_date) (
	SFUNC = vops_date_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev(vops_date) (
	SFUNC = vops_date_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

create function vops_date_wavg_accumulate(state internal, x vops_date, y vops_date) returns internal as 'MODULE_PATHNAME','vops_int4_wavg_accumulate' language C parallel safe;
CREATE AGGREGATE wavg(vops_date, vops_date) (
	SFUNC = vops_date_wavg_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_wavg_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

create function vops_date_avg_accumulate(state internal, val vops_date) returns internal as 'MODULE_PATHNAME','vops_int4_avg_accumulate' language C parallel safe;
CREATE AGGREGATE avg(vops_date) (
	SFUNC = vops_date_avg_accumulate,
	STYPE = internal,
	SSPACE = 16,
	FINALFUNC = vops_avg_final,
	COMBINEFUNC = vops_avg_combine,
	SERIALFUNC = vops_avg_serial,
	DESERIALFUNC = vops_avg_deserial,
	PARALLEL = SAFE
);
create function vops_date_avg_stub(state internal, val vops_date) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_date_avg_extend(state internal, val vops_date) returns internal as 'MODULE_PATHNAME','vops_int4_avg_extend' language C parallel safe;
create function vops_date_avg_reduce(state internal, val vops_date) returns internal as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mavg(vops_date) (
	SFUNC = vops_date_avg_stub,
	STYPE = internal,
	FINALFUNC = vops_mavg_final,
    mstype = internal,
    msfunc = vops_date_avg_extend,
    minvfunc = vops_date_avg_reduce,
	mfinalfunc = vops_mavg_final,
	PARALLEL = SAFE
);

create function vops_date_max_accumulate(state date, val vops_date) returns date as 'MODULE_PATHNAME','vops_int4_max_accumulate' language C parallel safe;
CREATE AGGREGATE max(vops_date) (
	SFUNC = vops_date_max_accumulate,
	STYPE = date,
    COMBINEFUNC = date_larger,
	PARALLEL = SAFE
);
create function vops_date_max_stub(state vops_date, val vops_date) returns vops_date as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_date_max_extend(state vops_date, val vops_date) returns vops_date as 'MODULE_PATHNAME','vops_int4_max_extend' language C parallel safe;
create function vops_date_max_reduce(state vops_date, val vops_date) returns vops_date as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mmax(vops_date) (
	SFUNC = vops_date_max_stub,
	STYPE = vops_date,
    mstype = vops_date,
    msfunc = vops_date_max_extend,
    minvfunc = vops_date_max_reduce,
	PARALLEL = SAFE
);

create function vops_date_min_accumulate(state date, val vops_date) returns date as 'MODULE_PATHNAME','vops_int4_min_accumulate' language C parallel safe;
CREATE AGGREGATE min(vops_date) (
	SFUNC = vops_date_min_accumulate,
	STYPE = date,
    COMBINEFUNC = date_smaller,
	PARALLEL = SAFE
);
create function vops_date_min_stub(state vops_date, val vops_date) returns vops_date as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_date_min_extend(state vops_date, val vops_date) returns vops_date as 'MODULE_PATHNAME','vops_int4_min_extend' language C parallel safe;
create function vops_date_min_reduce(state vops_date, val vops_date) returns vops_date as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mmin(vops_date) (
	SFUNC = vops_date_min_stub,
	STYPE = vops_date,
    mstype = vops_date,
    msfunc = vops_date_min_extend,
    minvfunc = vops_date_min_reduce,
	PARALLEL = SAFE
);

create function vops_date_lag_accumulate(state internal, val vops_date) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_date_lag_extend(state internal, val vops_date) returns internal as 'MODULE_PATHNAME','vops_int4_lag_extend' language C parallel safe;
create function vops_date_lag_reduce(state internal, val vops_date) returns internal as 'MODULE_PATHNAME','vops_lag_reduce' language C parallel safe;
create function vops_date_lag_final(state internal) returns vops_date as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE lag(vops_date) (
	SFUNC = vops_date_lag_accumulate,
	STYPE = internal,
	finalfunc = vops_date_lag_final,
    mstype = internal,
    msfunc = vops_date_lag_extend,
    minvfunc = vops_date_lag_reduce,
    mfinalfunc = vops_date_lag_final,
	PARALLEL = SAFE
);

create function vops_date_count_accumulate(state int8, val vops_date) returns int8 as 'MODULE_PATHNAME','vops_count_any_accumulate' language C parallel safe strict;
CREATE AGGREGATE count(vops_date) (
	SFUNC = vops_date_count_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);
create function vops_date_count_stub(state vops_int8, val vops_date) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate'  language C parallel safe strict;
create function vops_date_count_extend(state vops_int8, val vops_date) returns vops_int8 as 'MODULE_PATHNAME','vops_count_any_extend' language C parallel safe strict;
create function vops_date_count_reduce(state vops_int8, val vops_date) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe strict;
CREATE AGGREGATE mcount(vops_date) (
	SFUNC = vops_date_count_stub,
	STYPE = vops_int8,
	initcond = '0', 
    mstype = vops_int8,
	msfunc = vops_date_count_extend,
	minvfunc = vops_date_count_reduce,
	minitcond = '0', 
	PARALLEL = SAFE
);

create function vops_date_first_accumulate(state internal, val vops_date, ts vops_timestamp) returns internal as 'MODULE_PATHNAME','vops_int4_first_accumulate' language C parallel safe;
create function vops_date_first_final(state internal) returns date as 'MODULE_PATHNAME','vops_first_final' language C parallel safe;
CREATE AGGREGATE first(vops_date,vops_timestamp) (
	SFUNC = vops_date_first_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_date_first_final,
 	COMBINEFUNC = vops_first_combine,
	PARALLEL = SAFE
);

create function vops_date_last_accumulate(state internal, val vops_date, ts vops_timestamp) returns internal as 'MODULE_PATHNAME','vops_int4_last_accumulate' language C parallel safe;
CREATE AGGREGATE last(vops_date,vops_timestamp) (
	SFUNC = vops_date_last_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_date_first_final,
 	COMBINEFUNC = vops_last_combine,
	PARALLEL = SAFE
);

create function first(tile vops_date) returns date as 'MODULE_PATHNAME','vops_int4_first' language C parallel safe immutable strict;
create function last(tile vops_date) returns date as 'MODULE_PATHNAME','vops_int4_last' language C parallel safe immutable strict;
create function low(tile vops_date) returns date as 'MODULE_PATHNAME','vops_int4_low' language C parallel safe immutable strict;
create function high(tile vops_date) returns date as 'MODULE_PATHNAME','vops_int4_high' language C parallel safe immutable strict;

-- timestamp tile

create function time_bucket(interval, vops_timestamp) returns vops_timestamp  as 'MODULE_PATHNAME','vops_time_bucket' language C parallel safe immutable strict;

create function vops_timestamp_const(opd timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_const' language C parallel safe immutable strict;
create cast (timestamp as vops_timestamp) with function vops_timestamp_const(timestamp) AS IMPLICIT;

create function vops_timestamp_group_by(state internal, group_by vops_timestamp, aggregates cstring, variadic anyarray) returns internal as 'MODULE_PATHNAME','vops_int8_group_by' language C immutable;
create aggregate map(group_by vops_timestamp, aggregates cstring, variadic anyarray) (
	   sfunc = vops_timestamp_group_by, 
	   stype = internal,
	   finalfunc=vops_agg_final,
	   combinefunc = vops_agg_combine,
	   serialfunc = vops_agg_serial,
	   deserialfunc = vops_agg_deserial,
	   parallel = safe);

create function vops_timestamp_sub(left vops_timestamp, right vops_timestamp) returns vops_interval as 'MODULE_PATHNAME','vops_int8_sub' language C parallel safe immutable strict;
create function vops_timestamp_interval_sub(left vops_timestamp, right vops_interval) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_sub' language C parallel safe immutable strict;
create function vops_timestamp_sub_rconst(left vops_timestamp, right timestamp) returns vops_interval as 'MODULE_PATHNAME','vops_int8_sub_rconst' language C parallel safe immutable strict;
create function vops_timestamp_sub_lconst(left timestamp, right vops_timestamp) returns vops_interval as 'MODULE_PATHNAME','vops_int8_sub_lconst' language C parallel safe immutable strict;
create function vops_timestamp_sub_interval_rconst(left vops_timestamp, right deltatime) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_sub_rconst' language C parallel safe immutable strict;
create function vops_timestamp_sub_interval_lconst(left timestamp, right vops_interval) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_sub_lconst' language C parallel safe immutable strict;
create operator - (leftarg=vops_timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_sub);
create operator - (leftarg=vops_timestamp, rightarg=vops_interval, procedure=vops_timestamp_interval_sub);
create operator - (leftarg=vops_timestamp, rightarg=timestamp, procedure=vops_timestamp_sub_rconst);
create operator - (leftarg=timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_sub_lconst);
create operator - (leftarg=vops_timestamp, rightarg=deltatime, procedure=vops_timestamp_sub_interval_rconst);
create operator - (leftarg=timestamp, rightarg=vops_interval, procedure=vops_timestamp_sub_interval_lconst);

create function vops_timestamp_interval_add(left vops_timestamp, right vops_interval) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_add' language C parallel safe immutable strict;
create function vops_interval_timestamp_add(left vops_interval, right vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_add' language C parallel safe immutable strict;
create function vops_timestamp_add_rconst(left vops_timestamp, right deltatime) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_add_rconst' language C parallel safe immutable strict;
create function vops_timestamp_add_lconst(left deltatime, right vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_add_lconst' language C parallel safe immutable strict;
create operator + (leftarg=vops_timestamp, rightarg=vops_interval, procedure=vops_timestamp_interval_add, commutator= +);
create operator + (leftarg=vops_interval, rightarg=vops_timestamp, procedure=vops_interval_timestamp_add, commutator= +);
create operator + (leftarg=vops_timestamp, rightarg=deltatime, procedure=vops_timestamp_add_rconst, commutator= +);
create operator + (leftarg=deltatime, rightarg=vops_timestamp, procedure=vops_timestamp_add_lconst, commutator= +);

create function vops_timestamp_mul(left vops_timestamp, right vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_mul' language C parallel safe immutable strict;
create function vops_timestamp_mul_rconst(left vops_timestamp, right timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_mul_rconst' language C parallel safe immutable strict;
create function vops_timestamp_mul_lconst(left timestamp, right vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_mul_lconst' language C parallel safe immutable strict;
create operator * (leftarg=vops_timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_mul, commutator= *);
create operator * (leftarg=vops_timestamp, rightarg=timestamp, procedure=vops_timestamp_mul_rconst, commutator= *);
create operator * (leftarg=timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_mul_lconst, commutator= *);

create function vops_timestamp_div(left vops_timestamp, right vops_int8) returns vops_int8 as 'MODULE_PATHNAME','vops_int8_div' language C parallel safe immutable strict;
create function vops_timestamp_div_rconst(left vops_timestamp, right int8) returns vops_int8 as 'MODULE_PATHNAME','vops_int8_div_rconst' language C parallel safe immutable strict;
create operator / (leftarg=vops_timestamp, rightarg=vops_int8, procedure=vops_timestamp_div);
create operator / (leftarg=vops_timestamp, rightarg=int8, procedure=vops_timestamp_div_rconst);

create function vops_timestamp_rem(left vops_timestamp, right vops_int8) returns vops_int8 as 'MODULE_PATHNAME','vops_int8_rem' language C parallel safe immutable strict;
create function vops_timestamp_rem_rconst(left vops_timestamp, right int8) returns vops_int8 as 'MODULE_PATHNAME','vops_int8_rem_rconst' language C parallel safe immutable strict;
create operator % (leftarg=vops_timestamp, rightarg=vops_int8, procedure=vops_timestamp_rem);
create operator % (leftarg=vops_timestamp, rightarg=int8, procedure=vops_timestamp_rem_rconst);

create function vops_timestamp_eq(left vops_timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_eq' language C parallel safe immutable strict;
create function vops_timestamp_eq_rconst(left vops_timestamp, right timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_eq_rconst' language C parallel safe immutable strict;
create function vops_timestamp_eq_lconst(left timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_eq_lconst' language C parallel safe immutable strict;
create operator = (leftarg=vops_timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_eq, commutator= =);
create operator = (leftarg=vops_timestamp, rightarg=timestamp, procedure=vops_timestamp_eq_rconst, commutator= =);
create operator = (leftarg=timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_eq_lconst, commutator= =);

create function vops_timestamp_ne(left vops_timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_ne' language C parallel safe immutable strict;
create function vops_timestamp_ne_rconst(left vops_timestamp, right timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_ne_rconst' language C parallel safe immutable strict;
create function vops_timestamp_ne_lconst(left timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_ne_lconst' language C parallel safe immutable strict;
create operator <> (leftarg=vops_timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_ne, commutator= <>);
create operator <> (leftarg=vops_timestamp, rightarg=timestamp, procedure=vops_timestamp_ne_rconst, commutator= <>);
create operator <> (leftarg=timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_ne_lconst, commutator= <>);

create function vops_timestamp_gt(left vops_timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_gt' language C parallel safe immutable strict;
create function vops_timestamp_gt_rconst(left vops_timestamp, right timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_gt_rconst' language C parallel safe immutable strict;
create function vops_timestamp_gt_lconst(left timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_gt_lconst' language C parallel safe immutable strict;
create operator > (leftarg=vops_timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_gt, commutator= <);
create operator > (leftarg=vops_timestamp, rightarg=timestamp, procedure=vops_timestamp_gt_rconst, commutator= <);
create operator > (leftarg=timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_gt_lconst, commutator= <);

create function vops_timestamp_lt(left vops_timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_lt' language C parallel safe immutable strict;
create function vops_timestamp_lt_rconst(left vops_timestamp, right timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_lt_rconst' language C parallel safe immutable strict;
create function vops_timestamp_lt_lconst(left timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_lt_lconst' language C parallel safe immutable strict;
create operator < (leftarg=vops_timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_lt, commutator= >);
create operator < (leftarg=vops_timestamp, rightarg=timestamp, procedure=vops_timestamp_lt_rconst, commutator= >);
create operator < (leftarg=timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_lt_lconst, commutator= >);

create function vops_timestamp_ge(left vops_timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_ge' language C parallel safe immutable strict;
create function vops_timestamp_ge_rconst(left vops_timestamp, right timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_ge_rconst' language C parallel safe immutable strict;
create function vops_timestamp_ge_lconst(left timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_ge_lconst' language C parallel safe immutable strict;
create operator >= (leftarg=vops_timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_ge, commutator= <=);
create operator >= (leftarg=vops_timestamp, rightarg=timestamp, procedure=vops_timestamp_ge_rconst, commutator= <=);
create operator >= (leftarg=timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_ge_lconst, commutator= <=);

create function vops_timestamp_le(left vops_timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_le' language C parallel safe immutable strict;
create function vops_timestamp_le_rconst(left vops_timestamp, right timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_le_rconst' language C parallel safe immutable strict;
create function vops_timestamp_le_lconst(left timestamp, right vops_timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_int8_le_lconst' language C parallel safe immutable strict;
create operator <= (leftarg=vops_timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_le, commutator= >=);
create operator <= (leftarg=vops_timestamp, rightarg=timestamp, procedure=vops_timestamp_le_rconst, commutator= >=);
create operator <= (leftarg=timestamp, rightarg=vops_timestamp, procedure=vops_timestamp_le_lconst, commutator= >=);

create function betwixt(opd vops_timestamp, low timestamp, high timestamp) returns vops_bool as 'MODULE_PATHNAME','vops_betwixt_int8' language C parallel safe immutable strict;

create function ifnull(opd vops_timestamp, subst timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_ifnull_int8' language C parallel safe immutable strict;
create function ifnull(opd vops_timestamp, subst vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_coalesce_int8' language C parallel safe immutable strict;

create function vops_timestamp_neg(right vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_neg' language C parallel safe immutable strict;
create operator - (rightarg=vops_timestamp, procedure=vops_timestamp_neg);

create function vops_timestamp_sum_accumulate(state int8, val vops_timestamp) returns int8 as 'MODULE_PATHNAME','vops_int8_sum_accumulate' language C parallel safe;
CREATE AGGREGATE sum(vops_timestamp) (
	SFUNC = vops_timestamp_sum_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	PARALLEL = SAFE
);
create function vops_timestamp_sum_stub(state vops_int8, val vops_timestamp) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_timestamp_sum_extend(state vops_int8, val vops_timestamp) returns vops_int8 as 'MODULE_PATHNAME','vops_int8_sum_extend' language C parallel safe;
create function vops_timestamp_sum_reduce(state vops_int8, val vops_timestamp) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE msum(vops_timestamp) (
	SFUNC = vops_timestamp_sum_stub,
	STYPE = vops_int8,
    mstype = vops_int8,
	msfunc = vops_timestamp_sum_extend,
	minvfunc = vops_timestamp_sum_reduce,
	PARALLEL = SAFE
);

create function vops_timestamp_msum_stub(state internal, val vops_timestamp, winsize integer) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_timestamp_msum_extend(state internal, val vops_timestamp, winsize integer) returns internal as 'MODULE_PATHNAME','vops_int8_msum_extend' language C parallel safe;
create function vops_timestamp_msum_reduce(state internal, val vops_timestamp, winsize integer) returns internal as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
create function vops_timestamp_msum_final(state internal) returns vops_int8 as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE msum(vops_timestamp,winsize integer) (
	SFUNC = vops_timestamp_msum_stub,
	STYPE = internal,
	finalfunc = vops_timestamp_msum_final,
    mstype = internal,
	msfunc = vops_timestamp_msum_extend,
	minvfunc = vops_timestamp_msum_reduce,
	mfinalfunc = vops_timestamp_msum_final,
	PARALLEL = SAFE
);

create function vops_timestamp_var_accumulate(state internal, val vops_timestamp) returns internal as 'MODULE_PATHNAME','vops_int8_var_accumulate' language C parallel safe;
CREATE AGGREGATE var_pop(vops_timestamp) (
	SFUNC = vops_timestamp_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_pop_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE var_samp(vops_timestamp) (
	SFUNC = vops_timestamp_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE variance(vops_timestamp) (
	SFUNC = vops_timestamp_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev_pop(vops_timestamp) (
	SFUNC = vops_timestamp_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_pop_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev_samp(vops_timestamp) (
	SFUNC = vops_timestamp_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev(vops_timestamp) (
	SFUNC = vops_timestamp_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

create function vops_timestamp_wavg_accumulate(state internal, x vops_timestamp, y vops_timestamp) returns internal as 'MODULE_PATHNAME','vops_int8_wavg_accumulate' language C parallel safe;
CREATE AGGREGATE wavg(vops_timestamp, vops_timestamp) (
	SFUNC = vops_timestamp_wavg_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_wavg_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

create function vops_timestamp_avg_accumulate(state internal, val vops_timestamp) returns internal as 'MODULE_PATHNAME','vops_int8_avg_accumulate' language C parallel safe;
CREATE AGGREGATE avg(vops_timestamp) (
	SFUNC = vops_timestamp_avg_accumulate,
	STYPE = internal,
	SSPACE = 16,
	FINALFUNC = vops_avg_final,
	COMBINEFUNC = vops_avg_combine,
	SERIALFUNC = vops_avg_serial,
	DESERIALFUNC = vops_avg_deserial,
	PARALLEL = SAFE
);
create function vops_timestamp_avg_stub(state internal, val vops_timestamp) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_timestamp_avg_extend(state internal, val vops_timestamp) returns internal as 'MODULE_PATHNAME','vops_int8_avg_extend' language C parallel safe;
create function vops_timestamp_avg_reduce(state internal, val vops_timestamp) returns internal as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mavg(vops_timestamp) (
	SFUNC = vops_timestamp_avg_stub,
	STYPE = internal,
	FINALFUNC = vops_mavg_final,
    mstype = internal,
    msfunc = vops_timestamp_avg_extend,
    minvfunc = vops_timestamp_avg_reduce,
	mfinalfunc = vops_mavg_final,
	PARALLEL = SAFE
);

create function vops_timestamp_max_accumulate(state timestamp, val vops_timestamp) returns timestamp as 'MODULE_PATHNAME','vops_int8_max_accumulate' language C parallel safe;
CREATE AGGREGATE max(vops_timestamp) (
	SFUNC = vops_timestamp_max_accumulate,
	STYPE = timestamp,
    COMBINEFUNC = timestamp_larger,
	PARALLEL = SAFE
);
create function vops_timestamp_max_stub(state vops_timestamp, val vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_timestamp_max_extend(state vops_timestamp, val vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_max_extend' language C parallel safe;
create function vops_timestamp_max_reduce(state vops_timestamp, val vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mmax(vops_timestamp) (
	SFUNC = vops_timestamp_max_stub,
	STYPE = vops_timestamp,
    mstype = vops_timestamp,
    msfunc = vops_timestamp_max_extend,
    minvfunc = vops_timestamp_max_reduce,
	PARALLEL = SAFE
);

create function vops_timestamp_min_accumulate(state timestamp, val vops_timestamp) returns timestamp as 'MODULE_PATHNAME','vops_int8_min_accumulate' language C parallel safe;
CREATE AGGREGATE min(vops_timestamp) (
	SFUNC = vops_timestamp_min_accumulate,
	STYPE = timestamp,
    COMBINEFUNC = timestamp_smaller,
	PARALLEL = SAFE
);
create function vops_timestamp_min_stub(state vops_timestamp, val vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_timestamp_min_extend(state vops_timestamp, val vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_int8_min_extend' language C parallel safe;
create function vops_timestamp_min_reduce(state vops_timestamp, val vops_timestamp) returns vops_timestamp as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mmin(vops_timestamp) (
	SFUNC = vops_timestamp_min_stub,
	STYPE = vops_timestamp,
    mstype = vops_timestamp,
    msfunc = vops_timestamp_min_extend,
    minvfunc = vops_timestamp_min_reduce,
	PARALLEL = SAFE
);

create function vops_timestamp_lag_accumulate(state internal, val vops_timestamp) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_timestamp_lag_extend(state internal, val vops_timestamp) returns internal as 'MODULE_PATHNAME','vops_int8_lag_extend' language C parallel safe;
create function vops_timestamp_lag_reduce(state internal, val vops_timestamp) returns internal as 'MODULE_PATHNAME','vops_lag_reduce' language C parallel safe;
create function vops_timestamp_lag_final(state internal) returns vops_timestamp as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE lag(vops_timestamp) (
	SFUNC = vops_timestamp_lag_accumulate,
	STYPE = internal,
	finalfunc = vops_timestamp_lag_final,
    mstype = internal,
    msfunc = vops_timestamp_lag_extend,
    minvfunc = vops_timestamp_lag_reduce,
    mfinalfunc = vops_timestamp_lag_final,
	PARALLEL = SAFE
);

create function vops_timestamp_count_accumulate(state int8, val vops_timestamp) returns int8 as 'MODULE_PATHNAME','vops_count_any_accumulate' language C parallel safe strict;
CREATE AGGREGATE count(vops_timestamp) (
	SFUNC = vops_timestamp_count_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);
create function vops_timestamp_count_stub(state vops_int8, val vops_timestamp) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate'  language C parallel safe strict;
create function vops_timestamp_count_extend(state vops_int8, val vops_timestamp) returns vops_int8 as 'MODULE_PATHNAME','vops_count_any_extend' language C parallel safe strict;
create function vops_timestamp_count_reduce(state vops_int8, val vops_timestamp) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe strict;
CREATE AGGREGATE mcount(vops_timestamp) (
	SFUNC = vops_timestamp_count_stub,
	STYPE = vops_int8,
	initcond = '0', 
    mstype = vops_int8,
	msfunc = vops_timestamp_count_extend,
	minvfunc = vops_timestamp_count_reduce,
	minitcond = '0', 
	PARALLEL = SAFE
);

create function first(tile vops_timestamp) returns timestamp as 'MODULE_PATHNAME','vops_int8_first' language C parallel safe immutable strict;
create function last(tile vops_timestamp) returns timestamp as 'MODULE_PATHNAME','vops_int8_last' language C parallel safe immutable strict;
create function low(tile vops_timestamp) returns timestamp as 'MODULE_PATHNAME','vops_int8_low' language C parallel safe immutable strict;
create function high(tile vops_timestamp) returns timestamp as 'MODULE_PATHNAME','vops_int8_high' language C parallel safe immutable strict;

-- deltatime tile

create function vops_interval_const(opd deltatime) returns vops_interval as 'MODULE_PATHNAME','vops_int8_const' language C parallel safe immutable strict;
create cast (deltatime as vops_interval) with function vops_interval_const(deltatime) AS IMPLICIT;

create function vops_interval_group_by(state internal, group_by vops_interval, aggregates cstring, variadic anyarray) returns internal as 'MODULE_PATHNAME','vops_int8_group_by' language C immutable;
create aggregate map(group_by vops_interval, aggregates cstring, variadic anyarray) (
	   sfunc = vops_interval_group_by, 
	   stype = internal,
	   finalfunc=vops_agg_final,
	   combinefunc = vops_agg_combine,
	   serialfunc = vops_agg_serial,
	   deserialfunc = vops_agg_deserial,
	   parallel = safe);

create function vops_interval_sub(left vops_interval, right vops_interval) returns vops_interval as 'MODULE_PATHNAME','vops_int8_sub' language C parallel safe immutable strict;
create function vops_interval_sub_rconst(left vops_interval, right deltatime) returns vops_interval as 'MODULE_PATHNAME','vops_int8_sub_rconst' language C parallel safe immutable strict;
create function vops_interval_sub_lconst(left deltatime, right vops_interval) returns vops_interval as 'MODULE_PATHNAME','vops_int8_sub_lconst' language C parallel safe immutable strict;
create operator - (leftarg=vops_interval, rightarg=vops_interval, procedure=vops_interval_sub);
create operator - (leftarg=vops_interval, rightarg=deltatime, procedure=vops_interval_sub_rconst);
create operator - (leftarg=deltatime, rightarg=vops_interval, procedure=vops_interval_sub_lconst);

create function vops_interval_add(left vops_interval, right vops_interval) returns vops_interval as 'MODULE_PATHNAME','vops_int8_add' language C parallel safe immutable strict;
create function vops_interval_add_rconst(left vops_interval, right deltatime) returns vops_interval as 'MODULE_PATHNAME','vops_int8_add_rconst' language C parallel safe immutable strict;
create function vops_interval_add_lconst(left deltatime, right vops_interval) returns vops_interval as 'MODULE_PATHNAME','vops_int8_add_lconst' language C parallel safe immutable strict;
create operator + (leftarg=vops_interval, rightarg=vops_interval, procedure=vops_interval_add, commutator= +);
create operator + (leftarg=vops_interval, rightarg=deltatime, procedure=vops_interval_add_rconst, commutator= +);
create operator + (leftarg=deltatime, rightarg=vops_interval, procedure=vops_interval_add_lconst, commutator= +);

create function vops_interval_int_mul(left vops_interval, right vops_int8) returns vops_interval as 'MODULE_PATHNAME','vops_int8_mul' language C parallel safe immutable strict;
create function vops_int_interval_mul(left vops_int8, right vops_interval) returns vops_interval as 'MODULE_PATHNAME','vops_int8_mul' language C parallel safe immutable strict;
create function vops_interval_mul_rconst(left vops_interval, right int8) returns vops_interval as 'MODULE_PATHNAME','vops_int8_mul_rconst' language C parallel safe immutable strict;
create function vops_interval_mul_lconst(left int8, right vops_interval) returns vops_interval as 'MODULE_PATHNAME','vops_int8_mul_lconst' language C parallel safe immutable strict;
create operator * (leftarg=vops_int8, rightarg=vops_interval, procedure=vops_int_interval_mul, commutator= *);
create operator * (leftarg=vops_interval, rightarg=vops_int8, procedure=vops_interval_int_mul, commutator= *);
create operator * (leftarg=vops_interval, rightarg=int8, procedure=vops_interval_mul_rconst, commutator= *);
create operator * (leftarg=int8, rightarg=vops_interval, procedure=vops_interval_mul_lconst, commutator= *);

create function vops_interval_div(left vops_interval, right vops_interval) returns vops_int8 as 'MODULE_PATHNAME','vops_int8_div' language C parallel safe immutable strict;
create function vops_interval_int_div(left vops_interval, right vops_int8) returns vops_interval as 'MODULE_PATHNAME','vops_int8_div' language C parallel safe immutable strict;
create function vops_interval_div_int_rconst(left vops_interval, right int8) returns vops_interval as 'MODULE_PATHNAME','vops_int8_div_rconst' language C parallel safe immutable strict;
create function vops_interval_div_rconst(left vops_interval, right deltatime) returns vops_int8 as 'MODULE_PATHNAME','vops_int8_div_rconst' language C parallel safe immutable strict;
create function vops_interval_div_lconst(left deltatime, right vops_interval) returns vops_int8 as 'MODULE_PATHNAME','vops_int8_div_lconst' language C parallel safe immutable strict;
create operator / (leftarg=vops_interval, rightarg=vops_interval, procedure=vops_interval_div);
create operator / (leftarg=vops_interval, rightarg=vops_int8, procedure=vops_interval_int_div);
create operator / (leftarg=vops_interval, rightarg=int8, procedure=vops_interval_div_int_rconst);
create operator / (leftarg=vops_interval, rightarg=deltatime, procedure=vops_interval_div_rconst);
create operator / (leftarg=deltatime, rightarg=vops_interval, procedure=vops_interval_div_lconst);

create function vops_interval_rem(left vops_interval, right vops_interval) returns vops_int8 as 'MODULE_PATHNAME','vops_int8_rem' language C parallel safe immutable strict;
create function vops_interval_int_rem(left vops_interval, right vops_int8) returns vops_interval as 'MODULE_PATHNAME','vops_int8_rem' language C parallel safe immutable strict;
create function vops_interval_rem_int_rconst(left vops_interval, right int8) returns vops_interval as 'MODULE_PATHNAME','vops_int8_rem_rconst' language C parallel safe immutable strict;
create function vops_interval_rem_rconst(left vops_interval, right deltatime) returns vops_int8 as 'MODULE_PATHNAME','vops_int8_rem_rconst' language C parallel safe immutable strict;
create function vops_interval_rem_lconst(left deltatime, right vops_interval) returns vops_int8 as 'MODULE_PATHNAME','vops_int8_rem_lconst' language C parallel safe immutable strict;
create operator % (leftarg=vops_interval, rightarg=vops_interval, procedure=vops_interval_rem);
create operator % (leftarg=vops_interval, rightarg=vops_int8, procedure=vops_interval_int_rem);
create operator % (leftarg=vops_interval, rightarg=int8, procedure=vops_interval_rem_int_rconst);
create operator % (leftarg=vops_interval, rightarg=deltatime, procedure=vops_interval_rem_rconst);
create operator % (leftarg=deltatime, rightarg=vops_interval, procedure=vops_interval_rem_lconst);

create function vops_interval_eq(left vops_interval, right vops_interval) returns vops_bool as 'MODULE_PATHNAME','vops_int8_eq' language C parallel safe immutable strict;
create function vops_interval_eq_rconst(left vops_interval, right deltatime) returns vops_bool as 'MODULE_PATHNAME','vops_int8_eq_rconst' language C parallel safe immutable strict;
create function vops_interval_eq_lconst(left deltatime, right vops_interval) returns vops_bool as 'MODULE_PATHNAME','vops_int8_eq_lconst' language C parallel safe immutable strict;
create operator = (leftarg=vops_interval, rightarg=vops_interval, procedure=vops_interval_eq, commutator= =);
create operator = (leftarg=vops_interval, rightarg=deltatime, procedure=vops_interval_eq_rconst, commutator= =);
create operator = (leftarg=deltatime, rightarg=vops_interval, procedure=vops_interval_eq_lconst, commutator= =);

create function vops_interval_ne(left vops_interval, right vops_interval) returns vops_bool as 'MODULE_PATHNAME','vops_int8_ne' language C parallel safe immutable strict;
create function vops_interval_ne_rconst(left vops_interval, right deltatime) returns vops_bool as 'MODULE_PATHNAME','vops_int8_ne_rconst' language C parallel safe immutable strict;
create function vops_interval_ne_lconst(left deltatime, right vops_interval) returns vops_bool as 'MODULE_PATHNAME','vops_int8_ne_lconst' language C parallel safe immutable strict;
create operator <> (leftarg=vops_interval, rightarg=vops_interval, procedure=vops_interval_ne, commutator= <>);
create operator <> (leftarg=vops_interval, rightarg=deltatime, procedure=vops_interval_ne_rconst, commutator= <>);
create operator <> (leftarg=deltatime, rightarg=vops_interval, procedure=vops_interval_ne_lconst, commutator= <>);

create function vops_interval_gt(left vops_interval, right vops_interval) returns vops_bool as 'MODULE_PATHNAME','vops_int8_gt' language C parallel safe immutable strict;
create function vops_interval_gt_rconst(left vops_interval, right deltatime) returns vops_bool as 'MODULE_PATHNAME','vops_int8_gt_rconst' language C parallel safe immutable strict;
create function vops_interval_gt_lconst(left deltatime, right vops_interval) returns vops_bool as 'MODULE_PATHNAME','vops_int8_gt_lconst' language C parallel safe immutable strict;
create operator > (leftarg=vops_interval, rightarg=vops_interval, procedure=vops_interval_gt, commutator= <);
create operator > (leftarg=vops_interval, rightarg=deltatime, procedure=vops_interval_gt_rconst, commutator= <);
create operator > (leftarg=deltatime, rightarg=vops_interval, procedure=vops_interval_gt_lconst, commutator= <);

create function vops_interval_lt(left vops_interval, right vops_interval) returns vops_bool as 'MODULE_PATHNAME','vops_int8_lt' language C parallel safe immutable strict;
create function vops_interval_lt_rconst(left vops_interval, right deltatime) returns vops_bool as 'MODULE_PATHNAME','vops_int8_lt_rconst' language C parallel safe immutable strict;
create function vops_interval_lt_lconst(left deltatime, right vops_interval) returns vops_bool as 'MODULE_PATHNAME','vops_int8_lt_lconst' language C parallel safe immutable strict;
create operator < (leftarg=vops_interval, rightarg=vops_interval, procedure=vops_interval_lt, commutator= >);
create operator < (leftarg=vops_interval, rightarg=deltatime, procedure=vops_interval_lt_rconst, commutator= >);
create operator < (leftarg=deltatime, rightarg=vops_interval, procedure=vops_interval_lt_lconst, commutator= >);

create function vops_interval_ge(left vops_interval, right vops_interval) returns vops_bool as 'MODULE_PATHNAME','vops_int8_ge' language C parallel safe immutable strict;
create function vops_interval_ge_rconst(left vops_interval, right deltatime) returns vops_bool as 'MODULE_PATHNAME','vops_int8_ge_rconst' language C parallel safe immutable strict;
create function vops_interval_ge_lconst(left deltatime, right vops_interval) returns vops_bool as 'MODULE_PATHNAME','vops_int8_ge_lconst' language C parallel safe immutable strict;
create operator >= (leftarg=vops_interval, rightarg=vops_interval, procedure=vops_interval_ge, commutator= <=);
create operator >= (leftarg=vops_interval, rightarg=deltatime, procedure=vops_interval_ge_rconst, commutator= <=);
create operator >= (leftarg=deltatime, rightarg=vops_interval, procedure=vops_interval_ge_lconst, commutator= <=);

create function vops_interval_le(left vops_interval, right vops_interval) returns vops_bool as 'MODULE_PATHNAME','vops_int8_le' language C parallel safe immutable strict;
create function vops_interval_le_rconst(left vops_interval, right deltatime) returns vops_bool as 'MODULE_PATHNAME','vops_int8_le_rconst' language C parallel safe immutable strict;
create function vops_interval_le_lconst(left deltatime, right vops_interval) returns vops_bool as 'MODULE_PATHNAME','vops_int8_le_lconst' language C parallel safe immutable strict;
create operator <= (leftarg=vops_interval, rightarg=vops_interval, procedure=vops_interval_le, commutator= >=);
create operator <= (leftarg=vops_interval, rightarg=deltatime, procedure=vops_interval_le_rconst, commutator= >=);
create operator <= (leftarg=deltatime, rightarg=vops_interval, procedure=vops_interval_le_lconst, commutator= >=);

create function betwixt(opd vops_interval, low deltatime, high deltatime) returns vops_bool as 'MODULE_PATHNAME','vops_betwixt_int8' language C parallel safe immutable strict;

create function ifnull(opd vops_interval, subst deltatime) returns vops_interval as 'MODULE_PATHNAME','vops_ifnull_int8' language C parallel safe immutable strict;
create function ifnull(opd vops_interval, subst vops_interval) returns vops_interval as 'MODULE_PATHNAME','vops_coalesce_int8' language C parallel safe immutable strict;

create function vops_interval_neg(right vops_interval) returns vops_interval as 'MODULE_PATHNAME','vops_int8_neg' language C parallel safe immutable strict;
create operator - (rightarg=vops_interval, procedure=vops_interval_neg);

create function vops_interval_sum_accumulate(state int8, val vops_interval) returns int8 as 'MODULE_PATHNAME','vops_int8_sum_accumulate' language C parallel safe;
CREATE AGGREGATE sum(vops_interval) (
	SFUNC = vops_interval_sum_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	PARALLEL = SAFE
);
create function vops_interval_sum_stub(state vops_int8, val vops_interval) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_interval_sum_extend(state vops_int8, val vops_interval) returns vops_int8 as 'MODULE_PATHNAME','vops_int8_sum_extend' language C parallel safe;
create function vops_interval_sum_reduce(state vops_int8, val vops_interval) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE msum(vops_interval) (
	SFUNC = vops_interval_sum_stub,
	STYPE = vops_int8,
    mstype = vops_int8,
	msfunc = vops_interval_sum_extend,
	minvfunc = vops_interval_sum_reduce,
	PARALLEL = SAFE
);

create function vops_interval_msum_stub(state internal, val vops_interval, winsize integer) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_interval_msum_extend(state internal, val vops_interval, winsize integer) returns internal as 'MODULE_PATHNAME','vops_int8_msum_extend' language C parallel safe;
create function vops_interval_msum_reduce(state internal, val vops_interval, winsize integer) returns internal as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
create function vops_interval_msum_final(state internal) returns vops_int8 as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE msum(vops_interval,winsize integer) (
	SFUNC = vops_interval_msum_stub,
	STYPE = internal,
	finalfunc = vops_interval_msum_final,
    mstype = internal,
	msfunc = vops_interval_msum_extend,
	minvfunc = vops_interval_msum_reduce,
	mfinalfunc = vops_interval_msum_final,
	PARALLEL = SAFE
);

create function vops_interval_var_accumulate(state internal, val vops_interval) returns internal as 'MODULE_PATHNAME','vops_int8_var_accumulate' language C parallel safe;
CREATE AGGREGATE var_pop(vops_interval) (
	SFUNC = vops_interval_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_pop_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE var_samp(vops_interval) (
	SFUNC = vops_interval_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE variance(vops_interval) (
	SFUNC = vops_interval_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev_pop(vops_interval) (
	SFUNC = vops_interval_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_pop_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev_samp(vops_interval) (
	SFUNC = vops_interval_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev(vops_interval) (
	SFUNC = vops_interval_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

create function vops_interval_wavg_accumulate(state internal, x vops_interval, y vops_interval) returns internal as 'MODULE_PATHNAME','vops_int8_wavg_accumulate' language C parallel safe;
CREATE AGGREGATE wavg(vops_interval, vops_interval) (
	SFUNC = vops_interval_wavg_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_wavg_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

create function vops_interval_avg_accumulate(state internal, val vops_interval) returns internal as 'MODULE_PATHNAME','vops_int8_avg_accumulate' language C parallel safe;
CREATE AGGREGATE avg(vops_interval) (
	SFUNC = vops_interval_avg_accumulate,
	STYPE = internal,
	SSPACE = 16,
	FINALFUNC = vops_avg_final,
	COMBINEFUNC = vops_avg_combine,
	SERIALFUNC = vops_avg_serial,
	DESERIALFUNC = vops_avg_deserial,
	PARALLEL = SAFE
);
create function vops_interval_avg_stub(state internal, val vops_interval) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_interval_avg_extend(state internal, val vops_interval) returns internal as 'MODULE_PATHNAME','vops_int8_avg_extend' language C parallel safe;
create function vops_interval_avg_reduce(state internal, val vops_interval) returns internal as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mavg(vops_interval) (
	SFUNC = vops_interval_avg_stub,
	STYPE = internal,
	FINALFUNC = vops_mavg_final,
    mstype = internal,
    msfunc = vops_interval_avg_extend,
    minvfunc = vops_interval_avg_reduce,
	mfinalfunc = vops_mavg_final,
	PARALLEL = SAFE
);

create function vops_interval_max_accumulate(state int8, val vops_interval) returns int8 as 'MODULE_PATHNAME','vops_int8_max_accumulate' language C parallel safe;
CREATE AGGREGATE max(vops_interval) (
	SFUNC = vops_interval_max_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8larger,
	PARALLEL = SAFE
);
create function vops_interval_max_stub(state vops_interval, val vops_interval) returns vops_interval as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_interval_max_extend(state vops_interval, val vops_interval) returns vops_interval as 'MODULE_PATHNAME','vops_int8_max_extend' language C parallel safe;
create function vops_interval_max_reduce(state vops_interval, val vops_interval) returns vops_interval as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mmax(vops_interval) (
	SFUNC = vops_interval_max_stub,
	STYPE = vops_interval,
    mstype = vops_interval,
    msfunc = vops_interval_max_extend,
    minvfunc = vops_interval_max_reduce,
	PARALLEL = SAFE
);

create function vops_interval_min_accumulate(state int8, val vops_interval) returns int8 as 'MODULE_PATHNAME','vops_int8_min_accumulate' language C parallel safe;
CREATE AGGREGATE min(vops_interval) (
	SFUNC = vops_interval_min_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8smaller,
	PARALLEL = SAFE
);
create function vops_interval_min_stub(state vops_interval, val vops_interval) returns vops_interval as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_interval_min_extend(state vops_interval, val vops_interval) returns vops_interval as 'MODULE_PATHNAME','vops_int8_min_extend' language C parallel safe;
create function vops_interval_min_reduce(state vops_interval, val vops_interval) returns vops_interval as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mmin(vops_interval) (
	SFUNC = vops_interval_min_stub,
	STYPE = vops_interval,
    mstype = vops_interval,
    msfunc = vops_interval_min_extend,
    minvfunc = vops_interval_min_reduce,
	PARALLEL = SAFE
);

create function vops_interval_lag_accumulate(state internal, val vops_interval) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_interval_lag_extend(state internal, val vops_interval) returns internal as 'MODULE_PATHNAME','vops_int8_lag_extend' language C parallel safe;
create function vops_interval_lag_reduce(state internal, val vops_interval) returns internal as 'MODULE_PATHNAME','vops_lag_reduce' language C parallel safe;
create function vops_interval_lag_final(state internal) returns vops_interval as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE lag(vops_interval) (
	SFUNC = vops_interval_lag_accumulate,
	STYPE = internal,
	finalfunc = vops_interval_lag_final,
    mstype = internal,
    msfunc = vops_interval_lag_extend,
    minvfunc = vops_interval_lag_reduce,
    mfinalfunc = vops_interval_lag_final,
	PARALLEL = SAFE
);

create function vops_interval_count_accumulate(state int8, val vops_interval) returns int8 as 'MODULE_PATHNAME','vops_count_any_accumulate' language C parallel safe strict;
CREATE AGGREGATE count(vops_interval) (
	SFUNC = vops_interval_count_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);
create function vops_interval_count_stub(state vops_int8, val vops_interval) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate'  language C parallel safe strict;
create function vops_interval_count_extend(state vops_int8, val vops_interval) returns vops_int8 as 'MODULE_PATHNAME','vops_count_any_extend' language C parallel safe strict;
create function vops_interval_count_reduce(state vops_int8, val vops_interval) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe strict;
CREATE AGGREGATE mcount(vops_interval) (
	SFUNC = vops_interval_count_stub,
	STYPE = vops_int8,
	initcond = '0', 
    mstype = vops_int8,
	msfunc = vops_interval_count_extend,
	minvfunc = vops_interval_count_reduce,
	minitcond = '0', 
	PARALLEL = SAFE
);

create function vops_interval_first_accumulate(state internal, val vops_interval, ts vops_timestamp) returns internal as 'MODULE_PATHNAME','vops_int8_first_accumulate' language C parallel safe;
create function vops_interval_first_final(state internal) returns int8 as 'MODULE_PATHNAME','vops_first_final' language C parallel safe;
CREATE AGGREGATE first(vops_interval,vops_timestamp) (
	SFUNC = vops_interval_first_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_interval_first_final,
 	COMBINEFUNC = vops_first_combine,
	PARALLEL = SAFE
);

create function vops_interval_last_accumulate(state internal, val vops_interval, ts vops_timestamp) returns internal as 'MODULE_PATHNAME','vops_int8_last_accumulate' language C parallel safe;
CREATE AGGREGATE last(vops_interval,vops_timestamp) (
	SFUNC = vops_interval_last_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_interval_first_final,
 	COMBINEFUNC = vops_last_combine,
	PARALLEL = SAFE
);

create function first(tile vops_interval) returns deltatime as 'MODULE_PATHNAME','vops_int8_first' language C parallel safe immutable strict;
create function last(tile vops_interval) returns deltatime as 'MODULE_PATHNAME','vops_int8_last' language C parallel safe immutable strict;
create function low(tile vops_interval) returns deltatime as 'MODULE_PATHNAME','vops_int8_low' language C parallel safe immutable strict;
create function high(tile vops_interval) returns deltatime as 'MODULE_PATHNAME','vops_int8_high' language C parallel safe immutable strict;

-- int8 tile

create function vops_int8_const(opd int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create cast (int8 as vops_int8) with function vops_int8_const(int8) AS IMPLICIT;

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
create operator + (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_add, commutator= +);
create operator + (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_add_rconst, commutator= +);
create operator + (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_add_lconst, commutator= +);

create function vops_int8_mul(left vops_int8, right vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_mul_rconst(left vops_int8, right int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_mul_lconst(left int8, right vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator * (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_mul, commutator= *);
create operator * (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_mul_rconst, commutator= *);
create operator * (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_mul_lconst, commutator= *);

create function vops_int8_div(left vops_int8, right vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_div_rconst(left vops_int8, right int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_div_lconst(left int8, right vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator / (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_div);
create operator / (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_div_rconst);
create operator / (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_div_lconst);

create function vops_int8_rem(left vops_int8, right vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_rem_rconst(left vops_int8, right int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_rem_lconst(left int8, right vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator % (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_rem);
create operator % (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_rem_rconst);
create operator % (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_rem_lconst);

create function vops_int8_eq(left vops_int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_eq_rconst(left vops_int8, right int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_eq_lconst(left int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator = (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_eq, commutator= =);
create operator = (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_eq_rconst, commutator= =);
create operator = (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_eq_lconst, commutator= =);

create function vops_int8_ne(left vops_int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_ne_rconst(left vops_int8, right int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_ne_lconst(left int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <> (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_ne, commutator= <>);
create operator <> (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_ne_rconst, commutator= <>);
create operator <> (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_ne_lconst, commutator= <>);

create function vops_int8_gt(left vops_int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_gt_rconst(left vops_int8, right int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_gt_lconst(left int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator > (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_gt, commutator= <);
create operator > (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_gt_rconst, commutator= <);
create operator > (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_gt_lconst, commutator= <);

create function vops_int8_lt(left vops_int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_lt_rconst(left vops_int8, right int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_lt_lconst(left int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator < (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_lt, commutator= >);
create operator < (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_lt_rconst, commutator= >);
create operator < (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_lt_lconst, commutator= >);

create function vops_int8_ge(left vops_int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_ge_rconst(left vops_int8, right int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_ge_lconst(left int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator >= (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_ge, commutator= <=);
create operator >= (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_ge_rconst, commutator= <=);
create operator >= (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_ge_lconst, commutator= <=);

create function vops_int8_le(left vops_int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_le_rconst(left vops_int8, right int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_int8_le_lconst(left int8, right vops_int8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <= (leftarg=vops_int8, rightarg=vops_int8, procedure=vops_int8_le, commutator= >=);
create operator <= (leftarg=vops_int8, rightarg=int8, procedure=vops_int8_le_rconst, commutator= >=);
create operator <= (leftarg=int8, rightarg=vops_int8, procedure=vops_int8_le_lconst, commutator= >=);

create function betwixt(opd vops_int8, low int8, high int8) returns vops_bool as 'MODULE_PATHNAME','vops_betwixt_int8' language C parallel safe immutable strict;

create function ifnull(opd vops_int8, subst int8) returns vops_int8 as 'MODULE_PATHNAME','vops_ifnull_int8' language C parallel safe immutable strict;
create function ifnull(opd vops_int8, subst vops_int8) returns vops_int8 as 'MODULE_PATHNAME','vops_coalesce_int8' language C parallel safe immutable strict;

create function vops_int8_neg(right vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (rightarg=vops_int8, procedure=vops_int8_neg);


create function vops_int8_sum_accumulate(state int8, val vops_int8) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE sum(vops_int8) (
	SFUNC = vops_int8_sum_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	PARALLEL = SAFE
);
create function vops_int8_sum_stub(state vops_int8, val vops_int8) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_int8_sum_extend(state vops_int8, val vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int8_sum_reduce(state vops_int8, val vops_int8) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE msum(vops_int8) (
	SFUNC = vops_int8_sum_stub,
	STYPE = vops_int8,
    mstype = vops_int8,
	msfunc = vops_int8_sum_extend,
	minvfunc = vops_int8_sum_reduce,
	PARALLEL = SAFE
);

create function vops_int8_msum_stub(state internal, val vops_int8, winsize integer) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_int8_msum_extend(state internal, val vops_int8, winsize integer) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int8_msum_reduce(state internal, val vops_int8, winsize integer) returns internal as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
create function vops_int8_msum_final(state internal) returns vops_int8 as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE msum(vops_int8,winsize integer) (
	SFUNC = vops_int8_msum_stub,
	STYPE = internal,
	finalfunc = vops_int8_msum_final,
    mstype = internal,
	msfunc = vops_int8_msum_extend,
	minvfunc = vops_int8_msum_reduce,
	mfinalfunc = vops_int8_msum_final,
	PARALLEL = SAFE
);


create function vops_int8_var_accumulate(state internal, val vops_int8) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE var_pop(vops_int8) (
	SFUNC = vops_int8_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_pop_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE var_samp(vops_int8) (
	SFUNC = vops_int8_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE variance(vops_int8) (
	SFUNC = vops_int8_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev_pop(vops_int8) (
	SFUNC = vops_int8_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_pop_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev_samp(vops_int8) (
	SFUNC = vops_int8_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev(vops_int8) (
	SFUNC = vops_int8_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

create function vops_int8_wavg_accumulate(state internal, x vops_int8, y vops_int8) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE wavg(vops_int8, vops_int8) (
	SFUNC = vops_int8_wavg_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_wavg_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

create function vops_int8_avg_accumulate(state internal, val vops_int8) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE avg(vops_int8) (
	SFUNC = vops_int8_avg_accumulate,
	STYPE = internal,
	SSPACE = 16,
	FINALFUNC = vops_avg_final,
	COMBINEFUNC = vops_avg_combine,
	SERIALFUNC = vops_avg_serial,
	DESERIALFUNC = vops_avg_deserial,
	PARALLEL = SAFE
);
create function vops_int8_avg_stub(state internal, val vops_int8) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_int8_avg_extend(state internal, val vops_int8) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int8_avg_reduce(state internal, val vops_int8) returns internal as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mavg(vops_int8) (
	SFUNC = vops_int8_avg_stub,
	STYPE = internal,
	FINALFUNC = vops_mavg_final,
    mstype = internal,
    msfunc = vops_int8_avg_extend,
    minvfunc = vops_int8_avg_reduce,
	mfinalfunc = vops_mavg_final,
	PARALLEL = SAFE
);

create function vops_int8_max_accumulate(state int8, val vops_int8) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE max(vops_int8) (
	SFUNC = vops_int8_max_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8larger,
	PARALLEL = SAFE
);
create function vops_int8_max_stub(state vops_int8, val vops_int8) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_int8_max_extend(state vops_int8, val vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int8_max_reduce(state vops_int8, val vops_int8) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mmax(vops_int8) (
	SFUNC = vops_int8_max_stub,
	STYPE = vops_int8,
    mstype = vops_int8,
    msfunc = vops_int8_max_extend,
    minvfunc = vops_int8_max_reduce,
	PARALLEL = SAFE
);

create function vops_int8_min_accumulate(state int8, val vops_int8) returns int8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE min(vops_int8) (
	SFUNC = vops_int8_min_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8smaller,
	PARALLEL = SAFE
);
create function vops_int8_min_stub(state vops_int8, val vops_int8) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_int8_min_extend(state vops_int8, val vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int8_min_reduce(state vops_int8, val vops_int8) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mmin(vops_int8) (
	SFUNC = vops_int8_min_stub,
	STYPE = vops_int8,
    mstype = vops_int8,
    msfunc = vops_int8_min_extend,
    minvfunc = vops_int8_min_reduce,
	PARALLEL = SAFE
);

create function vops_int8_lag_accumulate(state internal, val vops_int8) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_int8_lag_extend(state internal, val vops_int8) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int8_lag_reduce(state internal, val vops_int8) returns internal as 'MODULE_PATHNAME','vops_lag_reduce' language C parallel safe;
create function vops_int8_lag_final(state internal) returns vops_int8 as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE lag(vops_int8) (
	SFUNC = vops_int8_lag_accumulate,
	STYPE = internal,
	finalfunc = vops_int8_lag_final,
    mstype = internal,
    msfunc = vops_int8_lag_extend,
    minvfunc = vops_int8_lag_reduce,
    mfinalfunc = vops_int8_lag_final,
 	PARALLEL = SAFE
);

create function vops_int8_count_accumulate(state int8, val vops_int8) returns int8 as 'MODULE_PATHNAME','vops_count_any_accumulate' language C parallel safe strict;
CREATE AGGREGATE count(vops_int8) (
	SFUNC = vops_int8_count_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);
create function vops_int8_count_stub(state vops_int8, val vops_int8) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe strict;
create function vops_int8_count_extend(state vops_int8, val vops_int8) returns vops_int8 as 'MODULE_PATHNAME','vops_count_any_extend' language C parallel safe strict;
create function vops_int8_count_reduce(state vops_int8, val vops_int8) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe strict;
CREATE AGGREGATE mcount(vops_int8) (
	SFUNC = vops_int8_count_stub,
	STYPE = vops_int8,
	initcond = '0', 
    mstype = vops_int8,
	msfunc = vops_int8_count_extend,
	minvfunc = vops_int8_count_reduce,
	minitcond = '0', 
	PARALLEL = SAFE
);

create function vops_int8_first_accumulate(state internal, val vops_int8, ts vops_timestamp) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_int8_first_final(state internal) returns int8 as 'MODULE_PATHNAME','vops_first_final' language C parallel safe;
CREATE AGGREGATE first(vops_int8,vops_timestamp) (
	SFUNC = vops_int8_first_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_int8_first_final,
 	COMBINEFUNC = vops_first_combine,
	PARALLEL = SAFE
);

create function vops_int8_last_accumulate(state internal, val vops_int8, ts vops_timestamp) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE last(vops_int8,vops_timestamp) (
	SFUNC = vops_int8_last_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_int8_first_final,
 	COMBINEFUNC = vops_last_combine,
	PARALLEL = SAFE
);

create function first(tile vops_int8) returns int8 as 'MODULE_PATHNAME','vops_int8_first' language C parallel safe immutable strict;
create function last(tile vops_int8) returns int8 as 'MODULE_PATHNAME','vops_int8_last' language C parallel safe immutable strict;
create function low(tile vops_int8) returns int8 as 'MODULE_PATHNAME','vops_int8_low' language C parallel safe immutable strict;
create function high(tile vops_int8) returns int8 as 'MODULE_PATHNAME','vops_int8_high' language C parallel safe immutable strict;

-- float4 tile

create function vops_float4_const(opd float8) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create cast (float8 as vops_float4) with function vops_float4_const(float8) AS IMPLICIT;

create function vops_float4_sub(left vops_float4, right vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_sub_rconst(left vops_float4, right float8) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_sub_lconst(left float8, right vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_sub);
create operator - (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_sub_rconst);
create operator - (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_sub_lconst);

create function vops_float4_add(left vops_float4, right vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_add_rconst(left vops_float4, right float8) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_add_lconst(left float8, right vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator + (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_add, commutator= +);
create operator + (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_add_rconst, commutator= +);
create operator + (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_add_lconst, commutator= +);

create function vops_float4_mul(left vops_float4, right vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_mul_rconst(left vops_float4, right float8) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_mul_lconst(left float8, right vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator * (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_mul, commutator= *);
create operator * (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_mul_rconst, commutator= *);
create operator * (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_mul_lconst, commutator= *);

create function vops_float4_div(left vops_float4, right vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_div_rconst(left vops_float4, right float8) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_div_lconst(left float8, right vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator / (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_div);
create operator / (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_div_rconst);
create operator / (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_div_lconst);

create function vops_float4_eq(left vops_float4, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_eq_rconst(left vops_float4, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_eq_lconst(left float8, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator = (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_eq, commutator= =);
create operator = (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_eq_rconst, commutator= =);
create operator = (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_eq_lconst, commutator= =);

create function vops_float4_ne(left vops_float4, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_ne_rconst(left vops_float4, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_ne_lconst(left float8, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <> (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_ne, commutator= <>);
create operator <> (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_ne_rconst, commutator= <>);
create operator <> (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_ne_lconst, commutator= <>);

create function vops_float4_gt(left vops_float4, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_gt_rconst(left vops_float4, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_gt_lconst(left float8, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator > (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_gt, commutator= <);
create operator > (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_gt_rconst, commutator= <);
create operator > (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_gt_lconst, commutator= <);

create function vops_float4_lt(left vops_float4, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_lt_rconst(left vops_float4, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_lt_lconst(left float8, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator < (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_lt, commutator= >);
create operator < (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_lt_rconst, commutator= >);
create operator < (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_lt_lconst, commutator= >);

create function vops_float4_ge(left vops_float4, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_ge_rconst(left vops_float4, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_ge_lconst(left float8, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator >= (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_ge, commutator= <=);
create operator >= (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_ge_rconst, commutator= <=);
create operator >= (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_ge_lconst, commutator= <=);

create function vops_float4_le(left vops_float4, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_le_rconst(left vops_float4, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float4_le_lconst(left float8, right vops_float4) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <= (leftarg=vops_float4, rightarg=vops_float4, procedure=vops_float4_le, commutator= >=);
create operator <= (leftarg=vops_float4, rightarg=float8, procedure=vops_float4_le_rconst, commutator= >=);
create operator <= (leftarg=float8, rightarg=vops_float4, procedure=vops_float4_le_lconst, commutator= >=);

create function betwixt(opd vops_float4, low float8, high float8) returns vops_bool as 'MODULE_PATHNAME','vops_betwixt_float4' language C parallel safe immutable strict;

create function ifnull(opd vops_float4, subst float8) returns vops_float4 as 'MODULE_PATHNAME','vops_ifnull_float4' language C parallel safe immutable strict;
create function ifnull(opd vops_float4, subst vops_float4) returns vops_float4 as 'MODULE_PATHNAME','vops_coalesce_float4' language C parallel safe immutable strict;

create function vops_float4_neg(right vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (rightarg=vops_float4, procedure=vops_float4_neg);

create function vops_float4_sum_accumulate(state float8, val vops_float4) returns float8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE sum(vops_float4) (
	SFUNC = vops_float4_sum_accumulate,
	STYPE = float8,
    COMBINEFUNC = float8pl,
	PARALLEL = SAFE
);
create function vops_float4_sum_stub(state vops_float8, val vops_float4) returns vops_float8 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_float4_sum_extend(state vops_float8, val vops_float4) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe;
create function vops_float4_sum_reduce(state vops_float8, val vops_float4) returns vops_float8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE msum(vops_float4) (
	SFUNC = vops_float4_sum_stub,
	STYPE = vops_float8,
    mstype = vops_float8,
	msfunc = vops_float4_sum_extend,
	minvfunc = vops_float4_sum_reduce,
	PARALLEL = SAFE
);

create function vops_float4_msum_stub(state internal, val vops_float4, winsize integer) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_float4_msum_extend(state internal, val vops_float4, winsize integer) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_float4_msum_reduce(state internal, val vops_float4, winsize integer) returns internal as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
create function vops_float4_msum_final(state internal) returns vops_float8 as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE msum(vops_float4,winsize integer) (
	SFUNC = vops_float4_msum_stub,
	STYPE = internal,
	finalfunc = vops_float4_msum_final,
    mstype = internal,
	msfunc = vops_float4_msum_extend,
	minvfunc = vops_float4_msum_reduce,
	mfinalfunc = vops_float4_msum_final,
	PARALLEL = SAFE
);


create function vops_float4_var_accumulate(state internal, val vops_float4) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE var_pop(vops_float4) (
	SFUNC = vops_float4_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_pop_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE var_samp(vops_float4) (
	SFUNC = vops_float4_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE variance(vops_float4) (
	SFUNC = vops_float4_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev_pop(vops_float4) (
	SFUNC = vops_float4_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_pop_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev_samp(vops_float4) (
	SFUNC = vops_float4_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev(vops_float4) (
	SFUNC = vops_float4_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

create function vops_float4_wavg_accumulate(state internal, x vops_float4, y vops_float4) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE wavg(vops_float4,vops_float4) (
	SFUNC = vops_float4_wavg_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_wavg_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

create function vops_float4_avg_accumulate(state internal, val vops_float4) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE avg(vops_float4) (
	SFUNC = vops_float4_avg_accumulate,
	STYPE = internal,
	SSPACE = 16,
	FINALFUNC = vops_avg_final,
	COMBINEFUNC = vops_avg_combine,
	SERIALFUNC = vops_avg_serial,
	DESERIALFUNC = vops_avg_deserial,
	PARALLEL = SAFE
);
create function vops_float4_avg_stub(state internal, val vops_float4) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_float4_avg_extend(state internal, val vops_float4) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_float4_avg_reduce(state internal, val vops_float4) returns internal as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mavg(vops_float4) (
	SFUNC = vops_float4_avg_stub,
	STYPE = internal,
	FINALFUNC = vops_mavg_final,
    mstype = internal,
    msfunc = vops_float4_avg_extend,
    minvfunc = vops_float4_avg_reduce,
	mfinalfunc = vops_mavg_final,
	PARALLEL = SAFE
);

create function vops_float4_max_accumulate(state float4, val vops_float4) returns float4 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE max(vops_float4) (
	SFUNC = vops_float4_max_accumulate,
	STYPE = float4,
    COMBINEFUNC = float4larger,	
 	PARALLEL = SAFE
);
create function vops_float4_max_stub(state vops_float4, val vops_float4) returns vops_float4 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_float4_max_extend(state vops_float4, val vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe;
create function vops_float4_max_reduce(state vops_float4, val vops_float4) returns vops_float4 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mmax(vops_float4) (
	SFUNC = vops_float4_max_stub,
	STYPE = vops_float4,
    mstype = vops_float4,
    msfunc = vops_float4_max_extend,
    minvfunc = vops_float4_max_reduce,
 	PARALLEL = SAFE
);

create function vops_float4_min_accumulate(state float4, val vops_float4) returns float4 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE min(vops_float4) (
	SFUNC = vops_float4_min_accumulate,
	STYPE = float4,
    COMBINEFUNC = float4smaller,
	PARALLEL = SAFE
);
create function vops_float4_min_stub(state vops_float4, val vops_float4) returns vops_float4 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_float4_min_extend(state vops_float4, val vops_float4) returns vops_float4 as 'MODULE_PATHNAME' language C parallel safe;
create function vops_float4_min_reduce(state vops_float4, val vops_float4) returns vops_float4 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mmin(vops_float4) (
	SFUNC = vops_float4_min_stub,
	STYPE = vops_float4,
    mstype = vops_float4,
    msfunc = vops_float4_min_extend,
    minvfunc = vops_float4_min_reduce,
	PARALLEL = SAFE
);

create function vops_float4_lag_accumulate(state internal, val vops_float4) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_float4_lag_extend(state internal, val vops_float4) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_float4_lag_reduce(state internal, val vops_float4) returns internal as 'MODULE_PATHNAME','vops_lag_reduce' language C parallel safe;
create function vops_float4_lag_final(state internal) returns vops_float4 as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE lag(vops_float4) (
	SFUNC = vops_float4_lag_accumulate,
	STYPE = internal,
	finalfunc = vops_float4_lag_final,
    mstype = internal,
    msfunc = vops_float4_lag_extend,
    minvfunc = vops_float4_lag_reduce,
    mfinalfunc = vops_float4_lag_final,
	PARALLEL = SAFE
);

create function vops_float4_count_accumulate(state int8, val vops_float4) returns int8 as 'MODULE_PATHNAME','vops_count_any_accumulate' language C parallel safe strict;
CREATE AGGREGATE count(vops_float4) (
	SFUNC = vops_float4_count_accumulate,
	STYPE = int8,
    COMBINEFUNC = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);
create function vops_float4_count_stub(state vops_int8, val vops_float4) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate'  language C parallel safe strict;
create function vops_float4_count_extend(state vops_int8, val vops_float4) returns vops_int8 as 'MODULE_PATHNAME','vops_count_any_extend' language C parallel safe strict;
create function vops_float4_count_reduce(state vops_int8, val vops_float4) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe strict;
CREATE AGGREGATE mcount(vops_float4) (
	SFUNC = vops_float4_count_stub,
	STYPE = vops_int8,
	initcond = '0', 
    mstype = vops_int8,
	msfunc = vops_float4_count_extend,
	minvfunc = vops_float4_count_reduce,
	minitcond = '0', 
	PARALLEL = SAFE
);

create function vops_float4_first_accumulate(state internal, val vops_float4, ts vops_timestamp) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_float4_first_final(state internal) returns float4 as 'MODULE_PATHNAME','vops_first_final' language C parallel safe;
CREATE AGGREGATE first(vops_float4,vops_timestamp) (
	SFUNC = vops_float4_first_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_float4_first_final,
 	COMBINEFUNC = vops_first_combine,
	PARALLEL = SAFE
);

create function vops_float4_last_accumulate(state internal, val vops_float4, ts vops_timestamp) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE last(vops_float4,vops_timestamp) (
	SFUNC = vops_float4_last_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_float4_first_final,
 	COMBINEFUNC = vops_last_combine,
	PARALLEL = SAFE
);


create function first(tile vops_float4) returns float4 as 'MODULE_PATHNAME','vops_float4_first' language C parallel safe immutable strict;
create function last(tile vops_float4) returns float4 as 'MODULE_PATHNAME','vops_float4_last' language C parallel safe immutable strict;
create function low(tile vops_float4) returns float4 as 'MODULE_PATHNAME','vops_float4_low' language C parallel safe immutable strict;
create function high(tile vops_float4) returns float4 as 'MODULE_PATHNAME','vops_float4_high' language C parallel safe immutable strict;

-- float8 tile

create function vops_float8_const(opd float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create cast (float8 as vops_float8) with function vops_float8_const(float8) AS IMPLICIT;

create function vops_float8_sub(left vops_float8, right vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_sub_rconst(left vops_float8, right float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_sub_lconst(left float8, right vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_sub);
create operator - (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_sub_rconst);
create operator - (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_sub_lconst);

create function vops_float8_add(left vops_float8, right vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_add_rconst(left vops_float8, right float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_add_lconst(left float8, right vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator + (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_add, commutator= +);
create operator + (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_add_rconst, commutator= +);
create operator + (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_add_lconst, commutator= +);

create function vops_float8_mul(left vops_float8, right vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_mul_rconst(left vops_float8, right float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_mul_lconst(left float8, right vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator * (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_mul, commutator= *);
create operator * (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_mul_rconst, commutator= *);
create operator * (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_mul_lconst, commutator= *);

create function vops_float8_div(left vops_float8, right vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_div_rconst(left vops_float8, right float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_div_lconst(left float8, right vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator / (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_div);
create operator / (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_div_rconst);
create operator / (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_div_lconst);

create function vops_float8_eq(left vops_float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_eq_rconst(left vops_float8, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_eq_lconst(left float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator = (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_eq, commutator= =);
create operator = (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_eq_rconst, commutator= =);
create operator = (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_eq_lconst, commutator= =);

create function vops_float8_ne(left vops_float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_ne_rconst(left vops_float8, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_ne_lconst(left float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <> (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_ne, commutator= <>);
create operator <> (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_ne_rconst, commutator= <>);
create operator <> (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_ne_lconst, commutator= <>);

create function vops_float8_gt(left vops_float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_gt_rconst(left vops_float8, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_gt_lconst(left float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator > (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_gt, commutator= <);
create operator > (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_gt_rconst, commutator= <);
create operator > (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_gt_lconst, commutator= <);

create function vops_float8_lt(left vops_float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_lt_rconst(left vops_float8, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_lt_lconst(left float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator < (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_lt, commutator= >);
create operator < (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_lt_rconst, commutator= >);
create operator < (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_lt_lconst, commutator= >);

create function vops_float8_ge(left vops_float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_ge_rconst(left vops_float8, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_ge_lconst(left float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator >= (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_ge, commutator= <=);
create operator >= (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_ge_rconst, commutator= <=);
create operator >= (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_ge_lconst, commutator= <=);

create function vops_float8_le(left vops_float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_le_rconst(left vops_float8, right float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create function vops_float8_le_lconst(left float8, right vops_float8) returns vops_bool as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator <= (leftarg=vops_float8, rightarg=vops_float8, procedure=vops_float8_le, commutator= >=);
create operator <= (leftarg=vops_float8, rightarg=float8, procedure=vops_float8_le_rconst, commutator= >=);
create operator <= (leftarg=float8, rightarg=vops_float8, procedure=vops_float8_le_lconst, commutator= >=);

create function betwixt(opd vops_float8, low float8, high float8) returns vops_bool as 'MODULE_PATHNAME','vops_betwixt_float8' language C parallel safe immutable strict;

create function ifnull(opd vops_float8, subst float8) returns vops_float8 as 'MODULE_PATHNAME','vops_ifnull_float8' language C parallel safe immutable strict;
create function ifnull(opd vops_float8, subst vops_float8) returns vops_float8 as 'MODULE_PATHNAME','vops_coalesce_float8' language C parallel safe immutable strict;

create function vops_float8_neg(right vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe immutable strict;
create operator - (rightarg=vops_float8, procedure=vops_float8_neg);

create function vops_float8_sum_accumulate(state float8, val vops_float8) returns float8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE sum(vops_float8) (
	SFUNC = vops_float8_sum_accumulate,
	STYPE = float8,
    COMBINEFUNC = float8pl,
	PARALLEL = SAFE
);
create function vops_float8_sum_stub(state vops_float8, val vops_float8) returns vops_float8 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_float8_sum_extend(state vops_float8, val vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe;
create function vops_float8_sum_reduce(state vops_float8, val vops_float8) returns vops_float8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE msum(vops_float8) (
	SFUNC = vops_float8_sum_stub,
	STYPE = vops_float8,
    mstype = vops_float8,
	msfunc = vops_float8_sum_extend,
	minvfunc = vops_float8_sum_reduce,
	PARALLEL = SAFE
);

create function vops_float8_msum_stub(state internal, val vops_float8, winsize integer) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_float8_msum_extend(state internal, val vops_float8, winsize integer) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_float8_msum_reduce(state internal, val vops_float8, winsize integer) returns internal as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
create function vops_float8_msum_final(state internal) returns vops_float8 as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE msum(vops_float8,winsize integer) (
	SFUNC = vops_float8_msum_stub,
	STYPE = internal,
	finalfunc = vops_float8_msum_final,
    mstype = internal,
	msfunc = vops_float8_msum_extend,
	minvfunc = vops_float8_msum_reduce,
	mfinalfunc = vops_float8_msum_final,
	PARALLEL = SAFE
);


create function vops_float8_var_accumulate(state internal, val vops_float8) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE var_pop(vops_float8) (
	SFUNC = vops_float8_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_pop_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE var_samp(vops_float8) (
	SFUNC = vops_float8_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE variance(vops_float8) (
	SFUNC = vops_float8_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_var_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev_pop(vops_float8) (
	SFUNC = vops_float8_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_pop_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev_samp(vops_float8) (
	SFUNC = vops_float8_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

CREATE AGGREGATE stddev(vops_float8) (
	SFUNC = vops_float8_var_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_stddev_samp_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);

create function vops_float8_wavg_accumulate(state internal, x vops_float8, y vops_float8) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE wavg(vops_float8, vops_float8) (
	SFUNC = vops_float8_wavg_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_wavg_final,
	COMBINEFUNC = vops_var_combine,
	SERIALFUNC = vops_var_serial,
	DESERIALFUNC = vops_var_deserial,
	PARALLEL = SAFE
);


create function vops_float8_avg_accumulate(state internal, val vops_float8) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE avg(vops_float8) (
	SFUNC = vops_float8_avg_accumulate,
	STYPE = internal,
	SSPACE = 16,
	FINALFUNC = vops_avg_final,
	COMBINEFUNC = vops_avg_combine,
	SERIALFUNC = vops_avg_serial,
	DESERIALFUNC = vops_avg_deserial,
	PARALLEL = SAFE
);
create function vops_float8_avg_stub(state internal, val vops_float8) returns internal as 'MODULE_PATHNAME','vops_window_accumulate'  language C parallel safe;
create function vops_float8_avg_extend(state internal, val vops_float8) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_float8_avg_reduce(state internal, val vops_float8) returns internal as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mavg(vops_float8) (
	SFUNC = vops_float8_avg_stub,
	STYPE = internal,
	FINALFUNC = vops_mavg_final,
    mstype = internal,
    msfunc = vops_float8_avg_extend,
    minvfunc = vops_float8_avg_reduce,
	mfinalfunc = vops_mavg_final,
	PARALLEL = SAFE
);

create function vops_float8_max_accumulate(state float8, val vops_float8) returns float8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE max(vops_float8) (
	SFUNC = vops_float8_max_accumulate,
	STYPE = float8,
	COMBINEFUNC  = float8larger,
	PARALLEL = SAFE
);
create function vops_float8_max_stub(state vops_float8, val vops_float8) returns vops_float8 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_float8_max_extend(state vops_float8, val vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe;
create function vops_float8_max_reduce(state vops_float8, val vops_float8) returns vops_float8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mmax(vops_float8) (
	SFUNC = vops_float8_max_stub,
	STYPE = vops_float8,
    mstype = vops_float8,
    msfunc = vops_float8_max_extend,
    minvfunc = vops_float8_max_reduce,
	PARALLEL = SAFE
);

create function vops_float8_min_accumulate(state float8, val vops_float8) returns float8 as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE min(vops_float8) (
	SFUNC = vops_float8_min_accumulate,
	STYPE = float8,
	COMBINEFUNC  = float8smaller,
	PARALLEL = SAFE
);
create function vops_float8_min_stub(state vops_float8, val vops_float8) returns vops_float8 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_float8_min_extend(state vops_float8, val vops_float8) returns vops_float8 as 'MODULE_PATHNAME' language C parallel safe;
create function vops_float8_min_reduce(state vops_float8, val vops_float8) returns vops_float8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe;
CREATE AGGREGATE mmin(vops_float8) (
	SFUNC = vops_float8_min_stub,
	STYPE = vops_float8,
    mstype = vops_float8,
    msfunc = vops_float8_min_extend,
    minvfunc = vops_float8_min_reduce,
	PARALLEL = SAFE
);

create function vops_float8_lag_accumulate(state internal, val vops_float8) returns internal as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe;
create function vops_float8_lag_extend(state internal, val vops_float8) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_float8_lag_reduce(state internal, val vops_float8) returns internal as 'MODULE_PATHNAME','vops_lag_reduce' language C parallel safe;
create function vops_float8_lag_final(state internal) returns vops_float8 as 'MODULE_PATHNAME','vops_win_final' language C parallel safe strict;
CREATE AGGREGATE lag(vops_float8) (
	SFUNC = vops_float8_lag_accumulate,
	STYPE = internal,
	finalfunc = vops_float8_lag_final,
    mstype = internal,
    msfunc = vops_float8_lag_extend,
    minvfunc = vops_float8_lag_reduce,
    mfinalfunc = vops_float8_lag_final,
	PARALLEL = SAFE
);

create function vops_float8_count_accumulate(state int8, val vops_float8) returns int8 as 'MODULE_PATHNAME','vops_count_any_accumulate' language C parallel safe strict;
CREATE AGGREGATE count(vops_float8) (
	SFUNC = vops_float8_count_accumulate,
	STYPE = int8,
	COMBINEFUNC = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);
create function vops_float8_count_stub(state vops_int8, val vops_float8) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate'  language C parallel safe strict;
create function vops_float8_count_extend(state vops_int8, val vops_float8) returns vops_int8 as 'MODULE_PATHNAME','vops_count_any_extend' language C parallel safe strict;
create function vops_float8_count_reduce(state vops_int8, val vops_float8) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe strict;
CREATE AGGREGATE mcount(vops_float8) (
	SFUNC = vops_float8_count_stub,
	STYPE = vops_int8,
	initcond = '0', 
    mstype = vops_int8,
	msfunc = vops_float8_count_extend,
	minvfunc = vops_float8_count_reduce,
	minitcond = '0', 
	PARALLEL = SAFE
);

create function vops_float8_first_accumulate(state internal, val vops_float8, ts vops_timestamp) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_float8_first_final(state internal) returns float8 as 'MODULE_PATHNAME','vops_first_final' language C parallel safe;
CREATE AGGREGATE first(vops_float8,vops_timestamp) (
	SFUNC = vops_float8_first_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_float8_first_final,
 	COMBINEFUNC = vops_first_combine,
	PARALLEL = SAFE
);

create function vops_float8_last_accumulate(state internal, val vops_float8, ts vops_timestamp) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE last(vops_float8,vops_timestamp) (
	SFUNC = vops_float8_last_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_float8_first_final,
 	COMBINEFUNC = vops_last_combine,
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


create function vops_count_accumulate(state int8) returns int8 as 'MODULE_PATHNAME' language C parallel safe strict;
CREATE AGGREGATE countall(*) (
	SFUNC = vops_count_accumulate,
	STYPE = int8,
	COMBINEFUNC = int8pl,
	INITCOND = '0', 
	PARALLEL = SAFE
);
create function vops_count_stub(state vops_int8) returns vops_int8 as 'MODULE_PATHNAME','vops_window_accumulate' language C parallel safe strict;
create function vops_count_extend(state vops_int8) returns vops_int8 as 'MODULE_PATHNAME' language C parallel safe strict;
create function vops_count_reduce(state vops_int8) returns vops_int8 as 'MODULE_PATHNAME','vops_window_reduce' language C parallel safe strict;
CREATE AGGREGATE mcount(*) (
	SFUNC = vops_count_stub,
	STYPE = vops_int8,
	initcond = '0', 
    mstype = vops_int8,
	msfunc = vops_count_extend,
	minvfunc = vops_count_reduce,
	minitcond = '0', 
	PARALLEL = SAFE
);

create function vops_bool_first_accumulate(state internal, val vops_bool, ts vops_timestamp) returns internal as 'MODULE_PATHNAME' language C parallel safe;
create function vops_bool_first_final(state internal) returns bool as 'MODULE_PATHNAME','vops_first_final' language C parallel safe;
CREATE AGGREGATE first(vops_bool,vops_timestamp) (
	SFUNC = vops_bool_first_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_bool_first_final,
 	COMBINEFUNC = vops_first_combine,
	PARALLEL = SAFE
);

create function vops_bool_last_accumulate(state internal, val vops_bool, ts vops_timestamp) returns internal as 'MODULE_PATHNAME' language C parallel safe;
CREATE AGGREGATE last(vops_bool,vops_timestamp) (
	SFUNC = vops_bool_last_accumulate,
	STYPE = internal,
	SSPACE = 24,
	FINALFUNC = vops_bool_first_final,
 	COMBINEFUNC = vops_last_combine,
	PARALLEL = SAFE
);

create function first(tile vops_bool) returns bool as 'MODULE_PATHNAME','vops_bool_first' language C parallel safe immutable strict;
create function last(tile vops_bool) returns bool as 'MODULE_PATHNAME','vops_bool_last' language C parallel safe immutable strict;

-- Generic functions

-- Call this function to force loading of VOPS extension (if it is not registered in shared_preload_libraries list
create function vops_initialize() returns void as 'MODULE_PATHNAME' language C;

create function filter(condition vops_bool) returns bool as 'MODULE_PATHNAME','vops_filter' language C parallel safe strict immutable;

create function populate(destination regclass, source regclass, predicate cstring default null, sort cstring default null) returns bigint as 'MODULE_PATHNAME','vops_populate' language C;
create function import(destination regclass, csv_path cstring, separator cstring default ',', skip integer default 0) returns bigint as 'MODULE_PATHNAME','vops_import' language C strict;



create type vops_aggregates as(group_by int8, count int8, aggs float8[]);
create function reduce(bigint) returns setof vops_aggregates as 'MODULE_PATHNAME','vops_reduce' language C parallel safe strict immutable;

create function unnest(anyelement) returns setof record as 'MODULE_PATHNAME','vops_unnest' language C parallel safe strict immutable;

create cast (vops_bool as bool) with function filter(vops_bool) AS IMPLICIT;

create function is_null(anyelement) returns vops_bool as 'MODULE_PATHNAME','vops_is_null'  language C parallel safe immutable;
create function is_not_null(anyelement) returns vops_bool as 'MODULE_PATHNAME','vops_is_not_null'  language C parallel safe immutable;

-- VOPS FDW

CREATE FUNCTION vops_fdw_handler()
RETURNS fdw_handler
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT;

CREATE FUNCTION vops_fdw_validator(text[], oid)
RETURNS void
AS 'MODULE_PATHNAME'
LANGUAGE C STRICT;

CREATE FOREIGN DATA WRAPPER vops_fdw
  HANDLER vops_fdw_handler
  VALIDATOR vops_fdw_validator;

CREATE SERVER vops_server FOREIGN DATA WRAPPER vops_fdw;

-- Projection generator

create table vops_projections(projection text primary key, source_table oid, vector_columns integer[], scalar_columns integer[], key_name text);
create index on vops_projections(source_table);


create function drop_projection(projection_name text) returns void as $drop$
begin
	execute 'drop table '||projection_name;
	execute 'drop function '||projection_name||'_refresh()';
	delete from vops_projections where projection=projection_name;
end;
$drop$ language plpgsql;


create function create_projection(projection_name text, source_table regclass, vector_columns text[], scalar_columns text[] default null, order_by text default null) returns void as $create$
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
    create_func := 'create function '||projection_name||'_refresh() returns bigint as $$ select populate(source:='''||source_table::text||''',destination:='''||projection_name||''',sort:=''';
	if scalar_columns is not null
	then
		create_index := 'create index on '||projection_name||' using brin(';
		foreach att_name IN ARRAY scalar_columns
		loop
			select atttypid,attnum,typname into att_typid,att_num,att_typname from pg_attribute,pg_type where attrelid=source_table::oid and attname=att_name and atttypid=pg_type.oid;
        	if att_typid is null
			then
				raise exception 'No attribute % in table %',att_name,source_table;
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

    foreach att_name IN ARRAY vector_columns
	loop
		select atttypid,attnum,typname,atttypmod into att_typid,att_num,att_typname,att_typmod from pg_attribute,pg_type where attrelid=source_table::oid and attname=att_name and atttypid=pg_type.oid;
        if att_typid is null
		then
		    raise exception 'No attribute % in table %',att_name,source_table;
		end if;
		if att_typname='bpchar' or att_typname='varchar'
		then
			att_typname:='text('||att_typmod||')';
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
		    raise exception 'Invalid order column % for projection %',order_by,projection_name;
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
		create_func := create_func||',predicate:='''||order_by||'>(select coalesce(max(last('||order_by||')),'||min_value||') from '||projection_name||')''';
	end if;
	create_func := create_func||'); $$ language sql';
	execute create_func;

	insert into vops_projections values (projection_name, source_table, vector_attno, scalar_attno, order_by);
end;
$create$ language plpgsql;

