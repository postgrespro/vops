#include "postgres.h"

#include <float.h>
#include <math.h>
#include "funcapi.h"
#include "miscadmin.h"

#if PG_VERSION_NUM>=90300
#include "access/htup_details.h"
#endif
#include "access/relscan.h"
#include "catalog/catversion.h"
#include "catalog/dependency.h"
#include "catalog/index.h"
#include "catalog/namespace.h"
#include "catalog/pg_type.h"
#include "commands/explain.h"
#include "storage/ipc.h"
#include "storage/lmgr.h"
#include "storage/lwlock.h"
#include "storage/bufmgr.h"
#include "storage/proc.h"

#include "tcop/pquery.h"
#include "tcop/tcopprot.h"
#include "tcop/utility.h"

#include "utils/array.h"
#include "utils/datum.h"
#if PG_VERSION_NUM>=120000
#include "access/heapam.h"
#include "utils/float.h"
#else
#include "utils/tqual.h"
#endif
#include "utils/builtins.h"
#include "utils/datetime.h"
#include <utils/typcache.h>
#include "utils/lsyscache.h"
#include "utils/memutils.h"
#include "utils/snapmgr.h"
#include "utils/syscache.h"
#include "parser/parse_relation.h"
#include "parser/parse_func.h"
#include "parser/parse_type.h"
#include "parser/analyze.h"
#include "libpq/pqformat.h"
#include "executor/spi.h"
#include "nodes/nodeFuncs.h"
#include "nodes/makefuncs.h"
#include "nodes/pg_list.h"
#include "vops.h"

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

#if !USE_FLOAT8_BYVAL
#error VOPS requires 64-bit version of Postgres
#endif

#if PG_VERSION_NUM>=140000
#define FUNC_CALL_CTX COERCE_EXPLICIT_CALL, -1
#else
#define FUNC_CALL_CTX -1
#endif

/* pg module functions */
void _PG_init(void);

uint64 filter_mask = ~0;
static struct {
	char const* name;
	Oid         oid;
} vops_type_map[] = {
	{"vops_bool",      InvalidOid},
	{"vops_char",      InvalidOid},
	{"vops_int2",      InvalidOid},
	{"vops_int4",      InvalidOid},
	{"vops_int8",      InvalidOid},
	{"vops_date",      InvalidOid},
	{"vops_timestamp", InvalidOid},
	{"vops_float4",    InvalidOid},
	{"vops_float8",    InvalidOid},
	{"vops_interval",  InvalidOid},
	{"vops_text",      InvalidOid}
};

static struct {
	char const* name;
	vops_agg_kind kind;
} const vops_agg_kind_map[] = {
	{"sum", VOPS_AGG_SUM},
	{"avg", VOPS_AGG_AVG},
	{"max", VOPS_AGG_MAX},
	{"min", VOPS_AGG_MIN},
	{"count", VOPS_AGG_COUNT}
};


static const Oid vops_map_tid[] =
{
	BOOLOID,
	CHAROID,
	INT2OID,
	INT4OID,
	INT8OID,
	DATEOID,
	TIMESTAMPOID,
	FLOAT4OID,
	FLOAT8OID,
	INTERVALOID,
	TEXTOID
};

static bool vops_auto_substitute_projections;

static vops_agg_state* vops_init_agg_state(char const* aggregates, Oid elem_type, int n_aggregates);
static vops_agg_state* vops_create_agg_state(int n_aggregates);
static void vops_agg_state_accumulate(vops_agg_state* state, int64 group_by, int i, Datum* tiles, bool* nulls);
static void reset_static_cache(void);

vops_type vops_get_type(Oid typid)
{
	int i;
	if (vops_type_map[0].oid == InvalidOid) {
		for (i = 0; i < VOPS_LAST; i++) {
			vops_type_map[i].oid = TypenameGetTypid(vops_type_map[i].name);
		}
	}
	for (i = 0; i < VOPS_LAST && vops_type_map[i].oid != typid; i++);
	return (vops_type)i;
}

static bool is_vops_type(Oid typeid)
{
	return vops_get_type(typeid) != VOPS_LAST;
}

#define SCALAR_PAYLOAD(tile, i) ((tile)->payload[i])
#define BOOL_PAYLOAD(tile, i)   (((tile)->payload >> (i)) & 1)

/* Parameters used in macros:
 * TYPE:   Postgres SQL type:                          char,   int2,   int4,   int8, float4, float8
 * SSTYPE: Postgres SQL sum type:                      int8,   int8,   int8,   int8, float8, float8
 * CTYPE:  Postgres C type:                            char,  int16,  int32,  int64, float8, float8
 * XTYPE:  Postgres extended C type:                  int32,  int32,  int32,  int64, float8, float8
 * STYPE:  Postgres sum type:                        long64, long64, long64, long64, float8, float8
 * DTYPE:  Postgres type to convert to Datum:          Char,  Int16,  Int32,  Int64, Float4, Float8
 * GCTYPE: capitalized prefix used in GETARG macro:    CHAR,  INT16,  INT32,  INT64, FLOAT4, FLOAT8
 * GXTYPE: capitalized prefix of extended type:       INT32,  INT32,  INT32,  INT64, FLOAT8, FLOAT8
 * GSTYPE: capitalized prefix of sum type:            INT64,  INT64,  INT64,  INT64, FLOAT8, FLOAT8
 */
#define CMP_OP(TYPE,OP,COP)												\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_##OP);							\
	Datum vops_##TYPE##_##OP(PG_FUNCTION_ARGS)							\
	{																	\
		vops_##TYPE* left = (vops_##TYPE*)PG_GETARG_POINTER(0);			\
		vops_##TYPE* right = (vops_##TYPE*)PG_GETARG_POINTER(1);	    \
		vops_bool* result = (vops_bool*)palloc(sizeof(vops_bool));	    \
		int i;															\
		uint64 payload = 0;												\
		for (i = 0; i < TILE_SIZE; i++) payload |= (uint64)(left->payload[i] COP right->payload[i]) << i; \
		result->payload = payload;										\
		result->hdr.null_mask = left->hdr.null_mask | right->hdr.null_mask;	\
		result->hdr.empty_mask = left->hdr.empty_mask | right->hdr.empty_mask; \
		PG_RETURN_POINTER(result);										\
	}

#define CMP_RCONST_OP(TYPE,XTYPE,GXTYPE,OP,COP)							\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_##OP##_rconst);					\
	Datum vops_##TYPE##_##OP##_rconst(PG_FUNCTION_ARGS)					\
	{																	\
	    vops_##TYPE* left = (vops_##TYPE*)PG_GETARG_POINTER(0);			\
		XTYPE right = PG_GETARG_##GXTYPE(1);					        \
		vops_bool* result = (vops_bool*)palloc(sizeof(vops_bool));	    \
		int i;															\
		uint64 payload = 0;												\
		for (i = 0; i < TILE_SIZE; i++) payload |= (uint64)(left->payload[i] COP right) << i; \
		result->payload = payload;										\
		result->hdr = left->hdr;										\
		PG_RETURN_POINTER(result);										\
	}																	\

#define CMP_LCONST_OP(TYPE,XTYPE,GXTYPE,OP,COP)							\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_##OP##_lconst);					\
	Datum vops_##TYPE##_##OP##_lconst(PG_FUNCTION_ARGS)					\
	{																	\
		XTYPE left = PG_GETARG_##GXTYPE(0);						        \
		vops_##TYPE* right = (vops_##TYPE*)PG_GETARG_POINTER(1);		\
		vops_bool* result = (vops_bool*)palloc(sizeof(vops_bool));      \
		int i;															\
		uint64 payload = 0;												\
		for (i = 0; i < TILE_SIZE; i++) payload |= (uint64)(left COP right->payload[i]) << i; \
		result->payload = payload;										\
		result->hdr = right->hdr;										\
		PG_RETURN_POINTER(result);										\
	}

