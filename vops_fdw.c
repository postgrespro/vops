/*-------------------------------------------------------------------------
 *
 * postgres_fdw.c
 *		  Foreign-data wrapper for remote PostgreSQL servers
 *
 * Portions Copyright (c) 2012-2017, PostgreSQL Global Development Group
 *
 * IDENTIFICATION
 *		  contrib/postgres_fdw/postgres_fdw.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "vops_fdw.h"

#include "access/htup_details.h"
#include "access/sysattr.h"
#include "access/reloptions.h"
#include "catalog/pg_class.h"
#include "catalog/pg_foreign_server.h"
#include "catalog/pg_foreign_table.h"
#include "commands/defrem.h"
#include "commands/explain.h"
#include "commands/vacuum.h"
#include "commands/extension.h"
#include "foreign/fdwapi.h"
#include "funcapi.h"
#include "miscadmin.h"
#include "nodes/makefuncs.h"
#include "nodes/nodeFuncs.h"
#include "optimizer/cost.h"
#include "optimizer/clauses.h"
#include "optimizer/pathnode.h"
#include "optimizer/paths.h"
#include "optimizer/planmain.h"
#include "optimizer/plancat.h"
#if PG_VERSION_NUM>=140000
#include "optimizer/prep.h"
#endif
#include "optimizer/restrictinfo.h"
#if PG_VERSION_NUM>=120000
#include "access/table.h"
#include "nodes/primnodes.h"
#include "optimizer/optimizer.h"
#else
#include "optimizer/var.h"
#endif
#include "optimizer/tlist.h"
#include "parser/parsetree.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/lsyscache.h"
#include "utils/memutils.h"
#include "utils/rel.h"
#include "utils/sampling.h"
#include "utils/selfuncs.h"
#include "executor/spi.h"
#include "vops.h"

/*
 * Indexes of FDW-private information stored in fdw_private lists.
 *
 * These items are indexed with the enum FdwScanPrivateIndex, so an item
 * can be fetched with list_nth().  For example, to get the SELECT statement:
 *		sql = strVal(list_nth(fdw_private, FdwScanPrivateSelectSql));
 */
enum FdwScanPrivateIndex
{
	/* SQL statement to execute remotely (as a String node) */
	FdwScanPrivateSelectSql,
	/* Integer list of attribute numbers retrieved by the SELECT */
	FdwScanPrivateRetrievedAttrs
};

/*
 * Execution state of a foreign scan using postgres_fdw.
 */
typedef struct PgFdwScanState
{
	Relation	rel;			/* relcache entry for the foreign table. NULL
								 * for a foreign join scan. */
	TupleDesc	tupdesc;		/* tuple descriptor of scan */

	/* extracted fdw_private data */
	char	   *query;			/* text of SELECT command */
	List	   *retrieved_attrs;/* list of retrieved attribute numbers */

	/* for remote query execution */
	Portal      portal;			/* SPI portal */
	int			numParams;		/* number of parameters passed to query */
	int         tile_pos;
	uint64      table_pos;
	HeapTuple   spi_tuple;
	Datum*      src_values;
	Datum*      dst_values;
	bool*       src_nulls;
	bool*       dst_nulls;
	vops_type*  vops_types;
	Oid*        attr_types;
	MemoryContext spi_context;
	uint64      filter_mask;
} PgFdwScanState;

/*
 * SQL functions
 */
PG_FUNCTION_INFO_V1(vops_fdw_handler);
PG_FUNCTION_INFO_V1(vops_fdw_validator);

/*
 * FDW callback routines
 */
static void postgresGetForeignRelSize(PlannerInfo *root,
						  RelOptInfo *baserel,
						  Oid foreigntableid);
static void postgresGetForeignPaths(PlannerInfo *root,
						RelOptInfo *baserel,
						Oid foreigntableid);
static ForeignScan *postgresGetForeignPlan(PlannerInfo *root,
					   RelOptInfo *baserel,
					   Oid foreigntableid,
					   ForeignPath *best_path,
					   List *tlist,
					   List *scan_clauses,
					   Plan *outer_plan);
static void postgresBeginForeignScan(ForeignScanState *node, int eflags);
static TupleTableSlot *postgresIterateForeignScan(ForeignScanState *node);
static void postgresReScanForeignScan(ForeignScanState *node);
static void postgresEndForeignScan(ForeignScanState *node);
static void postgresExplainForeignScan(ForeignScanState *node,
						   ExplainState *es);
#if PG_VERSION_NUM>=110000
static void postgresGetForeignUpperPaths(PlannerInfo *root,
										 UpperRelationKind stage,
										 RelOptInfo *input_rel,
										 RelOptInfo *output_rel,
										 void* extra
	);
#else
static void postgresGetForeignUpperPaths(PlannerInfo *root,
										 UpperRelationKind stage,
										 RelOptInfo *input_rel,
										 RelOptInfo *output_rel
	);
#endif
static bool postgresIsForeignScanParallelSafe(PlannerInfo *root, RelOptInfo *rel,
											  RangeTblEntry *rte);
static bool postgresAnalyzeForeignTable(Relation relation,
							AcquireSampleRowsFunc *func,
							BlockNumber *totalpages);
/*
 * Helper functions
 */
static void estimate_path_cost_size(PlannerInfo *root,
						RelOptInfo *baserel,
						List *join_conds,
						List *pathkeys,
						double *p_rows, int *p_width,
						Cost *p_startup_cost, Cost *p_total_cost);

static bool foreign_grouping_ok(PlannerInfo *root, RelOptInfo *grouped_rel);
static void add_foreign_grouping_paths(PlannerInfo *root,
						   RelOptInfo *input_rel,
						   RelOptInfo *grouped_rel);
static int postgresAcquireSampleRowsFunc(Relation relation, int elevel,
							  HeapTuple *rows, int targrows,
							  double *totalrows,
							  double *totaldeadrows);


/*
 * Foreign-data wrapper handler function: return a struct with pointers
 * to my callback routines.
 */
Datum
vops_fdw_handler(PG_FUNCTION_ARGS)
{
	FdwRoutine *routine = makeNode(FdwRoutine);

	/* Functions for scanning foreign tables */
	routine->GetForeignRelSize = postgresGetForeignRelSize;
	routine->GetForeignPaths = postgresGetForeignPaths;
	routine->GetForeignPlan = postgresGetForeignPlan;
	routine->BeginForeignScan = postgresBeginForeignScan;
	routine->IterateForeignScan = postgresIterateForeignScan;
	routine->ReScanForeignScan = postgresReScanForeignScan;
	routine->EndForeignScan = postgresEndForeignScan;
	routine->IsForeignScanParallelSafe = postgresIsForeignScanParallelSafe;

	/* Support functions for ANALYZE */
	routine->AnalyzeForeignTable = postgresAnalyzeForeignTable;

	/* Support functions for EXPLAIN */
	routine->ExplainForeignScan = postgresExplainForeignScan;

	/* Support functions for upper relation push-down */
	routine->GetForeignUpperPaths = postgresGetForeignUpperPaths;

	PG_RETURN_POINTER(routine);
}


