# Copyright (c) 2025, Postgres Professional

# Does not support the PGXS infrastructure at this time. Please, compile as part
# of the contrib source tree.

vops_sources = files(
  'deparse.c',
  'vops.c',
  'vops_fdw.c',
)

if host_system == 'windows'
  vops_sources += rc_lib_gen.process(win32ver_rc, extra_args: [
    '--NAME', '_int',
    '--FILEDESC', 'VOPS - vectorized operations for PostgreSQL',])
endif

vops = shared_module('vops',
  vops_sources,
  kwargs: contrib_mod_args + {
    'dependencies': contrib_mod_args['dependencies'] + [libpq],
  },
)
contrib_targets += vops

install_data(
  'vops.control',
  'vops--1.0--1.1.sql',
  'vops--1.1.sql',
  kwargs: contrib_data_args,
)

tests += {
  'name': 'vops',
  'sd': meson.current_source_dir(),
  'bd': meson.current_build_dir(),
  'regress': {
    'sql': [
      'test',
    ],
  },
}
