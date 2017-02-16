#include "postgres.h"

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
#include "storage/ipc.h"
#include "storage/lmgr.h"
#include "storage/lwlock.h"
#include "storage/bufmgr.h"
#include "storage/proc.h"

#include "tcop/pquery.h"
#include "tcop/tcopprot.h"
#include "tcop/utility.h"

#include "utils/array.h"
#include "utils/tqual.h"
#include "utils/datum.h"
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

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

/* pg module functions */
void _PG_init(void);
void _PG_fini(void);

typedef enum 
{	
	VOPS_BOOL,
	VOPS_CHAR,
	VOPS_INT2,
	VOPS_INT4,
	VOPS_INT8,
	VOPS_DATE,
	VOPS_TIMESTAMP,
	VOPS_FLOAT4,
	VOPS_FLOAT8,
	VOPS_LAST,
} vops_type;

typedef enum
{
	VOPS_AGG_SUM,
	VOPS_AGG_AVG,
	VOPS_AGG_MAX,
	VOPS_AGG_MIN,
	VOPS_AGG_COUNT,
	VOPS_AGG_LAST
} vops_agg_kind;


#define TILE_SIZE 64 /* just because of maximum size of bitmask */
#define MAX_SQL_STMT_LEN 1024
#define MAX_TILE_STRLEN (TILE_SIZE*16)
#define INIT_MAP_SIZE (1024*1024)

static uint64 filter_mask;
typedef long long long64;

/* Common prefix for all tile */
typedef struct {
	uint64 nullmask;						   
} vops_tile;
	
#define TILE(TYPE,CTYPE)						\
	typedef struct {							\
		uint64 nullmask;						\
		CTYPE  payload[TILE_SIZE];				\
	} vops_##TYPE;

typedef struct {
	uint64 nullmask; 
	uint64 payload;
} vops_bool;

typedef struct { 
	uint64 count;
	double sum;
} vops_avg_state;

typedef struct {
	HTAB* htab;
	int   n_aggs;
	vops_type agg_type;
	vops_agg_kind* agg_kinds;
} vops_agg_state;

typedef union {
	bool b;
	char ch;
	int16 i2;
	int32 i4;
	int64 i8;
	float f4;
	double f8;
} vops_value;

typedef struct {
	vops_value acc;
	uint64     count;
} vops_agg_value;

typedef struct { 
	int64  group_by;
	uint64 count;
	vops_agg_value values[1];
} vops_group_by_entry;

#define VOPS_AGGREGATES_ATTRIBUTES 3

typedef struct {
	HASH_SEQ_STATUS iter;
	TupleDesc       desc;
	Datum*          elems;
	bool*           nulls;
    int16           elmlen;    
    bool            elmbyval;
    char            elmalign;
} vops_reduce_context;

typedef struct {
    Datum*          values;
    bool*           nulls;
	vops_type*      types;
    TupleDesc       desc;
	int             n_attrs;
	int             tile_pos;
	vops_tile**     tiles;
} vops_unnest_context;

typedef struct { 
	vops_type tid;
	int16     len;
	bool      byval;
	char      align;
} vops_type_info;	

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
	{"vops_float8",    InvalidOid}
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


static const Oid const vops_map_tid[] = 
{
	BOOLOID,
	CHAROID,
	INT2OID,
	INT4OID,
	INT8OID,
	DATEOID,
	TIMESTAMPOID,
	FLOAT4OID,
	FLOAT8OID
};
	
static vops_agg_state* vops_init_agg_state(char const* aggregates, Oid elem_type, int n_aggregates);
static vops_agg_state* vops_create_agg_state(int n_aggregates);
static void vops_agg_state_accumulate(vops_agg_state* state, int64 group_by, int i, Datum* tiles, bool* nulls);

static vops_type vops_get_type(Oid typid)  
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

