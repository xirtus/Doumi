use rusqlite::{params, Connection};
use std::path::Path;

use doumi_core::models::ProcessingResult;

const CREATE_SQL: &str = "
CREATE TABLE IF NOT EXISTS events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    ts          TEXT NOT NULL,
    rule_id     TEXT NOT NULL,
    rule_name   TEXT NOT NULL,
    file_path   TEXT NOT NULL,
    matched     INTEGER NOT NULL,
    dry_run     INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS actions (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id    INTEGER NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    action_type TEXT NOT NULL,
    success     INTEGER NOT NULL,
    message     TEXT,
    source      TEXT,
    destination TEXT,
    error       TEXT
);
CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts);
CREATE INDEX IF NOT EXISTS idx_events_rule ON events(rule_id);
CREATE INDEX IF NOT EXISTS idx_events_file ON events(file_path);
";

pub struct ActionLogger {
    conn: Connection,
}

impl ActionLogger {
    pub fn open(db_path: &Path) -> anyhow::Result<Self> {
        let conn = Connection::open(db_path)?;
        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")?;
        conn.execute_batch(CREATE_SQL)?;
        Ok(Self { conn })
    }

    pub fn log_result(&self, result: &ProcessingResult) -> anyhow::Result<()> {
        let ts = result.timestamp.format("%Y-%m-%dT%H:%M:%S%.3f").to_string();
        self.conn.execute(
            "INSERT INTO events (ts, rule_id, rule_name, file_path, matched, dry_run) VALUES (?1,?2,?3,?4,?5,?6)",
            params![
                ts,
                result.rule_id,
                result.rule_name,
                result.file_path.to_string_lossy(),
                result.matched as i64,
                result.dry_run as i64,
            ],
        )?;
        let event_id = self.conn.last_insert_rowid();

        for ar in &result.action_results {
            self.conn.execute(
                "INSERT INTO actions (event_id, action_type, success, message, source, destination, error) VALUES (?1,?2,?3,?4,?5,?6,?7)",
                params![
                    event_id,
                    ar.action_type,
                    ar.success as i64,
                    if ar.message.is_empty() { None } else { Some(ar.message.as_str()) },
                    ar.source.as_ref().map(|p| p.to_string_lossy().to_string()),
                    ar.destination.as_ref().map(|p| p.to_string_lossy().to_string()),
                    if ar.error.is_empty() { None } else { Some(ar.error.as_str()) },
                ],
            )?;
        }
        Ok(())
    }

    pub fn get_recent(
        &self,
        limit: usize,
        rule_id: Option<&str>,
    ) -> anyhow::Result<Vec<serde_json::Value>> {
        let rows = if let Some(rid) = rule_id {
            self.conn
                .prepare("SELECT id,ts,rule_id,rule_name,file_path,matched,dry_run FROM events WHERE rule_id=?1 ORDER BY ts DESC LIMIT ?2")?
                .query_map(params![rid, limit as i64], row_to_event)?
                .collect::<Result<Vec<_>, _>>()?
        } else {
            self.conn
                .prepare("SELECT id,ts,rule_id,rule_name,file_path,matched,dry_run FROM events ORDER BY ts DESC LIMIT ?1")?
                .query_map(params![limit as i64], row_to_event)?
                .collect::<Result<Vec<_>, _>>()?
        };

        let mut results = Vec::with_capacity(rows.len());
        for (event_id, mut ev) in rows {
            let actions: Vec<serde_json::Value> = self.conn
                .prepare("SELECT action_type,success,message,source,destination,error FROM actions WHERE event_id=?1")?
                .query_map(params![event_id], |row| {
                    Ok(serde_json::json!({
                        "action_type": row.get::<_,String>(0)?,
                        "success": row.get::<_,i64>(1)? != 0,
                        "message": row.get::<_,Option<String>>(2)?,
                        "source": row.get::<_,Option<String>>(3)?,
                        "destination": row.get::<_,Option<String>>(4)?,
                        "error": row.get::<_,Option<String>>(5)?,
                    }))
                })?
                .collect::<Result<Vec<_>, _>>()?;
            ev["actions"] = serde_json::Value::Array(actions);
            results.push(ev);
        }
        Ok(results)
    }

    pub fn get_stats(&self) -> anyhow::Result<serde_json::Value> {
        let total: i64 = self
            .conn
            .query_row("SELECT COUNT(*) FROM events", [], |r| r.get(0))?;
        let matched: i64 =
            self.conn
                .query_row("SELECT COUNT(*) FROM events WHERE matched=1", [], |r| {
                    r.get(0)
                })?;
        let ok: i64 =
            self.conn
                .query_row("SELECT COUNT(*) FROM actions WHERE success=1", [], |r| {
                    r.get(0)
                })?;
        let fail: i64 =
            self.conn
                .query_row("SELECT COUNT(*) FROM actions WHERE success=0", [], |r| {
                    r.get(0)
                })?;
        Ok(serde_json::json!({
            "total_events": total,
            "matched_events": matched,
            "actions_ok": ok,
            "actions_failed": fail,
        }))
    }

    pub fn purge_old(&self, max_entries: usize) -> anyhow::Result<usize> {
        let count: i64 = self
            .conn
            .query_row("SELECT COUNT(*) FROM events", [], |r| r.get(0))?;
        if count as usize <= max_entries {
            return Ok(0);
        }
        let delete_count = count as usize - max_entries;
        self.conn.execute(
            "DELETE FROM events WHERE id IN (SELECT id FROM events ORDER BY ts ASC LIMIT ?1)",
            params![delete_count as i64],
        )?;
        Ok(delete_count)
    }
}

fn row_to_event(row: &rusqlite::Row) -> rusqlite::Result<(i64, serde_json::Value)> {
    let id: i64 = row.get(0)?;
    let ev = serde_json::json!({
        "id": id,
        "ts": row.get::<_,String>(1)?,
        "rule_id": row.get::<_,String>(2)?,
        "rule_name": row.get::<_,String>(3)?,
        "file_path": row.get::<_,String>(4)?,
        "matched": row.get::<_,i64>(5)? != 0,
        "dry_run": row.get::<_,i64>(6)? != 0,
        "actions": [],
    });
    Ok((id, ev))
}