Datum
vops_fdw_validator(PG_FUNCTION_ARGS)
{
	List	   *options_list = untransformRelOptions(PG_GETARG_DATUM(0));
	Oid			catalog = PG_GETARG_OID(1);
	ListCell   *cell;

	if (catalog == ForeignTableRelationId) 
	{ 
		bool has_table_name = false;

		foreach(cell, options_list)
		{
			DefElem    *def = (DefElem *) lfirst(cell);
			if (strcmp(def->defname, "table_name") == 0) { 
				has_table_name = true;
			} else if (strcmp(def->defname, "schema_name") != 0) { 
				ereport(ERROR,
						(errcode(ERRCODE_FDW_INVALID_OPTION_NAME),
						 errmsg("invalid option \"%s\"", def->defname),
						 errhint("Valid options in this context are: table_name and schema_name")));
			}
		}
		if (!has_table_name) { 
			ereport(ERROR,
					(errcode(ERRCODE_FDW_INVALID_OPTION_NAME),
					 errmsg("table_name is not specified for foreign table"),
					 errhint("Name of VOPS table should be specified")));
		}
	}					
	PG_RETURN_VOID();
}	


static Relation open_vops_relation(ForeignTable* table)
{
	ListCell   *lc;
	char       *nspname = NULL;
	char       *relname = NULL;
	RangeVar   *rv;


	foreach(lc, table->options)
	{
		DefElem    *def = (DefElem *) lfirst(lc);

		if (strcmp(def->defname, "schema_name") == 0)
			nspname = defGetString(def);
		else if (strcmp(def->defname, "table_name") == 0)
			relname = defGetString(def);
	}
	Assert(relname != NULL);
	if (nspname == NULL) {
		nspname = get_namespace_name(get_rel_namespace(table->relid));
	}
	rv = makeRangeVar(nspname, relname, -1);
	return heap_openrv_extended(rv, RowExclusiveLock, false);
}

/*
 * postgresGetForeignRelSize
 *		Estimate # of rows and width of the result of the scan
 *
 * We should consider the effect of all baserestrictinfo clauses here, but
 * not any join clauses.
 */
static void
postgresGetForeignRelSize(PlannerInfo *root,
						  RelOptInfo *baserel,
						  Oid foreigntableid)
{
	ListCell   *lc;
	PgFdwRelationInfo *fpinfo;
	RangeTblEntry *rte = planner_rt_fetch(baserel->relid, root);
	char       *nspname = NULL;
	char       *relname = NULL;
	char       *refname = NULL;
	Relation    fdw_rel;
	Relation    vops_rel;
	TupleDesc	fdw_tupdesc;	
	TupleDesc	vops_tupdesc;	
	int         i, j;

	/*
	 * We use PgFdwRelationInfo to pass various information to subsequent
	 * functions.
	 */
	fpinfo = (PgFdwRelationInfo *) palloc0(sizeof(PgFdwRelationInfo));
	baserel->fdw_private = (void *) fpinfo;

	/* Base foreign tables need to be pushed down always. */
	fpinfo->pushdown_safe = true;

	/* Look up foreign-table catalog info. */
	fpinfo->table = GetForeignTable(foreigntableid);
	fpinfo->server = GetForeignServer(fpinfo->table->serverid);
	
	Assert(foreigntableid == fpinfo->table->relid);
	
	/*
	 * Build mappnig with VOPS table
	 */
	fpinfo->tile_attrs = NULL;
	fpinfo->vops_attrs = NULL;

	vops_rel = open_vops_relation(fpinfo->table);
	fdw_rel = heap_open(rte->relid, NoLock);
	
	estimate_rel_size(vops_rel, baserel->attr_widths, 
					  &baserel->pages, &baserel->tuples, &baserel->allvisfrac);
	
	baserel->tuples *= TILE_SIZE;

	vops_tupdesc = RelationGetDescr(vops_rel);
	fdw_tupdesc = RelationGetDescr(fdw_rel);

	for (i = 0; i < fdw_tupdesc->natts; i++) 
	{
		for (j = 0; j < vops_tupdesc->natts; j++) 
		{
			if (strcmp(NameStr(TupleDescAttr(vops_tupdesc, j)->attname), NameStr(TupleDescAttr(fdw_tupdesc, i)->attname)) == 0)
			{
				fpinfo->vops_attrs = bms_add_member(fpinfo->vops_attrs, i + 1 - FirstLowInvalidHeapAttributeNumber);
				if (vops_get_type(TupleDescAttr(vops_tupdesc, j)->atttypid) != VOPS_LAST)
				{
					fpinfo->tile_attrs = bms_add_member(fpinfo->tile_attrs, i + 1 - FirstLowInvalidHeapAttributeNumber);
				}						
			}
		}
	}		
    heap_close(fdw_rel, NoLock);
    heap_close(vops_rel, RowExclusiveLock);
	
	/*
	 * Identify which baserestrictinfo clauses can be sent to the remote
	 * server and which can't.
	 */
	vopsClassifyConditions(root, baserel, baserel->baserestrictinfo,
					   &fpinfo->remote_conds, &fpinfo->local_conds);


	/*
	 * Identify which attributes will need to be retrieved from the remote
	 * server.  These include all attrs needed for joins or final output, plus
	 * all attrs used in the local_conds.  (Note: if we end up using a
	 * parameterized scan, it's possible that some of the join clauses will be
	 * sent to the remote and thus we wouldn't really need to retrieve the
	 * columns used in them.  Doesn't seem worth detecting that case though.)
	 */
	fpinfo->attrs_used = NULL;
	pull_varattnos((Node *) baserel->reltarget->exprs, baserel->relid,
				   &fpinfo->attrs_used);
	foreach(lc, fpinfo->local_conds)
	{
		RestrictInfo *rinfo = (RestrictInfo *) lfirst(lc);

		pull_varattnos((Node *) rinfo->clause, baserel->relid,
					   &fpinfo->attrs_used);
	}


	/*
	 * Compute the selectivity and cost of the local_conds, so we don't have
	 * to do it over again for each path.  The best we can do for these
	 * conditions is to estimate selectivity on the basis of local statistics.
	 */
	fpinfo->local_conds_sel = clauselist_selectivity(root,
													 fpinfo->local_conds,
													 baserel->relid,
													 JOIN_INNER,
													 NULL);

	cost_qual_eval(&fpinfo->local_conds_cost, fpinfo->local_conds, root);

	/*
	 * Set cached relation costs to some negative value, so that we can detect
	 * when they are set to some sensible costs during one (usually the first)
	 * of the calls to estimate_path_cost_size().
	 */
	fpinfo->rel_startup_cost = -1;
	fpinfo->rel_total_cost = -1;

	/* Estimate baserel size as best we can with local statistics. */
	set_baserel_size_estimates(root, baserel);
	
	/* Fill in basically-bogus cost estimates for use later. */
	estimate_path_cost_size(root, baserel, NIL, NIL,
							&fpinfo->rows, &fpinfo->width,
							&fpinfo->startup_cost, &fpinfo->total_cost);

	/*
	 * Set the name of relation in fpinfo, while we are constructing it here.
	 * It will be used to build the string describing the join relation in
	 * EXPLAIN output. We can't know whether VERBOSE option is specified or
	 * not, so always schema-qualify the foreign table name.
	 */
	fpinfo->relation_name = makeStringInfo();
	nspname = get_namespace_name(get_rel_namespace(foreigntableid));
	relname = get_rel_name(foreigntableid);
	refname = rte->eref->aliasname;
	appendStringInfo(fpinfo->relation_name, "%s.%s",
					 quote_identifier(nspname),
					 quote_identifier(relname));
	if (*refname && strcmp(refname, relname) != 0)
		appendStringInfo(fpinfo->relation_name, " %s",
						 quote_identifier(rte->eref->aliasname));
}