/* Parameters used in macros: 
 * TYPE:  Postgres SQL type:                         char,    int2,   int4,   int8, float4, float8
 * CTYPE: Postgres C type:                           char,   int16,  int32,  int64, float8, float8
 * XTYPE: Postgres extended C type:                 int32,   int32,  int32,  int64, float8, float8
 * STYPE: Postgres sum type:                        long64, long64, long64, long64, float8, float8
 * GCTYPE: capitalized prefix used in GETARG macro:   CHAR,  INT16,  INT32,  INT64, FLOAT4, FLOAT8
 * GXTYPE: capitalized prefix of extended type:      INT32,  INT32,  INT32,  INT64, FLOAT8, FLOAT8 
 * GSTYPE: capitalized prefix of sum type:           INT64,  INT64,  INT64,  INT64, FLOAT8, FLOAT8 
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
		result->nullmask = left->nullmask | right->nullmask;			\
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
		result->nullmask = left->nullmask;								\
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
		result->nullmask = right->nullmask;								\
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
		result->nullmask = opd->nullmask;								\
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
		result->nullmask = left->nullmask;								\
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
		for (i = 0; i < TILE_SIZE; i++) result->payload[i] = left COP right->payload[i];	\
		result->nullmask = right->nullmask;								\
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
		result->nullmask = left->nullmask | right->nullmask;			\
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
		result->nullmask = opd->nullmask;								\
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
		result->nullmask = left->nullmask | right->nullmask;			\
		PG_RETURN_POINTER(result);										\
	}

#define SUM_AGG(TYPE,STYPE,GSTYPE)										\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_sum_accumulate);					\
	Datum vops_##TYPE##_sum_accumulate(PG_FUNCTION_ARGS)				\
	{																	\
	    vops_##TYPE* opd = (vops_##TYPE*)PG_GETARG_POINTER(1);			\
		bool is_null = PG_ARGISNULL(0);								    \
		STYPE sum = is_null ? 0 : PG_GETARG_##GSTYPE(0);				\
		int i;															\
		if ((~filter_mask | opd->nullmask) == 0) {						\
		    for (i = 0; i < TILE_SIZE; i++) {							\
			    sum += opd->payload[i];									\
			}															\
			PG_RETURN_##GSTYPE(sum);									\
		} else {														\
			for (i = 0; i < TILE_SIZE; i++) {							\
				if ((filter_mask & ~opd->nullmask) & ((uint64)1 << i)) { \
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

#define COUNT_AGG(TYPE)													\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_count_accumulate);				\
	Datum vops_##TYPE##_count_accumulate(PG_FUNCTION_ARGS)				\
	{																	\
	    vops_##TYPE* opd = (vops_##TYPE*)PG_GETARG_POINTER(1);			\
		int64 count = PG_GETARG_INT64(0);							    \
		int i;															\
		for (i = 0; i < TILE_SIZE; i++) {								\
			if ((filter_mask & ~opd->nullmask) & ((uint64)1 << i)) {	\
				count += 1;												\
			}															\
		}																\
		PG_RETURN_INT64(count);											\
	}

#define MINMAX_AGG(TYPE,CTYPE,GCTYPE,OP,COP)							\
    PG_FUNCTION_INFO_V1(vops_##TYPE##_##OP##_accumulate);	            \
	Datum vops_##TYPE##_##OP##_accumulate(PG_FUNCTION_ARGS)				\
	{																	\
	    vops_##TYPE* opd = (vops_##TYPE*)PG_GETARG_POINTER(1);			\
		bool is_null = PG_ARGISNULL(0);								    \
		CTYPE result = is_null ? 0 : PG_GETARG_##GCTYPE(0);				\
		int i;															\
		for (i = 0; i < TILE_SIZE; i++) {								\
			if ((filter_mask & ~opd->nullmask) & ((uint64)1 << i)) {	\
				if (is_null || opd->payload[i] COP result) {			\
					result = opd->payload[i];							\
					is_null = false;									\
				}														\
			}															\
		}																\
		if (is_null) {													\
			PG_RETURN_NULL();											\
		} else {														\
			PG_RETURN_##GCTYPE(result);									\
		}																\
	}

#define AVG_AGG(TYPE)													\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_avg_accumulate);					\
	Datum vops_##TYPE##_avg_accumulate(PG_FUNCTION_ARGS)				\
	{																	\
	    vops_##TYPE* opd = (vops_##TYPE*)PG_GETARG_POINTER(1);			\
		vops_avg_state* state = PG_ARGISNULL(0) ? NULL : (vops_avg_state*)PG_GETARG_POINTER(0); \
		int i;															\
		for (i = 0; i < TILE_SIZE; i++) {								\
		    if ((filter_mask & ~opd->nullmask) & ((uint64)1 << i)) {	\
			    if (state == NULL) {									\
					MemoryContext agg_context;							\
					MemoryContext old_context;							\
					if (!AggCheckCallContext(fcinfo, &agg_context))		\
						elog(ERROR, "aggregate function called in non-aggregate context"); \
					old_context = MemoryContextSwitchTo(agg_context);	\
					state = (vops_avg_state*)palloc0(sizeof(vops_avg_state)); \
					MemoryContextSwitchTo(old_context);					\
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

#define FIRST_AGG(TYPE,GCTYPE)											\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_first);							\
	Datum vops_##TYPE##_first(PG_FUNCTION_ARGS)							\
	{																	\
	    vops_##TYPE* tile = (vops_##TYPE*)PG_GETARG_POINTER(0);			\
		int i;															\
		for (i = 0; i < TILE_SIZE; i++) {								\
			if (!(tile->nullmask & ((uint64)1 << i))) {					\
				PG_RETURN_##GCTYPE(tile->payload[i]);					\
			}															\
		} 																\
		PG_RETURN_NULL();											    \
	}

#define LAST_AGG(TYPE,GCTYPE)											\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_last);							\
	Datum vops_##TYPE##_last(PG_FUNCTION_ARGS)							\
	{																	\
	    vops_##TYPE* tile = (vops_##TYPE*)PG_GETARG_POINTER(0);			\
		int i;															\
		for (i = TILE_SIZE; --i >= 0;) {								\
			if (!(tile->nullmask & ((uint64)1 << i))) {					\
				PG_RETURN_##GCTYPE(tile->payload[i]);					\
			}															\
		} 																\
		PG_RETURN_NULL();											    \
	}

#define LOW_AGG(TYPE,CTYPE,GCTYPE)										\
	PG_FUNCTION_INFO_V1(vops_##TYPE##_low);								\
	Datum vops_##TYPE##_low(PG_FUNCTION_ARGS)							\
	{																	\
	    vops_##TYPE* tile = (vops_##TYPE*)PG_GETARG_POINTER(0);			\
		int i;														    \
		CTYPE min = 0;													\
		bool is_null = true;											\
		for (i = 0; i < TILE_SIZE; i++) {								\
			if (!(tile->nullmask & ((uint64)1 << i))) {					\
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
		int i;														    \
		CTYPE max = 0;													\
		bool is_null = true;											\
		for (i = 0; i < TILE_SIZE; i++) {								\
			if (!(tile->nullmask & ((uint64)1 << i))) {					\
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
 		if (*str != '{') {												\
		    elog(ERROR, "Failed to parse tile '%s'", str);				\
		}																\
		result = (vops_##TYPE*)palloc(sizeof(vops_##TYPE));				\
		str += 1;														\
		result->nullmask = 0;											\
		for (i=0; i < TILE_SIZE; i++) {									\
			if (strncmp(str, "null", 4) == 0) {							\
				result->nullmask |= (uint64)1 << i;						\
				str += 4;												\
			} else {													\
				if (sscanf(str, "%" #FORMAT "%n", &val, &n) != 1) {		\
					elog(ERROR, "Failed to parse tile item %d: '%s'", i, str); \
				}														\
				str += n;												\
			}															\
			if (*str != ',' && *str != '}') {							\
				elog(ERROR, "Failed to parse tile: separator expected '%s' found", str); \
			}															\
			result->payload[i] = (CTYPE)val;							\
			str += 1;													\
		}																\
		if (*str != '\0') {												\
			elog(ERROR, "Failed to parse tile: unexpected trailing data '%s'", str); \
		}																\
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
 		     if (tile->nullmask & ((uint64)1 << i)) {					\
			     p += sprintf(buf + p, "%cnull", sep);					\
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
		char const* aggregates =  PG_GETARG_CSTRING(2);					\
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
		get_typlenbyvalalign(args->elemtype, &elmlen, &elmbyval, &elmalign); \
		deconstruct_array(args, args->elemtype, elmlen, elmbyval, elmalign, &elems, &nulls, &n_elems); \
		if (!AggCheckCallContext(fcinfo, &agg_context))					\
			elog(ERROR, "aggregate function called in non-aggregate context"); \
		old_context = MemoryContextSwitchTo(agg_context);				\
		if (state == NULL) {											\
			state = vops_init_agg_state(aggregates, args->elemtype, n_elems); \
		}																\
		for (i = 0; i < TILE_SIZE; i++) {								\
			if ((filter_mask & ~gby->nullmask) & ((uint64)1 << i)) {	\
				vops_agg_state_accumulate(state, gby->payload[i], i, elems, nulls); \
			}															\
		}																\
		MemoryContextSwitchTo(old_context);								\
        PG_RETURN_POINTER(state);										\
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
	if (sscanf(str, "{%llx,%llx}", (long64*)&result->nullmask, (long64*)&result->payload) != 2) { 
		elog(ERROR, "Failed to parse bool tile: '%s'", str);	
	}
	PG_RETURN_POINTER(result);
}

PG_FUNCTION_INFO_V1(vops_bool_output);
Datum vops_bool_output(PG_FUNCTION_ARGS)							
{																	
	vops_bool* tile = (vops_bool*)PG_GETARG_POINTER(0);				
	PG_RETURN_CSTRING(psprintf("{%llx,%llx}", (long64)tile->nullmask, (long64)tile->payload));	
}

PG_FUNCTION_INFO_V1(vops_filter);
Datum vops_filter(PG_FUNCTION_ARGS) 
{ 
	if (PG_ARGISNULL(0)) {
		filter_mask = 0;
	} else { 
		vops_bool* result = (vops_bool*)PG_GETARG_POINTER(0);
		filter_mask = result->payload & ~result->nullmask;
	}
	PG_RETURN_BOOL(filter_mask != 0);
}

PG_FUNCTION_INFO_V1(vops_bool_not);
Datum vops_bool_not(PG_FUNCTION_ARGS) 
{ 
	vops_bool* opd = (vops_bool*)PG_GETARG_POINTER(0);
	vops_bool* result = (vops_bool*)palloc(sizeof(vops_bool));
	result->payload = ~opd->payload;
	result->nullmask = opd->nullmask;
	PG_RETURN_POINTER(result);           
}
	
BOOL_BIN_OP(or,|)
BOOL_BIN_OP(and,&)

PG_FUNCTION_INFO_V1(vops_count_accumulate);
Datum vops_count_accumulate(PG_FUNCTION_ARGS) 
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
static EState *estate;
static TupleTableSlot* slot;
static Relation rel;

static void
UserTableUpdateOpenIndexes()
{
	List	   *recheckIndexes = NIL;

	/* HOT update does not require index inserts */
	if (HeapTupleIsHeapOnly(slot->tts_tuple))
		return;

	if (estate->es_result_relation_info->ri_NumIndices > 0)
	{
		recheckIndexes = ExecInsertIndexTuples(slot,
											   &slot->tts_tuple->t_self,
											   estate, false, NULL, NIL);

		if (recheckIndexes != NIL)
			ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
					 errmsg("vops doesn't support index rechecks")));
	}
}