#define BETWIXT_OP(TYPE,XTYPE,GXTYPE)									\
	PG_FUNCTION_INFO_V1(vops_betwixt_##TYPE);							\
	Datum vops_betwixt_##TYPE(PG_FUNCTION_ARGS)							\
	{																	\
	    vops_##TYPE* opd = (vops_##TYPE*)PG_GETARG_POINTER(0);			\
		XTYPE low = PG_GETARG_##GXTYPE(1);					            \
		XTYPE high = PG_GETARG_##GXTYPE(2);					            \
		vops_bool* result = (vops_bool*)palloc(sizeof(vops_bool));	    \
		int i;															\
		uint64 payload = 0;												\
		for (i = 0; i < TILE_SIZE; i++) payload |= (uint64)(opd->payload[i] >= low && opd->payload[i] <= high) << i; \
		result->payload = payload;										\
		result->hdr = opd->hdr;											\
		PG_RETURN_POINTER(result);										\
	}																	\

#define CONST_OP(TYPE,CTYPE,GXTYPE)										\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_const);							\
	Datum vops_##TYPE##_const(PG_FUNCTION_ARGS)							\
	{																	\
 	    CTYPE x = (CTYPE)PG_GETARG_##GXTYPE(0);							\
		vops_##TYPE* result = (vops_##TYPE*)palloc(sizeof(vops_##TYPE)); \
		int i;															\
		for (i = 0; i < TILE_SIZE; i++) {								\
			result->payload[i] = x;										\
		}																\
		result->hdr.null_mask = 0;										\
		result->hdr.empty_mask = 0;										\
		PG_RETURN_POINTER(result);										\
	}																	\


#define IFNULL_OP(TYPE,CTYPE,GXTYPE)									\
	PG_FUNCTION_INFO_V1(vops_ifnull_##TYPE);							\
	Datum vops_ifnull_##TYPE(PG_FUNCTION_ARGS)							\
	{																	\
	    vops_##TYPE* opd = (vops_##TYPE*)PG_GETARG_POINTER(0);			\
		CTYPE subst = (CTYPE)PG_GETARG_##GXTYPE(1);						\
		vops_##TYPE* result = (vops_##TYPE*)palloc(sizeof(vops_##TYPE)); \
		int i;															\
		for (i = 0; i < TILE_SIZE; i++) {								\
			result->payload[i] = (opd->hdr.null_mask & ((uint64)1 << i)) ? subst : opd->payload[i]; \
		}																\
		result->hdr.null_mask = 0;						                \
		result->hdr.empty_mask = opd->hdr.empty_mask;					\
		PG_RETURN_POINTER(result);										\
	}																	\

#define COALESCE_OP(TYPE,GXTYPE)										\
	PG_FUNCTION_INFO_V1(vops_coalesce_##TYPE);							\
	Datum vops_coalesce_##TYPE(PG_FUNCTION_ARGS)						\
	{																	\
	    vops_##TYPE* opd = (vops_##TYPE*)PG_GETARG_POINTER(0);			\
		vops_##TYPE* subst = (vops_##TYPE*)PG_GETARG_POINTER(1);	    \
		vops_##TYPE* result = (vops_##TYPE*)palloc(sizeof(vops_##TYPE)); \
		int i;															\
		for (i = 0; i < TILE_SIZE; i++) {								\
			result->payload[i] = (opd->hdr.null_mask & ((uint64)1 << i)) ? subst->payload[i] : opd->payload[i]; \
		}																\
		result->hdr.null_mask = opd->hdr.null_mask & subst->hdr.null_mask; \
		result->hdr.empty_mask = opd->hdr.empty_mask | subst->hdr.empty_mask; \
		PG_RETURN_POINTER(result);										\
	}																	\

#define BIN_RCONST_OP(TYPE,XTYPE,GXTYPE,OP,COP)							\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_##OP##_rconst);	                \
	Datum vops_##TYPE##_##OP##_rconst(PG_FUNCTION_ARGS)					\
	{																	\
	    vops_##TYPE* left = (vops_##TYPE*)PG_GETARG_POINTER(0);			\
		XTYPE right = PG_GETARG_##GXTYPE(1);					        \
		vops_##TYPE* result = (vops_##TYPE*)palloc(sizeof(vops_##TYPE));\
		int i;															\
		for (i = 0; i < TILE_SIZE; i++) result->payload[i] = left->payload[i] COP right; \
		result->hdr = left->hdr;										\
		PG_RETURN_POINTER(result);										\
	}

#define BIN_LCONST_OP(TYPE,XTYPE,GXTYPE,OP,COP)							\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_##OP##_lconst);					\
	Datum vops_##TYPE##_##OP##_lconst(PG_FUNCTION_ARGS)					\
	{																	\
		XTYPE left = PG_GETARG_##GXTYPE(0);								\
		vops_##TYPE* right = (vops_##TYPE*)PG_GETARG_POINTER(1);	    \
		vops_##TYPE* result = (vops_##TYPE*)palloc(sizeof(vops_##TYPE));\
		int i;														    \
		for (i = 0; i < TILE_SIZE; i++) result->payload[i] = left COP right->payload[i]; \
		result->hdr = right->hdr;										\
		PG_RETURN_POINTER(result);										\
	}

#define BIN_OP(TYPE,OP,COP)												\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_##OP);							\
	Datum vops_##TYPE##_##OP(PG_FUNCTION_ARGS)							\
	{																	\
		vops_##TYPE* left = (vops_##TYPE*)PG_GETARG_POINTER(0);			\
		vops_##TYPE* right = (vops_##TYPE*)PG_GETARG_POINTER(1);	    \
		vops_##TYPE* result = (vops_##TYPE*)palloc(sizeof(vops_##TYPE));\
		int i;														    \
		for (i = 0; i < TILE_SIZE; i++) result->payload[i] = left->payload[i] COP right->payload[i]; \
		result->hdr.null_mask = left->hdr.null_mask | right->hdr.null_mask;	\
		result->hdr.empty_mask = left->hdr.empty_mask | right->hdr.empty_mask; \
		PG_RETURN_POINTER(result);										\
	}

#define UNARY_OP(TYPE,OP,COP)											\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_##OP);							\
	Datum vops_##TYPE##_##OP(PG_FUNCTION_ARGS)							\
	{																	\
		vops_##TYPE* opd = (vops_##TYPE*)PG_GETARG_POINTER(0);			\
		vops_##TYPE* result = (vops_##TYPE*)palloc(sizeof(vops_##TYPE));\
		int i;														    \
		for (i = 0; i < TILE_SIZE; i++) result->payload[i] = COP opd->payload[i]; \
		result->hdr = opd->hdr;											\
		PG_RETURN_POINTER(result);										\
	}

#define BOOL_BIN_OP(OP,COP)											    \
	PG_FUNCTION_INFO_V1(vops_bool_##OP);								\
	Datum vops_bool_##OP(PG_FUNCTION_ARGS)								\
	{																	\
  	    vops_bool* left = (vops_bool*)PG_GETARG_POINTER(0);				\
		vops_bool* right = (vops_bool*)PG_GETARG_POINTER(1);			\
		vops_bool* result = (vops_bool*)palloc(sizeof(vops_bool));		\
		result->payload = left->payload COP right->payload;				\
		result->hdr.null_mask = left->hdr.null_mask | right->hdr.null_mask;	\
		result->hdr.empty_mask = left->hdr.empty_mask | right->hdr.empty_mask; \
		PG_RETURN_POINTER(result);										\
	}

#define SUM_AGG(TYPE,STYPE,GSTYPE)										\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_sum_accumulate);					\
	Datum vops_##TYPE##_sum_accumulate(PG_FUNCTION_ARGS)				\
	{																	\
	    vops_##TYPE* opd = (vops_##TYPE*)PG_GETARG_POINTER(1);			\
		bool is_null = PG_ARGISNULL(0);								    \
		STYPE sum = is_null ? 0 : PG_GETARG_##GSTYPE(0);				\
		uint64 mask = filter_mask & ~opd->hdr.null_mask & ~opd->hdr.empty_mask; \
		int i;															\
		if (~mask == 0) {												\
		    for (i = 0; i < TILE_SIZE; i++) {							\
			    sum += opd->payload[i];									\
			}															\
			PG_RETURN_##GSTYPE(sum);									\
		} else {														\
			for (i = 0; i < TILE_SIZE; i++) {							\
				if (mask & ((uint64)1 << i)) {							\
					is_null = false;									\
					sum += opd->payload[i];								\
				}														\
			}															\
			if (is_null) {												\
				PG_RETURN_NULL();										\
			} else {													\
				PG_RETURN_##GSTYPE(sum);								\
			}															\
		}																\
	}

#define SUM_WIN(TYPE,SSTYPE,STYPE)										\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_sum_extend);						\
	Datum vops_##TYPE##_sum_extend(PG_FUNCTION_ARGS)					\
	{																	\
 	    vops_##SSTYPE* state = (vops_##SSTYPE*)PG_GETARG_POINTER(0);	\
	    vops_##TYPE* val = (vops_##TYPE*)PG_GETARG_POINTER(1);			\
		STYPE sum;												        \
		int i;															\
		if (PG_ARGISNULL(0)) {											\
			MemoryContext agg_context;									\
			if (!AggCheckCallContext(fcinfo, &agg_context))				\
				elog(ERROR, "aggregate function called in non-aggregate context"); \
			state = (vops_##SSTYPE*)MemoryContextAllocZero(agg_context, sizeof(vops_##SSTYPE)); \
			state->hdr.null_mask = ~0;									\
		} else { 														\
			state->hdr.null_mask = (int64)state->hdr.null_mask >> 63;	\
		}																\
		state->hdr.empty_mask = ~filter_mask;                           \
		sum = state->payload[TILE_SIZE-1];								\
		if (PG_ARGISNULL(1)) {											\
			for (i = 0; i < TILE_SIZE; i++) {							\
				state->payload[i] = sum;								\
			}															\
		} else { 														\
			uint64 mask = filter_mask & ~val->hdr.empty_mask & ~val->hdr.null_mask; \
			state->hdr.empty_mask |= val->hdr.empty_mask;				\
			for (i = 0; i < TILE_SIZE; i++) {							\
				if (mask & ((uint64)1 << i)) {							\
					state->hdr.null_mask &= ((uint64)1 << i) - 1;		\
					sum += val->payload[i];								\
				}														\
				state->payload[i] = sum;								\
			}															\
		}																\
		PG_RETURN_POINTER(state);										\
	}																	\
	typedef struct { vops_##SSTYPE tile; vops_##TYPE hist; int n_nulls; } vops_##TYPE##_msum_state; \
	PG_FUNCTION_INFO_V1(vops_##TYPE##_msum_extend);						\
	Datum vops_##TYPE##_msum_extend(PG_FUNCTION_ARGS)					\
	{																	\
 	    vops_##TYPE##_msum_state* state = (vops_##TYPE##_msum_state*)PG_GETARG_POINTER(0); \
	    vops_##TYPE* val = (vops_##TYPE*)PG_GETARG_POINTER(1);			\
		uint32 size = PG_ARGISNULL(2) ? 0 : PG_GETARG_UINT32(2);	    \
		STYPE sum;												        \
		int i;															\
		uint64 null_mask = 0;											\
		if (size == 0 || size > TILE_SIZE) {							\
			elog(ERROR, "Window size should be in range [1,%d]", TILE_SIZE-1); \
		}																\
		if (PG_ARGISNULL(0)) {											\
			MemoryContext agg_context;									\
			if (!AggCheckCallContext(fcinfo, &agg_context))				\
				elog(ERROR, "aggregate function called in non-aggregate context"); \
			state = (vops_##TYPE##_msum_state*)MemoryContextAllocZero(agg_context, sizeof(vops_##TYPE##_msum_state));	\
			state->hist.hdr.null_mask = ~0;								\
			state->n_nulls = size;										\
		}																\
		state->tile.hdr.empty_mask = ~filter_mask;						\
		sum = state->tile.payload[TILE_SIZE-1];							\
		state->hist.hdr.null_mask = ~0;									\
		if (PG_ARGISNULL(1)) {											\
			for (i = 0; i < TILE_SIZE; i++) {							\
				sum -= state->hist.payload[(i-size) % TILE_SIZE];		\
				state->n_nulls -= (state->hist.hdr.null_mask >> ((i-size) % TILE_SIZE)) & 1; \
				null_mask |= (uint64)(++state->n_nulls == size) << i;	\
				state->hist.payload[i] = 0;								\
				state->tile.payload[i] = sum;							\
			}															\
		} else {														\
			uint64 mask = filter_mask & ~val->hdr.empty_mask & ~val->hdr.null_mask; \
			state->tile.hdr.empty_mask |= val->hdr.empty_mask;			\
			for (i = 0; i < TILE_SIZE; i++) {							\
				sum -= state->hist.payload[(i-size) % TILE_SIZE];		\
				state->n_nulls -= (state->hist.hdr.null_mask >> ((i-size) % TILE_SIZE)) & 1; \
				if (mask & ((uint64)1 << i)) {							\
					sum += val->payload[i];								\
					state->hist.payload[i] = val->payload[i];			\
					state->hist.hdr.null_mask &= ~((uint64)1 << i);		\
				} else {												\
					null_mask |= (uint64)(++state->n_nulls == size) << i; \
					state->hist.payload[i] = 0;							\
				}														\
				state->tile.payload[i] = sum;							\
			}															\
		}																\
		state->tile.hdr.null_mask = null_mask;							\
		PG_RETURN_POINTER(state);										\
	}																	\

#define AVG_WIN(TYPE)													\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_avg_extend);						\
	Datum vops_##TYPE##_avg_extend(PG_FUNCTION_ARGS)					\
	{																	\
 	    vops_window_state* state = (vops_window_state*)PG_GETARG_POINTER(0); \
	    vops_##TYPE* val = (vops_##TYPE*)PG_GETARG_POINTER(1);			\
		int i;															\
		if (PG_ARGISNULL(0)) {											\
			MemoryContext agg_context;									\
			if (!AggCheckCallContext(fcinfo, &agg_context))				\
				elog(ERROR, "aggregate function called in non-aggregate context"); \
			state = (vops_window_state*)MemoryContextAllocZero(agg_context, sizeof(vops_window_state));	\
			state->tile.hdr.null_mask = ~0;								\
		} else { 														\
		    state->tile.hdr.null_mask = (int64)state->tile.hdr.null_mask >> 63;	\
		}																\
		state->tile.hdr.empty_mask = ~filter_mask;						\
		if (PG_ARGISNULL(1)) {											\
			for (i = 0; i < TILE_SIZE; i++) {							\
				state->tile.payload[i] = state->tile.payload[TILE_SIZE-1]; \
			}															\
		} else {  														\
			uint64 mask = filter_mask & ~val->hdr.empty_mask & ~val->hdr.null_mask; \
			state->tile.hdr.empty_mask |= val->hdr.empty_mask;			\
			for (i = 0; i < TILE_SIZE; i++) {							\
				if (mask & ((uint64)1 << i)) {							\
					state->tile.hdr.null_mask &= ((uint64)1 << i) - 1;	\
					state->sum += val->payload[i];						\
					state->count += 1;									\
				}														\
				state->tile.payload[i] = state->sum/state->count;		\
			}															\
		}																\
		PG_RETURN_POINTER(state);										\
	}


#define MINMAX_WIN(TYPE,CTYPE,OP,COP)									\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_##OP##_extend);					\
	Datum vops_##TYPE##_##OP##_extend(PG_FUNCTION_ARGS)					\
	{																	\
 	    vops_##TYPE* state = (vops_##TYPE*)PG_GETARG_POINTER(0);		\
	    vops_##TYPE* val = (vops_##TYPE*)PG_GETARG_POINTER(1);			\
		CTYPE result;													\
		bool is_null = PG_ARGISNULL(0);									\
		int i;															\
		if (is_null) {													\
			MemoryContext agg_context;									\
			if (!AggCheckCallContext(fcinfo, &agg_context))				\
				elog(ERROR, "aggregate function called in non-aggregate context"); \
			state = (vops_##TYPE*)MemoryContextAllocZero(agg_context, sizeof(vops_##TYPE));			\
			state->hdr.null_mask = ~0;									\
		} else { 														\
			state->hdr.null_mask = (int64)state->hdr.null_mask >> 63;	\
			is_null = state->hdr.null_mask != 0;						\
		}																\
		state->hdr.empty_mask = ~filter_mask;			                \
		result = state->payload[TILE_SIZE-1];							\
		if (PG_ARGISNULL(1)) {											\
			for (i = 0; i < TILE_SIZE; i++) {							\
				state->payload[i] = result;								\
			}															\
		} else { 														\
			uint64 mask = filter_mask & ~val->hdr.empty_mask & ~val->hdr.null_mask; \
			state->hdr.empty_mask |= val->hdr.empty_mask;				\
			for (i = 0; i < TILE_SIZE; i++) {							\
				if (mask & ((uint64)1 << i)) {							\
					if (is_null || val->payload[i] COP result) {		\
						is_null = false;								\
						state->hdr.null_mask &= ((uint64)1 << i) - 1;	\
						result = val->payload[i];						\
					}													\
				}														\
				state->payload[i] = result;								\
			}															\
		}																\
		PG_RETURN_POINTER(state);										\
	}


#define MINMAX_AGG(TYPE,CTYPE,GCTYPE,OP,COP)							\
    PG_FUNCTION_INFO_V1(vops_##TYPE##_##OP##_accumulate);	            \
	Datum vops_##TYPE##_##OP##_accumulate(PG_FUNCTION_ARGS)				\
	{																	\
	    vops_##TYPE* opd = (vops_##TYPE*)PG_GETARG_POINTER(1);			\
		bool is_null = PG_ARGISNULL(0);								    \
		CTYPE result = is_null ? 0 : PG_GETARG_##GCTYPE(0);				\
		int i;															\
		if (!PG_ARGISNULL(1)) {											\
			uint64 mask = filter_mask & ~opd->hdr.empty_mask & ~opd->hdr.null_mask; \
			for (i = 0; i < TILE_SIZE; i++) {							\
				if (mask & ((uint64)1 << i)) {							\
					if (is_null || opd->payload[i] COP result) {		\
						result = opd->payload[i];						\
						is_null = false;								\
					}													\
				}														\
			}															\
		}																\
		if (is_null) {													\
			PG_RETURN_NULL();											\
		} else {														\
			PG_RETURN_##GCTYPE(result);									\
		}																\
	}

#define LAG_WIN(TYPE,CTYPE)												\
    typedef struct { vops_##TYPE tile; CTYPE lag; bool is_null; } vops_lag_##TYPE; \
	PG_FUNCTION_INFO_V1(vops_##TYPE##_lag_extend);					    \
	Datum vops_##TYPE##_lag_extend(PG_FUNCTION_ARGS)					\
	{																	\
	    vops_lag_##TYPE* state = (vops_lag_##TYPE*)PG_GETARG_POINTER(0);\
	    vops_##TYPE* opd = (vops_##TYPE*)PG_GETARG_POINTER(1);			\
		int i;														    \
		CTYPE lag;														\
		bool is_null = PG_ARGISNULL(0);									\
		if (is_null) {													\
			MemoryContext agg_context;									\
			if (PG_ARGISNULL(1)) PG_RETURN_NULL();						\
			if (!AggCheckCallContext(fcinfo, &agg_context))				\
				elog(ERROR, "aggregate function called in non-aggregate context"); \
			state = (vops_lag_##TYPE*)MemoryContextAllocZero(agg_context, sizeof(vops_lag_##TYPE));	\
			state->is_null = true;										\
			lag = 0;													\
		} else { 														\
			is_null = state->is_null;									\
			lag = state->lag;											\
		}																\
		state->tile.hdr.empty_mask = ~filter_mask;						\
		state->tile.hdr.null_mask = 0;									\
		if (PG_ARGISNULL(1)) {											\
			for (i = 0; i < TILE_SIZE; i++) {							\
				if (filter_mask & ((uint64)1 << i)) {					\
					state->tile.payload[i] = lag;						\
					state->tile.hdr.null_mask |= (uint64)is_null << i;	\
					is_null = true;										\
					break;												\
				}														\
			}															\
  	    } else {														\
		    uint64 mask = filter_mask & ~opd->hdr.empty_mask;			\
			state->tile.hdr.empty_mask |= opd->hdr.empty_mask;			\
			for (i = 0; i < TILE_SIZE; i++) {							\
				if (mask & ((uint64)1 << i)) {							\
					state->tile.payload[i] = lag;						\
					state->tile.hdr.null_mask |= (uint64)is_null << i;	\
					lag = opd->payload[i];								\
					is_null = (opd->hdr.null_mask >> i) & 1;			\
				}														\
			}															\
        }																\
		state->lag = lag;												\
		state->is_null = is_null;										\
		PG_RETURN_POINTER(state);										\
	}

#define AVG_AGG(TYPE)													\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_avg_accumulate);					\
	Datum vops_##TYPE##_avg_accumulate(PG_FUNCTION_ARGS)				\
	{																	\
	    vops_##TYPE* opd = (vops_##TYPE*)PG_GETARG_POINTER(1);			\
		vops_avg_state* state = PG_ARGISNULL(0) ? NULL : (vops_avg_state*)PG_GETARG_POINTER(0); \
		uint64 mask = filter_mask & ~opd->hdr.empty_mask & ~opd->hdr.null_mask; \
		int i;															\
		for (i = 0; i < TILE_SIZE; i++) {								\
		    if (mask & ((uint64)1 << i)) {								\
			    if (state == NULL) {									\
					MemoryContext agg_context;							\
					if (!AggCheckCallContext(fcinfo, &agg_context))		\
						elog(ERROR, "aggregate function called in non-aggregate context"); \
					state = (vops_avg_state*)MemoryContextAllocZero(agg_context, sizeof(vops_avg_state)); \
				}														\
				state->count += 1;										\
				state->sum += opd->payload[i];							\
			}															\
		}																\
		if (state == NULL) {											\
			PG_RETURN_NULL();											\
		} else {														\
			PG_RETURN_POINTER(state);									\
		}																\
	}																    \

#define WAVG_AGG(TYPE)													\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_wavg_accumulate);					\
	Datum vops_##TYPE##_wavg_accumulate(PG_FUNCTION_ARGS)				\
	{																	\
		vops_var_state* state = PG_ARGISNULL(0) ? NULL : (vops_var_state*)PG_GETARG_POINTER(0); \
	    vops_##TYPE* price = (vops_##TYPE*)PG_GETARG_POINTER(1);		\
		vops_##TYPE* volume = (vops_##TYPE*)PG_GETARG_POINTER(2);		\
		uint64 mask = filter_mask & ~price->hdr.empty_mask & ~price->hdr.null_mask & ~volume->hdr.null_mask; \
		int i;															\
		for (i = 0; i < TILE_SIZE; i++) {								\
			if (mask & ((uint64)1 << i)) {								\
				if (state == NULL) {									\
					MemoryContext agg_context;							\
					if (!AggCheckCallContext(fcinfo, &agg_context))		\
						elog(ERROR, "aggregate function called in non-aggregate context"); \
					state = (vops_var_state*)MemoryContextAllocZero(agg_context, sizeof(vops_var_state)); \
				}														\
				state->sum += (double)price->payload[i]*volume->payload[i]; \
				state->sum2 += volume->payload[i];						\
			}															\
		}																\
		if (state == NULL) {											\
			PG_RETURN_NULL();											\
		} else {														\
			PG_RETURN_POINTER(state);									\
		}																\
	}																    \

#define VAR_AGG(TYPE)													\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_var_accumulate);					\
	Datum vops_##TYPE##_var_accumulate(PG_FUNCTION_ARGS)				\
	{																	\
	    vops_##TYPE* opd = (vops_##TYPE*)PG_GETARG_POINTER(1);			\
		vops_var_state* state = PG_ARGISNULL(0) ? NULL : (vops_var_state*)PG_GETARG_POINTER(0); \
		uint64 mask = filter_mask & ~opd->hdr.empty_mask & ~opd->hdr.null_mask; \
		int i;															\
		for (i = 0; i < TILE_SIZE; i++) {								\
		    if (mask & ((uint64)1 << i)) {								\
			    if (state == NULL) {									\
					MemoryContext agg_context;							\
					if (!AggCheckCallContext(fcinfo, &agg_context))		\
						elog(ERROR, "aggregate function called in non-aggregate context"); \
					state = (vops_var_state*)MemoryContextAllocZero(agg_context, sizeof(vops_var_state)); \
				}														\
				state->count += 1;										\
				state->sum += opd->payload[i];							\
				state->sum2 += (double)opd->payload[i]*opd->payload[i];	\
			}															\
		}																\
		if (state == NULL) {											\
			PG_RETURN_NULL();											\
		} else {														\
			PG_RETURN_POINTER(state);									\
		}																\
	}																    \

	#define FIRST_AGG(TYPE,GCTYPE,PAYLOAD)								\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_first);							\
	Datum vops_##TYPE##_first(PG_FUNCTION_ARGS)							\
	{																	\
	    vops_##TYPE* tile = (vops_##TYPE*)PG_GETARG_POINTER(0);			\
		uint64 mask = ~(tile->hdr.empty_mask | tile->hdr.null_mask);	\
		int i;															\
		for (i = 0; i < TILE_SIZE; i++) {								\
			if (mask & ((uint64)1 << i)) {								\
				PG_RETURN_##GCTYPE(PAYLOAD(tile, i));					\
			}															\
		} 																\
		PG_RETURN_NULL();											    \
	}

	#define LAST_AGG(TYPE,GCTYPE,PAYLOAD)								\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_last);							\
	Datum vops_##TYPE##_last(PG_FUNCTION_ARGS)							\
	{																	\
	    vops_##TYPE* tile = (vops_##TYPE*)PG_GETARG_POINTER(0);			\
		uint64 mask = ~(tile->hdr.empty_mask | tile->hdr.null_mask);	\
		int i;															\
		for (i = TILE_SIZE; --i >= 0;) {								\
			if (mask & ((uint64)1 << i)) {								\
				PG_RETURN_##GCTYPE(PAYLOAD(tile, i));					\
			}															\
		} 																\
		PG_RETURN_NULL();											    \
	}

#define LOW_AGG(TYPE,CTYPE,GCTYPE)										\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_low);								\
	Datum vops_##TYPE##_low(PG_FUNCTION_ARGS)							\
	{																	\
	    vops_##TYPE* tile = (vops_##TYPE*)PG_GETARG_POINTER(0);			\
		CTYPE min = 0;													\
		bool is_null = true;											\
		uint64 mask = ~(tile->hdr.empty_mask | tile->hdr.null_mask);	\
		int i;														    \
		for (i = 0; i < TILE_SIZE; i++) {								\
			if (mask & ((uint64)1 << i)) {								\
				if (is_null || tile->payload[i] < min) {				\
					is_null = false;									\
					min = tile->payload[i];								\
				}														\
			}															\
		} 																\
		if (is_null) {													\
			PG_RETURN_NULL();											\
	    } else {														\
			PG_RETURN_##GCTYPE(min);									\
		}																\
	}

#define HIGH_AGG(TYPE,CTYPE,GCTYPE)										\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_high);							\
	Datum vops_##TYPE##_high(PG_FUNCTION_ARGS)							\
	{																	\
	    vops_##TYPE* tile = (vops_##TYPE*)PG_GETARG_POINTER(0);			\
		CTYPE max = 0;													\
		bool is_null = true;											\
		uint64 mask = ~(tile->hdr.empty_mask | tile->hdr.null_mask);	\
		int i;														    \
		for (i = 0; i < TILE_SIZE; i++) {								\
			if (mask & ((uint64)1 << i)) {								\
				if (is_null || tile->payload[i] > max) {				\
					is_null = false;									\
					max = tile->payload[i];								\
				}														\
			}															\
		} 																\
		if (is_null) {													\
			PG_RETURN_NULL();											\
	    } else {														\
			PG_RETURN_##GCTYPE(max);									\
		}																\
	}

#define IN_FUNC(TYPE,CTYPE,STYPE,FORMAT)								\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_input);							\
	Datum vops_##TYPE##_input(PG_FUNCTION_ARGS)							\
	{																	\
	    char const* str = PG_GETARG_CSTRING(0);							\
		int i, n;														\
		STYPE val = 0;													\
		vops_##TYPE* result;											\
		if (str == NULL) {												\
			PG_RETURN_NULL();											\
		}																\
		result = (vops_##TYPE*)palloc(sizeof(vops_##TYPE));				\
		result->hdr.null_mask = 0;										\
		result->hdr.empty_mask = 0;										\
 		if (*str != '{') {												\
			if (sscanf(str, "%" #FORMAT "%n", &val, &n) != 1) {			\
				elog(ERROR, "Failed to parse VOPS constant '%s'", str);	\
			}															\
			if (str[n] != '\0') {										\
				elog(ERROR, "Failed to parse constant: '%s'", str);		\
			}															\
			for (i=0; i < TILE_SIZE; i++) {							    \
				result->payload[i] = (CTYPE)val;						\
			}															\
		} else { 														\
			str += 1;													\
			for (i=0; i < TILE_SIZE; i++) {								\
				if (*str == ',' || *str == '}') {						\
					result->hdr.empty_mask |= (uint64)1 << i;			\
					if (*str == ',') {									\
						str += 1;										\
					}													\
				} else {												\
					if (*str == '?') {									\
						result->hdr.null_mask |= (uint64)1 << i;		\
						str += 1;										\
					} else {											\
						if (sscanf(str, "%" #FORMAT "%n", &val, &n) != 1) {	\
							elog(ERROR, "Failed to parse tile item %d: '%s'", i, str); \
						}												\
						str += n;										\
						result->payload[i] = (CTYPE)val;				\
					}													\
					if (*str == ',') {									\
						str += 1;										\
					} else if (*str != '}') {							\
						elog(ERROR, "Failed to parse tile: separator expected '%s' found", str); \
					}													\
				}														\
			}															\
			if (*str != '}') {											\
				elog(ERROR, "Failed to parse tile: unexpected trailing data '%s'", str); \
			}															\
		} 																\
		PG_RETURN_POINTER(result);										\
	}

#define OUT_FUNC(TYPE,STYPE,FORMAT,PREC)						     	\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_output);						    \
	Datum vops_##TYPE##_output(PG_FUNCTION_ARGS)						\
	{																	\
		vops_##TYPE* tile = (vops_##TYPE*)PG_GETARG_POINTER(0);			\
		char buf[MAX_TILE_STRLEN];									    \
		int p = 0;														\
		char sep = '{';													\
		int i;															\
		for (i = 0; i < TILE_SIZE; i++) {								\
			if (tile->hdr.empty_mask & ((uint64)1 << i)) {				\
				p += sprintf(buf + p, "%c", sep);						\
			} else if (tile->hdr.null_mask & ((uint64)1 << i)) {		\
				p += sprintf(buf + p, "%c?", sep);						\
			} else {													\
				p += sprintf(buf + p, "%c%.*" #FORMAT, sep, PREC, (STYPE)tile->payload[i]); \
			}															\
			sep = ',';													\
		}																\
		strcpy(buf + p, "}");											\
		PG_RETURN_CSTRING(pstrdup(buf));								\
    }



#define GROUP_BY_FUNC(TYPE)												\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_group_by);						\
	Datum vops_##TYPE##_group_by(PG_FUNCTION_ARGS)						\
	{																	\
		vops_agg_state* state = (vops_agg_state*)(PG_ARGISNULL(0) ? NULL : PG_GETARG_POINTER(0)); \
		vops_##TYPE* gby = (vops_##TYPE*)PG_GETARG_POINTER(1);			\
		char const* aggregates = PG_GETARG_CSTRING(2);				    \
		ArrayType* args = PG_GETARG_ARRAYTYPE_P(3);						\
		int i;															\
		int16 elmlen;													\
		bool elmbyval;													\
		char elmalign;													\
		Datum* elems;													\
		bool* nulls;													\
		int n_elems;													\
		MemoryContext old_context;										\
		MemoryContext agg_context;										\
		uint64 mask = filter_mask & ~gby->hdr.null_mask & ~gby->hdr.empty_mask;	\
		get_typlenbyvalalign(args->elemtype, &elmlen, &elmbyval, &elmalign); \
		deconstruct_array(args, args->elemtype, elmlen, elmbyval, elmalign, &elems, &nulls, &n_elems); \
		if (!AggCheckCallContext(fcinfo, &agg_context))					\
			elog(ERROR, "aggregate function called in non-aggregate context"); \
		old_context = MemoryContextSwitchTo(agg_context);				\
		if (state == NULL) {											\
			state = vops_init_agg_state(aggregates, args->elemtype, n_elems); \
		}																\
		for (i = 0; i < TILE_SIZE; i++) {								\
			if (mask & ((uint64)1 << i)) {	                            \
				vops_agg_state_accumulate(state, gby->payload[i], i, elems, nulls); \
			}															\
		}																\
		MemoryContextSwitchTo(old_context);								\
        PG_RETURN_POINTER(state);										\
    }


#define FIRST_FUNC(TYPE,DTYPE,NAME,CMP,PAYLOAD)							\
PG_FUNCTION_INFO_V1(vops_##TYPE##_##NAME##_accumulate);				    \
Datum vops_##TYPE##_##NAME##_accumulate(PG_FUNCTION_ARGS)				\
{																		\
	vops_first_state* state = (vops_first_state*)PG_GETARG_POINTER(0);	\
	vops_##TYPE* vars = (vops_##TYPE*)PG_GETARG_POINTER(1);				\
	vops_int8* tss = (vops_int8*)PG_GETARG_POINTER(2);					\
	if (state == NULL) {												\
		MemoryContext agg_context;										\
		if (!AggCheckCallContext(fcinfo, &agg_context))					\
			elog(ERROR, "aggregate function called in non-aggregate context"); \
		state = (vops_first_state*)MemoryContextAlloc(agg_context, sizeof(vops_first_state));	\
		state->val_is_null = true;										\
		state->ts_is_null = true;										\
	}																	\
	if (tss != NULL)													\
	{																	\
		int i;															\
		uint64 mask = ~(tss->hdr.empty_mask | tss->hdr.null_mask);		\
		for (i = 0; i < TILE_SIZE; i++) {								\
			if (mask & ((uint64)1 << i)) {								\
				if (state->ts_is_null || tss->payload[i] CMP state->ts) { \
					state->ts = tss->payload[i];						\
					state->ts_is_null = false;							\
					if (vars != NULL) {									\
						if ((vars->hdr.empty_mask | vars->hdr.null_mask) & ((uint64)1 << i)) { \
							state->val_is_null = true;					\
						} else {										\
							state->val = DTYPE##GetDatum(PAYLOAD(vars, i)); \
							state->val_is_null = false;					\
						}												\
					} else {											\
						state->val_is_null = true;						\
					}													\
				}														\
			}															\
		}																\
	}																	\
	PG_RETURN_POINTER(state);											\
}


PG_FUNCTION_INFO_V1(vops_bool_input);
Datum vops_bool_input(PG_FUNCTION_ARGS)
{
	char const* str = PG_GETARG_CSTRING(0);
	vops_bool* result;
	if (str == NULL) {
		PG_RETURN_NULL();
	}
	result = (vops_bool*)palloc(sizeof(vops_bool));
	if (sscanf(str, "{%llx,%llx,%llx}", (long64*)&result->hdr.null_mask, (long64*)&result->hdr.empty_mask, (long64*)&result->payload) != 2) {
		elog(ERROR, "Failed to parse bool tile: '%s'", str);
	}
	PG_RETURN_POINTER(result);
}

PG_FUNCTION_INFO_V1(vops_bool_output);
Datum vops_bool_output(PG_FUNCTION_ARGS)
{
	vops_bool* tile = (vops_bool*)PG_GETARG_POINTER(0);
	PG_RETURN_CSTRING(psprintf("{%llx,%llx,%llx}",
							   (long64)tile->hdr.null_mask, (long64)tile->hdr.empty_mask, (long64)tile->payload));
}

PG_FUNCTION_INFO_V1(vops_filter);
Datum vops_filter(PG_FUNCTION_ARGS)
{
	if (PG_ARGISNULL(0)) {
		filter_mask = 0;
	} else {
		vops_bool* result = (vops_bool*)PG_GETARG_POINTER(0);
		filter_mask = result->payload & ~result->hdr.empty_mask & ~result->hdr.null_mask;
	}
	PG_RETURN_BOOL(filter_mask != 0);
}

PG_FUNCTION_INFO_V1(vops_bool_not);
Datum vops_bool_not(PG_FUNCTION_ARGS)
{
	vops_bool* opd = (vops_bool*)PG_GETARG_POINTER(0);
	vops_bool* result = (vops_bool*)palloc(sizeof(vops_bool));
	result->payload = ~opd->payload;
	result->hdr = opd->hdr;
	PG_RETURN_POINTER(result);
}

BOOL_BIN_OP(or,|)
BOOL_BIN_OP(and,&)
FIRST_AGG(bool,BOOL,BOOL_PAYLOAD)
LAST_AGG(bool,BOOL,BOOL_PAYLOAD)
FIRST_FUNC(bool,Bool,first,<,BOOL_PAYLOAD)
FIRST_FUNC(bool,Bool,last,>,BOOL_PAYLOAD)

PG_FUNCTION_INFO_V1(vops_count_accumulate);
Datum vops_count_accumulate(PG_FUNCTION_ARGS)
{
	vops_tile_hdr* opd = (vops_tile_hdr*)PG_GETARG_POINTER(1);
	int64 count = PG_GETARG_INT64(0);
	uint64 mask = filter_mask & ~opd->empty_mask;
	int i;
	for (i = 0; i < TILE_SIZE; i++) {
		if (mask & ((uint64)1 << i)) {
			count += 1;
		}
	}
	PG_RETURN_INT64(count);
}

PG_FUNCTION_INFO_V1(vops_count_any_accumulate);
Datum vops_count_any_accumulate(PG_FUNCTION_ARGS)
{
	vops_tile_hdr* opd = (vops_tile_hdr*)PG_GETARG_POINTER(1);
	int64 count = PG_GETARG_INT64(0);
	uint64 mask = filter_mask & ~opd->null_mask & ~opd->empty_mask;
	int i;
	for (i = 0; i < TILE_SIZE; i++) {
		if (mask & ((uint64)1 << i)) {
			count += 1;
		}
	}
	PG_RETURN_INT64(count);
}


PG_FUNCTION_INFO_V1(vops_count_any_extend);
Datum vops_count_any_extend(PG_FUNCTION_ARGS)
{
	vops_int8* state = (vops_int8*)PG_GETARG_POINTER(0);
	vops_tile_hdr* opd = (vops_tile_hdr*)PG_GETARG_POINTER(1);
	int64 count = state->payload[TILE_SIZE-1];
	uint64 mask = filter_mask & ~opd->null_mask & ~opd->empty_mask;
	int i;
	state->hdr.empty_mask = ~filter_mask | opd->empty_mask;
	for (i = 0; i < TILE_SIZE; i++) {
		if (mask & ((uint64)1 << i)) {
			count += 1;
		}
		state->payload[i] = count;
	}
	PG_RETURN_POINTER(state);
}

PG_FUNCTION_INFO_V1(vops_count_extend);
Datum vops_count_extend(PG_FUNCTION_ARGS)
{
	vops_int8* state = (vops_int8*)PG_GETARG_POINTER(0);
	int64 count = state->payload[TILE_SIZE-1];
	uint64 mask = filter_mask;
	int i;
	state->hdr.empty_mask = ~mask;
	for (i = 0; i < TILE_SIZE; i++) {
		if (mask & ((uint64)1 << i)) {
			count += 1;
		}
		state->payload[i] = count;
	}
	PG_RETURN_POINTER(state);
}

PG_FUNCTION_INFO_V1(vops_count_all_accumulate);
Datum vops_count_all_accumulate(PG_FUNCTION_ARGS)
{
	int64 count = PG_GETARG_INT64(0);
	int i;
	for (i = 0; i < TILE_SIZE; i++) {
		if (filter_mask & ((uint64)1 << i)) {
			count += 1;
		}
	}
	PG_RETURN_INT64(count);
}

PG_FUNCTION_INFO_V1(vops_time_bucket);
Datum vops_time_bucket(PG_FUNCTION_ARGS)
{
	Interval* interval = PG_GETARG_INTERVAL_P(0);
	vops_int8* timestamp = (vops_int8*)PG_GETARG_POINTER(1);
	vops_int8* result = (vops_int8*)palloc(sizeof(vops_int8));
	int i;
	result->hdr = timestamp->hdr;
	if (interval->day == 0 && interval->month == 0) {
		for (i = 0; i < TILE_SIZE; i++) {
			result->payload[i] = timestamp->payload[i] / interval->time * interval->time;
		}
	} else if (interval->month == 0) {
		time_t days = interval->day * USECS_PER_DAY + interval->time;

		for (i = 0; i < TILE_SIZE; i++) {
			result->payload[i] = timestamp->payload[i] / days * days;
		}
	} else {
		int tz;
		struct pg_tm tm;
		fsec_t fsec;
		Timestamp dt;
		int months;

		if (interval->day != 0 || interval->time != 0)
			elog(ERROR, "Month interval may not include days and time");

		for (i = 0; i < TILE_SIZE; i++) {
			timestamp2tm(timestamp->payload[i], &tz, &tm, &fsec, NULL, NULL);
			tm.tm_sec = 0;
			tm.tm_min = 0;
			tm.tm_hour = 0;
			tm.tm_sec = 0;
			tm.tm_mday = 1;
			months = (tm.tm_year*12 + tm.tm_mon - 1) / interval->month;
			tm.tm_year = months/12;
			tm.tm_mon = months%12 + 1;
			fsec = 0;
			tm2timestamp(&tm, fsec, &tz, &dt);
			result->payload[i] = dt;
		}
	}
	PG_RETURN_POINTER(result);
}

PG_FUNCTION_INFO_V1(vops_date_bucket);
Datum vops_date_bucket(PG_FUNCTION_ARGS)
{
	Interval* interval = PG_GETARG_INTERVAL_P(0);
	vops_int4* date = (vops_int4*)PG_GETARG_POINTER(1);
	vops_int4* result = (vops_int4*)palloc(sizeof(vops_int4));
	int i;

	if (interval->time)
		elog(ERROR, "Date interval may not include time");

	result->hdr = date->hdr;

	if (interval->month == 0) {
		time_t days = interval->day;

		for (i = 0; i < TILE_SIZE; i++) {
			result->payload[i] = date->payload[i] / days * days;
		}
	} else {
		int year, month, day, months;

		if (interval->day != 0)
			elog(ERROR, "Month interval may not include days");

		for (i = 0; i < TILE_SIZE; i++) {
			j2date(date->payload[i], &year, &month, &day);
			months = (year*12 + month - 1) / interval->month;
			year = months / 12;
			month = months % 12 + 1;
			day = 1;
			result->payload[i] = date2j(year, month, day);
		}
	}
	PG_RETURN_POINTER(result);
}




static EState *estate;
static TupleTableSlot* slot;
static Relation rel;

static void
UserTableUpdateOpenIndexes()
{
	List	   *recheckIndexes = NIL;
#if PG_VERSION_NUM>=120000
	HeapTuple tuple = ExecFetchSlotHeapTuple(slot, true, NULL);
#else
	HeapTuple tuple = slot->tts_tuple;
#endif

	/* HOT update does not require index inserts */
	if (HeapTupleIsHeapOnly(tuple))
		return;

#if PG_VERSION_NUM>=140000
	if (estate->es_result_relations[0]->ri_NumIndices > 0)
	{
		recheckIndexes = ExecInsertIndexTuples(estate->es_result_relations[0],
#else
	if (estate->es_result_relation_info->ri_NumIndices > 0)
	{
		recheckIndexes = ExecInsertIndexTuples(
#endif
											   slot,
#if PG_VERSION_NUM<120000
											   &tuple->t_self,
#endif
											   estate,
#if PG_VERSION_NUM>=140000
											   false,
#endif
											   false, NULL, NIL);
		if (recheckIndexes != NIL)
			ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
					 errmsg("vops doesn't support index rechecks")));
	}
}


static void begin_batch_insert(Oid oid)
{
	ResultRelInfo *resultRelInfo;

	rel = heap_open(oid, RowExclusiveLock);

	PushActiveSnapshot(GetTransactionSnapshot());

	estate = CreateExecutorState();

	resultRelInfo = makeNode(ResultRelInfo);
	resultRelInfo->ri_RangeTableIndex = 1;		/* dummy */
	resultRelInfo->ri_RelationDesc = rel;
	resultRelInfo->ri_TrigInstrument = NULL;

#if PG_VERSION_NUM>=140000
	estate->es_result_relations = (ResultRelInfo **)palloc(sizeof(ResultRelInfo *));
	estate->es_result_relations[0] = resultRelInfo;
#else
	estate->es_result_relations = resultRelInfo;
	estate->es_num_result_relations = 1;
	estate->es_result_relation_info = resultRelInfo;
#endif
	ExecOpenIndices(resultRelInfo, false);
#if PG_VERSION_NUM>=120000
	slot = ExecInitExtraTupleSlot(estate, RelationGetDescr(rel), &TTSOpsHeapTuple);
#elif PG_VERSION_NUM>=110000
	slot = ExecInitExtraTupleSlot(estate, RelationGetDescr(rel));
#else
	slot = ExecInitExtraTupleSlot(estate);
	ExecSetSlotDescriptor(slot, RelationGetDescr(rel));
#endif
}

static void insert_tuple(Datum* values, bool* nulls)
{
	HeapTuple tup = heap_form_tuple(RelationGetDescr(rel), values, nulls);
#if PG_VERSION_NUM>=120000
	ExecStoreHeapTuple(tup, slot, true);
	simple_table_tuple_insert(rel, slot);
#else
	ExecStoreTuple(tup, slot, InvalidBuffer, true);
	simple_heap_insert(rel, slot->tts_tuple);
#endif
    UserTableUpdateOpenIndexes();
}

static void end_batch_insert()
{
#if PG_VERSION_NUM>=140000
	ExecCloseIndices(estate->es_result_relations[0]);
#else
	ExecCloseIndices(estate->es_result_relation_info);
#endif
	if (ActiveSnapshotSet()) {
		PopActiveSnapshot();
	}
    heap_close(rel, NoLock);
    ExecResetTupleTable(estate->es_tupleTable, true);
    FreeExecutorState(estate);
}

PG_FUNCTION_INFO_V1(vops_avg_final);
Datum vops_avg_final(PG_FUNCTION_ARGS)
{
	vops_avg_state* state = (vops_avg_state*)PG_GETARG_POINTER(0);
	PG_RETURN_FLOAT8(state->sum / state->count);
}

PG_FUNCTION_INFO_V1(vops_avg_combine);
Datum vops_avg_combine(PG_FUNCTION_ARGS)
{
	vops_avg_state* state0 = PG_ARGISNULL(0) ? NULL : (vops_avg_state*)PG_GETARG_POINTER(0);
	vops_avg_state* state1 = PG_ARGISNULL(1) ? NULL : (vops_avg_state*)PG_GETARG_POINTER(1);
	if (state0 == NULL) {
		if (state1 == NULL) {
			PG_RETURN_NULL();
		} else {
			MemoryContext agg_context;
			if (!AggCheckCallContext(fcinfo, &agg_context))
				elog(ERROR, "aggregate function called in non-aggregate context");
			state0 = (vops_avg_state*)MemoryContextAllocZero(agg_context, sizeof(vops_avg_state));
			*state0 = *state1;
		}
	} else if (state1 != NULL) {
		state0->sum += state1->sum;
		state0->count += state1->count;
	}
	PG_RETURN_POINTER(state0);
}

PG_FUNCTION_INFO_V1(vops_avg_serial);
Datum vops_avg_serial(PG_FUNCTION_ARGS)
{
	vops_avg_state* state = (vops_avg_state*)PG_GETARG_POINTER(0);
	StringInfoData buf;
	bytea* result;
	pq_begintypsend(&buf);
	pq_sendint64(&buf, state->count);
	pq_sendfloat8(&buf, state->sum);
	result = pq_endtypsend(&buf);
	PG_RETURN_BYTEA_P(result);
}

PG_FUNCTION_INFO_V1(vops_avg_deserial);
Datum vops_avg_deserial(PG_FUNCTION_ARGS)
{
	bytea* sstate = PG_GETARG_BYTEA_P(0);
	vops_avg_state* state = (vops_avg_state*)palloc(sizeof(vops_avg_state));
	StringInfoData buf;

	initStringInfo(&buf);
	appendBinaryStringInfo(&buf, VARDATA(sstate), VARSIZE(sstate) - VARHDRSZ);

	state->count = pq_getmsgint64(&buf);
	state->sum = pq_getmsgfloat8(&buf);

	pq_getmsgend(&buf);
	pfree(buf.data);

	PG_RETURN_POINTER(state);
}

PG_FUNCTION_INFO_V1(vops_wavg_final);
Datum vops_wavg_final(PG_FUNCTION_ARGS)
{
	vops_var_state* state = (vops_var_state*)PG_GETARG_POINTER(0);
	PG_RETURN_FLOAT8(state->sum / state->sum2);
}

PG_FUNCTION_INFO_V1(vops_var_samp_final);
Datum vops_var_samp_final(PG_FUNCTION_ARGS)
{
	vops_var_state* state = (vops_var_state*)PG_GETARG_POINTER(0);
	if (state->count <= 1) {
		PG_RETURN_NULL();
	}
	PG_RETURN_FLOAT8((state->sum2 * state->count - state->sum*state->sum) / ((double)state->count * (state->count - 1)));
}

PG_FUNCTION_INFO_V1(vops_var_pop_final);
Datum vops_var_pop_final(PG_FUNCTION_ARGS)
{
	vops_var_state* state = (vops_var_state*)PG_GETARG_POINTER(0);
	PG_RETURN_FLOAT8((state->sum2 - state->sum*state->sum/state->count) / state->count);
}

PG_FUNCTION_INFO_V1(vops_stddev_samp_final);
Datum vops_stddev_samp_final(PG_FUNCTION_ARGS)
{
	vops_var_state* state = (vops_var_state*)PG_GETARG_POINTER(0);
	double var;
	if (state->count <= 1) {
		PG_RETURN_NULL();
	}
	var = (state->sum2 * state->count - state->sum*state->sum) / ((double)state->count * (state->count - 1));
	PG_RETURN_FLOAT8(var <= 0.0 ? 0.0 : sqrt(var));
}

PG_FUNCTION_INFO_V1(vops_stddev_pop_final);
Datum vops_stddev_pop_final(PG_FUNCTION_ARGS)
{
	vops_var_state* state = (vops_var_state*)PG_GETARG_POINTER(0);
	double var = (state->sum2 - state->sum*state->sum/state->count) / state->count;
	PG_RETURN_FLOAT8(var <= 0.0 ? 0.0 : sqrt(var));
}

PG_FUNCTION_INFO_V1(vops_var_combine);
Datum vops_var_combine(PG_FUNCTION_ARGS)
{
	vops_var_state* state0 = PG_ARGISNULL(0) ? NULL : (vops_var_state*)PG_GETARG_POINTER(0);
	vops_var_state* state1 = PG_ARGISNULL(1) ? NULL : (vops_var_state*)PG_GETARG_POINTER(1);
	if (state0 == NULL) {
		if (state1 == NULL) {
			PG_RETURN_NULL();
		} else {
			MemoryContext agg_context;
			if (!AggCheckCallContext(fcinfo, &agg_context))
				elog(ERROR, "aggregate function called in non-aggregate context");
			state0 = (vops_var_state*)MemoryContextAllocZero(agg_context, sizeof(vops_var_state));
			*state0 = *state1;
		}
	} else if (state1 != NULL) {
		state0->sum += state1->sum;
		state0->sum2 += state1->sum2;
		state0->count += state1->count;
	}
	PG_RETURN_POINTER(state0);
}

PG_FUNCTION_INFO_V1(vops_var_serial);
Datum vops_var_serial(PG_FUNCTION_ARGS)
{
	vops_var_state* state = (vops_var_state*)PG_GETARG_POINTER(0);
	StringInfoData buf;
	bytea* result;
	pq_begintypsend(&buf);
	pq_sendint64(&buf, state->count);
	pq_sendfloat8(&buf, state->sum);
	pq_sendfloat8(&buf, state->sum2);
	result = pq_endtypsend(&buf);
	PG_RETURN_BYTEA_P(result);
}

PG_FUNCTION_INFO_V1(vops_var_deserial);
Datum vops_var_deserial(PG_FUNCTION_ARGS)
{
	bytea* sstate = PG_GETARG_BYTEA_P(0);
	vops_var_state* state = (vops_var_state*)palloc(sizeof(vops_var_state));
	StringInfoData buf;

	initStringInfo(&buf);
	appendBinaryStringInfo(&buf, VARDATA(sstate), VARSIZE(sstate) - VARHDRSZ);

	state->count = pq_getmsgint64(&buf);
	state->sum = pq_getmsgfloat8(&buf);
	state->sum2 = pq_getmsgfloat8(&buf);

	pq_getmsgend(&buf);
	pfree(buf.data);

	PG_RETURN_POINTER(state);
}

PG_FUNCTION_INFO_V1(vops_agg_serial);
Datum vops_agg_serial(PG_FUNCTION_ARGS)
{
	vops_agg_state* state = (vops_agg_state*)PG_GETARG_POINTER(0);
	StringInfoData buf;
	HASH_SEQ_STATUS iter;
	vops_group_by_entry* entry;
	bytea* result;
	int n_aggregates = state->n_aggs;
	int i;

	hash_seq_init(&iter, state->htab);

	pq_begintypsend(&buf);
	pq_sendint(&buf, n_aggregates, sizeof n_aggregates);
	pq_sendint(&buf, state->agg_type, sizeof state->agg_type);
	for (i = 0; i < n_aggregates; i++) {
		pq_sendint(&buf, state->agg_kinds[i], sizeof state->agg_kinds[i]);
	}

	pq_sendint64(&buf, hash_get_num_entries(state->htab));

    while ((entry = (vops_group_by_entry*)hash_seq_search(&iter)) != NULL)
    {
		pq_sendint64(&buf, entry->group_by);
		pq_sendint64(&buf, entry->count);
		for (i = 0; i < n_aggregates; i++) {
			pq_sendint64(&buf, entry->values[i].count);
			pq_sendint64(&buf, entry->values[i].acc.i8);
		}
	}

	result = pq_endtypsend(&buf);
	PG_RETURN_BYTEA_P(result);
}

PG_FUNCTION_INFO_V1(vops_agg_deserial);
Datum vops_agg_deserial(PG_FUNCTION_ARGS)
{
	bytea* sstate = PG_GETARG_BYTEA_P(0);
	vops_agg_state* state;
	StringInfoData buf;
	int64 size;
	int n_aggregates;
	int i;
	initStringInfo(&buf);
	appendBinaryStringInfo(&buf, VARDATA(sstate), VARSIZE(sstate) - VARHDRSZ);

	n_aggregates = pq_getmsgint(&buf, sizeof n_aggregates);
	state = vops_create_agg_state(n_aggregates);

	state->agg_type = (vops_type)pq_getmsgint(&buf, sizeof state->agg_type);
	for (i = 0; i < n_aggregates; i++) {
		state->agg_kinds[i] = (vops_agg_kind)pq_getmsgint(&buf, sizeof state->agg_kinds[i]);
	}
	size = pq_getmsgint64(&buf);
	while (--size >= 0) {
		int64 group_by = pq_getmsgint64(&buf);
		bool found;
		vops_group_by_entry* entry = (vops_group_by_entry*)hash_search(state->htab, &group_by, HASH_ENTER, &found);
		Assert(!found);
		entry->count = pq_getmsgint64(&buf);
		for (i = 0; i < n_aggregates; i++) {
			entry->values[i].count = pq_getmsgint64(&buf);
			entry->values[i].acc.i8 = pq_getmsgint64(&buf);
		}
	}
	pq_getmsgend(&buf);
	pfree(buf.data);

	PG_RETURN_POINTER(state);
}

#define ROTL32(x, r) ((x) << (r)) | ((x) >> (32 - (r)))
#define HASH_BITS 25
#define N_HASHES (1 << (32 - HASH_BITS))
#define MURMUR_SEED 0x5C1DB

static uint32 murmur_hash3_32(const void* key, const int len, const uint32 seed)
{
    const uint8* data = (const uint8*)key;
    const int nblocks = len / 4;

    uint32 h1 = seed;

    uint32 c1 = 0xcc9e2d51;
    uint32 c2 = 0x1b873593;
    int i;
    uint32 k1;
    const uint8* tail;
    const uint32* blocks = (const uint32 *)(data + nblocks*4);

    for(i = -nblocks; i; i++)
    {
        k1 = blocks[i];

        k1 *= c1;
        k1 = ROTL32(k1,15);
        k1 *= c2;

        h1 ^= k1;
        h1 = ROTL32(h1,13);
        h1 = h1*5+0xe6546b64;
    }

    tail = (const uint8*)(data + nblocks*4);

    k1 = 0;

    switch(len & 3)
    {
      case 3:
        k1 ^= tail[2] << 16;
        /* fall through */
      case 2:
        k1 ^= tail[1] << 8;
        /* fall through */
      case 1:
        k1 ^= tail[0];
        k1 *= c1;
        k1 = ROTL32(k1,15);
        k1 *= c2;
        h1 ^= k1;
    }

    h1 ^= len;
    h1 ^= h1 >> 16;
    h1 *= 0x85ebca6b;
    h1 ^= h1 >> 13;
    h1 *= 0xc2b2ae35;
    h1 ^= h1 >> 16;

    return h1;
}

inline static void calculate_zero_bits(uint32 h, uint8* max_zero_bits)
{
    int j = h >> HASH_BITS;
    int zero_bits = 1;
    while ((h & 1) == 0 && zero_bits <= HASH_BITS)  {
        h >>= 1;
        zero_bits += 1;
    }
    if (max_zero_bits[j] < zero_bits) {
        max_zero_bits[j] = zero_bits;
    }
}

inline static void calculate_hash_functions(void const* val, int size, uint8* max_zero_bits)
{
    uint32 h = murmur_hash3_32(val, size, MURMUR_SEED);
    calculate_zero_bits(h, max_zero_bits);
}

inline static void merge_zero_bits(uint8* dst_max_zero_bits, uint8* src_max_zero_bits)
{
    int i;
    for (i = 0; i < N_HASHES; i++) {
        if (dst_max_zero_bits[i] < src_max_zero_bits[i]) {
            dst_max_zero_bits[i] = src_max_zero_bits[i];
        }
    }
}

static uint64 approximate_distinct_count(uint8* max_zero_bits)
{
    const int m = N_HASHES;
    const double alpha_m = 0.7213 / (1 + 1.079 / (double)m);
    const double pow_2_32 = 0xffffffff;
    double E, c = 0;
    int i;
    for (i = 0; i < m; i++)
    {
        c += 1 / pow(2., (double)max_zero_bits[i]);
    }
    E = alpha_m * m * m / c;

    if (E <= (5 / 2. * m))
    {
        double V = 0;
        for (i = 0; i < m; i++)
        {
            if (max_zero_bits[i] == 0) V++;
        }

        if (V > 0)
        {
            E = m * log(m / V);
        }
    }
    else if (E > (1 / 30. * pow_2_32))
    {
        E = -pow_2_32 * log(1 - E / pow_2_32);
    }
    return (uint64)E;
}

typedef struct {
    uint8 max_zero_bits[N_HASHES];
} vops_approxdc_state;


PG_FUNCTION_INFO_V1(vops_approxdc_final);
Datum vops_approxdc_final(PG_FUNCTION_ARGS)
{
	vops_approxdc_state* state = (vops_approxdc_state*)PG_GETARG_POINTER(0);
	PG_RETURN_INT64(approximate_distinct_count(state->max_zero_bits));
}

PG_FUNCTION_INFO_V1(vops_approxdc_combine);
Datum vops_approxdc_combine(PG_FUNCTION_ARGS)
{
	vops_approxdc_state* state0 = (vops_approxdc_state*)PG_GETARG_POINTER(0);
	vops_approxdc_state* state1 = (vops_approxdc_state*)PG_GETARG_POINTER(1);
	if (state0 == NULL) {
		if (state1 == NULL) {
			PG_RETURN_NULL();
		} else {
			MemoryContext agg_context;
			if (!AggCheckCallContext(fcinfo, &agg_context))
				elog(ERROR, "aggregate function called in non-aggregate context");
			state0 = (vops_approxdc_state*)MemoryContextAllocZero(agg_context, sizeof(vops_approxdc_state));
			*state0 = *state1;
		}
	} else if (state1 != NULL) {
		merge_zero_bits(state0->max_zero_bits, state1->max_zero_bits);
	}
	PG_RETURN_POINTER(state0);
}

PG_FUNCTION_INFO_V1(vops_approxdc_serial);
Datum vops_approxdc_serial(PG_FUNCTION_ARGS)
{
	vops_approxdc_state* state = (vops_approxdc_state*)PG_GETARG_POINTER(0);
	bytea* p = (text*)palloc(VARHDRSZ + N_HASHES);
	SET_VARSIZE(p, VARHDRSZ + N_HASHES);
	memcpy(VARDATA(p), state->max_zero_bits, N_HASHES);
	PG_RETURN_BYTEA_P(p);
}

PG_FUNCTION_INFO_V1(vops_approxdc_deserial);
Datum vops_approxdc_deserial(PG_FUNCTION_ARGS)
{
	bytea* p = PG_GETARG_BYTEA_P(0);
	vops_approxdc_state* state = (vops_approxdc_state*)palloc(sizeof(vops_approxdc_state));
	memcpy(state->max_zero_bits, VARDATA(p), N_HASHES);
	Assert(VARSIZE(p) - VARHDRSZ == N_HASHES);
	PG_RETURN_POINTER(state);
}

#define APPROXDC_AGG(TYPE)												\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_approxdc_accumulate);				\
	Datum vops_##TYPE##_approxdc_accumulate(PG_FUNCTION_ARGS)			\
	{																	\
	    vops_##TYPE* opd = (vops_##TYPE*)PG_GETARG_POINTER(1);			\
		vops_approxdc_state* state = PG_ARGISNULL(0) ? NULL : (vops_approxdc_state*)PG_GETARG_POINTER(0); \
		uint64 mask = filter_mask & ~opd->hdr.empty_mask & ~opd->hdr.null_mask; \
		int i;															\
		for (i = 0; i < TILE_SIZE; i++) {								\
		    if (mask & ((uint64)1 << i)) {								\
			    if (state == NULL) {									\
					MemoryContext agg_context;							\
					if (!AggCheckCallContext(fcinfo, &agg_context))		\
						elog(ERROR, "aggregate function called in non-aggregate context"); \
					state = (vops_approxdc_state*)MemoryContextAllocZero(agg_context, sizeof(vops_approxdc_state)); \
				}														\
				calculate_hash_functions(&opd->payload[i], sizeof(opd->payload[i]), state->max_zero_bits); \
			}															\
		}																\
		if (state == NULL) {											\
			PG_RETURN_NULL();											\
		} else {														\
			PG_RETURN_POINTER(state);									\
		}																\
	}																    \


PG_FUNCTION_INFO_V1(vops_text_approxdc_accumulate);
Datum vops_text_approxdc_accumulate(PG_FUNCTION_ARGS)
{
	struct varlena* var = PG_GETARG_VARLENA_PP(1);
	vops_tile_hdr* opd = VOPS_TEXT_TILE(var);
	vops_approxdc_state* state = PG_ARGISNULL(1) ? NULL : (vops_approxdc_state*)PG_GETARG_POINTER(1);
	uint64 mask = filter_mask & ~opd->empty_mask & ~opd->null_mask;
	size_t elem_size = VOPS_ELEM_SIZE(var);
	char* elems = (char*)(opd+1);
	int i;
	for (i = 0; i < TILE_SIZE; i++) {
		if (mask & ((uint64)1 << i)) {
			if (state == NULL) {
				MemoryContext agg_context;
				if (!AggCheckCallContext(fcinfo, &agg_context))
					elog(ERROR, "aggregate function called in non-aggregate context");
				state = (vops_approxdc_state*)MemoryContextAllocZero(agg_context, sizeof(vops_approxdc_state));
			}
			calculate_hash_functions(elems + i*elem_size, elem_size, state->max_zero_bits);
		}
	}
	if (state == NULL) {
		PG_RETURN_NULL();
	} else {
		PG_RETURN_POINTER(state);
	}
}


#define REGISTER_BIN_OP(TYPE,OP,COP,XTYPE,GXTYPE)			\
	BIN_OP(TYPE,OP,COP)										\
	BIN_LCONST_OP(TYPE,XTYPE,GXTYPE,OP,COP)					\
	BIN_RCONST_OP(TYPE,XTYPE,GXTYPE,OP,COP)

#define REGISTER_CMP_OP(TYPE,OP,COP,XTYPE,GXTYPE)			\
	CMP_OP(TYPE,OP,COP)										\
	CMP_LCONST_OP(TYPE,XTYPE,GXTYPE,OP,COP)					\
	CMP_RCONST_OP(TYPE,XTYPE,GXTYPE,OP,COP)

#define REGISTER_TYPE(TYPE,SSTYPE,CTYPE,XTYPE,STYPE,DTYPE,GCTYPE,GXTYPE,GSTYPE,FORMAT,PREC) \
	UNARY_OP(TYPE,neg,-)									\
	REGISTER_BIN_OP(TYPE,add,+,XTYPE,GXTYPE)				\
	REGISTER_BIN_OP(TYPE,sub,-,XTYPE,GXTYPE)				\
	REGISTER_BIN_OP(TYPE,mul,*,XTYPE,GXTYPE)				\
	REGISTER_BIN_OP(TYPE,div,/,XTYPE,GXTYPE)				\
	REGISTER_CMP_OP(TYPE,eq,==,XTYPE,GXTYPE)				\
	REGISTER_CMP_OP(TYPE,ne,!=,XTYPE,GXTYPE)				\
	REGISTER_CMP_OP(TYPE,lt,<,XTYPE,GXTYPE)					\
	REGISTER_CMP_OP(TYPE,le,<=,XTYPE,GXTYPE)				\
	REGISTER_CMP_OP(TYPE,gt,>,XTYPE,GXTYPE)					\
	REGISTER_CMP_OP(TYPE,ge,>=,XTYPE,GXTYPE)				\
	BETWIXT_OP(TYPE,XTYPE,GXTYPE)							\
	IFNULL_OP(TYPE,CTYPE,GXTYPE)							\
	CONST_OP(TYPE,CTYPE,GXTYPE)								\
	COALESCE_OP(TYPE,GXTYPE)								\
	SUM_AGG(TYPE,STYPE,GSTYPE)								\
	SUM_WIN(TYPE,SSTYPE,STYPE)								\
	AVG_WIN(TYPE)											\
	LAG_WIN(TYPE,CTYPE)										\
	AVG_AGG(TYPE)											\
	APPROXDC_AGG(TYPE)										\
	VAR_AGG(TYPE)											\
	WAVG_AGG(TYPE)											\
	MINMAX_AGG(TYPE,CTYPE,GCTYPE,min,<)						\
	MINMAX_AGG(TYPE,CTYPE,GCTYPE,max,>)						\
	MINMAX_WIN(TYPE,CTYPE,min,<)							\
	MINMAX_WIN(TYPE,CTYPE,max,>)							\
	FIRST_AGG(TYPE,GCTYPE,SCALAR_PAYLOAD)					\
	LAST_AGG(TYPE,GCTYPE,SCALAR_PAYLOAD)					\
	LOW_AGG(TYPE,CTYPE,GCTYPE)								\
	HIGH_AGG(TYPE,CTYPE,GCTYPE)								\
	IN_FUNC(TYPE,CTYPE,STYPE,FORMAT)						\
	OUT_FUNC(TYPE,STYPE,FORMAT,PREC)						\
	GROUP_BY_FUNC(TYPE)									    \
	FIRST_FUNC(TYPE,DTYPE,first,<,SCALAR_PAYLOAD)			\
	FIRST_FUNC(TYPE,DTYPE,last,>,SCALAR_PAYLOAD)

/*             TYPE,   SSTYPE, CTYPE,  XTYPE,  STYPE,  DTYPE, GCTYPE, GXTYPE, GSTYPE, FORMAT, PREC */
REGISTER_TYPE( char,    int8,   char,   char, long64,   Char,   CHAR,   CHAR,  INT64, lld, -1)
REGISTER_TYPE( int2,    int8,  int16,  int32, long64,  Int16,  INT16,  INT32,  INT64, lld, -1)
REGISTER_TYPE( int4,    int8,  int32,  int32, long64,  Int32,  INT32,  INT32,  INT64, lld, -1)
REGISTER_TYPE( int8,    int8,  int64,  int64, long64,  Int64,  INT64,  INT64,  INT64, lld, -1)
REGISTER_TYPE(float4, float8, float4, float8, float8, Float4, FLOAT4, FLOAT8, FLOAT8, lg, Max(1, FLT_DIG + extra_float_digits))
REGISTER_TYPE(float8, float8, float8, float8, float8, Float8, FLOAT8, FLOAT8, FLOAT8, lg, Max(1, DBL_DIG + extra_float_digits))

REGISTER_BIN_OP(char,rem,%,char,CHAR)
REGISTER_BIN_OP(int2,rem,%,int32,INT32)
REGISTER_BIN_OP(int4,rem,%,int32,INT32)
REGISTER_BIN_OP(int8,rem,%,int64,INT64)


PG_FUNCTION_INFO_V1(vops_deltatime_output);
Datum vops_deltatime_output(PG_FUNCTION_ARGS)
{
	Interval interval;
	interval.time = PG_GETARG_INT64(0);
	interval.day  = 0;
	interval.month = 0;
	PG_RETURN_DATUM(DirectFunctionCall1(interval_out, PointerGetDatum(&interval)));
}

PG_FUNCTION_INFO_V1(vops_deltatime_input);
Datum vops_deltatime_input(PG_FUNCTION_ARGS)
{
	Interval* interval =
		DatumGetIntervalP(DirectFunctionCall3(interval_in,
											  PG_GETARG_DATUM(0),
											  ObjectIdGetDatum(InvalidOid),
											  Int32GetDatum(-1)));
	if (interval->day || interval->month)
		elog(ERROR, "Day, month and year intervals are not supported");
	PG_RETURN_INT64(interval->time);
}

PG_FUNCTION_INFO_V1(vops_time_interval);
Datum vops_time_interval(PG_FUNCTION_ARGS)
{
	Interval* interval = PG_GETARG_INTERVAL_P(0);
	if (interval->day || interval->month)
		elog(ERROR, "Day, month and year intervals are not supported");
	PG_RETURN_INT64(interval->time);
}


static struct varlena*
vops_alloc_text(int width)
{
	struct varlena* var = (struct varlena*)palloc0(VOPS_SIZEOF_TEXT(width));
	SET_VARSIZE(var, VOPS_SIZEOF_TEXT(width));
	return var;
}

PG_FUNCTION_INFO_V1(vops_text_input);
Datum vops_text_input(PG_FUNCTION_ARGS)
{
	char const* str = PG_GETARG_CSTRING(0);
	int width = PG_GETARG_INT32(2);
	struct varlena* var;
	vops_tile_hdr* result;
	char* dst;
	int i, len;

	if (str == NULL) {
		PG_RETURN_NULL();
	}
	if (width <= 0)
		elog(ERROR, "Invalid vops_char width");

	var = vops_alloc_text(width);
	result = VOPS_TEXT_TILE(var);
	result->null_mask = 0;
	result->empty_mask = 0;
	dst = (char*)(result + 1);
	if (*str != '{')
	{
		len = (int)strlen(str);
		if (len >= width) {
			for (i=0; i < TILE_SIZE; i++) {
				memcpy(dst, str, width);
				dst += width;
			}
		} else {
			for (i=0; i < TILE_SIZE; i++) {
				memcpy(dst, str, len);
				memset(dst + len, '\0', width - len);
				dst += width;
			}
		}
	} else {
		str += 1;
		for (i=0; i < TILE_SIZE; i++, dst += width)
		{
			if (*str == ',' || *str == '}') {
				result->empty_mask |= (uint64)1 << i;
				if (*str == ',') {
					str += 1;
				}
			} else {
				if (*str == '?') {
					result->null_mask |= (uint64)1 << i;
					str += 1;
				} else {
					char const* end = str;
					while (*++end != '}' && *end != ',' && *end != '\0');
					len = end - str;
					if (len < width) {
						memcpy(dst, str, len);
						memset(dst + len, '\0', width - len);
					} else {
						memcpy(dst, str, width);
					}
					str = end;
				}
				if (*str == ',') {
					str += 1;
				} else if (*str != '}') {
					elog(ERROR, "Failed to parse tile: separator expected '%s' found", str);
				}
			}
		}
		if (*str != '}') {
			elog(ERROR, "Failed to parse tile: unexpected trailing data '%s'", str);
		}
	}
	PG_RETURN_POINTER(var);
}

PG_FUNCTION_INFO_V1(vops_text_output);
Datum vops_text_output(PG_FUNCTION_ARGS)
{
	struct varlena* var =  (struct varlena*)PG_GETARG_POINTER(0);
	vops_tile_hdr* tile = VOPS_TEXT_TILE(var);
	char* src = (char*)(tile + 1);
	int width = VOPS_ELEM_SIZE(var);
	int i;
	char* buf = palloc((width+1)*TILE_SIZE + 2);
	char* dst = buf;
	char sep = '{';
	for (i=0; i < TILE_SIZE; i++, src += width) {
		*dst++ = sep;
		if (!(tile->empty_mask & ((uint64)1 << i))) {
			if (tile->null_mask & ((uint64)1 << i)) {
				*dst++ = '?';
			} else {
				strncpy(dst, src, width);
				dst += strnlen(src, width);
			}
		}
		sep = ',';
	}
	*dst++ = '}';
	*dst = '\0';
	PG_RETURN_CSTRING(buf);
}

PG_FUNCTION_INFO_V1(vops_text_typmod_in);
Datum vops_text_typmod_in(PG_FUNCTION_ARGS)
{
    ArrayType* arr = (ArrayType*)DatumGetPointer(PG_DETOAST_DATUM(PG_GETARG_DATUM(0)));
    int n;
    int32* typemods = ArrayGetIntegerTypmods(arr, &n);
    int len;
    if (n != 1)
	   elog(ERROR, "vops_text should have exactly one type modifier");
    len = typemods[0];
    PG_RETURN_INT32(len);
}

#define VOPS_TEXT_CMP(op,cmp)										    \
PG_FUNCTION_INFO_V1(vops_text_##op);								    \
Datum vops_text_##op(PG_FUNCTION_ARGS)									\
{																		\
	struct varlena* vl = PG_GETARG_VARLENA_PP(0);						\
	struct varlena* vr = PG_GETARG_VARLENA_PP(1);						\
    vops_tile_hdr* left = VOPS_TEXT_TILE(vl);							\
    vops_tile_hdr* right = VOPS_TEXT_TILE(vl);							\
	size_t left_elem_size = VOPS_ELEM_SIZE(vl);							\
	size_t right_elem_size = VOPS_ELEM_SIZE(vr);						\
	char* l = (char*)(left + 1);										\
	char* r = (char*)(right + 1);										\
	vops_bool* result = (vops_bool*)palloc(sizeof(vops_bool));			\
	int i;																\
	uint64 payload = 0;													\
	if (left_elem_size < right_elem_size) {								\
		for (i = 0; i < TILE_SIZE; i++) {								\
			int diff = memcmp(l + left_elem_size*i, r + right_elem_size*i, left_elem_size); \
			if (diff == 0 && r[right_elem_size*i + left_elem_size] != '\0') diff = -1;	\
			payload |= (uint64)(diff cmp 0) << i;						\
		}																\
	} else if (left_elem_size > right_elem_size) {						\
		for (i = 0; i < TILE_SIZE; i++) {								\
			int diff = memcmp(l + left_elem_size*i, r + right_elem_size*i, right_elem_size); \
			if (diff == 0 && l[left_elem_size*i + right_elem_size] != '\0') diff = 1;	\
			payload |= (uint64)(diff cmp 0) << i;						\
		}																\
	} else {															\
		for (i = 0; i < TILE_SIZE; i++) payload |= (uint64)(memcmp(l + left_elem_size*i, r + right_elem_size*i, left_elem_size) cmp 0) << i; \
	}																	\
	result->payload = payload;											\
	result->hdr.null_mask = left->null_mask | right->null_mask;			\
	result->hdr.empty_mask = left->empty_mask | right->empty_mask;		\
	PG_RETURN_POINTER(result);											\
}																		\
PG_FUNCTION_INFO_V1(vops_text_##op##_rconst);						    \
Datum vops_text_##op##_rconst(PG_FUNCTION_ARGS)						    \
{																		\
	struct varlena* var = PG_GETARG_VARLENA_PP(0);						\
	text* t = PG_GETARG_TEXT_P(1);										\
	vops_tile_hdr* left = VOPS_TEXT_TILE(var);							\
	size_t elem_size = VOPS_ELEM_SIZE(var);								\
	char* const_data = (char*)VARDATA(t);								\
	size_t const_size = VARSIZE(t) - VARHDRSZ;							\
	char* l = (char*)(left + 1);										\
	vops_bool* result = (vops_bool*)palloc(sizeof(vops_bool));			\
	int i;																\
	uint64 payload = 0;													\
	if (elem_size > const_size) {										\
        for (i = 0; i < TILE_SIZE; i++) {								\
			int diff = memcmp(l + elem_size*i, const_data, const_size); \
			if (diff == 0) diff = (l[elem_size*i + const_size] == '\0') ? 0 : 1; \
			payload |= (uint64)(diff cmp 0) << i;						\
		}																\
	} else if (elem_size < const_size) {								\
        for (i = 0; i < TILE_SIZE; i++) {								\
			int diff = memcmp(l + elem_size*i, const_data, elem_size);	\
			if (diff == 0) diff = -1;									\
			payload |= (uint64)(diff cmp 0) << i;						\
		}																\
	} else {															\
        for (i = 0; i < TILE_SIZE; i++) {								\
			int diff = memcmp(l + elem_size*i, const_data, elem_size);	\
			payload |= (uint64)(diff cmp 0) << i;						\
		}																\
	}																	\
	result->payload = payload;											\
	result->hdr = *left;												\
	PG_RETURN_POINTER(result);											\
}																		\
PG_FUNCTION_INFO_V1(vops_text_##op##_lconst);						    \
Datum vops_text_##op##_lconst(PG_FUNCTION_ARGS)							\
{																		\
	struct varlena* var = PG_GETARG_VARLENA_PP(1);						\
	text* t = PG_GETARG_TEXT_P(0);										\
    vops_tile_hdr* right = VOPS_TEXT_TILE(var);							\
	size_t elem_size = VOPS_ELEM_SIZE(var);								\
	char* const_data = (char*)VARDATA(t);								\
	size_t const_size = VARSIZE(t) - VARHDRSZ;							\
	char* r = (char*)(right + 1);										\
	vops_bool* result = (vops_bool*)palloc(sizeof(vops_bool));			\
	int i;																\
	uint64 payload = 0;													\
	if (elem_size > const_size) {										\
        for (i = 0; i < TILE_SIZE; i++) {								\
			int diff = memcmp(const_data, r + elem_size*i, const_size);	\
			if (diff == 0) diff = (r[elem_size*i + const_size] == '\0') ? 0 : -1; \
			payload |= (uint64)(diff cmp 0) << i;						\
		}																\
	} else if (elem_size < const_size) {								\
        for (i = 0; i < TILE_SIZE; i++) {								\
			int diff = memcmp(const_data, r + elem_size*i, elem_size);	\
			if (diff == 0) diff = 1;									\
			payload |= (uint64)(diff cmp 0) << i;						\
		}																\
	} else {															\
        for (i = 0; i < TILE_SIZE; i++) {								\
			int diff = memcmp(const_data, r + elem_size*i, elem_size);	\
			payload |= (uint64)(diff cmp 0) << i;						\
		}																\
	}																	\
	result->payload = payload;											\
	result->hdr = *right;												\
	PG_RETURN_POINTER(result);											\
}																		\

VOPS_TEXT_CMP(eq, ==);
VOPS_TEXT_CMP(ne, !=);
VOPS_TEXT_CMP(le, <=);
VOPS_TEXT_CMP(lt, <);
VOPS_TEXT_CMP(ge, >=);
VOPS_TEXT_CMP(gt, >);

PG_FUNCTION_INFO_V1(vops_text_const);
Datum vops_text_const(PG_FUNCTION_ARGS)
{
	text* t = PG_GETARG_TEXT_P(0);
	char* const_data = (char*)VARDATA(t);
	size_t const_size = VARSIZE(t) - VARHDRSZ;
	int width = PG_GETARG_INT32(1);
	struct varlena* var = vops_alloc_text(width);
	vops_tile_hdr* result = VOPS_TEXT_TILE(var);
	char* dst = (char*)(result + 1);
	int i;
	for (i = 0; i < TILE_SIZE; i++)
	{
		if (const_size < width)
		{
			memcpy(dst, const_data, const_size);
			memset(dst + const_size, 0, width - const_size);
		}
		else
		{
			memcpy(dst, const_data, width);
		}
		dst += width;
	}
	result->null_mask = 0;
	result->empty_mask = 0;
	PG_RETURN_POINTER(var);
}

PG_FUNCTION_INFO_V1(vops_text_concat);
Datum vops_text_concat(PG_FUNCTION_ARGS)
{
	struct varlena* vl = PG_GETARG_VARLENA_PP(0);
	struct varlena* vr = PG_GETARG_VARLENA_PP(1);
    vops_tile_hdr* left = VOPS_TEXT_TILE(vl);
    vops_tile_hdr* right = VOPS_TEXT_TILE(vl);
	size_t left_elem_size = VOPS_ELEM_SIZE(vl);
	size_t right_elem_size = VOPS_ELEM_SIZE(vr);
	char* l = (char*)(left + 1);
	char* r = (char*)(right + 1);
	struct varlena* var = vops_alloc_text(left_elem_size + right_elem_size);
	vops_tile_hdr* result = VOPS_TEXT_TILE(var);
	char* dst = (char*)(result + 1);
	int i;
	for (i = 0; i < TILE_SIZE; i++) {
		memcpy(dst + i*(left_elem_size + right_elem_size), l + left_elem_size*i, left_elem_size);
		memcpy(dst + i*(left_elem_size + right_elem_size) + left_elem_size, r + right_elem_size*i, right_elem_size);
	}
	result->null_mask = left->null_mask | right->null_mask;
	result->empty_mask = left->empty_mask | right->empty_mask;
	PG_RETURN_POINTER(var);
}

PG_FUNCTION_INFO_V1(vops_betwixt_text);
Datum vops_betwixt_text(PG_FUNCTION_ARGS)
{
	struct varlena* var = PG_GETARG_VARLENA_PP(0);
	text* from = PG_GETARG_TEXT_P(1);
	text* till = PG_GETARG_TEXT_P(2);
	size_t elem_size = VOPS_ELEM_SIZE(var);
	char* from_data = (char*)VARDATA(from);
	size_t from_size = VARSIZE(from) - VARHDRSZ;
	char* till_data = (char*)VARDATA(till);
	size_t till_size = VARSIZE(till) - VARHDRSZ;
    vops_tile_hdr* left = VOPS_TEXT_TILE(var);
	char* l = (char*)(left + 1);
	vops_bool* result = (vops_bool*)palloc(sizeof(vops_bool));
	int i;
	uint64 payload = 0;
	size_t min_from_size = Min(elem_size, from_size);
	size_t min_till_size = Min(elem_size, till_size);
	for (i = 0; i < TILE_SIZE; i++) {
		int diff = memcmp(l + elem_size*i, from_data, min_from_size);
		if (diff == 0 && elem_size != from_size)
			diff = (elem_size < from_size) ? ((from_data[elem_size] == '\0') ? 0 : -1) : ((l[elem_size*i + from_size] == '\0') ? 0 : 1);
		if (diff >= 0) {
			diff = memcmp(l + elem_size*i, till_data, min_till_size);
			if (diff == 0 && elem_size != till_size)
				diff = (elem_size < till_size) ? ((till_data[elem_size] == '\0') ? 0 : -1) : ((l[elem_size*i + till_size] == '\0') ? 0 : 1);
			if (diff <= 0)
				payload |= (uint64)1 << i;
		}
	}
	result->payload = payload;
	result->hdr = *left;
	PG_RETURN_POINTER(result);
}

PG_FUNCTION_INFO_V1(vops_ifnull_text);
Datum vops_ifnull_text(PG_FUNCTION_ARGS)
{
	struct varlena* var = PG_GETARG_VARLENA_PP(0);
	vops_tile_hdr* opd = VOPS_TEXT_TILE(var);
	size_t elem_size = VOPS_ELEM_SIZE(var);
	text* subst = PG_GETARG_TEXT_P(1);
	char* subst_data = (char*)VARDATA(subst);
	size_t subst_size = VARSIZE(subst) - VARHDRSZ;
	struct varlena* result = vops_alloc_text(elem_size);
	vops_tile_hdr* res = VOPS_TEXT_TILE(result);
	char* dst = (char*)(res + 1);
	char* src = (char*)(opd + 1);
	int i;
	for (i = 0; i < TILE_SIZE; i++) {
		if (opd->null_mask & ((uint64)1 << i)) {
			if (subst_size < elem_size) {
				memcpy(dst + elem_size*i, subst_data, subst_size);
				memset(dst + elem_size*i + subst_size, 0, elem_size - subst_size);
			} else {
				memcpy(dst + elem_size*i, subst_data, elem_size);
			}
		} else {
			memcpy(dst + elem_size*i, src + elem_size*i, elem_size);
		}
	}
	res->null_mask = 0;
	res->empty_mask = opd->empty_mask;
	PG_RETURN_POINTER(result);
}

PG_FUNCTION_INFO_V1(vops_coalesce_text);
Datum vops_coalesce_text(PG_FUNCTION_ARGS)
{
	struct varlena* left = PG_GETARG_VARLENA_PP(0);
	vops_tile_hdr* opd = VOPS_TEXT_TILE(left);
	size_t elem_size = VOPS_ELEM_SIZE(left);

	struct varlena* right = PG_GETARG_VARLENA_PP(1);
	vops_tile_hdr* subst = VOPS_TEXT_TILE(right);
	size_t subst_elem_size = VOPS_ELEM_SIZE(right);

	struct varlena* result = vops_alloc_text(elem_size);
	vops_tile_hdr* res = VOPS_TEXT_TILE(result);
	char* dst = (char*)(res + 1);
	char* src = (char*)(opd + 1);
	int i;
	for (i = 0; i < TILE_SIZE; i++) {
		if (opd->null_mask & ((uint64)1 << i)) {
			if (subst_elem_size < elem_size) {
				memcpy(dst + elem_size*i, src + subst_elem_size*i, subst_elem_size);
				memset(dst + elem_size*i + subst_elem_size, 0, elem_size - subst_elem_size);
			} else {
				memcpy(dst + elem_size*i, src + subst_elem_size*i, elem_size);
			}
		}
	}
	res->null_mask = opd->null_mask & subst->null_mask;
	res->empty_mask = opd->empty_mask | subst->empty_mask;
	PG_RETURN_POINTER(result);
}

PG_FUNCTION_INFO_V1(vops_text_first);
Datum vops_text_first(PG_FUNCTION_ARGS)
{
	struct varlena* var = PG_GETARG_VARLENA_PP(0);
	vops_tile_hdr* tile = VOPS_TEXT_TILE(var);
	size_t elem_size = VOPS_ELEM_SIZE(var);

	uint64 mask = ~(tile->empty_mask | tile->null_mask);
	int i;
	for (i = 0; i < TILE_SIZE; i++) {
		if (mask & ((uint64)1 << i)) {
			char* src = (char*)(tile + 1) + i*elem_size;
			size_t len = strnlen(src, elem_size);
			text* t = (text*)palloc(VARHDRSZ + len);
			SET_VARSIZE(t, VARHDRSZ + len);
			memcpy(VARDATA(t), src, len);
			PG_RETURN_POINTER(t);
		}
	}
	PG_RETURN_NULL();
}

PG_FUNCTION_INFO_V1(vops_text_last);
Datum vops_text_last(PG_FUNCTION_ARGS)
{
	struct varlena* var = PG_GETARG_VARLENA_PP(0);
	vops_tile_hdr* tile = VOPS_TEXT_TILE(var);
	size_t elem_size = VOPS_ELEM_SIZE(var);

	uint64 mask = ~(tile->empty_mask | tile->null_mask);
	int i;
	for (i = TILE_SIZE; --i >= 0;) {
		if (mask & ((uint64)1 << i)) {
			char* src = (char*)(tile + 1) + i*elem_size;
			size_t len = strnlen(src, elem_size);
			text* t = (text*)palloc(VARHDRSZ + len);
			SET_VARSIZE(t, VARHDRSZ + len);
			memcpy(VARDATA(t), src, len);
			PG_RETURN_POINTER(t);
		}
	}
	PG_RETURN_NULL();
}

PG_FUNCTION_INFO_V1(vops_text_low);
Datum vops_text_low(PG_FUNCTION_ARGS)
{
	struct varlena* var = PG_GETARG_VARLENA_PP(0);
	vops_tile_hdr* tile = VOPS_TEXT_TILE(var);
	size_t elem_size = VOPS_ELEM_SIZE(var);

	uint64 mask = ~(tile->empty_mask | tile->null_mask);
	bool is_null = true;
	int min = 0;
	int i;
	char* src = (char*)(tile + 1);

	for (i = 0; i < TILE_SIZE; i++) {
		if (mask & ((uint64)1 << i)) {
			if (is_null || memcmp(src + elem_size*i, src + elem_size*min, elem_size) < 0) {
				is_null = false;
				min = i;
			}
		}
	}
	if (is_null) {
		PG_RETURN_NULL();
	} else {
		size_t len = strnlen(src + min*elem_size, elem_size);
		text* t = (text*)palloc(VARHDRSZ + len);
		SET_VARSIZE(t, VARHDRSZ + len);
		memcpy(VARDATA(t), src + min*elem_size, len);
		PG_RETURN_POINTER(t);
	}
}

PG_FUNCTION_INFO_V1(vops_text_high);
Datum vops_text_high(PG_FUNCTION_ARGS)
{
	struct varlena* var = PG_GETARG_VARLENA_PP(0);
	vops_tile_hdr* tile = VOPS_TEXT_TILE(var);
	size_t elem_size = VOPS_ELEM_SIZE(var);

	uint64 mask = ~(tile->empty_mask | tile->null_mask);
	bool is_null = true;
	int max = 0;
	int i;
	char* src = (char*)(tile + 1);

	for (i = 0; i < TILE_SIZE; i++) {
		if (mask & ((uint64)1 << i)) {
			if (is_null || memcmp(src + elem_size*i, src + elem_size*max, elem_size) > 0) {
				is_null = false;
				max = i;
			}
		}
	}
	if (is_null) {
		PG_RETURN_NULL();
	} else {
		size_t len = strnlen(src + max*elem_size, elem_size);
		text* t = (text*)palloc(VARHDRSZ + len);
		SET_VARSIZE(t, VARHDRSZ + len);
		memcpy(VARDATA(t), src + max*elem_size, len);
		PG_RETURN_POINTER(t);
	}
}

PG_FUNCTION_INFO_V1(vops_text_first_accumulate);
Datum vops_text_first_accumulate(PG_FUNCTION_ARGS)
{
	vops_first_state* state = (vops_first_state*)PG_GETARG_POINTER(0);
	struct varlena* vars = PG_GETARG_VARLENA_PP(1);
	vops_int8* tss = (vops_int8*) PG_GETARG_POINTER(2);
	if (state == NULL) {
		MemoryContext agg_context;
		if (!AggCheckCallContext(fcinfo, &agg_context))
			elog(ERROR, "aggregate function called in non-aggregate context");
		state = (vops_first_state*)MemoryContextAlloc(agg_context, sizeof(vops_first_state));
		state->val_is_null = true;
		state->ts_is_null = true;
	}
	if (tss != NULL)
	{
		int i;
		uint64 mask = ~(tss->hdr.empty_mask | tss->hdr.null_mask);
		for (i = 0; i < TILE_SIZE; i++) {
			if (mask & ((uint64)1 << i)) {
				if (state->ts_is_null || tss->payload[i] < state->ts) {
					state->ts = tss->payload[i];
					state->ts_is_null = false;
					if (vars != NULL) {
						vops_tile_hdr* tile = VOPS_TEXT_TILE(vars);
						if ((tile->empty_mask | tile->null_mask) & ((uint64)1 << i)) {
							state->val_is_null = true;
						} else {
							text* dst = (text*)DatumGetPointer(state->val);
							size_t elem_size = VOPS_ELEM_SIZE(vars);
							char* src;
							size_t len;
							if (dst == NULL) {
								MemoryContext agg_context = GetMemoryChunkContext(state);
								dst = (text*)MemoryContextAlloc(agg_context, VARHDRSZ + elem_size);
								state->val = PointerGetDatum(dst);
							}
							src = (char*)(tile + 1) + elem_size*i;
							len = strnlen(src, elem_size);
							memcpy(VARDATA(dst), src, len);
							SET_VARSIZE(dst, VARHDRSZ + len);
							state->val_is_null = false;
						}
					} else {
						state->val_is_null = true;
					}
				}
			}
		}
	}
	PG_RETURN_POINTER(state);
}

PG_FUNCTION_INFO_V1(vops_text_last_accumulate);
Datum vops_text_last_accumulate(PG_FUNCTION_ARGS)
{
	vops_first_state* state = (vops_first_state*)PG_GETARG_POINTER(0);
	struct varlena* vars = PG_GETARG_VARLENA_PP(1);
	vops_int8* tss = (vops_int8*)PG_GETARG_POINTER(2);
	if (state == NULL) {
		MemoryContext agg_context;
		if (!AggCheckCallContext(fcinfo, &agg_context))
			elog(ERROR, "aggregate function called in non-aggregate context");
		state = (vops_first_state*)MemoryContextAlloc(agg_context, sizeof(vops_first_state));
		state->val_is_null = true;
		state->ts_is_null = true;
	}
	if (tss != NULL)
	{
		int i;
		uint64 mask = ~(tss->hdr.empty_mask | tss->hdr.null_mask);
		for (i = TILE_SIZE; --i >= 0;) {
			if (mask & ((uint64)1 << i)) {
				if (state->ts_is_null || tss->payload[i] > state->ts) {
					state->ts = tss->payload[i];
					state->ts_is_null = false;
					if (vars != NULL) {
						vops_tile_hdr* tile = VOPS_TEXT_TILE(vars);
						if ((tile->empty_mask | tile->null_mask) & ((uint64)1 << i)) {
							state->val_is_null = true;
						} else {
							text* dst = (text*)DatumGetPointer(state->val);
							size_t elem_size = VOPS_ELEM_SIZE(vars);
							char* src;
							size_t len;
							if (dst == NULL) {
								MemoryContext agg_context = GetMemoryChunkContext(state);
								dst = (text*)MemoryContextAlloc(agg_context, VARHDRSZ + elem_size);
								state->val = PointerGetDatum(dst);
							}
							src = (char*)(tile + 1) + elem_size*i;
							len = strnlen(src, elem_size);
							memcpy(VARDATA(dst), src, len);
							SET_VARSIZE(dst, VARHDRSZ + len);
							state->val_is_null = false;
						}
					} else {
						state->val_is_null = true;
					}
				}
			}
		}
	}
	PG_RETURN_POINTER(state);
}

PG_FUNCTION_INFO_V1(vops_first_final);
Datum vops_first_final(PG_FUNCTION_ARGS)
{
	vops_first_state* state = (vops_first_state*)PG_GETARG_POINTER(0);
	if (state->val_is_null)
		PG_RETURN_NULL();
	else
		PG_RETURN_DATUM(state->val);
}

PG_FUNCTION_INFO_V1(vops_first_combine);
Datum vops_first_combine(PG_FUNCTION_ARGS)
{
	vops_first_state* state0 = (vops_first_state*)PG_GETARG_POINTER(0);
	vops_first_state* state1 = (vops_first_state*)PG_GETARG_POINTER(1);
	if (state0 == NULL) {
		if (state1 == NULL) {
			PG_RETURN_NULL();
		} else {
			MemoryContext agg_context;
			if (!AggCheckCallContext(fcinfo, &agg_context))
				elog(ERROR, "aggregate function called in non-aggregate context");
			state0 = (vops_first_state*)MemoryContextAlloc(agg_context, sizeof(vops_first_state));
			*state0 = *state1;
		}
	} else if (state1 != NULL && !state1->ts_is_null && (state0->ts_is_null || state0->ts > state1->ts)) {
		state0->ts_is_null = false;
		state0->val_is_null = state1->val_is_null;
		state0->ts = state1->ts;
		state0->val = state1->val;
	}
	PG_RETURN_POINTER(state0);
}

PG_FUNCTION_INFO_V1(vops_last_combine);
Datum vops_last_combine(PG_FUNCTION_ARGS)
{
	vops_first_state* state0 = (vops_first_state*)PG_GETARG_POINTER(0);
	vops_first_state* state1 = (vops_first_state*)PG_GETARG_POINTER(1);
	if (state0 == NULL) {
		if (state1 == NULL) {
			PG_RETURN_NULL();
		} else {
			MemoryContext agg_context;
			if (!AggCheckCallContext(fcinfo, &agg_context))
				elog(ERROR, "aggregate function called in non-aggregate context");
			state0 = (vops_first_state*)MemoryContextAlloc(agg_context, sizeof(vops_first_state));
			*state0 = *state1;
		}
	} else if (state1 != NULL && !state1->ts_is_null && (state0->ts_is_null || state0->ts < state1->ts)) {
		state0->ts_is_null = false;
		state0->val_is_null = state1->val_is_null;
		state0->ts = state1->ts;
		state0->val = state1->val;
	}
	PG_RETURN_POINTER(state0);
}


const size_t vops_sizeof[] =
{
	sizeof(vops_bool),
	sizeof(vops_char),
	sizeof(vops_int2),
	sizeof(vops_int4),
	sizeof(vops_int8),
	sizeof(vops_int4),
	sizeof(vops_int8),
	sizeof(vops_float4),
	sizeof(vops_float8),
	sizeof(vops_int8),
	0
};

PG_FUNCTION_INFO_V1(vops_populate);
Datum vops_populate(PG_FUNCTION_ARGS)
{
    Oid destination = PG_GETARG_OID(0);
    Oid source = PG_GETARG_OID(1);
    char const* predicate = PG_GETARG_CSTRING(2);
    char const* sort = PG_GETARG_CSTRING(3);
	char* sql;
	char sep;
	TupleDesc spi_tupdesc;
	int i, j, n, n_attrs;
	vops_type_info* types;
	Datum* values;
	bool*  nulls;
    SPIPlanPtr plan;
    Portal portal;
	int rc;
	bool is_null;
	int64 loaded;
	bool type_checked = false;
	static Oid self_oid = InvalidOid;
    char stmt[MAX_SQL_STMT_LEN];

	/* Detect case when extension is drop and created several times */
	if (fcinfo->flinfo->fn_oid != self_oid)
	{
		reset_static_cache();
		self_oid = fcinfo->flinfo->fn_oid;
	}

    SPI_connect();
	sql = psprintf("select attname,atttypid,atttypmod from pg_attribute where attrelid=%d and attnum>0 order by attnum", destination);
    rc = SPI_execute(sql, true, 0);
    if (rc != SPI_OK_SELECT) {
        elog(ERROR, "Select failed with status %d", rc);
    }
    n_attrs = SPI_processed;
    if (n_attrs == 0) {
        elog(ERROR, "Table %s.%s doesn't exist",
			 get_namespace_name(get_rel_namespace(destination)),
			 get_rel_name(destination));
    }
	types = (vops_type_info*)palloc(sizeof(vops_type_info)*n_attrs);
	values = (Datum*)palloc(sizeof(Datum)*n_attrs);
	nulls = (bool*)palloc0(sizeof(bool)*n_attrs);

	n = sprintf(stmt, "select");
	sep = ' ';
	spi_tupdesc = SPI_tuptable->tupdesc;
	for (i = 0; i < n_attrs; i++) {
        HeapTuple spi_tuple = SPI_tuptable->vals[i];
        char const* name = SPI_getvalue(spi_tuple, spi_tupdesc, 1);
        Oid type_id = DatumGetObjectId(SPI_getbinval(spi_tuple, spi_tupdesc, 2, &is_null));
		types[i].dst_type = type_id;
		types[i].tid = vops_get_type(type_id);
		get_typlenbyvalalign(type_id, &types[i].len, &types[i].byval, &types[i].align);
		if (types[i].tid != VOPS_LAST && types[i].len < 0) { /* varying length type: extract size from atttypmod */
			types[i].len = DatumGetInt32(SPI_getbinval(spi_tuple, spi_tupdesc, 3, &is_null));
			if (types[i].len < 0) {
				elog(ERROR, "Size of column %s is unknown", name);
			}
		}
		n += sprintf(stmt + n, "%c%s", sep, name);
		sep = ',';
		SPI_freetuple(spi_tuple);
	}
    SPI_freetuptable(SPI_tuptable);

	n += sprintf(stmt + n, " from %s.%s",
				 get_namespace_name(get_rel_namespace(source)),
				 get_rel_name(source));
	if (predicate && *predicate) {
		n += sprintf(stmt + n, " where %s", predicate);
	}
	if (sort && *sort) {
		n += sprintf(stmt + n, " order by %s", sort);
	}
    plan = SPI_prepare(stmt, 0, NULL);
    portal = SPI_cursor_open(NULL, plan, NULL, NULL, true);

	begin_batch_insert(destination);

	for (i = 0; i < n_attrs; i++) {
		values[i] = PointerGetDatum(types[i].tid != VOPS_LAST ? types[i].tid == VOPS_TEXT ? vops_alloc_text(types[i].len) : palloc0(vops_sizeof[types[i].tid]) : NULL);
	}

	for (j = 0, loaded = 0; ; j++, loaded++) {
        SPI_cursor_fetch(portal, true, 1);
        if (SPI_processed) {
            HeapTuple spi_tuple = SPI_tuptable->vals[0];
            spi_tupdesc = SPI_tuptable->tupdesc;
			if (!type_checked)
			{
				for (i = 0; i < n_attrs; i++)
				{
					Oid dst_type = types[i].dst_type;
					Oid src_type = SPI_gettypeid(spi_tupdesc, i+1);
					types[i].src_type = src_type;
					if (types[i].tid != VOPS_LAST)
						dst_type = vops_map_tid[types[i].tid];
					if (!(dst_type == src_type ||
						  (dst_type == CHAROID && src_type == TEXTOID) ||
						  (dst_type == TEXTOID && src_type == VARCHAROID) ||
						  (dst_type == TEXTOID && src_type == BPCHAROID)))
					{
						elog(ERROR, "Incompatible type of attribute %d: %s vs. %s",
							 i+1, format_type_be(dst_type), format_type_be(src_type));
					}
				}
				type_checked = true;
			}
			if (j == TILE_SIZE) {
				for (i = 0; i < n_attrs; i++) {
					if (types[i].tid != VOPS_LAST) {
						vops_tile_hdr* tile = VOPS_GET_TILE(values[i], types[i].tid);
						tile->empty_mask = 0;
					}
				}
				insert_tuple(values, nulls);
				j = 0;
			}
		  Pack:
			for (i = 0; i < n_attrs; i++) {
				Datum val = SPI_getbinval(spi_tuple, spi_tupdesc, i+1, &is_null);
				if (types[i].tid == VOPS_LAST) {
					if (j == 0) {
						nulls[i] = is_null;
						if (types[i].byval) {
							values[i] = val;
						} else if (!is_null) {
							if (DatumGetPointer(values[i]) != NULL) {
								pfree(DatumGetPointer(values[i]));
							}
							values[i] = datumCopy(val, false, types[i].len);
						}
					}
					else if (is_null != nulls[i]
							 || !(is_null || datumIsEqual(values[i], val, types[i].byval, types[i].len)))
					{
						/* Mark unassigned elements as empty */
						for (i = 0; i < n_attrs; i++) {
							if (types[i].tid != VOPS_LAST) {
								vops_tile_hdr* tile = VOPS_GET_TILE(values[i], types[i].tid);
								tile->empty_mask = (uint64)~0 << j;
							}
						}
						insert_tuple(values, nulls);
						j = 0;
						goto Pack;
					}
				} else {
					vops_tile_hdr* tile = VOPS_GET_TILE(values[i], types[i].tid);
					tile->null_mask &= ~((uint64)1 << j);
					tile->null_mask |= (uint64)is_null << j;
					switch (types[i].tid) {
					  case VOPS_BOOL:
						((vops_bool*)tile)->payload &= ~((uint64)1 << j);
						((vops_bool*)tile)->payload |= (uint64)DatumGetBool(val) << j;
						break;
					  case VOPS_CHAR:
						((vops_char*)tile)->payload[j] = types[i].src_type == CHAROID
							? DatumGetChar(val)
							: *VARDATA(DatumGetTextP(val));
						break;
					  case VOPS_INT2:
						((vops_int2*)tile)->payload[j] = DatumGetInt16(val);
						break;
					  case VOPS_INT4:
					  case VOPS_DATE:
						((vops_int4*)tile)->payload[j] = DatumGetInt32(val);
						break;
					  case VOPS_INT8:
					  case VOPS_TIMESTAMP:
						((vops_int8*)tile)->payload[j] = DatumGetInt64(val);
						break;
					  case VOPS_FLOAT4:
						((vops_float4*)tile)->payload[j] = DatumGetFloat4(val);
						break;
					  case VOPS_FLOAT8:
						((vops_float8*)tile)->payload[j] = DatumGetFloat8(val);
						break;
					  case VOPS_INTERVAL:
					  {
						  Interval* it = DatumGetIntervalP(val);
						  if (it->day || it->month)
							  elog(ERROR, "Day, month and year intervals are not supported");
						  ((vops_int8*)tile)->payload[j] = it->time;
						  break;
					  }
					  case VOPS_TEXT:
					  {
						  text* t = DatumGetTextP(val);
						  int elem_size = types[i].len;
						  int len = VARSIZE(t) - VARHDRSZ;
						  char* dst = (char*)(tile + 1);
						  if (len < elem_size) {
							  memcpy(dst + j*elem_size, VARDATA(t), len);
							  memset(dst + j*elem_size + len, 0, elem_size - len);
						  } else {
							  memcpy(dst + j*elem_size, VARDATA(t), elem_size);
						  }
						  break;
					  }
					  default:
						Assert(false);
					}
				}
			}
            SPI_freetuple(spi_tuple);
            SPI_freetuptable(SPI_tuptable);
		} else {
			break;
		}
	}
	if (j != 0) {
		if (j != TILE_SIZE) {
			/* Mark unassigned elements as empty */
			for (i = 0; i < n_attrs; i++) {
				if (types[i].tid != VOPS_LAST) {
					vops_tile_hdr* tile = VOPS_GET_TILE(values[i], types[i].tid);
					tile->empty_mask = (uint64)~0 << j;
				}
			}
		}
		insert_tuple(values, nulls);
	}
	end_batch_insert();

    SPI_cursor_close(portal);
 	SPI_finish();

	PG_RETURN_INT64(loaded);
}

static int64 vops_import_lineno;
static int   vops_import_attno;
static int   vops_import_relid;

static void vops_import_error_callback(void* arg)
{
	errcontext("IMPORT %s, line %lld, column %d",
			   get_rel_name(vops_import_relid),
			   (long long)vops_import_lineno,
			   vops_import_attno);
}

PG_FUNCTION_INFO_V1(vops_import);
Datum vops_import(PG_FUNCTION_ARGS)
{
    Oid destination = PG_GETARG_OID(0);
    char const* csv_path = PG_GETARG_CSTRING(1);
    char sep = *(char*)PG_GETARG_CSTRING(2);
	int skip = PG_GETARG_INT32(3);
	char* sql;
	TupleDesc spi_tupdesc;
	int i, j, k, n_attrs;
	vops_type_info* types;
	Datum* values;
	bool*  nulls;
	int rc;
	FILE* in;
	bool is_null;
	int64 loaded;
	ErrorContextCallback errcallback;
    char buf[MAX_CSV_LINE_LEN];

    SPI_connect();
	sql = psprintf("select attname,atttypid,atttypmod from pg_attribute where attrelid=%d and attnum>0 order by attnum", destination);
    rc = SPI_execute(sql, true, 0);
    if (rc != SPI_OK_SELECT) {
        elog(ERROR, "Select failed with status %d", rc);
    }
    n_attrs = SPI_processed;
    if (n_attrs == 0) {
        elog(ERROR, "Table %s.%s doesn't exist",
			 get_namespace_name(get_rel_namespace(destination)),
			 get_rel_name(destination));
    }
	types = (vops_type_info*)palloc(sizeof(vops_type_info)*n_attrs);
	values = (Datum*)palloc(sizeof(Datum)*n_attrs);
	nulls = (bool*)palloc0(sizeof(bool)*n_attrs);

	spi_tupdesc = SPI_tuptable->tupdesc;
	for (i = 0; i < n_attrs; i++) {
        HeapTuple spi_tuple = SPI_tuptable->vals[i];
        char const* name = SPI_getvalue(spi_tuple, spi_tupdesc, 1);
        Oid type_id = DatumGetObjectId(SPI_getbinval(spi_tuple, spi_tupdesc, 2, &is_null));
		Oid input_oid;
		types[i].tid = vops_get_type(type_id);
		if (types[i].tid != VOPS_LAST) {
			type_id = vops_map_tid[types[i].tid];
		}
		get_typlenbyvalalign(type_id, &types[i].len, &types[i].byval, &types[i].align);
		if (types[i].len < 0) { /* varying length type: extract size from atttypmod */
			types[i].len = DatumGetInt32(SPI_getbinval(spi_tuple, spi_tupdesc, 3, &is_null));
			if (types[i].len < 0) {
				elog(ERROR, "Size of column %s is unknown", name);
			}
		}
		getTypeInputInfo(type_id, &input_oid, &types[i].inproc_param_oid);
		fmgr_info_cxt(input_oid, &types[i].inproc, fcinfo->flinfo->fn_mcxt);
		SPI_freetuple(spi_tuple);
	}
    SPI_freetuptable(SPI_tuptable);

	for (i = 0; i < n_attrs; i++) {
		values[i] = PointerGetDatum(types[i].tid != VOPS_LAST ? types[i].tid == VOPS_TEXT ? vops_alloc_text(types[i].len) : palloc0(vops_sizeof[types[i].tid]) : NULL);
	}

	in = fopen(csv_path, "r");
	if (in == NULL) {
		elog(ERROR, "Failed to open file %s: %m", csv_path);
	}

	for (vops_import_lineno = 1; --skip >= 0; vops_import_lineno++) {
		if (fgets(buf, sizeof buf, in) == NULL) {
			elog(ERROR, "File %s contains no data", csv_path);
		}
	}

	vops_import_relid = destination;
	errcallback.callback = vops_import_error_callback;
	errcallback.arg =  NULL;
	errcallback.previous = error_context_stack;
	error_context_stack = &errcallback;

	begin_batch_insert(destination);

	for (j = 0, loaded = 0; fgets(buf, sizeof buf, in) != NULL; loaded++, vops_import_lineno++, j++) {
		char* p = buf;
		if (j == TILE_SIZE) {
			for (i = 0; i < n_attrs; i++) {
				if (types[i].tid != VOPS_LAST) {
					vops_tile_hdr* tile = VOPS_GET_TILE(values[i], types[i].tid);
					tile->empty_mask = 0;
				}
			}
			insert_tuple(values, nulls);
			j = 0;
		}
		for (i = 0; i < n_attrs; i++) {
			char quote = '\0';
			char* str;
			char* dst;
			Datum val;

			vops_import_attno = i+1;

			if (*p != sep && (*p == '\'' || *p == '"')) {
				quote = *p++;
				dst = p;
				str = p;
				do {
					while (*p != quote) {
						if (*p == '\0') {
							elog(ERROR, "Unterminated string %s", str);
						}
						*dst++ = *p++;
					}
				} while (*++p == quote);

				*dst = '\0';
				if (*p == sep) {
					p += 1;
				}
				is_null = false;
			} else {
				str = p;
				while (*p != sep && *p != '\n' && *p != '\r' && *p != '\0') {
					p += 1;
				}
				if (*p == sep) {
					*p++ = '\0';
				} else {
					*p = '\0';
				}
				is_null = *str == '\0';
			}
			val = is_null ? Int32GetDatum(0) : InputFunctionCall(&types[i].inproc, str, types[i].inproc_param_oid, -1);
			if (types[i].tid == VOPS_LAST) {
				if (j == 0) {
					nulls[i] = is_null;
					if (types[i].byval) {
						values[i] = val;
					} else if (!is_null) {
						if (DatumGetPointer(values[i]) != NULL) {
							pfree(DatumGetPointer(values[i]));
						}
						values[i] = val;
					}
				}
				else if (is_null != nulls[i]
						 || !(is_null || datumIsEqual(values[i], val, types[i].byval, types[i].len)))
				{
					/* Mark unassigned elements as empty */
					for (k = 0; k < n_attrs; k++) {
						if (types[k].tid != VOPS_LAST) {
							vops_tile_hdr* tile = VOPS_GET_TILE(values[k], types[k].tid);
							tile->empty_mask = (uint64)~0 << j;
						}
					}
					insert_tuple(values, nulls);
					for (k = 0; k < i; k++) {
						if (types[k].tid != VOPS_LAST) {
							vops_tile_hdr* tile = VOPS_GET_TILE(values[k], types[k].tid);
							tile->null_mask = is_null;
							switch (types[k].tid) {
							  case VOPS_BOOL:
								((vops_bool*)tile)->payload >>= j;
								break;
							  case VOPS_CHAR:
								((vops_char*)tile)->payload[0] = ((vops_char*)tile)->payload[j];
								break;
							  case VOPS_INT2:
								((vops_int2*)tile)->payload[0] = ((vops_int2*)tile)->payload[j];
								break;
							  case VOPS_INT4:
							  case VOPS_DATE:
								((vops_int4*)tile)->payload[0] = ((vops_int4*)tile)->payload[j];
								break;
							  case VOPS_INT8:
							  case VOPS_TIMESTAMP:
							  case VOPS_INTERVAL:
								((vops_int8*)tile)->payload[0] = ((vops_int8*)tile)->payload[j];
								break;
							  case VOPS_FLOAT4:
								((vops_float4*)tile)->payload[0] = ((vops_float4*)tile)->payload[j];
								break;
							  case VOPS_FLOAT8:
								((vops_float8*)tile)->payload[0] = ((vops_float8*)tile)->payload[j];
								break;
							  default:
								Assert(false);
							}
						}
					}
					j = 0;
					values[i] = val;
					nulls[i] = is_null;
				}
			} else {
				vops_tile_hdr* tile = VOPS_GET_TILE(values[i], types[i].tid);
				tile->null_mask &= ~((uint64)1 << j);
				tile->null_mask |= (uint64)is_null << j;
				switch (types[i].tid) {
				  case VOPS_BOOL:
					((vops_bool*)tile)->payload &= ~((uint64)1 << j);
					((vops_bool*)tile)->payload |= (uint64)DatumGetBool(val) << j;
					break;
				  case VOPS_CHAR:
					((vops_char*)tile)->payload[j] = DatumGetChar(val);
					break;
				  case VOPS_INT2:
					((vops_int2*)tile)->payload[j] = DatumGetInt16(val);
					break;
				  case VOPS_INT4:
				  case VOPS_DATE:
					((vops_int4*)tile)->payload[j] = DatumGetInt32(val);
					break;
				  case VOPS_INT8:
				  case VOPS_TIMESTAMP:
					((vops_int8*)tile)->payload[j] = DatumGetInt64(val);
					break;
				  case VOPS_FLOAT4:
					((vops_float4*)tile)->payload[j] = DatumGetFloat4(val);
					break;
				  case VOPS_FLOAT8:
					((vops_float8*)tile)->payload[j] = DatumGetFloat8(val);
					break;
				  case VOPS_INTERVAL:
				  {
					  Interval* it = DatumGetIntervalP(val);

					  if (it == NULL) {
						  elog(ERROR, "NULL intervals are not supported");
						  break;
					  }

					  if (it->day || it->month)
						  elog(ERROR, "Day, month and year intervals are not supported");
					  ((vops_int8*)tile)->payload[j] = it->time;
					  break;
				  }
				  case VOPS_TEXT:
				  {
					  text* t = DatumGetTextP(val);
					  int elem_size = types[i].len;
					  int len = VARSIZE(t) - VARHDRSZ;
					  char* dst = (char*)(tile + 1);
					  if (len < elem_size) {
						  memcpy(dst + j*elem_size, VARDATA(t), len);
						  memset(dst + j*elem_size + len, 0, elem_size - len);
					  } else {
						  memcpy(dst + j*elem_size, VARDATA(t), elem_size);
					  }
					  break;
				  }
				  default:
					Assert(false);
				}
			}
		}
	}
	if (j != 0) {
		if (j != TILE_SIZE) {
			/* Mark unassigned elements as empty */
			for (i = 0; i < n_attrs; i++) {
				if (types[i].tid != VOPS_LAST) {
					vops_tile_hdr* tile = VOPS_GET_TILE(values[i], types[i].tid);
					tile->empty_mask = (uint64)~0 << j;
				}
			}
		}
		insert_tuple(values, nulls);
	}
	end_batch_insert();

	error_context_stack = errcallback.previous;
	fclose(in);
 	SPI_finish();

	PG_RETURN_INT64(loaded);
}

PG_FUNCTION_INFO_V1(vops_win_final);
Datum vops_win_final(PG_FUNCTION_ARGS)
{
	filter_mask = ~0; /* it is assumed that at the moment of window aggregate finalization, filter_mask is not needed any more, so reset it */
	PG_RETURN_POINTER(PG_GETARG_POINTER(0));
}


static vops_agg_state* vops_create_agg_state(int n_aggregates)
{
	HASHCTL	ctl;
	vops_agg_state* state;
	MemSet(&ctl, 0, sizeof(ctl));
	ctl.keysize = sizeof(int64);
	ctl.entrysize = sizeof(vops_group_by_entry) + (n_aggregates - 1)*sizeof(vops_agg_value);
	state = (vops_agg_state*)palloc(sizeof(vops_agg_state));
	state->htab = hash_create("group_by_map", INIT_MAP_SIZE, &ctl, HASH_ELEM|HASH_BLOBS);
	state->n_aggs = n_aggregates;
	state->agg_kinds = (vops_agg_kind*)palloc(n_aggregates*sizeof(vops_agg_kind));
	return state;
}

static vops_agg_state* vops_init_agg_state(char const* aggregates, Oid elem_type, int n_aggregates)
{
	vops_agg_state* state;
	int i, j;
	if (n_aggregates < 1) {
		elog(ERROR, "At least one aggregate should be specified in map() function");
	}
	state = vops_create_agg_state(n_aggregates);
	state->agg_type = vops_get_type(elem_type);
	if (state->agg_type == VOPS_LAST) {
		elog(ERROR, "Group by attributes should have VOPS tile type but its type is %d", elem_type);
	}
	for (i = 0; i < n_aggregates; i++) {
		for (j = 0; j < VOPS_AGG_LAST && strncmp(aggregates, vops_agg_kind_map[j].name, strlen(vops_agg_kind_map[j].name)) != 0; j++);
		if (j == VOPS_AGG_LAST) {
			elog(ERROR, "Invalid aggregate name %s", aggregates);
		}
		state->agg_kinds[i] = vops_agg_kind_map[j].kind;
		aggregates += strlen(vops_agg_kind_map[j].name);
		if (i+1 == n_aggregates) {
			if (*aggregates != '\0')  {
				elog(ERROR, "Too much aggregates: '%s'", aggregates);
			}
		} else {
			if (*aggregates != ',')  {
				elog(ERROR, "',' expected in aggregates list but '%s' is found", aggregates);
			}
		}
		aggregates += 1;
	}
	return state;
}

static void vops_agg_state_accumulate(vops_agg_state* state, int64 group_by, int i, Datum* tiles, bool* nulls)
{
	int j;
	bool found;
	vops_group_by_entry* entry = (vops_group_by_entry*)hash_search(state->htab, &group_by, HASH_ENTER, &found);
	int n_aggregates = state->n_aggs;
	if (!found) {
		entry->count = 0;
		for (j = 0; j < n_aggregates; j++) {
			entry->values[j].count = 0;
			entry->values[j].acc.i8 = 0;
		}
	}
	entry->count += 1;

	switch (state->agg_type) {
	  case VOPS_BOOL:
		for (j = 0; j < n_aggregates; j++) {
			vops_bool* tile = (vops_bool*)DatumGetPointer(tiles[j]);
			if (!nulls[j] && (filter_mask & ~tile->hdr.null_mask & ~tile->hdr.empty_mask & ((uint64)1 << i)))
			{
				switch (state->agg_kinds[j]) {
				  case VOPS_AGG_SUM:
				  case VOPS_AGG_AVG:
					entry->values[j].acc.i8 += (tile->payload >> i) & 1;
					break;
				  case VOPS_AGG_MAX:
					if (entry->values[j].count == 0 || !entry->values[j].acc.b) {
						entry->values[j].acc.b = (tile->payload >> i) & 1;
					}
					break;
				  case VOPS_AGG_MIN:
					if (entry->values[j].count == 0 || entry->values[j].acc.b) {
						entry->values[j].acc.b = (tile->payload >> i) & 1;
					}
					break;
				  default:
					break;
				}
				entry->values[j].count += 1;
			}
		}
		break;
	  case VOPS_CHAR:
		for (j = 0; j < n_aggregates; j++) {
			vops_char* tile = (vops_char*)DatumGetPointer(tiles[j]);
			if (!nulls[j] && (filter_mask & ~tile->hdr.null_mask & ~tile->hdr.empty_mask & ((uint64)1 << i)))
			{
				switch (state->agg_kinds[j]) {
				  case VOPS_AGG_SUM:
				  case VOPS_AGG_AVG:
					entry->values[j].acc.i8 += tile->payload[i];
					break;
				  case VOPS_AGG_MAX:
					if (entry->values[j].count == 0 || entry->values[j].acc.ch < tile->payload[i]) {
						entry->values[j].acc.ch = tile->payload[i];
					}
					break;
				  case VOPS_AGG_MIN:
					if (entry->values[j].count == 0 || entry->values[j].acc.ch > tile->payload[i]) {
						entry->values[j].acc.ch = tile->payload[i];
					}
					break;
				  default:
					break;
				}
				entry->values[j].count += 1;
			}
		}
		break;
	  case VOPS_INT2:
		for (j = 0; j < n_aggregates; j++) {
			vops_int2* tile = (vops_int2*)DatumGetPointer(tiles[j]);
			if (!nulls[j] && (filter_mask & ~tile->hdr.null_mask & ~tile->hdr.empty_mask & ((uint64)1 << i)))
			{
				switch (state->agg_kinds[j]) {
				  case VOPS_AGG_SUM:
				  case VOPS_AGG_AVG:
					entry->values[j].acc.i8 += tile->payload[i];
					break;
				  case VOPS_AGG_MAX:
					if (entry->values[j].count == 0 || entry->values[j].acc.i2 < tile->payload[i]) {
						entry->values[j].acc.i2 = tile->payload[i];
					}
					break;
				  case VOPS_AGG_MIN:
					if (entry->values[j].count == 0 || entry->values[j].acc.i2 > tile->payload[i]) {
						entry->values[j].acc.i2 = tile->payload[i];
					}
					break;
				  default:
					break;
				}
				entry->values[j].count += 1;
			}
		}
		break;
	  case VOPS_INT4:
	  case VOPS_DATE:
		for (j = 0; j < n_aggregates; j++) {
			vops_int4* tile = (vops_int4*)DatumGetPointer(tiles[j]);
			if (!nulls[j] && (filter_mask & ~tile->hdr.null_mask & ~tile->hdr.empty_mask & ((uint64)1 << i)))
			{
				switch (state->agg_kinds[j]) {
				  case VOPS_AGG_SUM:
				  case VOPS_AGG_AVG:
					entry->values[j].acc.i8 += tile->payload[i];
					break;
				  case VOPS_AGG_MAX:
					if (entry->values[j].count == 0 || entry->values[j].acc.i4 < tile->payload[i]) {
						entry->values[j].acc.i4 = tile->payload[i];
					}
					break;
				  case VOPS_AGG_MIN:
					if (entry->values[j].count == 0 || entry->values[j].acc.i4 > tile->payload[i]) {
						entry->values[j].acc.i4 = tile->payload[i];
					}
					break;
				  default:
					break;
				}
				entry->values[j].count += 1;
			}
		}
		break;
	  case VOPS_INT8:
	  case VOPS_TIMESTAMP:
	  case VOPS_INTERVAL:
		for (j = 0; j < n_aggregates; j++) {
			vops_int8* tile = (vops_int8*)DatumGetPointer(tiles[j]);
			if (!nulls[j] && !(tile->hdr.null_mask & ((uint64)1 << i)))
			{
				switch (state->agg_kinds[j]) {
				  case VOPS_AGG_SUM:
				  case VOPS_AGG_AVG:
					entry->values[j].acc.i8 += tile->payload[i];
					break;
				  case VOPS_AGG_MAX:
					if (entry->values[j].count == 0 || entry->values[j].acc.i8 < tile->payload[i]) {
						entry->values[j].acc.i8 = tile->payload[i];
					}
					break;
				  case VOPS_AGG_MIN:
					if (entry->values[j].count == 0 || entry->values[j].acc.i8 > tile->payload[i]) {
						entry->values[j].acc.i8 = tile->payload[i];
					}
					break;
				  default:
					break;
				}
				entry->values[j].count += 1;
			}
		}
		break;
	  case VOPS_FLOAT4:
		for (j = 0; j < n_aggregates; j++) {
			vops_float4* tile = (vops_float4*)DatumGetPointer(tiles[j]);
			if (!nulls[j] && (filter_mask & ~tile->hdr.null_mask & ~tile->hdr.empty_mask & ((uint64)1 << i)))
			{
				switch (state->agg_kinds[j]) {
				  case VOPS_AGG_SUM:
				  case VOPS_AGG_AVG:
					entry->values[j].acc.f8 += tile->payload[i];
					break;
				  case VOPS_AGG_MAX:
					if (entry->values[j].count == 0 || entry->values[j].acc.f4 < tile->payload[i]) {
						entry->values[j].acc.f4 = tile->payload[i];
					}
					break;
				  case VOPS_AGG_MIN:
					if (entry->values[j].count == 0 || entry->values[j].acc.f4 > tile->payload[i]) {
						entry->values[j].acc.f4 = tile->payload[i];
					}
					break;
				  default:
					break;
				}
				entry->values[j].count += 1;
			}
		}
		break;
	  case VOPS_FLOAT8:
		for (j = 0; j < n_aggregates; j++) {
			vops_float8* tile = (vops_float8*)DatumGetPointer(tiles[j]);
			if (!nulls[j] && (filter_mask & ~tile->hdr.null_mask & ~tile->hdr.empty_mask & ((uint64)1 << i)))
			{
				switch (state->agg_kinds[j]) {
				  case VOPS_AGG_SUM:
				  case VOPS_AGG_AVG:
					entry->values[j].acc.f8 += tile->payload[i];
					break;
				  case VOPS_AGG_MAX:
					if (entry->values[j].count == 0 || entry->values[j].acc.f8 < tile->payload[i]) {
						entry->values[j].acc.f8 = tile->payload[i];
					}
					break;
				  case VOPS_AGG_MIN:
					if (entry->values[j].count == 0 || entry->values[j].acc.f8 > tile->payload[i]) {
						entry->values[j].acc.f8 = tile->payload[i];
					}
					break;
				  default:
					break;
				}
				entry->values[j].count += 1;
			}
		}
		break;
	  default:
		Assert(false);
	}
}

PG_FUNCTION_INFO_V1(vops_agg_final);
Datum vops_agg_final(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64((size_t)PG_GETARG_POINTER(0));
}

PG_FUNCTION_INFO_V1(vops_agg_combine);
Datum vops_agg_combine(PG_FUNCTION_ARGS)
{
	int i;
	vops_agg_state* state0 = (vops_agg_state*)(PG_ARGISNULL(0) ? 0 : PG_GETARG_POINTER(0));
	vops_agg_state* state1 = (vops_agg_state*)(PG_ARGISNULL(1) ? 0 : PG_GETARG_POINTER(1));
	vops_group_by_entry* entry0;
	vops_group_by_entry* entry1;
	MemoryContext old_context;
	MemoryContext agg_context;
	HASH_SEQ_STATUS iter;
	int n_aggregates;

	if (state1 == NULL) {
		if (state0 == NULL) {
			PG_RETURN_NULL();
		} else {
			PG_RETURN_POINTER(state0);
		}
	}
	hash_seq_init(&iter, state1->htab);

	if (!AggCheckCallContext(fcinfo, &agg_context))
		elog(ERROR, "aggregate function called in non-aggregate context");
	old_context = MemoryContextSwitchTo(agg_context);
	n_aggregates = state1->n_aggs;

	if (state0 == NULL) {
	    state0 = vops_create_agg_state(n_aggregates);
		state0->agg_type = state1->agg_type;
		for (i = 0; i < n_aggregates; i++) {
 	        state0->agg_kinds[i] = state1->agg_kinds[i];
        }
    }

    while ((entry1 = (vops_group_by_entry*)hash_seq_search(&iter)) != NULL)
    {
		bool found;
		entry0 = (vops_group_by_entry*)hash_search(state0->htab, &entry1->group_by, HASH_ENTER, &found);

	    if (!found) {
			entry0->count = 0;
			for (i = 0; i < n_aggregates; i++) {
				entry0->values[i].count = 0;
				entry0->values[i].acc.i8 = 0;
			}
		}
		entry0->count += entry1->count;

		for (i = 0; i < n_aggregates; i++) {
			switch (state1->agg_kinds[i]) {
			  case VOPS_AGG_SUM:
			  case VOPS_AGG_AVG:
				if (state0->agg_type < VOPS_FLOAT4) {
					entry0->values[i].acc.i8 += entry1->values[i].acc.i8;
				} else {
					entry0->values[i].acc.f8 += entry1->values[i].acc.f8;
				}
				break;
			  case VOPS_AGG_MAX:
				if (entry0->values[i].count == 0) {
					entry0->values[i].acc = entry1->values[i].acc;
                } else {
					switch (state0->agg_type) {
					  case VOPS_BOOL:
						if (!entry0->values[i].acc.b) {
							entry0->values[i].acc.b = entry1->values[i].acc.b;
						}
						break;
					  case VOPS_CHAR:
						if (entry0->values[i].acc.ch < entry1->values[i].acc.ch) {
							entry0->values[i].acc.ch = entry1->values[i].acc.ch;
						}
						break;
					  case VOPS_INT2:
						if (entry0->values[i].acc.i2 < entry1->values[i].acc.i2) {
							entry0->values[i].acc.i2 = entry1->values[i].acc.i2;
						}
						break;
					  case VOPS_INT4:
					  case VOPS_DATE:
						if (entry0->values[i].acc.i4 < entry1->values[i].acc.i4) {
							entry0->values[i].acc.i4 = entry1->values[i].acc.i4;
						}
						break;
					  case VOPS_INT8:
					  case VOPS_TIMESTAMP:
					  case VOPS_INTERVAL:
						if (entry0->values[i].acc.i8 < entry1->values[i].acc.i8) {
							entry0->values[i].acc.i8 = entry1->values[i].acc.i8;
						}
						break;
					  case VOPS_FLOAT4:
						if (entry0->values[i].acc.f4 < entry1->values[i].acc.f4) {
							entry0->values[i].acc.f4 = entry1->values[i].acc.f4;
						}
						break;
					  case VOPS_FLOAT8:
						if (entry0->values[i].acc.f8 < entry1->values[i].acc.f8) {
							entry0->values[i].acc.f8 = entry1->values[i].acc.f8;
						}
						break;
					  default:
						Assert(false);
					}
				}
				break;
			  case VOPS_AGG_MIN:
				if (entry0->values[i].count == 0) {
					entry0->values[i].acc = entry1->values[i].acc;
                } else {
					switch (state0->agg_type) {
					  case VOPS_BOOL:
						if (entry0->values[i].acc.b) {
							entry0->values[i].acc.b = entry1->values[i].acc.b;
						}
						break;
					  case VOPS_CHAR:
						if (entry0->values[i].acc.ch > entry1->values[i].acc.ch) {
							entry0->values[i].acc.ch = entry1->values[i].acc.ch;
						}
						break;
					  case VOPS_INT2:
						if (entry0->values[i].acc.i2 > entry1->values[i].acc.i2) {
							entry0->values[i].acc.i2 = entry1->values[i].acc.i2;
						}
						break;
					  case VOPS_INT4:
					  case VOPS_DATE:
						if (entry0->values[i].acc.i4 > entry1->values[i].acc.i4) {
							entry0->values[i].acc.i4 = entry1->values[i].acc.i4;
						}
						break;
					  case VOPS_INT8:
					  case VOPS_TIMESTAMP:
					  case VOPS_INTERVAL:
						if (entry0->values[i].acc.i8 > entry1->values[i].acc.i8) {
							entry0->values[i].acc.i8 = entry1->values[i].acc.i8;
						}
						break;
					  case VOPS_FLOAT4:
						if (entry0->values[i].acc.f4 > entry1->values[i].acc.f4) {
							entry0->values[i].acc.f4 = entry1->values[i].acc.f4;
						}
						break;
					  case VOPS_FLOAT8:
						if (entry0->values[i].acc.f8 > entry1->values[i].acc.f8) {
							entry0->values[i].acc.f8 = entry1->values[i].acc.f8;
						}
						break;
					  default:
						Assert(false);
                    }
					break;
				  default:
					break;
                }
			}
			entry0->values[i].count += entry1->values[i].count;
        }
	}
	MemoryContextSwitchTo(old_context);

	PG_RETURN_POINTER(state0);
}

PG_FUNCTION_INFO_V1(vops_reduce);
Datum vops_reduce(PG_FUNCTION_ARGS)
{
	vops_agg_state* state = (vops_agg_state*)(size_t)PG_GETARG_INT64(0);
    FuncCallContext* func_ctx;
    vops_reduce_context* user_ctx;
	vops_group_by_entry* entry;
	int n_aggregates = state->n_aggs;

	if (SRF_IS_FIRSTCALL()) {
        MemoryContext old_context;
		func_ctx = SRF_FIRSTCALL_INIT();
		old_context = MemoryContextSwitchTo(func_ctx->multi_call_memory_ctx);
		user_ctx = (vops_reduce_context*)palloc(sizeof(vops_reduce_context));
		get_call_result_type(fcinfo, NULL, &user_ctx->desc);
		func_ctx->user_fctx = user_ctx;
		hash_seq_init(&user_ctx->iter, state->htab);
		user_ctx->elems = (Datum*)palloc(sizeof(Datum)*n_aggregates);
		user_ctx->nulls = (bool*)palloc(sizeof(bool)*n_aggregates);
		get_typlenbyvalalign(FLOAT8OID, &user_ctx->elmlen, &user_ctx->elmbyval, &user_ctx->elmalign);
		MemoryContextSwitchTo(old_context);
	}
	func_ctx = SRF_PERCALL_SETUP();
    user_ctx = (vops_reduce_context*)func_ctx->user_fctx;
	entry = (vops_group_by_entry*)hash_seq_search(&user_ctx->iter);
	if (entry != NULL) {
		Datum values[3];
		bool nulls[3] = {false,false,false};
		int lbs = 1;
		double val = 0;
		int i;

		for (i = 0; i < n_aggregates; i++) {
			user_ctx->nulls[i] = entry->values[i].count == 0;
			if (!user_ctx->nulls[i] || state->agg_kinds[i] == VOPS_AGG_COUNT) {
				switch (state->agg_kinds[i]) {
				  case VOPS_AGG_COUNT:
					user_ctx->elems[i] = Float8GetDatum((double)entry->values[i].count);
					user_ctx->nulls[i] = false;
					break;
				  case VOPS_AGG_SUM:
					user_ctx->elems[i] = Float8GetDatum((state->agg_type < VOPS_FLOAT4)
														? (double)entry->values[i].acc.i8
														: entry->values[i].acc.f8);
					break;
				  case VOPS_AGG_AVG:
					user_ctx->elems[i] = Float8GetDatum(((state->agg_type < VOPS_FLOAT4)
														 ? (double)entry->values[i].acc.i8
														 : entry->values[i].acc.f8)/entry->values[i].count);
					break;
				  case VOPS_AGG_MAX:
				  case VOPS_AGG_MIN:
					switch (state->agg_type) {
					  case VOPS_BOOL:
						val = (double)entry->values[i].acc.b;
						break;
					  case VOPS_CHAR:
						val = (double)entry->values[i].acc.ch;
						break;
					  case VOPS_INT2:
						val = (double)entry->values[i].acc.i2;
						break;
					  case VOPS_INT4:
					  case VOPS_DATE:
						val = (double)entry->values[i].acc.i4;
						break;
					  case VOPS_INT8:
					  case VOPS_TIMESTAMP:
					  case VOPS_INTERVAL:
						val = (double)entry->values[i].acc.i8;
						break;
					  case VOPS_FLOAT4:
						val = (double)entry->values[i].acc.f4;
						break;
					  case VOPS_FLOAT8:
						val = entry->values[i].acc.f8;
						break;
					  default:
						Assert(false);
					}
					user_ctx->elems[i] = Float8GetDatum(val);
					break;
				  default:
					Assert(false);
				}
			}
		}
		values[0] = Int64GetDatum(entry->group_by);
		values[1] = UInt64GetDatum(entry->count);
		values[2] = PointerGetDatum(construct_md_array(user_ctx->elems, user_ctx->nulls, 1, &state->n_aggs, &lbs, FLOAT8OID, user_ctx->elmlen, user_ctx->elmbyval, user_ctx->elmalign));
		SRF_RETURN_NEXT(func_ctx, HeapTupleGetDatum(heap_form_tuple(user_ctx->desc, values, nulls)));
	} else {
		SRF_RETURN_DONE(func_ctx);
	}
}

PG_FUNCTION_INFO_V1(vops_unnest);
Datum vops_unnest(PG_FUNCTION_ARGS)
{
	int i, j, n_attrs;
	FuncCallContext* func_ctx;
    vops_unnest_context* user_ctx;

	if (SRF_IS_FIRSTCALL()) {
		Oid	argtype;
        MemoryContext old_context;
		char typtype;
		HeapTupleHeader t;
		TupleDesc src_desc;

		func_ctx = SRF_FIRSTCALL_INIT();
		old_context = MemoryContextSwitchTo(func_ctx->multi_call_memory_ctx);

		t = PG_GETARG_HEAPTUPLEHEADER(0);
		src_desc = lookup_rowtype_tupdesc(HeapTupleHeaderGetTypeId(t), HeapTupleHeaderGetTypMod(t));

		user_ctx = (vops_unnest_context*)palloc(sizeof(vops_unnest_context));
        argtype = get_fn_expr_argtype(fcinfo->flinfo, 0);
        typtype = get_typtype(argtype);
        if (typtype != 'c' && typtype != 'p') {
			elog(ERROR, "Argument of unnest function should have compound type");
        }
		n_attrs = src_desc->natts;

		user_ctx->values = (Datum*)palloc(sizeof(Datum)*n_attrs);
        user_ctx->nulls = (bool*)palloc(sizeof(bool)*n_attrs);
        user_ctx->types = (vops_type*)palloc(sizeof(vops_type)*n_attrs);
		user_ctx->tiles = (vops_tile_hdr**)palloc(sizeof(vops_tile_hdr*)*n_attrs);
#if PG_VERSION_NUM>=120000
        user_ctx->desc = CreateTemplateTupleDesc(n_attrs);
#else
        user_ctx->desc = CreateTemplateTupleDesc(n_attrs, false);
#endif
        func_ctx->user_fctx = user_ctx;
        user_ctx->n_attrs = n_attrs;
		user_ctx->tile_pos = 0;
		user_ctx->filter_mask = filter_mask;
		filter_mask = ~0;

        for (i = 0; i < n_attrs; i++) {
			Form_pg_attribute attr = TupleDescAttr(src_desc, i);
			vops_type tid = vops_get_type(attr->atttypid);
			Datum val = GetAttributeByNum(t, attr->attnum, &user_ctx->nulls[i]);
			user_ctx->types[i] = tid;
			if (tid == VOPS_LAST) {
				user_ctx->values[i] = val;
				TupleDescInitEntry(user_ctx->desc, attr->attnum, attr->attname.data, attr->atttypid, attr->atttypmod, attr->attndims);
			} else {
				if (user_ctx->nulls[i]) {
					user_ctx->tiles[i] = NULL;
				} else {
					user_ctx->tiles[i] = VOPS_GET_TILE(val, tid);
				}
				TupleDescInitEntry(user_ctx->desc, attr->attnum, attr->attname.data, vops_map_tid[tid], -1, 0);
			}
		}
		TupleDescGetAttInMetadata(user_ctx->desc);
 		ReleaseTupleDesc(src_desc);
        MemoryContextSwitchTo(old_context);
	}
	func_ctx = SRF_PERCALL_SETUP();
    user_ctx = (vops_unnest_context*)func_ctx->user_fctx;
	n_attrs = user_ctx->n_attrs;

	for (j = user_ctx->tile_pos; j < TILE_SIZE; j++) {
		if (user_ctx->filter_mask & ((uint64)1 << j))
		{
			for (i = 0; i < n_attrs; i++) {
				if (user_ctx->types[i] != VOPS_LAST) {
					vops_tile_hdr* tile = user_ctx->tiles[i];
					if (tile != NULL && (tile->empty_mask & ((uint64)1 << j))) {
						goto NextTuple;
					}
					if (tile == NULL || (tile->null_mask & ((uint64)1 << j))) {
						user_ctx->nulls[i] = true;
					} else {
						Datum value = 0;
						switch (user_ctx->types[i]) {
						  case VOPS_BOOL:
							value = BoolGetDatum((((vops_bool*)tile)->payload >> j) & 1);
						break;
						  case VOPS_CHAR:
							value = CharGetDatum(((vops_char*)tile)->payload[j]);
							break;
						  case VOPS_INT2:
							value = Int16GetDatum(((vops_int2*)tile)->payload[j]);
							break;
						  case VOPS_INT4:
						  case VOPS_DATE:
							value = Int32GetDatum(((vops_int4*)tile)->payload[j]);
							break;
						  case VOPS_INT8:
						  case VOPS_TIMESTAMP:
						  case VOPS_INTERVAL:
							value = Int64GetDatum(((vops_int8*)tile)->payload[j]);
							break;
						  case VOPS_FLOAT4:
							value = Float4GetDatum(((vops_float4*)tile)->payload[j]);
							break;
						  case VOPS_FLOAT8:
							value = Float8GetDatum(((vops_float8*)tile)->payload[j]);
							break;
						  case VOPS_TEXT:
						  {
							  size_t elem_size = VOPS_ELEM_SIZE((char*)tile - LONGALIGN(VARHDRSZ));
							  char* src = (char*)(tile + 1) + elem_size * j;
							  size_t len = strnlen(src, elem_size);
							  text* t = (text*)palloc(VARHDRSZ + len);
							  SET_VARSIZE(t, VARHDRSZ + len);
							  memcpy(VARDATA(t), src, len);
							  value = PointerGetDatum(t);
							  break;
						  }
						  default:
							Assert(false);
						}
						user_ctx->values[i] = value;
						user_ctx->nulls[i] = false;
					}
				}
			}
			user_ctx->tile_pos = j+1;
			SRF_RETURN_NEXT(func_ctx, HeapTupleGetDatum(heap_form_tuple(user_ctx->desc, user_ctx->values, user_ctx->nulls)));
		}
	  NextTuple:;
	}
	SRF_RETURN_DONE(func_ctx);
}


PG_FUNCTION_INFO_V1(vops_char_concat);
Datum vops_char_concat(PG_FUNCTION_ARGS)
{
	vops_char* left = (vops_char*)PG_GETARG_POINTER(0);
	vops_char* right = (vops_char*)PG_GETARG_POINTER(1);
	vops_int2* result = (vops_int2*)palloc(sizeof(vops_int2));
	int i;
	for (i = 0; i < TILE_SIZE; i++) {
		result->payload[i] = ((uint16)(uint8)left->payload[i] << 8) | (uint8)right->payload[i];
	}
	result->hdr.null_mask = left->hdr.null_mask | right->hdr.null_mask;
	result->hdr.empty_mask = left->hdr.empty_mask | right->hdr.empty_mask;
	PG_RETURN_POINTER(result);
}

PG_FUNCTION_INFO_V1(vops_int2_concat);
Datum vops_int2_concat(PG_FUNCTION_ARGS)
{
	vops_int2* left = (vops_int2*)PG_GETARG_POINTER(0);
	vops_int2* right = (vops_int2*)PG_GETARG_POINTER(1);
	vops_int4* result = (vops_int4*)palloc(sizeof(vops_int4));
	int i;
	for (i = 0; i < TILE_SIZE; i++) {
		result->payload[i] = ((uint32)(uint16)left->payload[i] << 16) | (uint16)right->payload[i];
	}
	result->hdr.null_mask = left->hdr.null_mask | right->hdr.null_mask;
	result->hdr.empty_mask = left->hdr.empty_mask | right->hdr.empty_mask;
	PG_RETURN_POINTER(result);
}

PG_FUNCTION_INFO_V1(vops_int4_concat);
Datum vops_int4_concat(PG_FUNCTION_ARGS)
{
	vops_int4* left = (vops_int4*)PG_GETARG_POINTER(0);
	vops_int4* right = (vops_int4*)PG_GETARG_POINTER(1);
	vops_int8* result = (vops_int8*)palloc(sizeof(vops_int8));
	int i;
	for (i = 0; i < TILE_SIZE; i++) {
		result->payload[i] = ((uint64)(uint32)left->payload[i] << 32) | (uint32)right->payload[i];
	}
	result->hdr.null_mask = left->hdr.null_mask | right->hdr.null_mask;
	result->hdr.empty_mask = left->hdr.empty_mask | right->hdr.empty_mask;
	PG_RETURN_POINTER(result);
}

PG_FUNCTION_INFO_V1(vops_is_null);
Datum vops_is_null(PG_FUNCTION_ARGS)
{
	vops_bool* result = (vops_bool*)palloc(sizeof(vops_bool));
	result->hdr.null_mask = 0;
	if (PG_ARGISNULL(0)) {
		result->payload = 0;
		result->hdr.empty_mask = ~0;
	} else {
		vops_type tid = vops_get_type(get_fn_expr_argtype(fcinfo->flinfo, 0));
		vops_tile_hdr* opd = VOPS_GET_TILE(PG_GETARG_DATUM(0), tid);
		result->payload = opd->null_mask;
		result->hdr.empty_mask = opd->empty_mask;
	}
	PG_RETURN_POINTER(result);
}

PG_FUNCTION_INFO_V1(vops_is_not_null);
Datum vops_is_not_null(PG_FUNCTION_ARGS)
{
	vops_bool* result = (vops_bool*)palloc(sizeof(vops_bool));
	result->hdr.null_mask = 0;
	if (PG_ARGISNULL(0)) {
		result->payload = 0;
		result->hdr.empty_mask = ~0;
	} else {
		vops_type tid = vops_get_type(get_fn_expr_argtype(fcinfo->flinfo, 0));
		vops_tile_hdr* opd = VOPS_GET_TILE(PG_GETARG_DATUM(0), tid);
		result->payload = ~opd->null_mask;
		result->hdr.empty_mask = opd->empty_mask;
	}
	PG_RETURN_POINTER(result);
}

PG_FUNCTION_INFO_V1(vops_window_accumulate);
Datum vops_window_accumulate(PG_FUNCTION_ARGS)
{
	elog(ERROR, "window function requires an OVER clause");
	PG_RETURN_NULL();
}

PG_FUNCTION_INFO_V1(vops_window_reduce);
Datum vops_window_reduce(PG_FUNCTION_ARGS)
{
	elog(ERROR, "Only window aggregates with unbounded preceding frame are supported");
	PG_RETURN_NULL();
}


PG_FUNCTION_INFO_V1(vops_lag_reduce);
Datum vops_lag_reduce(PG_FUNCTION_ARGS)
{
	if (PG_ARGISNULL(0)) {
		PG_RETURN_NULL();
	} else {
		PG_RETURN_POINTER(PG_GETARG_POINTER(0));
	}
}


PG_FUNCTION_INFO_V1(vops_initialize);
Datum vops_initialize(PG_FUNCTION_ARGS)
{
	PG_RETURN_VOID();
}


static Oid vops_bool_oid;
static Oid filter_oid;
static Oid vops_and_oid;
static Oid vops_or_oid;
static Oid vops_not_oid;
static Oid vcount_oid;
static Oid count_oid;
static Oid is_null_oid;
static Oid is_not_null_oid;
static Oid coalesce_oids[VOPS_LAST];

typedef struct
{
	int varno;
	int varattno;
	int vartype;
} vops_var;

static bool
is_select_from_vops_projection(Query* query, vops_var* var)
{
	int relno;
	int n_rels = list_length(query->rtable);
	for (relno = 1; relno <= n_rels; relno++)
	{
		RangeTblEntry* rte = list_nth_node(RangeTblEntry, query->rtable, relno-1);
		if (rte->rtekind == RTE_RELATION)
		{
			Relation rel = heap_open(rte->relid, NoLock); /* Assume we already have adequate lock */
			int attno;
			for (attno = 1; attno <= rel->rd_att->natts; attno++)
			{
				Oid typid = TupleDescAttr(rel->rd_att, attno-1)->atttypid;
				if (is_vops_type(typid))
				{
					heap_close(rel, NoLock);
					var->varno = relno;
					var->varattno = attno;
					var->vartype = typid;
					return true;
				}
			}
			heap_close(rel, NoLock);
		}
	}
	return false;
}



static Node*
vops_expression_tree_mutator(Node *node, void *context)
{
	vops_var* var = (vops_var*)context;
	if (node == NULL)
	{
		return NULL;
	}
	if (IsA(node, Query))
	{
		vops_var save_var = *var;
		Query* query = (Query*)node;
		if (is_select_from_vops_projection(query, var))
		{
			node = (Node *) query_tree_mutator(query,
											   vops_expression_tree_mutator,
											   context,
											   QTW_DONT_COPY_QUERY);
			*var = save_var; /* restore query context */
		}
		return node;
	}
	/* depth first traversal */
	node = expression_tree_mutator(node, vops_expression_tree_mutator, context
#if PG_VERSION_NUM<140000
#ifdef 	QTW_DONT_COPY_DEFAULT
								   ,0
#endif
#endif
	);

	if (IsA(node, BoolExpr))
	{
		BoolExpr* expr = (BoolExpr*)node;
		ListCell *cell;
		List* vector_args = NULL;
		List* scalar_args = NULL;
		FuncExpr* filter;

		foreach(cell, expr->args)
		{
			Node* arg = lfirst(cell);
			if (IsA(arg, FuncExpr))
			{
				filter = (FuncExpr*)arg;
				if (filter->funcid == filter_oid) {
					vector_args = lappend(vector_args, linitial(filter->args));
					continue;
				}
			}
			scalar_args = lappend(scalar_args, arg);
		}
		if (expr->boolop == NOT_EXPR)
		{
			if (list_length(vector_args) != 0)
			{
				Assert(list_length(vector_args) == 1);
				/* Transform expression (NOT filter(o1)) to (filter(vops_not(o1)) */
				return (Node*)makeFuncExpr(filter_oid, BOOLOID,
										   list_make1(makeFuncExpr(vops_not_oid, vops_bool_oid,
																   vector_args,
																   InvalidOid, InvalidOid, COERCE_EXPLICIT_CALL)),
										   InvalidOid, InvalidOid, COERCE_EXPLICIT_CALL);
			}
		}
		else if (list_length(vector_args) > 1)
		{
 			/* Transaform expression (filter(o1) AND filter(o2)) to (filter(vops_and(o1, o2))) */
			Node* filter_arg = NULL;

			foreach(cell, vector_args)
			{
				if (filter_arg == NULL)
				{
					filter_arg = (Node*)lfirst(cell);
				}
				else
				{
					filter_arg = (Node*)makeFuncExpr(expr->boolop == AND_EXPR ? vops_and_oid : vops_or_oid,
													 vops_bool_oid,
													 list_make2(filter_arg, lfirst(cell)),
													 InvalidOid, InvalidOid, COERCE_EXPLICIT_CALL);
				}
			}
			filter = makeFuncExpr(filter_oid, BOOLOID, list_make1(filter_arg),
								  InvalidOid, InvalidOid, COERCE_EXPLICIT_CALL);
			return list_length(scalar_args) != 0
				? (Node*)makeBoolExpr(expr->boolop, lappend(scalar_args, filter), expr->location)
				: (Node*)filter;
		}
	}
	else if (IsA(node, NullTest))
	{
		NullTest* test = (NullTest*)node;
		if (!test->argisrow && is_vops_type(exprType((Node*)test->arg)))
		{
			return (Node*)makeFuncExpr(filter_oid, BOOLOID,
									   list_make1(makeFuncExpr(test->nulltesttype == IS_NULL
															   ? is_null_oid
															   : is_not_null_oid,
															   vops_bool_oid,
															   list_make1(test->arg),
															   InvalidOid, InvalidOid, COERCE_EXPLICIT_CALL)),

									   InvalidOid, InvalidOid, COERCE_EXPLICIT_CALL);
		}
	}
	else if (IsA(node, Aggref))
	{
		Aggref* agg = (Aggref*)node;
		if (agg->aggfnoid == count_oid) {
			Assert(agg->aggstar);
			agg->aggfnoid = vcount_oid;
			agg->aggstar = false;
			agg->aggargtypes = list_make1_oid(var->vartype);
			agg->args = list_make1(makeTargetEntry((Expr*)makeVar(var->varno, var->varattno, var->vartype, -1, 0, 0), 1, NULL, false));
		}
	}
	else if (IsA(node, CoalesceExpr))
	{
		CoalesceExpr *coalesce = (CoalesceExpr *) node;
		vops_type tid = vops_get_type(coalesce->coalescetype);
		if (tid != VOPS_LAST && list_length(coalesce->args) == 2) { /* TODO: right now only two arguments case is handled */
			return (Node*)makeFuncExpr(coalesce_oids[tid], coalesce->coalescetype, coalesce->args,
									   InvalidOid, InvalidOid, COERCE_EXPLICIT_CALL);
		}
	}
	return node;
}

static post_parse_analyze_hook_type	post_parse_analyze_hook_next;
#if PG_VERSION_NUM<140000
static ExplainOneQuery_hook_type save_explain_hook;
#endif


typedef enum
{
	SCOPE_DEFAULT     = 0,
	SCOPE_WHERE       = 1, /* WHERE clause */
	SCOPE_AGGREGATE   = 2, /* argument of aggregate */
	SCOPE_TARGET_LIST = 4  /* target list */
} vops_clause_scope;

/* Usage of table's attributes */
typedef struct
{
	Bitmapset* where;   /* set of vars used in WHERE clause */
	Bitmapset* agg;     /* set of vars used in aggregate expressions */
	Bitmapset* other;   /* set of vars used in any other location */
} vops_table_refs;

/* Cluster of variables: columns used in one expression */
typedef struct vops_vars_cluster
{
	struct vops_vars_cluster* next;
	Bitmapset* vars;
} vops_vars_cluster;

typedef struct
{
	Query*     query;      /* executed query */
	int        scope;      /* mask of vops_clause_scope bits */
	int        n_rels;     /* number of relations in query (join pseudorelations) */
    Const**    consts;     /* array references to Const nodes in query, indexed by literal location */
	Bitmapset* operands;   /* columns used in one expression */
	vops_table_refs* refs; /* usage of table' variables (index by relation number - 1) */
	vops_vars_cluster* clusters; /* clusters of query variables */
} vops_pullvar_context;

/*
 * Add new variable cluster to context.
 * ctx->operands is bitmapset of columns used in one expression.
 * If it is intersected with some of the existed clusters, then join them and repeat this procedure recusrively.
 */
static void
vops_update_vars_clusters(vops_pullvar_context *ctx)
{
	Bitmapset* operands = ctx->operands;
	if (operands)
	{
		vops_vars_cluster *clu, **clup;
		do
		{
			for (clup = &ctx->clusters; (clu = *clup) != NULL; clup = &clu->next)
			{
				if (bms_overlap(clu->vars, operands))
				{
					*clup = clu->next;
					operands = bms_join(clu->vars, operands);
					break;
				}
			}
		} while (clu != NULL);

		clu = (vops_vars_cluster*)palloc(sizeof(vops_vars_cluster));
		clu->vars = operands;
		clu->next = ctx->clusters;
		ctx->clusters = clu;
	}
}

/*
 * Check that all variables used together are both either scalar, either vector.
 */
static bool
vops_check_clusters(vops_vars_cluster* clusters, Bitmapset* vectorCols, Bitmapset* scalarCols)
{
	vops_vars_cluster* cluster;

	Assert(!bms_overlap(vectorCols, scalarCols));

	for (cluster = clusters; cluster != NULL; cluster = cluster->next)
	{
		if (!bms_is_subset(cluster->vars, vectorCols) &&
			!bms_is_subset(cluster->vars, scalarCols))
		{
			return false;
		}
	}
	return true;
}

/*
 * Collect information about attribute usage in the query
 */
static bool
vops_pullvars_walker(Node *node, vops_pullvar_context *ctx)
{
	int scope = ctx->scope;

	if (node == NULL)
		return false;

	if (IsA(node, Var))
	{
		Var	*var = (Var *) node;
		int  relid = var->varno;
		int  attno = var->varattno;

		if (!IS_SPECIAL_VARNO(relid) && attno >= 0)
		{
			RangeTblEntry* tbl;
			/* Locate table from which this variables come from */
			while (true)
			{
				tbl = list_nth_node(RangeTblEntry, ctx->query->rtable, relid-1);
				if (tbl->rtekind == RTE_JOIN)
				{
					Assert(attno != 0); /* attno==0 correspondns to "SELECT *" */
					var = list_nth_node(Var, tbl->joinaliasvars, attno-1);
					attno = var->varattno;
					relid = var->varno;
				}
				else break;
			}
			if (tbl->rtekind == RTE_RELATION)
			{
				vops_table_refs* rel = &ctx->refs[relid-1];
				if (scope & SCOPE_AGGREGATE)
				{
					rel->agg = bms_add_member(rel->agg, attno);
				}
				else if (scope & SCOPE_WHERE)
				{
					ctx->operands = bms_add_member(ctx->operands, attno*ctx->n_rels + relid - 1);
					rel->where = bms_add_member(rel->where, attno);
				}
				else
				{
					rel->other = bms_add_member(rel->other, attno);
				}
			}
		}
		return false;
	}
	else if (IsA(node, Const))
	{
		Const* c = (Const*)node;
		if (c->location >= 0)
			ctx->consts[c->location] = c;
	}
	else if (IsA(node, BoolExpr))
	{
		ListCell* cell;
		BoolExpr* bop = (BoolExpr*)node;
		Bitmapset* save_operands = ctx->operands;
		/* Each conjunct or disjunct forms its own cluster */
		foreach (cell, bop->args)
		{
			Node* opd = (Node*)lfirst(cell);
			ctx->operands = NULL;
			(void) expression_tree_walker(opd, vops_pullvars_walker, ctx);
			vops_update_vars_clusters(ctx);
		}
		ctx->operands = save_operands;
		return false;
	}
	else if (IsA(node, Aggref))
	{
		ctx->scope |= SCOPE_AGGREGATE;
	}
	else if (IsA(node, TargetEntry))
	{
		ctx->scope |= SCOPE_TARGET_LIST;
	}
	else if (IsA(node, FromExpr))
	{
		FromExpr* from = (FromExpr*)node;
		Bitmapset* save_operands = ctx->operands;
		ctx->operands = NULL;
		ctx->scope |= SCOPE_WHERE;
		(void) expression_tree_walker(from->quals, vops_pullvars_walker, ctx);
		vops_update_vars_clusters(ctx);
		ctx->operands = save_operands;
		ctx->scope = scope;
		node = (Node*)from->fromlist;
	}
	(void) expression_tree_walker(node, vops_pullvars_walker, ctx);
	ctx->scope = scope;
	return false;
}

/*
 * If projection has order key and it is used in qurey predicate, then
 * add correspodent conditions for BRIN index to allow optimizer to perfor index scan
 * to locate relevant blocks.
 */
static List*
vops_add_index_cond(Node* clause, List* conjuncts, char const* keyName)
{
	conjuncts = lappend(conjuncts, clause);

	if (IsA(clause, A_Expr))
	{
		A_Expr* expr = (A_Expr*)clause;
		if (list_length(expr->name) == 1 && IsA(expr->lexpr, ColumnRef))
		{
			ColumnRef* col = (ColumnRef*)expr->lexpr;
			if (list_length(col->fields) == 1
				&& strcmp(strVal(linitial(col->fields)), keyName) == 0)
			{
				char* op = strVal(linitial(expr->name));
				if (*op == '<' || *op == '>') {
					A_Expr* bound = makeNode(A_Expr);
					FuncCall* call = makeFuncCall(list_make1(makeString(*op == '<' ? "first" : "last")),
												  list_make1(expr->lexpr), FUNC_CALL_CTX);
					bound->kind = expr->kind;
					bound->name = expr->name;
					bound->lexpr = (Node*)call;
					bound->rexpr = expr->rexpr;
					bound->location = -1;
					conjuncts = lappend(conjuncts, bound);
				} else if (expr->kind == AEXPR_BETWEEN) {
					A_Expr* bound = makeNode(A_Expr);
					FuncCall* call = makeFuncCall(list_make1(makeString("last")),
												  list_make1(expr->lexpr), FUNC_CALL_CTX);
					bound->kind = AEXPR_OP;
					bound->name = list_make1(makeString(">="));
					bound->lexpr = (Node*)call;
					bound->rexpr = linitial((List*)expr->rexpr);
					bound->location = -1;
					conjuncts = lappend(conjuncts, bound);

					bound = makeNode(A_Expr);
					call = makeFuncCall(list_make1(makeString("first")),
										list_make1(expr->lexpr), FUNC_CALL_CTX);
					bound->kind = AEXPR_OP;
					bound->name = list_make1(makeString("<="));
					bound->lexpr = (Node*)call;
					bound->rexpr = lsecond((List*)expr->rexpr);
					bound->location = -1;
					conjuncts = lappend(conjuncts, bound);
				} else if (*op == '=') {
					A_Expr* bound = makeNode(A_Expr);
					FuncCall* call = makeFuncCall(list_make1(makeString("last")),
												  list_make1(expr->lexpr), FUNC_CALL_CTX);
					bound->kind = expr->kind;
					bound->name = list_make1(makeString(">="));
					bound->lexpr = (Node*)call;
					bound->rexpr = expr->rexpr;
					bound->location = -1;
					conjuncts = lappend(conjuncts, bound);

					bound = makeNode(A_Expr);
					call = makeFuncCall(list_make1(makeString("first")),
										list_make1(expr->lexpr), FUNC_CALL_CTX);
					bound->kind = expr->kind;
					bound->name = list_make1(makeString("<="));
					bound->lexpr = (Node*)call;
					bound->rexpr = expr->rexpr;
					bound->location = -1;
					conjuncts = lappend(conjuncts, bound);
				}
			}
		}
	}
	return conjuncts;
}

/*
 * Postgres query analyzer is able to automatically resolve string literal types if them are compare with scalar attributes,
 * i.e. (day = '01.11.2018'). But if "day" column has VOPS tile type (i.e. vops_date), then error is reported.
 * So we have to add explicit type cast to string literal to eliminate such error.
 */
static Node*
vops_add_literal_type_casts(Node* node, Const** consts)
{
	if (node == NULL)
		return NULL;

	if (IsA(node, BoolExpr))
	{
		ListCell* cell;
		BoolExpr* andExpr = (BoolExpr*)node;
		foreach (cell, andExpr->args)
		{
			Node* conjunct = (Node*)lfirst(cell);
			vops_add_literal_type_casts(conjunct, consts);
		}
	}
	else if (IsA(node, List))
	{
		ListCell* cell;
		foreach (cell, (List *) node)
		{
			lfirst(cell) = vops_add_literal_type_casts(lfirst(cell), consts);
		}
	}
	else if (IsA(node, A_Expr))
	{
		A_Expr* expr = (A_Expr*)node;
		expr->lexpr = vops_add_literal_type_casts(expr->lexpr, consts);
		expr->rexpr = vops_add_literal_type_casts(expr->rexpr, consts);
	}
	else if (IsA(node, A_Const))
	{
		A_Const* ac = (A_Const*)node;
#if PG_VERSION_NUM >= 150000
		if (ac->val.sval.type == T_String && ac->location >= 0)
#else
		if (ac->val.type == T_String && ac->location >= 0)
#endif
		{
			Const* c = consts[ac->location];
			if (c != NULL && c->consttype != TEXTOID) {
				TypeCast* cast = makeNode(TypeCast);
				char* type_name;
#if PG_VERSION_NUM>=110000
				type_name = format_type_extended(c->consttype, c->consttypmod, FORMAT_TYPE_TYPEMOD_GIVEN);
#else
				type_name = format_type_with_typemod(c->consttype, c->consttypmod);
#endif
				cast->arg = (Node*)ac;
				cast->typeName = makeTypeName(type_name);
				cast->location = ac->location;
				node = (Node*)cast;
			}
		}
	}
	return node;
}

static RangeVar*
vops_get_join_rangevar(Node* node, int* relno)
{
	if (IsA(node, JoinExpr))
	{
		RangeVar* rv;
		JoinExpr* join = (JoinExpr*)node;
		rv = vops_get_join_rangevar(join->larg, relno);
		if (rv != NULL)
			return rv;
		rv = vops_get_join_rangevar(join->rarg, relno);
		if (rv != NULL)
			return rv;
	}
	else
	{
		Assert(IsA(node, RangeVar));
		if (--*relno == 0)
			return (RangeVar*)node;
	}
	return NULL;
}

static RangeVar*
vops_get_rangevar(List* from, int relno)
{
	ListCell* cell;
	foreach (cell, from)
	{
		Node* node = (Node*)lfirst(cell);
		RangeVar* rv = vops_get_join_rangevar(node, &relno);
		if (rv != NULL)
			return rv;
	}
	return NULL;
}

/*
 * Try to substitute tables with their VOPS projections.
 * Criterias for such substitution:
 *   1. All attributes used in query are available in projection
 *   2. Vector attributes are used only in aggregates ot in WHERE clause
 *   3. Query pperforms some aggregation on vector attributes
 *   4. Attributes used in the same expression are either all scalar, either all vector.
 */
static void
vops_substitute_tables_with_projections(char const* queryString, Query *query)
{
	vops_pullvar_context pullvar_ctx;
	int i, j, relno, fromno, rc;
	int n_rels = list_length(query->rtable);
	MemoryContext memctx = CurrentMemoryContext;
	Oid argtype = OIDOID;
	Datum reloid;
	SelectStmt* select = NULL;
	Bitmapset* vectorCols = NULL; /* bitmap set of vector columns from all tables: (attno*n_rels + relno - 1) */
	Bitmapset* scalarCols = NULL; /* bitmap set of scalar columns from all tables: (attno*n_rels + relno - 1) */
	bool hasAggregates = false;
#if PG_VERSION_NUM>=100000
	RawStmt *parsetree = NULL;
#else
	Node *parsetree = NULL;
#endif

	pullvar_ctx.query = query;
	pullvar_ctx.n_rels = n_rels;
	pullvar_ctx.clusters = NULL;
	pullvar_ctx.consts = (Const**)palloc0((strlen(queryString) + 1)*sizeof(Const*));
	pullvar_ctx.scope = SCOPE_DEFAULT;
	pullvar_ctx.refs = palloc0(n_rels*sizeof(vops_table_refs));
	query_tree_walker(query, vops_pullvars_walker, &pullvar_ctx, QTW_IGNORE_CTE_SUBQUERIES|QTW_IGNORE_RANGE_TABLE);

    SPI_connect();

	for (relno = 0, fromno = 0; relno < n_rels; relno++)
	{
		RangeTblEntry* rte = list_nth_node(RangeTblEntry, query->rtable, relno);
		vops_table_refs* refs = &pullvar_ctx.refs[relno];

		if (rte->rtekind != RTE_RELATION)
			continue;

		fromno += 1;
		reloid = ObjectIdGetDatum(rte->relid);
		rc = SPI_execute_with_args("select * from vops_projections where source_table=$1",
								   1, &argtype, &reloid, NULL, true, 0);
		if (rc != SPI_OK_SELECT)
		{
			Assert(select == NULL);
			elog(WARNING, "Table vops_projections doesn't exists");
			break;
		}
		for (i = 0; i < SPI_processed; i++)
		{
			HeapTuple tuple = SPI_tuptable->vals[i];
			TupleDesc tupDesc = SPI_tuptable->tupdesc;
			bool isnull;
			char* projectionName = SPI_getvalue(tuple, tupDesc, 1);
			ArrayType* vectorColumns = NULL;
			ArrayType* scalarColumns = NULL;
			char* keyName = SPI_getvalue(tuple, tupDesc, 5);
			Datum* vectorAttnos;
			Datum* scalarAttnos;
			Datum  datum;
			int    nScalarColumns;
			int    nVectorColumns;
			Bitmapset* vectorAttrs = NULL;
			Bitmapset* scalarAttrs = NULL;
			Bitmapset* allAttrs;


			datum = SPI_getbinval(tuple, tupDesc, 3, &isnull);
			if (!isnull)
			{
				vectorColumns = (ArrayType*)DatumGetPointer(PG_DETOAST_DATUM(datum));

				/* Construct set of used vector columns */
				deconstruct_array(vectorColumns, INT4OID, 4, true, 'i', &vectorAttnos, NULL, &nVectorColumns);
				for (j = 0; j < nVectorColumns; j++)
				{
					vectorAttrs = bms_add_member(vectorAttrs, DatumGetInt32(vectorAttnos[j]));
				}
			}

			datum = SPI_getbinval(tuple, tupDesc, 4, &isnull);
			if (!isnull)
			{
				scalarColumns = isnull ? NULL : (ArrayType*)DatumGetPointer(PG_DETOAST_DATUM(datum));

				/* Construct set of used scalar columns */
				deconstruct_array(scalarColumns, INT4OID, 4, true, 'i', &scalarAttnos, NULL, &nScalarColumns);
				for (j = 0; j < nScalarColumns; j++)
				{
					scalarAttrs = bms_add_member(scalarAttrs, DatumGetInt32(scalarAttnos[j]));
				}
			} 
			allAttrs = bms_union(vectorAttrs, vectorAttrs);

			hasAggregates |= refs->agg != NULL;
			if (bms_is_subset(refs->where, allAttrs)        /* attributes in WHERE clause can be either scalar either vector */
				&& bms_is_subset(refs->agg, vectorAttrs)    /* aggregates are calculated only for vector columns */
				&& bms_is_subset(refs->other, scalarAttrs)) /* variables used in other clauses can be only scalar */
			{
				MemoryContext spi_memctx = MemoryContextSwitchTo(memctx);
				RangeVar* rv;

				if (select == NULL)
				{
					List *parsetree_list;

					parsetree_list = pg_parse_query(queryString);
					if (list_length(parsetree_list) != 1)
					{
						SPI_finish();
						MemoryContextSwitchTo(memctx);
						return;
					}
#if PG_VERSION_NUM>=100000
					parsetree = linitial_node(RawStmt, parsetree_list);
#if PG_VERSION_NUM>=140000
					if (parsetree->stmt->type == T_ExplainStmt)
					{
						ExplainStmt* explain = (ExplainStmt*)parsetree->stmt;
						select = (SelectStmt*)explain->query;
						parsetree->stmt = (Node*)select;
					}
					else
#endif
						select = (SelectStmt*)parsetree->stmt;
#else
					parsetree = (Node*) linitial(parsetree_list);
					select = (SelectStmt*) parsetree;
#endif
				}
				/* Replace table with partition */
				elog(DEBUG1, "Use projection %s instead of table %d", projectionName, rte->relid);
				rv = vops_get_rangevar(select->fromClause, fromno);
				Assert(rv != NULL);
				if (rv->alias == NULL)
					rv->alias = makeAlias(rv->relname, NULL);
				rv->relname = pstrdup(projectionName);

				/* Update vector/scalar bitmap sets for this query for this projection */
				for (j = 0; j < nVectorColumns; j++)
				{
					vectorCols = bms_add_member(vectorCols, DatumGetInt32(vectorAttnos[j])*n_rels + relno);
				}
				for (j = 0; j < nScalarColumns; j++)
				{
					scalarCols = bms_add_member(scalarCols, DatumGetInt32(scalarAttnos[j])*n_rels + relno);
				}
				if (keyName != NULL && select->whereClause)
				{
					if (IsA(select->whereClause, BoolExpr)
						&& ((BoolExpr*)select->whereClause)->boolop == AND_EXPR)
					{
						ListCell* cell;
						BoolExpr* andExpr = (BoolExpr*)select->whereClause;
						List* conjuncts = NULL;
						foreach (cell, andExpr->args)
						{
							Node* conjunct = (Node*)lfirst(cell);
							conjuncts = vops_add_index_cond(conjunct, conjuncts, keyName);
						}
						andExpr->args = conjuncts;
					}
					else
					{
						List* conjuncts = vops_add_index_cond(select->whereClause, NULL, keyName);
						if (list_length(conjuncts) > 1)
						{
							BoolExpr* andExpr = makeNode(BoolExpr);
							andExpr->args = conjuncts;
							andExpr->boolop = AND_EXPR;
							andExpr->location = -1;
							select->whereClause = (Node*)andExpr;
						}
					}
				}
				MemoryContextSwitchTo(spi_memctx);
				break;
			}
			SPI_freetuple(tuple);
		}

		if (i == SPI_processed) /* No suitable projection was found... */
		{
			int	bit = -1;
			Bitmapset* all = bms_join(bms_join(refs->agg, refs->where), refs->other);
			MemoryContext spi_memctx = MemoryContextSwitchTo(memctx);
			/* Add all used attributes to set of scalar columns */
			while ((bit = bms_next_member(all, bit)) >= 0)
			{
				scalarCols = bms_add_member(scalarCols, bit*n_rels + relno);
			}
			MemoryContextSwitchTo(spi_memctx);
		}
		SPI_freetuptable(SPI_tuptable);
	}
 	SPI_finish();
	MemoryContextSwitchTo(memctx);

	if (select != NULL    /* We did some substitution... */
		&& hasAggregates  /* use projection only if we do some aggregation */
		&& vops_check_clusters(pullvar_ctx.clusters, vectorCols, scalarCols)) /* vector and scalar columns are not mixed in one expression */ 
	{
		vops_add_literal_type_casts(select->whereClause, pullvar_ctx.consts);

		PG_TRY();
		{
#if PG_VERSION_NUM>=150000
#define parse_analyze parse_analyze_fixedparams
#endif
			Query* subst = parse_analyze(parsetree, queryString, NULL, 0
#if PG_VERSION_NUM>=100000
										 , NULL
#endif
				);
			*query = *subst; /* Urgh! Copying structs is not the best way to substitute the query */
		}
		PG_CATCH();
		{
			elog(LOG, "Failed to substitute query %s", queryString);
			/*
			 * We are leaking some relcache entries in case of error, but it is better
			 * then aborting the query
			 */
		}
		PG_END_TRY();
	}
}

static void
vops_resolve_functions(void)
{

	if (is_not_null_oid == InvalidOid)
	{
		int i;
		Oid profile[2];
		Oid any = ANYELEMENTOID;
		is_not_null_oid = LookupFuncName(list_make1(makeString("is_not_null")), 1, &any, true); /* lookup last functions defined in extension */
		if (is_not_null_oid != InvalidOid) /* if extension is already intialized */
		{
			vops_get_type(InvalidOid); /* initialize type map */
			vops_bool_oid = vops_type_map[VOPS_BOOL].oid;
			profile[0] = vops_bool_oid;
			profile[1] = vops_bool_oid;
			filter_oid = LookupFuncName(list_make1(makeString("filter")), 1, profile, false);
			vops_and_oid = LookupFuncName(list_make1(makeString("vops_bool_and")), 2, profile, false);
			vops_or_oid = LookupFuncName(list_make1(makeString("vops_bool_or")), 2, profile, false);
			vops_not_oid = LookupFuncName(list_make1(makeString("vops_bool_not")), 1, profile, false);
			count_oid = LookupFuncName(list_make1(makeString("count")), 0, profile, false);
			vcount_oid = LookupFuncName(list_make1(makeString("vcount")), 1, &any, false);
			is_null_oid = LookupFuncName(list_make1(makeString("is_null")), 1, &any, false);

			for (i = VOPS_CHAR; i < VOPS_LAST; i++) {
				profile[0] = profile[1] = vops_type_map[i].oid;
				coalesce_oids[i] = LookupFuncName(list_make1(makeString("ifnull")), 2, profile, false);
			}
		}
	}
}

#if PG_VERSION_NUM>=140000
static void vops_post_parse_analysis_hook(ParseState *pstate, Query *query, JumbleState *jstate)
#else
static void vops_post_parse_analysis_hook(ParseState *pstate, Query *query)
#endif
{
	vops_var var;

	/* Invoke original hook if needed */
	if (post_parse_analyze_hook_next)
	{
#if PG_VERSION_NUM>=140000
		post_parse_analyze_hook_next(pstate, query, jstate);
#else
		post_parse_analyze_hook_next(pstate, query);
#endif
	}
	vops_resolve_functions();

	filter_mask = ~0;
	if (query->commandType == CMD_SELECT &&
		vops_auto_substitute_projections &&
		pstate->p_paramref_hook == NULL)    /* do not support prepared statements yet */
	{
		vops_substitute_tables_with_projections(pstate->p_sourcetext, query);
	}
	if (is_select_from_vops_projection(query, &var))
	{
		(void)query_tree_mutator(query, vops_expression_tree_mutator, &var, QTW_DONT_COPY_QUERY);
	}
}

#if PG_VERSION_NUM<140000
#if PG_VERSION_NUM>=110000
static void vops_explain_hook(Query *query,
							  int cursorOptions,
							  IntoClause *into,
							  ExplainState *es,
							  const char *queryString,
							  ParamListInfo params,
							  QueryEnvironment *queryEnv)
{
#elif PG_VERSION_NUM>=100000
static void vops_explain_hook(Query *query,
							  int cursorOptions,
							  IntoClause *into,
							  ExplainState *es,
							  const char *queryString,
							  ParamListInfo params)
{
	QueryEnvironment *queryEnv = NULL;
#else
static void vops_explain_hook(Query *query,
							  IntoClause *into,
							  ExplainState *es,
							  const char *queryString,
							  ParamListInfo params)
{
	int cursorOptions = 0;
#endif
	vops_var var;
	PlannedStmt *plan;
	instr_time	planstart, planduration;

	INSTR_TIME_SET_CURRENT(planstart);

	vops_resolve_functions();

	if (query->commandType == CMD_SELECT &&
		vops_auto_substitute_projections &&
		params == NULL)    /* do not support prepared statements yet */
	{
		char* explain = pstrdup(queryString);
		char* select;
		size_t prefix;
		select = strstr(explain, "select");
		if (select == NULL) {
			select = strstr(explain, "SELECT");
		}
		prefix = (select != NULL) ? (select - explain) : 7;
		memset(explain, ' ', prefix);  /* clear "explain" prefix: we need to preseve node locations */
		vops_substitute_tables_with_projections(explain, query);
	}
	if (is_select_from_vops_projection(query, &var))
	{
		(void)query_tree_mutator(query, vops_expression_tree_mutator, &var, QTW_DONT_COPY_QUERY);
	}
	plan = pg_plan_query(query,
#if PG_VERSION_NUM>=130000
						 queryString,
#endif
						 cursorOptions,
						 params);

	INSTR_TIME_SET_CURRENT(planduration);
	INSTR_TIME_SUBTRACT(planduration, planstart);

	/* run it (if needed) and produce output */
	ExplainOnePlan(plan, into, es, queryString, params,
#if PG_VERSION_NUM>=100000
				   queryEnv,
#endif
				   &planduration
#if PG_VERSION_NUM>=130000
				   ,NULL
#endif
		);
}
#endif

static void reset_static_cache(void)
{
	vops_type_map[0].oid = InvalidOid;
	is_not_null_oid = InvalidOid;
}

void _PG_init(void)
{
	elog(LOG, "Initialize VOPS extension");
	post_parse_analyze_hook_next	= post_parse_analyze_hook;
	post_parse_analyze_hook			= vops_post_parse_analysis_hook;
#if PG_VERSION_NUM<140000
	save_explain_hook = ExplainOneQuery_hook;
	ExplainOneQuery_hook = vops_explain_hook;
#endif
    DefineCustomBoolVariable("vops.auto_substitute_projections",
							 "Automatically substitute tables with thier projections",
							 NULL,
							 &vops_auto_substitute_projections,
							 false,
							 PGC_USERSET,
							 0,
							 NULL,
							 NULL,
							 NULL);
}