static bool postgresIsForeignScanParallelSafe(PlannerInfo *root, RelOptInfo *rel,
											  RangeTblEntry *rte)
{
	return true;
}

/*
 * postgresGetForeignPaths
 *		Create possible scan paths for a scan on the foreign table
 */
static void
postgresGetForeignPaths(PlannerInfo *root,
						RelOptInfo *baserel,
						Oid foreigntableid)
{
	PgFdwRelationInfo *fpinfo = (PgFdwRelationInfo *) baserel->fdw_private;
	ForeignPath *path;

	/*
	 * Create simplest ForeignScan path node and add it to baserel.  This path
	 * corresponds to SeqScan path of regular tables (though depending on what
	 * baserestrict conditions we were able to send to remote, there might
	 * actually be an indexscan happening there).  We already did all the work
	 * to estimate cost and size of this path.
	 */
	path = create_foreignscan_path(root,
								   baserel,
								   NULL,		/* default pathtarget */
								   fpinfo->rows,
								   fpinfo->startup_cost,
								   fpinfo->total_cost,
								   NIL,			/* no pathkeys */
								   NULL,		/* no outer rel either */
								   NULL,		/* no extra plan */
#if PG_VERSION_NUM>=170000
								   NIL,			/* no fdw_restrictinfo list */
#endif
								   NIL);		/* no fdw_private list */
	add_path(baserel, (Path *) path);
}

/*
 * postgresGetForeignPlan
 *		Create ForeignScan plan node which implements selected best path
 */
static ForeignScan *
postgresGetForeignPlan(PlannerInfo *root,
					   RelOptInfo *foreignrel,
					   Oid foreigntableid,
					   ForeignPath *best_path,
					   List *tlist,
					   List *scan_clauses,
					   Plan *outer_plan)
{
	PgFdwRelationInfo *fpinfo = (PgFdwRelationInfo *) foreignrel->fdw_private;
	Index		scan_relid;
	List	   *fdw_private;
	List	   *remote_conds = NIL;
	List	   *remote_exprs = NIL;
	List	   *local_exprs = NIL;
	List	   *params_list = NIL;
	List	   *retrieved_attrs;
	ListCell   *lc;
	List	   *fdw_scan_tlist = NIL;
	StringInfoData sql;

	/*
	 * For base relations, set scan_relid as the relid of the relation. For
	 * other kinds of relations set it to 0.
	 */
	if (foreignrel->reloptkind == RELOPT_BASEREL ||
		foreignrel->reloptkind == RELOPT_OTHER_MEMBER_REL)
		scan_relid = foreignrel->relid;
	else
	{
		scan_relid = 0;

		/*
		 * create_scan_plan() and create_foreignscan_plan() pass
		 * rel->baserestrictinfo + parameterization clauses through
		 * scan_clauses. For a join rel->baserestrictinfo is NIL and we are
		 * not considering parameterization right now, so there should be no
		 * scan_clauses for a joinrel and upper rel either.
		 */
		Assert(!scan_clauses);
	}

	/*
	 * Separate the scan_clauses into those that can be executed remotely and
	 * those that can't.  baserestrictinfo clauses that were previously
	 * determined to be safe or unsafe by classifyConditions are shown in
	 * fpinfo->remote_conds and fpinfo->local_conds.  Anything else in the
	 * scan_clauses list will be a join clause, which we have to check for
	 * remote-safety.
	 *
	 * Note: the join clauses we see here should be the exact same ones
	 * previously examined by postgresGetForeignPaths.  Possibly it'd be worth
	 * passing forward the classification work done then, rather than
	 * repeating it here.
	 *
	 * This code must match "extract_actual_clauses(scan_clauses, false)"
	 * except for the additional decision about remote versus local execution.
	 * Note however that we don't strip the RestrictInfo nodes from the
	 * remote_conds list, since appendWhereClause expects a list of
	 * RestrictInfos.
	 */
	foreach(lc, scan_clauses)
	{
		RestrictInfo *rinfo = castNode(RestrictInfo, lfirst(lc));

		/* Ignore any pseudoconstants, they're dealt with elsewhere */
		if (rinfo->pseudoconstant)
			continue;

		if (list_member_ptr(fpinfo->remote_conds, rinfo))
		{
			remote_conds = lappend(remote_conds, rinfo);
			remote_exprs = lappend(remote_exprs, rinfo->clause);
		}
		else if (list_member_ptr(fpinfo->local_conds, rinfo))
			local_exprs = lappend(local_exprs, rinfo->clause);
		else if (vops_is_foreign_expr(root, foreignrel, rinfo->clause))
		{
			remote_conds = lappend(remote_conds, rinfo);
			remote_exprs = lappend(remote_exprs, rinfo->clause);
		}
		else
			local_exprs = lappend(local_exprs, rinfo->clause);
	}

	if (foreignrel->reloptkind == RELOPT_JOINREL ||
		foreignrel->reloptkind == RELOPT_UPPER_REL)
	{
		/* For a join relation, get the conditions from fdw_private structure */
		remote_conds = fpinfo->remote_conds;
		local_exprs = fpinfo->local_conds;

		/* Build the list of columns to be fetched from the foreign server. */
		fdw_scan_tlist = vops_build_tlist_to_deparse(foreignrel);
	}

	/*
	 * Build the query string to be sent for execution, and identify
	 * expressions to be sent as parameters.
	 */
	initStringInfo(&sql);
	vopsDeparseSelectStmtForRel(&sql, root, foreignrel, fdw_scan_tlist,
							remote_conds, best_path->path.pathkeys,
							&retrieved_attrs, &params_list);
	elog(LOG, "Execute VOPS query %s", sql.data);

	/*
	 * Build the fdw_private list that will be available to the executor.
	 * Items in the list must match order in enum FdwScanPrivateIndex.
	 */
	fdw_private = list_make2(makeString(sql.data), retrieved_attrs);
	/*
	 * Create the ForeignScan node for the given relation.
	 *
	 * Note that the remote parameter expressions are stored in the fdw_exprs
	 * field of the finished plan node; we can't keep them in private state
	 * because then they wouldn't be subject to later planner processing.
	 */
	return make_foreignscan(tlist,
							local_exprs,
							scan_relid,
							params_list,
							fdw_private,
							fdw_scan_tlist,
							remote_exprs,
							outer_plan);
}

