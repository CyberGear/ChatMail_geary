[CCode (cheader_filename = "libayatana-appindicator/app-indicator.h", lower_case_cprefix = "app_indicator_")]
namespace AppIndicator {
    [CCode (cname = "AppIndicatorCategory", cprefix = "APP_INDICATOR_CATEGORY_", has_type_id = false)]
    public enum IndicatorCategory {
        APPLICATION_STATUS,
        COMMUNICATIONS,
        SYSTEM_SERVICES,
        HARDWARE,
        OTHER
    }

    [CCode (cname = "AppIndicatorStatus", cprefix = "APP_INDICATOR_STATUS_", has_type_id = false)]
    public enum IndicatorStatus {
        PASSIVE,
        ACTIVE,
        ATTENTION
    }

    [CCode (cname = "AppIndicator", type_id = "app_indicator_get_type ()")]
    public class Indicator : GLib.Object {
        [CCode (cname = "app_indicator_new")]
        public Indicator (string id, string icon_name, IndicatorCategory category);
        [CCode (cname = "app_indicator_set_status")]
        public void set_status (IndicatorStatus status);
        [CCode (cname = "app_indicator_set_attention_icon_full")]
        public void set_attention_icon_full (string icon_name, string? icon_desc);
        [CCode (cname = "app_indicator_set_menu")]
        public void set_menu (Gtk.Menu menu);
        [CCode (cname = "app_indicator_set_title")]
        public void set_title (string title);
        [CCode (cname = "app_indicator_set_icon_full")]
        public void set_icon_full (string icon_name, string? icon_desc);
    }
}
