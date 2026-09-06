[CCode (cprefix = "", lower_case_cprefix = "", cheader_filename = "config.h")]
namespace Config {
    // Заполняются meson-ом в build/config.h. Нужны, чтобы gettext знал, как
    // называется домен и где искать скомпилированные переводы.
    public const string GETTEXT_PACKAGE;
    public const string LOCALEDIR;
}
