# contrib/vops/Makefile

MODULE_big = vops
OBJS = vops.o

EXTENSION = vops
DATA = vops--1.0.sql
PGFILEDESC = "vops - vectorized operations"
CUSTOM_COPT = -O3

REGRESS = test

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
