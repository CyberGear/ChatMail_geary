/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

int main(string[] args) {
    // Disable WebKit's bubblewrap sandbox when it cannot use user
    // namespaces (e.g. unprivileged containers, hardened kernels).
    // This must be set before any WebKit class is instantiated.
    Environment.set_variable(
        "WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS", "1", false
    );

    // Init logging right up front so as to capture as many log
    // messages as possible
    Geary.Logging.init();
    GLib.Log.set_writer_func(Geary.Logging.default_log_writer);

    Application.Client app = new Application.Client();

    int ec = app.run(args);

#if REF_TRACKING
    Geary.BaseObject.dump_refs(stdout);
#endif

    return ec;
}