/*
 * postgresBeginForeignScan
 *		Initiate an executor scan of a foreign PostgreSQL table.
 */
static void
postgresBeginForeignScan(ForeignScanState *node, int eflags)
{
	ForeignScan *fsplan = (ForeignScan *) node->ss.ps.plan;
	EState	    *estate = node->ss.ps.state;
	PgFdwScanState *fsstate;
	int			numParams;
	MemoryContext oldcontext;
	/*
	 * Do nothing in EXPLAIN (no ANALYZE) case.  node->fdw_state stays NULL.
	 */
	if (eflags & EXEC_FLAG_EXPLAIN_ONLY)
		return;

	/*
	 * We'll save private state in node->fdw_state.
	 */
	fsstate = (PgFdwScanState *) palloc0(sizeof(PgFdwScanState));
	node->fdw_state = (void *) fsstate;

	/* Get private info created by planner functions. */
	fsstate->query = strVal(list_nth(fsplan->fdw_private, FdwScanPrivateSelectSql));
	fsstate->retrieved_attrs = (List *) list_nth(fsplan->fdw_private,
												 FdwScanPrivateRetrievedAttrs);

	fsstate->spi_context = AllocSetContextCreate(estate->es_query_cxt,
												 "vops_fdw spi context",
												 ALLOCSET_DEFAULT_SIZES);
	oldcontext = MemoryContextSwitchTo(fsstate->spi_context);
    SPI_connect();
	MemoryContextSwitchTo(oldcontext);

	/*
	 * Get info we'll need for converting data fetched from the foreign server
	 * into local representation and error reporting during that process.
	 */
	if (fsplan->scan.scanrelid > 0)
	{
		fsstate->rel = node->ss.ss_currentRelation;
		fsstate->tupdesc = RelationGetDescr(fsstate->rel);
	}
	else
	{
		fsstate->rel = NULL;
		fsstate->tupdesc = node->ss.ss_ScanTupleSlot->tts_tupleDescriptor;
	}

	/*
	 * Prepare for processing of parameters used in remote query, if any.
	 */
	numParams = list_length(fsplan->fdw_exprs);
	fsstate->numParams = numParams;
	fsstate->dst_values = palloc(fsstate->tupdesc->natts*sizeof(Datum));
	fsstate->src_values = palloc(fsstate->tupdesc->natts*sizeof(Datum));
	fsstate->dst_nulls = palloc(fsstate->tupdesc->natts*sizeof(bool));
	fsstate->src_nulls = palloc(fsstate->tupdesc->natts*sizeof(bool));
	/* Initialize to nulls for any columns not present in result */
	memset(fsstate->dst_nulls, true, fsstate->tupdesc->natts*sizeof(bool));
	
	postgresReScanForeignScan(node);
}

/*
 * postgresIterateForeignScan
 *		Retrieve next row from the result set, or clear tuple slot to indicate
 *		EOF.
 */
