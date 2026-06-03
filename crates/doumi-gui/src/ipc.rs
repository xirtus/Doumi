use std::io::{BufRead, BufReader, Write as IoWrite};
use std::net::Shutdown;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;

use serde_json::Value;

pub fn ipc_call(socket: &PathBuf, cmd: Value) -> Value {
    let Ok(mut stream) = UnixStream::connect(socket) else {
        return serde_json::json!({"ok": false, "error": "Daemon not running"});
    };
    stream
        .set_read_timeout(Some(std::time::Duration::from_secs(5)))
        .ok();
    let payload = format!("{}\n", serde_json::to_string(&cmd).unwrap_or_default());
    if stream.write_all(payload.as_bytes()).is_err() {
        return serde_json::json!({"ok": false, "error": "Write failed"});
    }
    let _ = stream.shutdown(Shutdown::Write);
    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    reader.read_line(&mut line).ok();
    serde_json::from_str(&line).unwrap_or(serde_json::json!({"ok": false}))
}

/// Run IPC in a background thread; deliver result via glib idle on UI thread.
pub fn ipc_async<F: FnOnce(Value) + 'static>(socket: PathBuf, cmd: Value, callback: F) {
    let cb = std::sync::Arc::new(std::sync::Mutex::new(Some(callback)));
    let (tx, rx) = std::sync::mpsc::channel::<Value>();

    std::thread::spawn(move || {
        let _ = tx.send(ipc_call(&socket, cmd));
    });

    gtk4::glib::idle_add_local(move || {
        if let Ok(v) = rx.try_recv() {
            let mut guard = cb.lock().unwrap();
            if let Some(f) = guard.take() {
                drop(guard);
                f(v);
            }
            return gtk4::glib::ControlFlow::Break;
        }
        gtk4::glib::ControlFlow::Continue
    });
}