static void begin_batch_insert(Oid oid)
{
	ResultRelInfo *resultRelInfo;

	rel = heap_open(oid, NoLock);

	PushActiveSnapshot(GetTransactionSnapshot());

	estate = CreateExecutorState();

	resultRelInfo = makeNode(ResultRelInfo);
	resultRelInfo->ri_RangeTableIndex = 1;		/* dummy */
	resultRelInfo->ri_RelationDesc = rel;
	resultRelInfo->ri_TrigInstrument = NULL;

	estate->es_result_relations = resultRelInfo;
	estate->es_num_result_relations = 1;
	estate->es_result_relation_info = resultRelInfo;

	ExecOpenIndices(estate->es_result_relation_info, false);
	slot = ExecInitExtraTupleSlot(estate);
	ExecSetSlotDescriptor(slot, RelationGetDescr(rel));
}

static void insert_tuple(Datum* values, bool* nulls)
{
	HeapTuple tup = heap_form_tuple(RelationGetDescr(rel), values, nulls);
	ExecStoreTuple(tup, slot, InvalidBuffer, true);
	simple_heap_insert(rel, slot->tts_tuple);
    UserTableUpdateOpenIndexes(estate, slot);
}

static void end_batch_insert()
{
	ExecCloseIndices(estate->es_result_relation_info);
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
			MemoryContext old_context;									
			if (!AggCheckCallContext(fcinfo, &agg_context))				
				elog(ERROR, "aggregate function called in non-aggregate context"); 
			old_context = MemoryContextSwitchTo(agg_context);			
			state0 = (vops_avg_state*)palloc0(sizeof(vops_avg_state));	
			MemoryContextSwitchTo(old_context);							
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
	
#define REGISTER_TYPE(TYPE,CTYPE,XTYPE,STYPE,GCTYPE,GXTYPE,GSTYPE,FORMAT,PREC) \
	TILE(TYPE,CTYPE)										\
	UNARY_OP(TYPE,neg,-)									\
	BIN_OP(TYPE,add,+)										\
	BIN_LCONST_OP(TYPE,XTYPE,GXTYPE,add,+)					\
	BIN_RCONST_OP(TYPE,XTYPE,GXTYPE,add,+)					\
	BIN_OP(TYPE,sub,-)										\
	BIN_LCONST_OP(TYPE,XTYPE,GXTYPE,sub,-)					\
	BIN_RCONST_OP(TYPE,XTYPE,GXTYPE,sub,-)					\
	BIN_OP(TYPE,mul,*)										\
	BIN_LCONST_OP(TYPE,XTYPE,GXTYPE,mul,*)					\
	BIN_RCONST_OP(TYPE,XTYPE,GXTYPE,mul,*)					\
	BIN_OP(TYPE,div,/)										\
	BIN_LCONST_OP(TYPE,XTYPE,GXTYPE,div,/)					\
	BIN_RCONST_OP(TYPE,XTYPE,GXTYPE,div,/)					\
	CMP_OP(TYPE,eq,==)										\
	CMP_LCONST_OP(TYPE,XTYPE,GXTYPE,eq,==)					\
	CMP_RCONST_OP(TYPE,XTYPE,GXTYPE,eq,==)					\
	CMP_OP(TYPE,ne,!=)										\
	CMP_LCONST_OP(TYPE,XTYPE,GXTYPE,ne,!=)					\
	CMP_RCONST_OP(TYPE,XTYPE,GXTYPE,ne,!=)					\
	CMP_OP(TYPE,lt,<)										\
	CMP_LCONST_OP(TYPE,XTYPE,GXTYPE,lt,<)					\
	CMP_RCONST_OP(TYPE,XTYPE,GXTYPE,lt,<)					\
	CMP_OP(TYPE,le,<=)										\
	CMP_LCONST_OP(TYPE,XTYPE,GXTYPE,le,<=)					\
	CMP_RCONST_OP(TYPE,XTYPE,GXTYPE,le,<=)					\
	CMP_OP(TYPE,gt,>)										\
	CMP_LCONST_OP(TYPE,XTYPE,GXTYPE,gt,>)					\
	CMP_RCONST_OP(TYPE,XTYPE,GXTYPE,gt,>)					\
	CMP_OP(TYPE,ge,>=)										\
	CMP_LCONST_OP(TYPE,XTYPE,GXTYPE,ge,>=)					\
	CMP_RCONST_OP(TYPE,XTYPE,GXTYPE,ge,>=)					\
	BETWIXT_OP(TYPE,XTYPE,GXTYPE)							\
    COUNT_AGG(TYPE)											\
	SUM_AGG(TYPE,STYPE,GSTYPE)								\
	AVG_AGG(TYPE)											\
	MINMAX_AGG(TYPE,CTYPE,GCTYPE,min,<)						\
	MINMAX_AGG(TYPE,CTYPE,GCTYPE,max,>)						\
	FIRST_AGG(TYPE,GCTYPE)									\
	LAST_AGG(TYPE,GCTYPE)									\
	LOW_AGG(TYPE,CTYPE,GCTYPE)								\
	HIGH_AGG(TYPE,CTYPE,GCTYPE)								\
	IN_FUNC(TYPE,CTYPE,STYPE,FORMAT)						\
	OUT_FUNC(TYPE,STYPE,FORMAT,PREC)						\
    GROUP_BY_FUNC(TYPE)

/*            TYPE,    CTYPE,  XTYPE,  STYPE, GCTYPE, GXTYPE, GSTYPE, FORMAT, PREC */
REGISTER_TYPE(char,     char,  int32, long64,   CHAR,  INT32,  INT64, lld, 0)
REGISTER_TYPE(int2,    int16,  int32, long64,  INT16,  INT32,  INT64, lld, 0)
REGISTER_TYPE(int4,    int32,  int32, long64,  INT32,  INT32,  INT64, lld, 0)
REGISTER_TYPE(int8,    int64,  int64, long64,  INT64,  INT64,  INT64, lld, 0)
REGISTER_TYPE(float4, float4, float8, float8, FLOAT4, FLOAT8, FLOAT8, lg, Max(1, FLT_DIG + extra_float_digits))
REGISTER_TYPE(float8, float8, float8, float8, FLOAT8, FLOAT8, FLOAT8, lg, Max(1, DBL_DIG + extra_float_digits))

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
	sizeof(vops_float8)
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
    char stmt[MAX_SQL_STMT_LEN];

    SPI_connect();    
	sql = psprintf("select attname,atttypid from pg_attribute where attrelid=%d and attnum>0 order by attnum", destination);
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
		types[i].tid = vops_get_type(type_id);
		get_typlenbyvalalign(type_id, &types[i].len, &types[i].byval, &types[i].align);
		n += sprintf(stmt + n, "%c%s", sep, name);
		sep = ',';
		SPI_freetuple(spi_tuple);
	}
    SPI_freetuptable(SPI_tuptable);

	n += sprintf(stmt + n, " from %s.%s", 
				 get_namespace_name(get_rel_namespace(source)), 
				 get_rel_name(source)); 
	if (predicate) { 
		n += sprintf(stmt + n, " where %s", predicate);
	}
	if (sort) { 
		n += sprintf(stmt + n, " order by %s", sort);
	}		
    plan = SPI_prepare(stmt, 0, NULL);	
    portal = SPI_cursor_open(NULL, plan, NULL, NULL, true);

	begin_batch_insert(destination);

	for (i = 0; i < n_attrs; i++) {
		values[i] = PointerGetDatum(types[i].tid != VOPS_LAST ? palloc(vops_sizeof[types[i].tid]) : NULL);
	}
     		
	for (j = 0; ; j++) { 
        SPI_cursor_fetch(portal, true, 1);
        if (SPI_processed) { 
            HeapTuple spi_tuple = SPI_tuptable->vals[0];
            spi_tupdesc = SPI_tuptable->tupdesc;
			if (j == TILE_SIZE) { 
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
							values[i] = datumCopy(val, true, types[i].len);
						}
					}
					else if (is_null != nulls[i] 
							 || !(is_null || datumIsEqual(values[i], val, types[i].byval, types[i].len)))
					{
						/* Mark unassigned elements as nulls */
						for (i = 0; i < n_attrs; i++) { 
							if (types[i].tid != VOPS_LAST) { 
								vops_tile* tile = (vops_tile*)DatumGetPointer(values[i]);
								tile->nullmask |= (uint64)~0 << j;
							}
						}        
						insert_tuple(values, nulls);
						j = 0;
						goto Pack;
					}
				} else { 
					vops_tile* tile = (vops_tile*)DatumGetPointer(values[i]);
					tile->nullmask &= ~((uint64)1 << j);
					tile->nullmask |= (uint64)is_null << j;
					switch (types[i].tid) {
					  case VOPS_BOOL:
						((vops_bool*)tile)->payload &= ~((uint64)1 << j);
						((vops_bool*)tile)->payload |= (uint64)DatumGetBool(val) << j;
					break;
					  case VOPS_CHAR:					
						((vops_char*)tile)->payload[j] = SPI_gettypeid(spi_tupdesc, i+1) == CHAROID
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
			/* Mark unassigned elements as nulls */
			for (i = 0; i < n_attrs; i++) { 
				if (types[i].tid != VOPS_LAST) { 
					vops_tile* tile = (vops_tile*)DatumGetPointer(values[i]);
					tile->nullmask |= (uint64)~0 << j;
				}
			}        
		}
		insert_tuple(values, nulls);		
	}
	end_batch_insert();
	
    SPI_cursor_close(portal);
 	SPI_finish();

	PG_RETURN_VOID();
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
		elog(ERROR, "Group by attributes should have VOPS tile type");
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
			if (!nulls[j] && !(tile->nullmask & ((uint64)1 << i))) 
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
			if (!nulls[j] && !(tile->nullmask & ((uint64)1 << i))) 
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
			if (!nulls[j] && !(tile->nullmask & ((uint64)1 << i))) 
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
			if (!nulls[j] && !(tile->nullmask & ((uint64)1 << i))) 
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
		for (j = 0; j < n_aggregates; j++) { 
			vops_int8* tile = (vops_int8*)DatumGetPointer(tiles[j]);		  
			if (!nulls[j] && !(tile->nullmask & ((uint64)1 << i))) 
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
			if (!nulls[j] && !(tile->nullmask & ((uint64)1 << i))) 
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
			if (!nulls[j] && !(tile->nullmask & ((uint64)1 << i))) 
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
		user_ctx->tiles = (vops_tile**)palloc(sizeof(vops_tile*)*n_attrs);
        user_ctx->desc = CreateTemplateTupleDesc(n_attrs, false);
        func_ctx->user_fctx = user_ctx;
        user_ctx->n_attrs = n_attrs;
		user_ctx->tile_pos = 0;

        for (i = 0; i < n_attrs; i++) {
			Form_pg_attribute attr = src_desc->attrs[i]; 
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
					user_ctx->tiles[i] = (vops_tile*)PointerGetDatum(val);				
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
		if (filter_mask & ((uint64)1 << j)) {
			for (i = 0; i < n_attrs; i++) {
				vops_tile* tile = user_ctx->tiles[i];
				if (tile == NULL || (tile->nullmask & ((uint64)1 << j))) { 
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
						value = Int64GetDatum(((vops_int8*)tile)->payload[j]);
						break;
					  case VOPS_FLOAT4:
						value = Float4GetDatum(((vops_float4*)tile)->payload[j]);
						break;
					  case VOPS_FLOAT8:
						value = Float8GetDatum(((vops_float8*)tile)->payload[j]);
						break;
					  default:
						Assert(false);
					}
					user_ctx->values[i] = value;
					user_ctx->nulls[i] = false;
				}
			}
			user_ctx->tile_pos = j+1;
			SRF_RETURN_NEXT(func_ctx, HeapTupleGetDatum(heap_form_tuple(user_ctx->desc, user_ctx->values, user_ctx->nulls)));
		}
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
	result->nullmask = left->nullmask | right->nullmask;
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
	result->nullmask = left->nullmask | right->nullmask;
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
	result->nullmask = left->nullmask | right->nullmask;
	PG_RETURN_POINTER(result);
}
		