static TupleTableSlot *
postgresIterateForeignScan(ForeignScanState *node)
{
	PgFdwScanState *fsstate = (PgFdwScanState *) node->fdw_state;
	TupleTableSlot *slot = node->ss.ss_ScanTupleSlot;
	int i, j;
	HeapTuple tup;
	ListCell *lc;
	int n_attrs = fsstate->tupdesc->natts;
	List* retrieved_attrs = fsstate->retrieved_attrs;
	MemoryContext oldcontext = MemoryContextSwitchTo(fsstate->spi_context);

	while (true) {
		if (fsstate->spi_tuple == NULL) { 
			if (fsstate->portal != NULL) { 
				filter_mask = ~0;
				SPI_cursor_fetch(fsstate->portal, true, 1);
				fsstate->table_pos = 0;
			}
			if (fsstate->table_pos == SPI_processed) {
				MemoryContextSwitchTo(oldcontext);
				return ExecClearTuple(slot);
			}
			if (fsstate->rel == NULL) { 
				fsstate->tile_pos = TILE_SIZE-1;
				fsstate->filter_mask = ~0;
			} else {
				fsstate->tile_pos = 0;
				fsstate->filter_mask = filter_mask;
			}
			fsstate->spi_tuple = SPI_tuptable->vals[fsstate->table_pos++];
			if (fsstate->vops_types == NULL) { 
				fsstate->vops_types = palloc(sizeof(vops_type_info)*n_attrs);
				fsstate->attr_types = palloc(sizeof(Oid)*n_attrs);
				for (i = 0; i < n_attrs; i++) {
					fsstate->vops_types[i] = VOPS_LAST;
				}
				j = 0;
				foreach(lc, retrieved_attrs)
				{
					i = lfirst_int(lc);
					if (i > 0)
					{
						/* ordinary column */
						Assert(i <= n_attrs);
						Assert(j < SPI_tuptable->tupdesc->natts);
						fsstate->attr_types[i-1] = TupleDescAttr(SPI_tuptable->tupdesc, j)->atttypid;
						fsstate->vops_types[i-1] = vops_get_type(fsstate->attr_types[i-1]);
					}
					j += 1;
				}
			}
			j = 0;
			foreach(lc, retrieved_attrs)
			{
				i = lfirst_int(lc);
				if (i > 0)
				{
					/* ordinary column */
					fsstate->src_values[i - 1] = SPI_getbinval(fsstate->spi_tuple, SPI_tuptable->tupdesc, j+1, &fsstate->src_nulls[i - 1]);
				}
				j += 1;
			}
		}
		for (j = fsstate->tile_pos; j < TILE_SIZE; j++) {
			if (fsstate->filter_mask & ((uint64)1 << j)) 
			{
				for (i = 0; i < n_attrs; i++) {
					if (fsstate->vops_types[i] != VOPS_LAST) {
						vops_tile_hdr* tile = VOPS_GET_TILE(fsstate->src_values[i], fsstate->vops_types[i]);
						if (tile != NULL && (tile->empty_mask & ((uint64)1 << j))) {
							goto NextTuple;
						}
						if (tile == NULL || (tile->null_mask & ((uint64)1 << j))) {
							fsstate->dst_nulls[i] = true;
						} else {
							Datum value = 0;
							switch (fsstate->vops_types[i]) {
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
							  case VOPS_INTERVAL:
							  case VOPS_TIMESTAMP:
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
							fsstate->dst_values[i] = value;
							fsstate->dst_nulls[i] = false;
						}
					} else { 
						if (fsstate->attr_types[i] == FLOAT8OID	&& TupleDescAttr(fsstate->tupdesc, i)->atttypid == FLOAT4OID)
						{
							fsstate->dst_values[i] = Float4GetDatum((float)DatumGetFloat8(fsstate->src_values[i]));
						} else { 
							fsstate->dst_values[i] = fsstate->src_values[i];
						}
						fsstate->dst_nulls[i] = fsstate->src_nulls[i];
					}
				}
				fsstate->tile_pos = j+1;
				/*
				 * Return the next tuple.
				 */
				MemoryContextSwitchTo(oldcontext);
				tup = heap_form_tuple(fsstate->tupdesc, fsstate->dst_values, fsstate->dst_nulls);				
#if PG_VERSION_NUM>=120000
				ExecStoreHeapTuple(tup, slot, false);
#else
				ExecStoreTuple(tup, slot, InvalidBuffer, false);
#endif
				return slot;
			}
		  NextTuple:;
		}
		SPI_freetuple(fsstate->spi_tuple);
		if (fsstate->portal) { 
			SPI_freetuptable(SPI_tuptable);
		}
		fsstate->spi_tuple = NULL;
	}
}


/*
 * postgresReScanForeignScan
 *		Restart the scan.
 */
static void
postgresReScanForeignScan(ForeignScanState *node)
{
	PgFdwScanState *fsstate = (PgFdwScanState *) node->fdw_state;
	Datum*      values = NULL;
	char*       nulls = NULL;
	MemoryContext oldcontext = MemoryContextSwitchTo(fsstate->spi_context);
	Oid* argtypes = NULL;
	int rc;

	if (fsstate->numParams > 0) {
		ExprContext *econtext = node->ss.ps.ps_ExprContext;
		ForeignScan *fsplan = (ForeignScan *) node->ss.ps.plan;
		List* param_exprs = (List *)ExecInitExpr((Expr *)fsplan->fdw_exprs, (PlanState *) node);
		ListCell *lc;
		int i = 0;

		values = palloc(sizeof(Datum)*fsstate->numParams);
		nulls = palloc(sizeof(bool)*fsstate->numParams);
		argtypes = palloc(sizeof(Oid)*fsstate->numParams);

		foreach(lc, param_exprs)
		{
			ExprState  *expr_state = (ExprState *) lfirst(lc);
			bool isnull;
			/* Evaluate the parameter expression */
#if PG_VERSION_NUM<100000
			ExprDoneCond isDone;
			values[i] = ExecEvalExpr(expr_state, econtext, &isnull, &isDone);
#else
			values[i] = ExecEvalExpr(expr_state, econtext, &isnull);
#endif
			nulls[i] = (char)isnull;
			argtypes[i] = exprType((Node*)expr_state->expr);
			i += 1;
		}
	}
	if (fsstate->rel == NULL) { /* aggregate is pushed down: do not use cusror to allow parallel query execution */
		rc = SPI_execute_with_args(fsstate->query, fsstate->numParams, argtypes, values, nulls, true, 0);
		if (rc != SPI_OK_SELECT) { 
			elog(ERROR, "Failed to execute VOPS query %s: %d", fsstate->query, rc);
		}
		fsstate->portal = NULL;
	} else { 
		fsstate->portal = SPI_cursor_open_with_args(NULL, fsstate->query, fsstate->numParams, argtypes, values, nulls, true, CURSOR_OPT_PARALLEL_OK);
	}
	fsstate->table_pos = 0;
	fsstate->spi_tuple = NULL;

	MemoryContextSwitchTo(oldcontext);
}

/*
 * postgresEndForeignScan
 *		Finish scanning foreign table and dispose objects used for this scan
 */
static void
postgresEndForeignScan(ForeignScanState *node)
{
	PgFdwScanState *fsstate = (PgFdwScanState *) node->fdw_state;

	/* if fsstate is NULL, we are in EXPLAIN; nothing to do */
	if (fsstate != NULL)
	{
		MemoryContext oldcontext = MemoryContextSwitchTo(fsstate->spi_context);

		if (fsstate->portal) {
			SPI_cursor_close(fsstate->portal);
		}
		SPI_finish();

		MemoryContextSwitchTo(oldcontext);
	}
}

/*
 * postgresExplainForeignScan
 *		Produce extra output for EXPLAIN of a ForeignScan on a foreign table
 */
static void
postgresExplainForeignScan(ForeignScanState *node, ExplainState *es)
{
	List	   *fdw_private;
	char	   *sql;

	fdw_private = ((ForeignScan *) node->ss.ps.plan)->fdw_private;

	/*
	 * Add remote query, when VERBOSE option is specified.
	 */
	if (es->verbose)
	{
		sql = strVal(list_nth(fdw_private, FdwScanPrivateSelectSql));
		ExplainPropertyText("VOPS query", sql, es);
	}
}

/*
 * estimate_path_cost_size
 *		Get cost and size estimates for a foreign scan on given foreign relation
 *		either a base relation or a join between foreign relations or an upper
 *		relation containing foreign relations.
 *
 * param_join_conds are the parameterization clauses with outer relations.
 * pathkeys specify the expected sort order if any for given path being costed.
 *
 * The function returns the cost and size estimates in p_row, p_width,
 * p_startup_cost and p_total_cost variables.
 */
static void
estimate_path_cost_size(PlannerInfo *root,
						RelOptInfo *foreignrel,
						List *param_join_conds,
						List *pathkeys,
						double *p_rows, int *p_width,
						Cost *p_startup_cost, Cost *p_total_cost)
{
	PgFdwRelationInfo *fpinfo = (PgFdwRelationInfo *) foreignrel->fdw_private;
	double		rows;
	double		retrieved_rows;
	int			width;
	Cost		startup_cost;
	Cost		total_cost;
	Cost		cpu_per_tuple;
	Cost		run_cost = 0;
	
   /*
	* We don't support join conditions in this mode (hence, no
	* parameterized paths can be made).
	*/
	Assert(param_join_conds == NIL);
	
	/*
	 * Use rows/width estimates made by set_baserel_size_estimates() for
	 * base foreign relations and set_joinrel_size_estimates() for join
	 * between foreign relations.
	 */
	rows = foreignrel->rows;
	width = foreignrel->reltarget->width;
	
	/* Back into an estimate of the number of retrieved rows. */
	retrieved_rows = clamp_row_est(rows / fpinfo->local_conds_sel);
	
	/*
	 * We will come here again and again with different set of pathkeys
	 * that caller wants to cost. We don't need to calculate the cost of
	 * bare scan each time. Instead, use the costs if we have cached them
	 * already.
	 */
	if (fpinfo->rel_startup_cost > 0 && fpinfo->rel_total_cost > 0)
	{
		startup_cost = fpinfo->rel_startup_cost;
		run_cost = fpinfo->rel_total_cost - fpinfo->rel_startup_cost;
	}
	else if (foreignrel->reloptkind == RELOPT_UPPER_REL)
	{
		PgFdwRelationInfo *ofpinfo;
		PathTarget *ptarget = root->upper_targets[UPPERREL_GROUP_AGG];
		AggClauseCosts aggcosts;
		double		input_rows;
		int			numGroupCols;
		double		numGroups = 1;
		
		/*
		 * This cost model is mixture of costing done for sorted and
		 * hashed aggregates in cost_agg().  We are not sure which
		 * strategy will be considered at remote side, thus for
		 * simplicity, we put all startup related costs in startup_cost
		 * and all finalization and run cost are added in total_cost.
		 *
		 * Also, core does not care about costing HAVING expressions and
		 * adding that to the costs.  So similarly, here too we are not
		 * considering remote and local conditions for costing.
		 */
		
		ofpinfo = (PgFdwRelationInfo *) fpinfo->upperrel->fdw_private;
		
		/* Get rows and width from input rel */
		input_rows = ofpinfo->rows;
		width = ofpinfo->width;
		
		/* Collect statistics about aggregates for estimating costs. */
		MemSet(&aggcosts, 0, sizeof(AggClauseCosts));
		if (root->parse->hasAggs)
		{
#if PG_VERSION_NUM>=140000
			get_agg_clause_costs(root, AGGSPLIT_SIMPLE, &aggcosts);
#else
			get_agg_clause_costs(root, (Node *) fpinfo->grouped_tlist,
								 AGGSPLIT_SIMPLE, &aggcosts);
			get_agg_clause_costs(root, (Node *) root->parse->havingQual,
								 AGGSPLIT_SIMPLE, &aggcosts);
#endif
		}
		
		/* Get number of grouping columns and possible number of groups */
		numGroupCols = list_length(root->parse->groupClause);
		numGroups = estimate_num_groups(root,
										get_sortgrouplist_exprs(root->parse->groupClause,
																fpinfo->grouped_tlist),
										input_rows,
#if PG_VERSION_NUM>=140000
										NULL,
#endif
										NULL);
		
		/*
		 * Number of rows expected from foreign server will be same as
		 * that of number of groups.
		 */
		rows = retrieved_rows = numGroups;
		
		/*-----
		 * Startup cost includes:
		 *	  1. Startup cost for underneath input * relation
		 *	  2. Cost of performing aggregation, per cost_agg()
		 *	  3. Startup cost for PathTarget eval
			 *-----
			 */
		startup_cost = ofpinfo->rel_startup_cost;
		startup_cost += aggcosts.transCost.startup;
		startup_cost += aggcosts.transCost.per_tuple * input_rows;
		startup_cost += (cpu_operator_cost * numGroupCols) * input_rows;
		startup_cost += ptarget->cost.startup;

		/*-----
		 * Run time cost includes:
		 *	  1. Run time cost of underneath input relation
		 *	  2. Run time cost of performing aggregation, per cost_agg()
		 *	  3. PathTarget eval cost for each output row
		 *-----
		 */
		run_cost = ofpinfo->rel_total_cost - ofpinfo->rel_startup_cost;
#if PG_VERSION_NUM>=120000
		run_cost += aggcosts.finalCost.per_tuple * numGroups;
#else
		run_cost += aggcosts.finalCost * numGroups;
#endif
		run_cost += cpu_tuple_cost * numGroups;
		run_cost += ptarget->cost.per_tuple * numGroups;
	}
	else
	{
		/* Clamp retrieved rows estimates to at most foreignrel->tuples. */
		retrieved_rows = Min(retrieved_rows, foreignrel->tuples);

		/*
		 * Cost as though this were a seqscan, which is pessimistic.  We
		 * effectively imagine the local_conds are being evaluated
		 * remotely, too.
		 */
		startup_cost = 0;
		run_cost = 0;
		run_cost += seq_page_cost * foreignrel->pages;
		
		startup_cost += foreignrel->baserestrictcost.startup;
		cpu_per_tuple = cpu_tuple_cost + foreignrel->baserestrictcost.per_tuple;
		run_cost += cpu_per_tuple * foreignrel->tuples;
	}

	total_cost = startup_cost + run_cost;

	/*
	 * Cache the costs for scans without any pathkeys or parameterization
	 * before adding the costs for transferring data from the foreign server.
	 * These costs are useful for costing the join between this relation and
	 * another foreign relation or to calculate the costs of paths with
	 * pathkeys for this relation, when the costs can not be obtained from the
	 * foreign server. This function will be called at least once for every
	 * foreign relation without pathkeys and parameterization.
	 */
	if (pathkeys == NIL && param_join_conds == NIL)
	{
		fpinfo->rel_startup_cost = startup_cost;
		fpinfo->rel_total_cost = total_cost;
	}

	total_cost += cpu_tuple_cost * retrieved_rows;

	/* Return results. */
	*p_rows = rows;
	*p_width = width;
	*p_startup_cost = startup_cost;
	*p_total_cost = total_cost;
}


/*
 * Assess whether the aggregation, grouping and having operations can be pushed
 * down to the foreign server.  As a side effect, save information we obtain in
 * this function to PgFdwRelationInfo of the input relation.
 */
static bool
foreign_grouping_ok(PlannerInfo *root, RelOptInfo *grouped_rel)
{
	Query	   *query = root->parse;
	PathTarget *grouping_target;
	PgFdwRelationInfo *fpinfo = (PgFdwRelationInfo *) grouped_rel->fdw_private;
	PgFdwRelationInfo *ofpinfo;
	List	   *aggvars;
	ListCell   *lc;
	int			i;
	List	   *tlist = NIL;
	Bitmapset  *groupby_attrs = NULL;

	/* Grouping Sets are not pushable */
	if (query->groupingSets)
		return false;

	/* Get the fpinfo of the underlying scan relation. */
	ofpinfo = (PgFdwRelationInfo *) fpinfo->upperrel->fdw_private;

	/*
	 * If underneath input relation has any local conditions, those conditions
	 * are required to be applied before performing aggregation.  Hence the
	 * aggregate cannot be pushed down.
	 */
	if (ofpinfo->local_conds)
		return false;
	
	fpinfo->vops_attrs = ofpinfo->vops_attrs;
	fpinfo->tile_attrs = ofpinfo->tile_attrs;

	/*
	 * The targetlist expected from this node and the targetlist pushed down
	 * to the foreign server may be different. The latter requires
	 * sortgrouprefs to be set to push down GROUP BY clause, but should not
	 * have those arising from ORDER BY clause. These sortgrouprefs may be
	 * different from those in the plan's targetlist. Use a copy of path
	 * target to record the new sortgrouprefs.
	 */
	grouping_target = copy_pathtarget(root->upper_targets[UPPERREL_GROUP_AGG]);

	/*
	 * Evaluate grouping targets and check whether they are safe to push down
	 * to the foreign side.  All GROUP BY expressions will be part of the
	 * grouping target and thus there is no need to evaluate it separately.
	 * While doing so, add required expressions into target list which can
	 * then be used to pass to foreign server.
	 */
	i = 0;
	foreach(lc, grouping_target->exprs)
	{
		Expr	   *expr = (Expr *) lfirst(lc);
		Index		sgref = get_pathtarget_sortgroupref(grouping_target, i);
		ListCell   *l;

		/* Check whether this expression is part of GROUP BY clause */
		if (sgref && get_sortgroupref_clause_noerr(sgref, query->groupClause))
		{
			/*
			 * If any of the GROUP BY expression is not shippable we can not
			 * push down aggregation to the foreign server.
			 */
			if (!vops_is_foreign_expr(root, grouped_rel, expr))
				return false;

			pull_varattnos((Node *)expr, fpinfo->upperrel->relid, &groupby_attrs);
		
			/* Pushable, add to tlist */
			tlist = add_to_flat_tlist(tlist, list_make1(expr));
		}
		else
		{
			/* Check entire expression whether it is pushable or not */
			if (vops_is_foreign_expr(root, grouped_rel, expr))
			{
				/* Pushable, add to tlist */
				tlist = add_to_flat_tlist(tlist, list_make1(expr));
			}
			else
			{
				/*
				 * If we have sortgroupref set, then it means that we have an
				 * ORDER BY entry pointing to this expression.  Since we are
				 * not pushing ORDER BY with GROUP BY, clear it.
				 */
				if (sgref)
					grouping_target->sortgrouprefs[i] = 0;

				/* Not matched exactly, pull the var with aggregates then */
				aggvars = pull_var_clause((Node *) expr,
										  PVC_INCLUDE_AGGREGATES);

				if (!vops_is_foreign_expr(root, grouped_rel, (Expr *) aggvars))
					return false;

				/*
				 * Add aggregates, if any, into the targetlist.  Plain var
				 * nodes should be either same as some GROUP BY expression or
				 * part of some GROUP BY expression. In later case, the query
				 * cannot refer plain var nodes without the surrounding
				 * expression.  In both the cases, they are already part of
				 * the targetlist and thus no need to add them again.  In fact
				 * adding pulled plain var nodes in SELECT clause will cause
				 * an error on the foreign server if they are not same as some
				 * GROUP BY expression.
				 */
				foreach(l, aggvars)
				{
					Expr	   *current_expr = (Expr *) lfirst(l);

					if (IsA(current_expr, Aggref))
						tlist = add_to_flat_tlist(tlist,
												  list_make1(current_expr));
				}
			}
		}

		i++;
	}

	/* 
	 * VOPS can perform grouping only by scalar attributes 
	 */
	if (bms_overlap(groupby_attrs, ofpinfo->tile_attrs)) 
	{
		return false;
	}

	/*
	 * Classify the pushable and non-pushable having clauses and save them in
	 * remote_conds and local_conds of the grouped rel's fpinfo.
	 */
	if (root->hasHavingQual && query->havingQual)
	{
		foreach(lc, (List *) query->havingQual)
		{
			Expr	   *expr = (Expr *) lfirst(lc);

			if (!vops_is_foreign_expr(root, grouped_rel, expr))
				fpinfo->local_conds = lappend(fpinfo->local_conds, expr);
			else
				fpinfo->remote_conds = lappend(fpinfo->remote_conds, expr);
		}
	}

	/*
	 * If there are any local conditions, pull Vars and aggregates from it and
	 * check whether they are safe to pushdown or not.
	 */
	if (fpinfo->local_conds)
	{
		aggvars = pull_var_clause((Node *) fpinfo->local_conds,
								  PVC_INCLUDE_AGGREGATES);

		foreach(lc, aggvars)
		{
			Expr	   *expr = (Expr *) lfirst(lc);

			/*
			 * If aggregates within local conditions are not safe to push
			 * down, then we cannot push down the query.  Vars are already
			 * part of GROUP BY clause which are checked above, so no need to
			 * access them again here.
			 */
			if (IsA(expr, Aggref))
			{
				if (!vops_is_foreign_expr(root, grouped_rel, expr))
					return false;

				tlist = add_to_flat_tlist(tlist, aggvars);
			}
		}
	}

	/* Transfer any sortgroupref data to the replacement tlist */
	apply_pathtarget_labeling_to_tlist(tlist, grouping_target);

	/* Store generated targetlist */
	fpinfo->grouped_tlist = tlist;

	/* Safe to pushdown */
	fpinfo->pushdown_safe = true;

	/*
	 * Set cached relation costs to some negative value, so that we can detect
	 * when they are set to some sensible costs, during one (usually the
	 * first) of the calls to estimate_path_cost_size().
	 */
	fpinfo->rel_startup_cost = -1;
	fpinfo->rel_total_cost = -1;

	/*
	 * Set the string describing this grouped relation to be used in EXPLAIN
	 * output of corresponding ForeignScan.
	 */
	fpinfo->relation_name = makeStringInfo();
	appendStringInfo(fpinfo->relation_name, "Aggregate on (%s)",
					 ofpinfo->relation_name->data);

	return true;
}

/*
 * postgresGetForeignUpperPaths
 *		Add paths for post-join operations like aggregation, grouping etc. if
 *		corresponding operations are safe to push down.
 *
 * Right now, we only support aggregate, grouping and having clause pushdown.
 */
static void
postgresGetForeignUpperPaths(PlannerInfo *root, UpperRelationKind stage,
							 RelOptInfo *input_rel, RelOptInfo *output_rel
#if PG_VERSION_NUM>=110000
							 , void* extra
#endif
	)
{
	PgFdwRelationInfo *fpinfo;

	/*
	 * If input rel is not safe to pushdown, then simply return as we cannot
	 * perform any post-join operations on the foreign server.
	 */
	if (!input_rel->fdw_private ||
		!((PgFdwRelationInfo *) input_rel->fdw_private)->pushdown_safe)
		return;

	/* Ignore stages we don't support; and skip any duplicate calls. */
	if (stage != UPPERREL_GROUP_AGG || output_rel->fdw_private)
		return;

	fpinfo = (PgFdwRelationInfo *) palloc0(sizeof(PgFdwRelationInfo));
	fpinfo->pushdown_safe = false;
	output_rel->fdw_private = fpinfo;

	add_foreign_grouping_paths(root, input_rel, output_rel);
}

/*
 * add_foreign_grouping_paths
 *		Add foreign path for grouping and/or aggregation.
 *
 * Given input_rel represents the underlying scan.  The paths are added to the
 * given grouped_rel.
 */
static void
add_foreign_grouping_paths(PlannerInfo *root, RelOptInfo *input_rel,
						   RelOptInfo *grouped_rel)
{
	Query	   *parse = root->parse;
	PgFdwRelationInfo *ifpinfo = input_rel->fdw_private;
	PgFdwRelationInfo *fpinfo = grouped_rel->fdw_private;
	ForeignPath *grouppath;
	double		rows;
	int			width;
	Cost		startup_cost;
	Cost		total_cost;

	/* Nothing to be done, if there is no grouping or aggregation required. */
	if (!parse->groupClause && !parse->groupingSets && !parse->hasAggs &&
		!root->hasHavingQual)
		return;

	/* save the input_rel as outerrel in fpinfo */
	fpinfo->upperrel = input_rel;

	/*
	 * Copy foreign table, foreign server, user mapping, FDW options etc.
	 * details from the input relation's fpinfo.
	 */
	fpinfo->table = ifpinfo->table;
	fpinfo->server = ifpinfo->server;

	/* Assess if it is safe to push down aggregation and grouping. */
	if (!foreign_grouping_ok(root, grouped_rel))
		return;

	/*
	 * Compute the selectivity and cost of the local_conds, so we don't have
	 * to do it over again for each path.  (Currently we create just a single
	 * path here, but in future it would be possible that we build more paths
	 * such as pre-sorted paths as in postgresGetForeignPaths and
	 * postgresGetForeignJoinPaths.)  The best we can do for these conditions
	 * is to estimate selectivity on the basis of local statistics.
	 */
	fpinfo->local_conds_sel = clauselist_selectivity(root,
													 fpinfo->local_conds,
													 0,
													 JOIN_INNER,
													 NULL);

	cost_qual_eval(&fpinfo->local_conds_cost, fpinfo->local_conds, root);

	/* Estimate the cost of push down */
	estimate_path_cost_size(root, grouped_rel, NIL, NIL,
							&rows, &width, &startup_cost, &total_cost);

	/* Now update this information in the fpinfo */
	fpinfo->rows = rows;
	fpinfo->width = width;
	fpinfo->startup_cost = startup_cost;
	fpinfo->total_cost = total_cost;

	/* Create and add foreign path to the grouping relation. */
#if PG_VERSION_NUM>=120000
	grouppath = create_foreign_upper_path(root, 
										  grouped_rel,
										  grouped_rel->reltarget,
										  rows,
										  startup_cost,
										  total_cost,
										  NIL,	/* no pathkeys */
										  NULL,	/* no extra plan */
#if PG_VERSION_NUM>=170000
										  NIL,	/* no fdw_restrictinfo list */
#endif
										  NIL); /* no fdw_private list */
#else
	grouppath = create_foreignscan_path(root,
										grouped_rel,
										grouped_rel->reltarget,
										rows,
										startup_cost,
										total_cost,
										NIL,	/* no pathkeys */
										grouped_rel->lateral_relids,
										NULL,	/* no extra plan */
#if PG_VERSION_NUM>=170000
										NIL,	/* no fdw_restrictinfo list */
#endif
										NIL);	/* no fdw_private list */
#endif

	/* Add generated path into grouped_rel by add_path(). */
	add_path(grouped_rel, (Path *) grouppath);
}

/*
 * postgresAnalyzeForeignTable
 *		Test whether analyzing this foreign table is supported
 */
static bool
postgresAnalyzeForeignTable(Relation relation,
							AcquireSampleRowsFunc *func,
							BlockNumber *totalpages)
{
	ForeignTable *table;
	Relation vops_rel;
	double tuples;
	double allvisfrac;

	/* Return the row-analysis function pointer */
	*func = postgresAcquireSampleRowsFunc;

	table = GetForeignTable(RelationGetRelid(relation));
	vops_rel = open_vops_relation(table);
	estimate_rel_size(vops_rel, NULL, totalpages, &tuples, &allvisfrac);
    heap_close(vops_rel, RowExclusiveLock);

	return true;
}

/*
 * Acquire a random sample of rows from VOPS table
 */
static int
postgresAcquireSampleRowsFunc(Relation relation, int elevel,
							  HeapTuple *rows, int targrows,
							  double *totalrows,
							  double *totaldeadrows)
{
	TupleDesc tupdesc = RelationGetDescr(relation);
	StringInfoData sql;
	StringInfoData record;
	double samplerows;
	Portal portal;
	int i;
	bool first = true;
	char*colname;

    SPI_connect();
	
	initStringInfo(&sql);
	initStringInfo(&record);
	appendStringInfoString(&sql, "SELECT ");

	for (i = 0; i < tupdesc->natts; i++)
	{
		/* Ignore dropped columns. */
		if (TupleDescAttr(tupdesc, i)->attisdropped)
			continue;
		if (!first) {
			appendStringInfoString(&record, ", ");
			appendStringInfoString(&sql, ", ");
		}
		first = false;

		/* Use attribute name or column_name option. */
		colname = NameStr(TupleDescAttr(tupdesc, i)->attname);
		appendStringInfoString(&sql, "r.");                                         
 		appendStringInfoString(&sql, quote_identifier(colname));
		
		appendStringInfo(&record, "%s %s", quote_identifier(colname), vops_deparse_type_name(TupleDescAttr(tupdesc, i)->atttypid, TupleDescAttr(tupdesc, i)->atttypmod));
	}
	appendStringInfoString(&sql, " FROM ");
	vopsDeparseRelation(&sql, relation);
	appendStringInfo(&sql, " t,vops_unnest(t) r(%s)", record.data);
	
	portal = SPI_cursor_open_with_args(NULL, sql.data, 0, NULL, NULL, NULL, true, 0);

	/* First targrows rows are always included into the sample */
	SPI_cursor_fetch(portal, true, targrows);
	for (i = 0; i < SPI_processed; i++)
	{
		rows[i] = SPI_copytuple(SPI_tuptable->vals[i]);
	}
	samplerows = i;

	if (i == targrows) 
	{ 
		ReservoirStateData rstate; /* state for reservoir sampling */
		double rowstoskip = -1;    /* -1 means not set yet */

		reservoir_init_selection_state(&rstate, targrows);

		while (true) 
		{ 
			SPI_freetuptable(SPI_tuptable);
			SPI_cursor_fetch(portal, true, 1);
			if (!SPI_processed) { 
				break;
			}
			samplerows += 1;
			if (rowstoskip < 0) {
				rowstoskip = reservoir_get_next_S(&rstate, samplerows, targrows);
			}
			if (rowstoskip <= 0)
			{
				/* Choose a random reservoir element to replace. */
#if PG_VERSION_NUM >= 150000
				int pos = (int) (targrows * sampler_random_fract(&rstate.randstate));
#else
				int pos = (int) (targrows * sampler_random_fract(rstate.randstate));
#endif
				Assert(pos >= 0 && pos < targrows);
				SPI_freetuple(rows[pos]);
				rows[pos] = SPI_copytuple(SPI_tuptable->vals[0]);
			}
			rowstoskip -= 1;
		}
	}
	SPI_cursor_close(portal);
	SPI_finish();

	/* We assume that we have no dead tuple. */
	*totaldeadrows = 0.0;

	/* We've retrieved all living tuples from foreign server. */
	*totalrows = samplerows;

	return i;
}
