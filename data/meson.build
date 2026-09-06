install_data('org.flaemer.way-shell.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas',
)

# Компилирует схему в build/data/gschemas.compiled, чтобы бинарник из
# build-каталога запускался без установки (GSETTINGS_SCHEMA_DIR в shell.nix).
gnome.compile_schemas(
  depend_files: files('org.flaemer.way-shell.gschema.xml'),
  build_by_default: true,
)