static Oid vops_bool_oid;
static Oid filter_oid;
static Oid vops_and_oid;
static Oid vops_or_oid;
static Oid vops_not_oid;
static Oid countall_oid;
static Oid count_oid;

typedef struct
{
	Aggref* countall;
	bool    has_vector_aggregates;
} vops_mutator_context;

static Node*
vops_expression_tree_mutator(Node *node, void *context)
{
	vops_mutator_context* ctx = (vops_mutator_context*)context;
	if (node == NULL) 
	{ 
		return NULL;
	}
	if (IsA(node, Query))
	{
		vops_mutator_context save_ctx = *ctx;
		ctx->countall = NULL;
		ctx->has_vector_aggregates = false;
		
		node = (Node *) query_tree_mutator((Query *) node,
										   vops_expression_tree_mutator,
										   context,
										   QTW_DONT_COPY_QUERY);
		*(vops_mutator_context*)context = save_ctx; /* restore qurye context */
		return node;
	}
	/* depth first traversal */
	node = expression_tree_mutator(node, vops_expression_tree_mutator, context);
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
	else if (IsA(node, Aggref))
	{
		Aggref* agg = (Aggref*)node;
		if (agg->aggfnoid == count_oid) {
			Assert(agg->aggstar);
			if (ctx->has_vector_aggregates) { 
				agg->aggfnoid = countall_oid;
				ctx->countall = NULL;
			} else { 
				ctx->countall = agg;
			}
		} else if (!agg->aggstar && !ctx->has_vector_aggregates) {
			Assert(list_length(agg->aggargtypes) >= 1);
			if (vops_get_type(linitial_oid(agg->aggargtypes)) != VOPS_LAST) {
				ctx->has_vector_aggregates = true;
				if (ctx->countall) {
					ctx->countall->aggfnoid = countall_oid;
					ctx->countall = NULL;
				} 
			}
		}
	}
	return node;
}

