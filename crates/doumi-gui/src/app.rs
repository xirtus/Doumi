use gtk4::gdk;
use gtk4::gio;
use gtk4::glib;
use gtk4::prelude::*;
use libadwaita as adw;
use libadwaita::prelude::*;

pub fn run() -> glib::ExitCode {
    let app = adw::Application::builder()
        .application_id("io.github.doumi")
        .build();

    app.set_accels_for_action("app.quit", &["<Ctrl>q"]);
    app.set_accels_for_action("app.new-rule", &["<Ctrl>n"]);

    app.connect_activate(on_activate);
    app.run()
}

fn on_activate(app: &adw::Application) {
    // Prevent opening multiple windows
    if app.windows().len() > 1 {
        app.windows()[0].present();
        return;
    }

    load_css();
    setup_actions(app);

    let config = doumi_core::config::ConfigManager::new().expect("config init");
    let win = crate::window::build(app, config);
    win.present();
}

fn load_css() {
    let provider = gtk4::CssProvider::new();
    provider.load_from_string(include_str!("style.css"));
    if let Some(display) = gdk::Display::default() {
        gtk4::style_context_add_provider_for_display(
            &display,
            &provider,
            gtk4::STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }
}

fn setup_actions(app: &adw::Application) {
    let quit = gio::SimpleAction::new("quit", None);
    let app_q = app.clone();
    quit.connect_activate(move |_, _| app_q.quit());
    app.add_action(&quit);

    let new_rule = gio::SimpleAction::new("new-rule", None);
    let app_nr = app.clone();
    new_rule.connect_activate(move |_, _| {
        if let Some(win) = app_nr.active_window() {
            win.activate_action("win.new-rule", None).ok();
        }
    });
    app.add_action(&new_rule);

    let about = gio::SimpleAction::new("about", None);
    let app_ab = app.clone();
    about.connect_activate(move |_, _| {
        let dialog = adw::AboutDialog::builder()
            .application_name("Doumi")
            .application_icon("doumi")
            .version("0.1.0")
            .developer_name("Doumi Contributors")
            .website("https://github.com/doumi/doumi")
            .comments("Intelligent file organizer for Linux.\nThe open-format Hazel replacement.")
            .build();
        if let Some(win) = app_ab.active_window() {
            dialog.present(Some(&win));
        }
    });
    app.add_action(&about);

    let start_daemon = gio::SimpleAction::new("start-daemon", None);
    start_daemon.connect_activate(|_, _| {
        if let Ok(exe) = std::env::current_exe() {
            let doumid = exe
                .parent()
                .unwrap_or(std::path::Path::new("."))
                .join("doumid");
            let _ = std::process::Command::new(&doumid)
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .spawn();
        }
    });
    app.add_action(&start_daemon);

    let stop_daemon = gio::SimpleAction::new("stop-daemon", None);
    stop_daemon.connect_activate(|_, _| {
        let _ = std::process::Command::new("pkill")
            .arg("-f")
            .arg("doumid")
            .status();
    });
    app.add_action(&stop_daemon);
}
