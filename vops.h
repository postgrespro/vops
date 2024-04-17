#ifndef __VOPS_H__
#define __VOPS_H__

#define VOPS_SIZEOF_TEXT(width) (LONGALIGN(VARHDRSZ) + sizeof(vops_tile_hdr) + (width)*TILE_SIZE)
#define VOPS_ELEM_SIZE(var)     ((VARSIZE(var) - LONGALIGN(VARHDRSZ) - sizeof(vops_tile_hdr)) / TILE_SIZE)
#define VOPS_TEXT_TILE(val)     ((vops_tile_hdr*)((char*) pg_detoast_datum(val) + LONGALIGN(VARHDRSZ)))
#define VOPS_GET_TILE(val,tid)  (((tid) == VOPS_TEXT) ? VOPS_TEXT_TILE((struct varlena *) DatumGetPointer(val)) : (vops_tile_hdr*)DatumGetPointer(val))

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
	VOPS_INTERVAL,
	VOPS_TEXT,
	VOPS_LAST,
} vops_type;

static inline bool
is_vops_type_integer(vops_type type)
{
	return type < VOPS_FLOAT4 || type == VOPS_INTERVAL;
}

typedef enum
{
	VOPS_AGG_SUM,
	VOPS_AGG_AVG,
	VOPS_AGG_MAX,
	VOPS_AGG_MIN,
	VOPS_AGG_COUNT,
	VOPS_AGG_LAST
} vops_agg_kind;


#define TILE_SIZE 64			/* just because of maximum size of bitmask */
#define MAX_CSV_LINE_LEN 4096
#define INIT_MAP_SIZE (1024*1024)

typedef long long long64;

extern uint64 filter_mask;

/* Common prefix for all tile */
typedef struct
{
	uint64		null_mask;
	uint64		empty_mask;
} vops_tile_hdr;

#define TILE(TYPE,CTYPE)						\
	typedef struct {							\
		vops_tile_hdr hdr;						\
		CTYPE  payload[TILE_SIZE];				\
	} vops_##TYPE

TILE(char, char);
TILE(int2, int16);
TILE(int4, int32);
TILE(int8, int64);
TILE(float4, float4);
TILE(float8, float8);

typedef struct
{
	vops_tile_hdr hdr;
	uint64		payload;
} vops_bool;

typedef struct
{
	uint64		count;
	double		sum;
} vops_avg_state;

typedef struct
{
	uint64		count;
	double		sum;
	double		sum2;
} vops_var_state;

typedef struct
{
	HTAB	   *htab;
	int			n_aggs;
	vops_type	agg_type;
	vops_agg_kind *agg_kinds;
} vops_agg_state;

typedef union
{
	bool		b;
	char		ch;
	int16		i2;
	int32		i4;
	int64		i8;
	float		f4;
	double		f8;
} vops_value;

typedef struct
{
	vops_value	acc;
	uint64		count;
} vops_agg_value;

typedef struct
{
	int64		group_by;
	uint64		count;
	vops_agg_value values[1];
} vops_group_by_entry;

#define VOPS_AGGREGATES_ATTRIBUTES 3

typedef struct
{
	HASH_SEQ_STATUS iter;
	TupleDesc	desc;
	Datum	   *elems;
	bool	   *nulls;
	int16		elmlen;
	bool		elmbyval;
	char		elmalign;
} vops_reduce_context;

typedef struct
{
	Datum	   *values;
	bool	   *nulls;
	vops_type  *types;
	TupleDesc	desc;
	int			n_attrs;
	int			tile_pos;
	uint64		filter_mask;
	vops_tile_hdr **tiles;
} vops_unnest_context;

typedef struct
{
	vops_float8 tile;
	double		sum;
	double		sum2;
	uint64		count;
} vops_window_state;


typedef struct
{
	vops_type	tid;
	int16		len;
	bool		byval;
	char		align;
	FmgrInfo	inproc;
	Oid			inproc_param_oid;
	Oid			src_type;
	Oid			dst_type;
} vops_type_info;

typedef struct
{
	Datum		val;
	Datum		ts;
	bool		val_is_null;
	bool		ts_is_null;
} vops_first_state;

extern vops_type vops_get_type(Oid typid);

#if PG_VERSION_NUM>=130000
#define heap_open(oid, lock) table_open(oid, lock)
#define heap_close(oid, lock) table_close(oid, lock)
#define heap_openrv_extended(rel, lockmode, missing_ok) table_openrv_extended(rel, lockmode, missing_ok)
#endif


#endif