static post_parse_analyze_hook_type	post_parse_analyze_hook_next;

static void vops_post_parse_analysis_hook(ParseState *pstate, Query *query)
{
	vops_mutator_context ctx = {NULL,false};	
	/* Invoke original hook if needed */
	if (post_parse_analyze_hook_next) {
		post_parse_analyze_hook_next(pstate, query);
	}
	if (vops_bool_oid == InvalidOid) { 
		Oid profile[2];
		vops_bool_oid = LookupTypeNameOid(NULL, makeTypeName("vops_bool"), false);
		profile[0] = vops_bool_oid;
		profile[1] = vops_bool_oid;
		filter_oid = LookupFuncName(list_make1(makeString("filter")), 1, profile, false);
		vops_and_oid = LookupFuncName(list_make1(makeString("vops_bool_and")), 2, profile, false);
		vops_or_oid = LookupFuncName(list_make1(makeString("vops_bool_or")), 2, profile, false);
		vops_not_oid = LookupFuncName(list_make1(makeString("vops_bool_not")), 1, profile, false);
		count_oid = LookupFuncName(list_make1(makeString("count")), 0, profile, false);
		countall_oid = LookupFuncName(list_make1(makeString("countall")), 0, profile, false);
	}
	(void)query_tree_mutator(query, vops_expression_tree_mutator, &ctx, QTW_DONT_COPY_QUERY);
}

void _PG_init(void)
{
	post_parse_analyze_hook_next	= post_parse_analyze_hook;
	post_parse_analyze_hook			= vops_post_parse_analysis_hook;
}

void _PG_fini(void)
{
	post_parse_analyze_hook = post_parse_analyze_hook_next;
}
