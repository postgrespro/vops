# contrib/vops/Makefile

MODULE_big = vops
OBJS = vops.o vops_fdw.o deparse.o
PGFILEDESC = "VOPS - vectorized operations for PostgreSQL"

PG_CPPFLAGS = -I$(libpq_srcdir)
SHLIB_LINK = $(libpq)

EXTENSION = vops
DATA = vops--1.0.sql
#CUSTOM_COPT = -O0

REGRESS = test

PG_CPPFLAGS = -I$(libpq_srcdir)
PG_LIBS = $(libpq_pgport)

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/vops
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif
