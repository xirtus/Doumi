mod app;
mod ipc;
mod window;

fn main() -> gtk4::glib::ExitCode {
    app::run()
}
