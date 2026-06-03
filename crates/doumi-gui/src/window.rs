use std::cell::RefCell;
use std::rc::Rc;

use gtk4::gio;
use gtk4::glib;
use gtk4::prelude::*;
use libadwaita as adw;
use libadwaita::prelude::*;
use serde_json::Value;

use doumi_core::config::ConfigManager;
use doumi_core::rule::RuleConfig;

use crate::ipc::ipc_async;

// ─── Shared window state ─────────────────────────────────────────────────────

struct State {
    config: ConfigManager,
    rules: Vec<RuleConfig>,
    selected_idx: Option<usize>,
}

type S = Rc<RefCell<State>>;

// ─── Main window builder ─────────────────────────────────────────────────────

pub fn build(app: &adw::Application, config: ConfigManager) -> adw::ApplicationWindow {
    let state: S = Rc::new(RefCell::new(State {
        config,
        rules: vec![],
        selected_idx: None,
    }));

    // Window
    let window = adw::ApplicationWindow::builder()
        .application(app)
        .title("Doumi")
        .default_width(1020)
        .default_height(680)
        .build();

    // Toast overlay wraps everything
    let toast_overlay = adw::ToastOverlay::new();
    window.set_content(Some(&toast_overlay));

    // Navigation split
    let split = adw::NavigationSplitView::new();
    split.set_min_sidebar_width(240.0);
    split.set_max_sidebar_width(320.0);
    toast_overlay.set_child(Some(&split));

    // ── Content panel (built first so sidebar closures can reference it) ─────

    let content_title = adw::WindowTitle::builder()
        .title("Doumi")
        .subtitle("File Organizer")
        .build();

    let run_btn = gtk4::Button::builder()
        .label("Run Now")
        .icon_name("media-playback-start-symbolic")
        .css_classes(["suggested-action"])
        .tooltip_text("Run rule against watched folders")
        .visible(false)
        .build();

    let preview_btn = gtk4::Button::builder()
        .label("Preview")
        .icon_name("document-properties-symbolic")
        .tooltip_text("Preview matched and skipped files")
        .visible(false)
        .build();

    let edit_btn = gtk4::Button::builder()
        .icon_name("document-edit-symbolic")
        .tooltip_text("Configure rule")
        .visible(false)
        .build();

    let delete_btn = gtk4::Button::builder()
        .icon_name("user-trash-symbolic")
        .tooltip_text("Delete rule")
        .css_classes(["destructive-action"])
        .visible(false)
        .build();

    let reload_btn = gtk4::Button::builder()
        .icon_name("view-refresh-symbolic")
        .tooltip_text("Reload rules")
        .build();

    let content_hbar = adw::HeaderBar::new();
    content_hbar.set_title_widget(Some(&content_title));
    content_hbar.pack_start(&run_btn);
    content_hbar.pack_start(&preview_btn);
    content_hbar.pack_start(&edit_btn);
    content_hbar.pack_end(&reload_btn);
    content_hbar.pack_end(&delete_btn);

    // Stack: dashboard | detail
    let stack = gtk4::Stack::builder()
        .transition_type(gtk4::StackTransitionType::Crossfade)
        .transition_duration(200)
        .build();

    let dashboard_box = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
    let status_page = adw::StatusPage::builder()
        .title("Welcome to Doumi")
        .description("Select a rule from the sidebar, or create a new one.\n\nStart the daemon to enable automatic file organization.")
        .icon_name("folder-symbolic")
        .vexpand(true)
        .build();
    dashboard_box.append(&status_page);
    stack.add_named(&dashboard_box, Some("dashboard"));

    let detail_scroll = gtk4::ScrolledWindow::builder()
        .hscrollbar_policy(gtk4::PolicyType::Never)
        .vexpand(true)
        .build();
    let detail_clamp = adw::Clamp::builder()
        .maximum_size(720)
        .margin_top(16)
        .margin_bottom(24)
        .margin_start(16)
        .margin_end(16)
        .build();
    let detail_inner = gtk4::Box::new(gtk4::Orientation::Vertical, 16);
    detail_clamp.set_child(Some(&detail_inner));
    detail_scroll.set_child(Some(&detail_clamp));
    stack.add_named(&detail_scroll, Some("detail"));

    let content_toolbar = adw::ToolbarView::new();
    content_toolbar.add_top_bar(&content_hbar);
    content_toolbar.set_content(Some(&stack));

    let content_page = adw::NavigationPage::new(&content_toolbar, "Rule Detail");
    split.set_content(Some(&content_page));

    // ── Sidebar ───────────────────────────────────────────────────────────────

    let status_dot = gtk4::Label::builder()
        .label("●")
        .css_classes(["status-dot", "status-offline"])
        .tooltip_text("Daemon offline")
        .build();

    let add_btn = gtk4::Button::builder()
        .icon_name("list-add-symbolic")
        .tooltip_text("New rule (Ctrl+N)")
        .build();

    let menu_model = gio::Menu::new();
    menu_model.append(Some("New Rule"), Some("app.new-rule"));
    menu_model.append(Some("Start Daemon"), Some("app.start-daemon"));
    menu_model.append(Some("Stop Daemon"), Some("app.stop-daemon"));
    menu_model.append(Some("About"), Some("app.about"));
    let menu_btn = gtk4::MenuButton::builder()
        .icon_name("open-menu-symbolic")
        .menu_model(&menu_model)
        .primary(true)
        .build();

    let sidebar_hbar = adw::HeaderBar::builder().show_title(false).build();
    sidebar_hbar.pack_start(&menu_btn);
    sidebar_hbar.pack_end(&status_dot);
    sidebar_hbar.pack_end(&add_btn);

    let search_entry = gtk4::SearchEntry::builder()
        .placeholder_text("Search rules…")
        .css_classes(["sidebar-search"])
        .margin_start(8)
        .margin_end(8)
        .margin_top(6)
        .margin_bottom(2)
        .build();

    let list_box = gtk4::ListBox::builder()
        .css_classes(["boxed-list"])
        .margin_start(8)
        .margin_end(8)
        .margin_top(4)
        .margin_bottom(8)
        .selection_mode(gtk4::SelectionMode::Single)
        .build();

    let placeholder = adw::StatusPage::builder()
        .title("No Rules")
        .description("Create a rule with the + button")
        .icon_name("folder-symbolic")
        .vexpand(true)
        .build();
    list_box.set_placeholder(Some(&placeholder));

    let list_scroll = gtk4::ScrolledWindow::builder()
        .hscrollbar_policy(gtk4::PolicyType::Never)
        .vexpand(true)
        .child(&list_box)
        .build();

    let sidebar_toolbar = adw::ToolbarView::new();
    sidebar_toolbar.add_top_bar(&sidebar_hbar);
    sidebar_toolbar.add_top_bar(&search_entry);
    sidebar_toolbar.set_content(Some(&list_scroll));

    let sidebar_page = adw::NavigationPage::new(&sidebar_toolbar, "Doumi");
    split.set_sidebar(Some(&sidebar_page));

    // ── Signal connections ────────────────────────────────────────────────────

    // Search filter
    {
        let list_box2 = list_box.clone();
        let state2 = state.clone();
        search_entry.connect_search_changed(move |entry| {
            let query = entry.text().to_lowercase();
            let s = state2.borrow();
            let mut i = 0usize;
            let mut row = list_box2.row_at_index(0);
            while let Some(r) = row {
                let name = s
                    .rules
                    .get(i)
                    .map(|r| r.name.to_lowercase())
                    .unwrap_or_default();
                let desc = s
                    .rules
                    .get(i)
                    .map(|r| r.description.to_lowercase())
                    .unwrap_or_default();
                r.set_visible(query.is_empty() || name.contains(&query) || desc.contains(&query));
                i += 1;
                row = list_box2.row_at_index(i as i32);
            }
        });
    }

    // Row activated → show detail
    {
        let state2 = state.clone();
        let detail_inner2 = detail_inner.clone();
        let stack2 = stack.clone();
        let content_title2 = content_title.clone();
        let run_btn2 = run_btn.clone();
        let preview_btn2 = preview_btn.clone();
        let edit_btn2 = edit_btn.clone();
        let delete_btn2 = delete_btn.clone();

        list_box.connect_row_activated(move |_, row| {
            let idx = row.index() as usize;
            {
                let mut s = state2.borrow_mut();
                s.selected_idx = Some(idx);
            }
            let s = state2.borrow();
            if let Some(rule) = s.rules.get(idx) {
                load_detail(&detail_inner2, rule);
                stack2.set_visible_child_name("detail");
                content_title2.set_title(&rule.name);
                content_title2.set_subtitle(&format!("Priority {}", rule.priority));
                run_btn2.set_visible(true);
                preview_btn2.set_visible(true);
                edit_btn2.set_visible(true);
                delete_btn2.set_visible(true);
            }
        });
    }

    // New rule button
    {
        let state2 = state.clone();
        let list_box2 = list_box.clone();
        let win2 = window.clone();
        let toast2 = toast_overlay.clone();
        let detail_inner2 = detail_inner.clone();
        let stack2 = stack.clone();
        let content_title2 = content_title.clone();
        let run_btn2 = run_btn.clone();
        let preview_btn2 = preview_btn.clone();
        let edit_btn2 = edit_btn.clone();
        let delete_btn2 = delete_btn.clone();

        add_btn.connect_clicked(move |_| {
            show_new_rule_dialog(
                &win2,
                state2.clone(),
                &list_box2,
                &toast2,
                &detail_inner2,
                &stack2,
                &content_title2,
                &run_btn2,
                &preview_btn2,
                &edit_btn2,
                &delete_btn2,
            );
        });
    }

    // Reload button
    {
        let state2 = state.clone();
        let list_box2 = list_box.clone();
        let stack2 = stack.clone();
        let content_title2 = content_title.clone();
        let run_btn2 = run_btn.clone();
        let preview_btn2 = preview_btn.clone();
        let edit_btn2 = edit_btn.clone();
        let delete_btn2 = delete_btn.clone();

        reload_btn.connect_clicked(move |_| {
            load_rules(
                state2.clone(),
                &list_box2,
                &stack2,
                &content_title2,
                &run_btn2,
                &preview_btn2,
                &edit_btn2,
                &delete_btn2,
            );
        });
    }

    // Run rule button
    {
        let state2 = state.clone();
        let toast2 = toast_overlay.clone();

        run_btn.connect_clicked(move |_| {
            let s = state2.borrow();
            let Some(idx) = s.selected_idx else { return };
            let Some(rule) = s.rules.get(idx) else { return };
            let rule_id = rule.id.clone();
            let socket = s.config.ipc_socket_path();
            drop(s);

            toast(&toast2, "Running rule…");
            let toast3 = toast2.clone();
            ipc_async(
                socket,
                serde_json::json!({"cmd": "run_rule", "rule_id": rule_id}),
                move |resp| {
                    if resp["ok"].as_bool().unwrap_or(false) {
                        let n = resp["data"]["files_processed"].as_u64().unwrap_or(0);
                        toast(&toast3, &format!("Processed {n} files"));
                    } else {
                        toast(
                            &toast3,
                            &format!("Error: {}", resp["error"].as_str().unwrap_or("unknown")),
                        );
                    }
                },
            );
        });
    }

    // Preview rule button
    {
        let state2 = state.clone();
        let toast2 = toast_overlay.clone();
        let win2 = window.clone();

        preview_btn.connect_clicked(move |_| {
            let s = state2.borrow();
            let Some(idx) = s.selected_idx else { return };
            let Some(rule) = s.rules.get(idx) else { return };
            let rule_id = rule.id.clone();
            let socket = s.config.ipc_socket_path();
            drop(s);

            toast(&toast2, "Previewing rule...");
            let toast3 = toast2.clone();
            let win3 = win2.clone();
            ipc_async(
                socket,
                serde_json::json!({"cmd": "preview_rule", "rule_id": rule_id, "limit": 200}),
                move |resp| {
                    if resp["ok"].as_bool().unwrap_or(false) {
                        show_preview_dialog(&win3, &resp["data"]);
                    } else {
                        toast(
                            &toast3,
                            &format!("Error: {}", resp["error"].as_str().unwrap_or("unknown")),
                        );
                    }
                },
            );
        });
    }

    // Edit rule button
    {
        let state2 = state.clone();
        let list_box2 = list_box.clone();
        let toast2 = toast_overlay.clone();
        let detail_inner2 = detail_inner.clone();
        let stack2 = stack.clone();
        let content_title2 = content_title.clone();
        let run_btn2 = run_btn.clone();
        let preview_btn2 = preview_btn.clone();
        let edit_btn2 = edit_btn.clone();
        let delete_btn2 = delete_btn.clone();
        let win2 = window.clone();

        edit_btn.connect_clicked(move |_| {
            let s = state2.borrow();
            let Some(idx) = s.selected_idx else { return };
            let Some(rule) = s.rules.get(idx) else { return };
            let rule = rule.clone();
            drop(s);
            show_edit_rule_dialog(
                &win2,
                state2.clone(),
                &list_box2,
                &toast2,
                &detail_inner2,
                &stack2,
                &content_title2,
                &run_btn2,
                &preview_btn2,
                &edit_btn2,
                &delete_btn2,
                rule,
            );
        });
    }

    // Delete rule button
    {
        let state2 = state.clone();
        let list_box2 = list_box.clone();
        let toast2 = toast_overlay.clone();
        let stack2 = stack.clone();
        let content_title2 = content_title.clone();
        let run_btn2 = run_btn.clone();
        let preview_btn2 = preview_btn.clone();
        let edit_btn2 = edit_btn.clone();
        let delete_btn2 = delete_btn.clone();
        let win2 = window.clone();

        delete_btn.connect_clicked(move |_| {
            let s = state2.borrow();
            let Some(idx) = s.selected_idx else { return };
            let Some(rule) = s.rules.get(idx) else { return };
            let rule_id = rule.id.clone();
            let rule_name = rule.name.clone();
            drop(s);

            let dialog = adw::AlertDialog::builder()
                .heading(format!("Delete \"{rule_name}\"?"))
                .body("This permanently deletes the rule file and cannot be undone.")
                .build();
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("delete", "Delete");
            dialog.set_response_appearance("delete", adw::ResponseAppearance::Destructive);
            dialog.set_default_response(Some("cancel"));

            let state3 = state2.clone();
            let list_box3 = list_box2.clone();
            let toast3 = toast2.clone();
            let stack3 = stack2.clone();
            let content_title3 = content_title2.clone();
            let run_btn3 = run_btn2.clone();
            let preview_btn3 = preview_btn2.clone();
            let edit_btn3 = edit_btn2.clone();
            let delete_btn3 = delete_btn2.clone();

            dialog.connect_response(None, move |_, response| {
                if response != "delete" {
                    return;
                }
                state3.borrow_mut().config.delete_rule(&rule_id);
                state3.borrow_mut().selected_idx = None;
                stack3.set_visible_child_name("dashboard");
                content_title3.set_title("Doumi");
                content_title3.set_subtitle("File Organizer");
                run_btn3.set_visible(false);
                preview_btn3.set_visible(false);
                edit_btn3.set_visible(false);
                delete_btn3.set_visible(false);
                load_rules(
                    state3.clone(),
                    &list_box3,
                    &stack3,
                    &content_title3,
                    &run_btn3,
                    &preview_btn3,
                    &edit_btn3,
                    &delete_btn3,
                );
                toast(&toast3, &format!("Deleted \"{rule_name}\""));
            });

            dialog.present(Some(&win2));
        });
    }

    // win-level new-rule action (so Ctrl+N works)
    {
        let state2 = state.clone();
        let list_box2 = list_box.clone();
        let toast2 = toast_overlay.clone();
        let win2 = window.clone();
        let detail_inner2 = detail_inner.clone();
        let stack2 = stack.clone();
        let content_title2 = content_title.clone();
        let run_btn2 = run_btn.clone();
        let preview_btn2 = preview_btn.clone();
        let edit_btn2 = edit_btn.clone();
        let delete_btn2 = delete_btn.clone();

        let new_rule_action = gio::SimpleAction::new("new-rule", None);
        new_rule_action.connect_activate(move |_, _| {
            show_new_rule_dialog(
                &win2,
                state2.clone(),
                &list_box2,
                &toast2,
                &detail_inner2,
                &stack2,
                &content_title2,
                &run_btn2,
                &preview_btn2,
                &edit_btn2,
                &delete_btn2,
            );
        });
        window.add_action(&new_rule_action);
    }

    // ── Initial load + daemon poll ────────────────────────────────────────────

    load_rules(
        state.clone(),
        &list_box,
        &stack,
        &content_title,
        &run_btn,
        &preview_btn,
        &edit_btn,
        &delete_btn,
    );

    start_daemon_poll(state.clone(), &status_dot, &stack, &dashboard_box);

    window
}

// ─── Load rules into sidebar list ─────────────────────────────────────────────

fn load_rules(
    state: S,
    list_box: &gtk4::ListBox,
    stack: &gtk4::Stack,
    content_title: &adw::WindowTitle,
    run_btn: &gtk4::Button,
    preview_btn: &gtk4::Button,
    edit_btn: &gtk4::Button,
    delete_btn: &gtk4::Button,
) {
    // Load from disk
    let rules = state.borrow().config.load_all_rules();
    {
        let mut s = state.borrow_mut();
        s.rules = rules;
        s.selected_idx = None;
    }

    // Clear list
    while let Some(row) = list_box.first_child() {
        list_box.remove(&row);
    }

    // Reset content panel
    stack.set_visible_child_name("dashboard");
    content_title.set_title("Doumi");
    content_title.set_subtitle("File Organizer");
    run_btn.set_visible(false);
    preview_btn.set_visible(false);
    edit_btn.set_visible(false);
    delete_btn.set_visible(false);

    // Rebuild rows
    let count = state.borrow().rules.len();
    for i in 0..count {
        let row = build_rule_row(state.clone(), i);
        list_box.append(&row);
    }
}

fn build_rule_row(state: S, idx: usize) -> adw::ActionRow {
    let s = state.borrow();
    let rule = &s.rules[idx];

    let row = adw::ActionRow::builder()
        .title(&rule.name)
        .subtitle(if !rule.description.is_empty() {
            rule.description.clone()
        } else {
            rule.folders
                .iter()
                .take(2)
                .map(|f| {
                    f.path.replace(
                        &dirs::home_dir()
                            .map(|h| h.to_string_lossy().to_string())
                            .unwrap_or_default(),
                        "~",
                    )
                })
                .collect::<Vec<_>>()
                .join(", ")
        })
        .activatable(true)
        .css_classes([
            "rule-row",
            if rule.enabled { "enabled" } else { "disabled" },
        ])
        .build();

    // Priority badge
    let prio = gtk4::Label::builder()
        .label(&rule.priority.to_string())
        .valign(gtk4::Align::Center)
        .css_classes(["caption", "dim-label", "priority-badge"])
        .width_chars(2)
        .build();
    row.add_prefix(&prio);

    // Enable switch
    let enabled = rule.enabled;
    drop(s);

    let switch = gtk4::Switch::builder()
        .valign(gtk4::Align::Center)
        .active(enabled)
        .build();

    let row_ref = row.clone();
    switch.connect_state_set(move |_, active| {
        if active {
            row_ref.add_css_class("enabled");
            row_ref.remove_css_class("disabled");
        } else {
            row_ref.add_css_class("disabled");
            row_ref.remove_css_class("enabled");
        }
        let mut s = state.borrow_mut();
        if let Some(rule) = s.rules.get_mut(idx) {
            rule.enabled = active;
            let rule_clone = rule.clone();
            let rules_dir = s.config.rules_dir.clone();
            std::thread::spawn(move || {
                if let Some(path) = &rule_clone.source_file {
                    let _ = doumi_core::loader::save_rule_file(&rule_clone, path);
                } else {
                    let safe: String = rule_clone
                        .id
                        .chars()
                        .map(|c| {
                            if c.is_alphanumeric() || c == '-' || c == '_' {
                                c
                            } else {
                                '_'
                            }
                        })
                        .collect();
                    let path = rules_dir.join(format!("{safe}.json"));
                    let _ = doumi_core::loader::save_rule_file(&rule_clone, &path);
                }
            });
        }
        glib::Propagation::Proceed
    });

    row.add_suffix(&switch);
    row
}

// ─── Rule detail panel ────────────────────────────────────────────────────────

fn load_detail(container: &gtk4::Box, rule: &RuleConfig) {
    while let Some(child) = container.first_child() {
        container.remove(&child);
    }

    // ── Header card ──────────────────────────────────────────────────────────
    let header = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Vertical)
        .spacing(4)
        .css_classes(["card"])
        .margin_start(0)
        .margin_end(0)
        .margin_top(0)
        .margin_bottom(4)
        .build();
    set_pad(&header, 18);

    let title_row = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Horizontal)
        .spacing(12)
        .build();

    let title_lbl = gtk4::Label::builder()
        .label(&rule.name)
        .xalign(0.0)
        .css_classes(["rule-detail-title"])
        .hexpand(true)
        .wrap(true)
        .build();
    title_row.append(&title_lbl);

    let badge_txt = if rule.enabled {
        "● Enabled"
    } else {
        "○ Disabled"
    };
    let badge_cls: &[&str] = if rule.enabled {
        &["pill", "success"]
    } else {
        &["pill", "dim-label"]
    };
    let badge = gtk4::Label::builder()
        .label(badge_txt)
        .valign(gtk4::Align::Center)
        .build();
    for c in badge_cls {
        badge.add_css_class(c);
    }
    title_row.append(&badge);
    header.append(&title_row);

    if !rule.description.is_empty() {
        let desc = gtk4::Label::builder()
            .label(&rule.description)
            .xalign(0.0)
            .wrap(true)
            .css_classes(["body", "dim-label"])
            .build();
        header.append(&desc);
    }

    // Trigger chips
    let trig_box = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Horizontal)
        .spacing(6)
        .margin_top(8)
        .build();
    if rule.triggers.on_add {
        trig_box.append(&chip("on-add", &["trigger-badge"]));
    }
    if rule.triggers.on_modify {
        trig_box.append(&chip("on-modify", &["trigger-badge"]));
    }
    if let Some(sched) = &rule.triggers.schedule {
        trig_box.append(&chip(&format!("⏱ {sched}"), &["trigger-badge", "schedule"]));
    }
    header.append(&trig_box);
    container.append(&header);

    // ── Folders ──────────────────────────────────────────────────────────────
    let folders_group = adw::PreferencesGroup::builder()
        .title("Watched Folders")
        .build();
    for f in &rule.folders {
        let home = dirs::home_dir()
            .map(|h| h.to_string_lossy().to_string())
            .unwrap_or_default();
        let display = f.path.replace(&home, "~");
        let frow = adw::ActionRow::builder()
            .title(&display)
            .css_classes(["monospace"])
            .build();
        let mut sub = vec![];
        if f.recursive {
            sub.push("recursive".to_string());
        }
        sub.push(format!("depth {}", f.depth));
        frow.set_subtitle(&sub.join("  ·  "));
        frow.add_prefix(&gtk4::Image::from_icon_name("folder-symbolic"));
        folders_group.add(&frow);
    }
    container.append(&folders_group);

    // ── Conditions ───────────────────────────────────────────────────────────
    let cond_group = adw::PreferencesGroup::builder().title("Conditions").build();
    let conditions_json = serde_json::to_value(&rule.conditions).unwrap_or_default();
    let match_label = conditions_json
        .get("match")
        .and_then(|v| v.as_str())
        .unwrap_or("all")
        .to_uppercase();
    let cond_expander = adw::ExpanderRow::builder()
        .title(&format!("Match {match_label} of these conditions"))
        .build();
    let items = conditions_json
        .get("items")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    if !items.is_empty() {
        for item in &items {
            cond_expander.add_row(&make_condition_row(item));
        }
        cond_expander.set_expanded(true);
    } else {
        cond_expander.set_subtitle("No conditions — matches all files");
    }
    cond_group.add(&cond_expander);
    container.append(&cond_group);

    // ── Actions ──────────────────────────────────────────────────────────────
    let act_group = adw::PreferencesGroup::builder().title("Actions").build();
    let actions_json = serde_json::to_value(&rule.actions).unwrap_or_default();
    if let Some(actions) = actions_json.as_array() {
        for (i, action) in actions.iter().enumerate() {
            let atype = action["type"].as_str().unwrap_or("?");
            let title = format!(
                "{}. {}",
                i + 1,
                atype
                    .replace('_', " ")
                    .split_whitespace()
                    .map(|w| {
                        let mut c = w.chars();
                        c.next()
                            .map(|f| f.to_uppercase().to_string() + c.as_str())
                            .unwrap_or_default()
                    })
                    .collect::<Vec<_>>()
                    .join(" ")
            );

            let arow = adw::ActionRow::builder().title(&title).build();
            let mut details = vec![];
            if let Some(d) = action["destination"].as_str() {
                if !d.is_empty() {
                    details.push(d.to_string());
                }
            }
            if let Some(p) = action["pattern"].as_str() {
                if !p.is_empty() {
                    details.push(format!("pattern: {p}"));
                }
            }
            arow.set_subtitle(&details.join("  ·  "));

            arow.add_prefix(&gtk4::Image::from_icon_name(action_icon(atype)));
            let is_destructive = matches!(atype, "delete" | "trash");
            let chip_widget = gtk4::Label::builder()
                .label(atype)
                .css_classes(["action-chip"])
                .build();
            if is_destructive {
                chip_widget.add_css_class("destructive");
            }
            arow.add_suffix(&chip_widget);
            act_group.add(&arow);
        }
    }
    container.append(&act_group);

    // ── JSON source ──────────────────────────────────────────────────────────
    let json_group = adw::PreferencesGroup::builder()
        .title("Rule Source (JSON)")
        .build();
    let json_expander = adw::ExpanderRow::builder()
        .title("View / copy raw JSON")
        .build();
    let json_str = serde_json::to_string_pretty(&serde_json::to_value(rule).unwrap_or_default())
        .unwrap_or_default();
    let json_label = gtk4::Label::builder()
        .label(&json_str)
        .css_classes(["monospace", "caption"])
        .xalign(0.0)
        .selectable(true)
        .wrap(true)
        .build();
    let json_wrap = gtk4::Box::new(gtk4::Orientation::Vertical, 0);
    set_pad(&json_wrap, 8);
    json_wrap.append(&json_label);
    json_expander.add_row(&json_wrap);
    json_group.add(&json_expander);
    container.append(&json_group);
}

fn make_condition_row(item: &Value) -> adw::ActionRow {
    let ctype = item["type"].as_str().unwrap_or("?");
    let op = item["operator"].as_str().unwrap_or("");
    let val = item.get("value").map(|v| v.to_string()).unwrap_or_default();
    let unit = item["unit"].as_str().unwrap_or("");
    let subtitle = format!(
        "{op} {val}{}",
        if unit.is_empty() {
            String::new()
        } else {
            format!(" {unit}")
        }
    );
    let row = adw::ActionRow::builder()
        .title(
            &ctype
                .replace('_', " ")
                .split_whitespace()
                .map(|w| {
                    let mut c = w.chars();
                    c.next()
                        .map(|f| f.to_uppercase().to_string() + c.as_str())
                        .unwrap_or_default()
                })
                .collect::<Vec<_>>()
                .join(" "),
        )
        .subtitle(subtitle.trim())
        .build();
    row.add_prefix(&gtk4::Image::from_icon_name(condition_icon(ctype)));
    row
}

// ─── Preview dialog ──────────────────────────────────────────────────────────

fn show_preview_dialog(window: &adw::ApplicationWindow, data: &Value) {
    let body = preview_dialog_body(data);
    let dialog = adw::AlertDialog::builder()
        .heading("Rule Preview")
        .body(&body)
        .build();
    dialog.add_response("close", "Close");
    dialog.set_default_response(Some("close"));
    dialog.present(Some(window));
}

fn preview_dialog_body(data: &Value) -> String {
    let files_scanned = data["files_scanned"].as_u64().unwrap_or(0);
    let matched = data["matched"].as_array().cloned().unwrap_or_default();
    let skipped = data["skipped"].as_array().cloned().unwrap_or_default();
    let truncated = data["truncated"].as_bool().unwrap_or(false);

    let mut lines = vec![format!(
        "Scanned {files_scanned} files. {} matched, {} skipped.",
        matched.len(),
        skipped.len()
    )];

    if truncated {
        lines.push("Results were truncated by the preview limit.".to_string());
    }

    if !matched.is_empty() {
        lines.push(String::new());
        lines.push("Matched".to_string());
        for item in matched.iter().take(8) {
            lines.push(format!(
                "- {}",
                item["path"].as_str().unwrap_or("unknown path")
            ));
            if let Some(actions) = item["actions"].as_array() {
                for action in actions.iter().take(3) {
                    let atype = action["type"].as_str().unwrap_or("action");
                    let msg = action["message"]
                        .as_str()
                        .or_else(|| action["error"].as_str())
                        .unwrap_or("");
                    lines.push(format!("  [dry] {atype}: {msg}"));
                }
            }
        }
        if matched.len() > 8 {
            lines.push(format!("... {} more matched files", matched.len() - 8));
        }
    }

    if !skipped.is_empty() {
        lines.push(String::new());
        lines.push("Skipped by safety".to_string());
        for item in skipped.iter().take(8) {
            lines.push(format!(
                "- {}",
                item["path"].as_str().unwrap_or("unknown path")
            ));
            lines.push(format!(
                "  {}",
                item["reason"].as_str().unwrap_or("unknown reason")
            ));
        }
        if skipped.len() > 8 {
            lines.push(format!("... {} more skipped files", skipped.len() - 8));
        }
    }

    lines.join("\n")
}

// ─── New rule dialog ──────────────────────────────────────────────────────────

#[allow(clippy::too_many_arguments)]
fn show_new_rule_dialog(
    window: &adw::ApplicationWindow,
    state: S,
    list_box: &gtk4::ListBox,
    toast_overlay: &adw::ToastOverlay,
    detail_inner: &gtk4::Box,
    stack: &gtk4::Stack,
    content_title: &adw::WindowTitle,
    run_btn: &gtk4::Button,
    preview_btn: &gtk4::Button,
    edit_btn: &gtk4::Button,
    delete_btn: &gtk4::Button,
) {
    let dialog = adw::AlertDialog::builder()
        .heading("Create Rule")
        .body("Build a rule from common file qualities and actions.")
        .build();

    let builder = RuleBuilderWidgets::new();
    dialog.set_extra_child(Some(&builder.root));

    dialog.add_response("cancel", "Cancel");
    dialog.add_response("create", "Create");
    dialog.set_response_appearance("create", adw::ResponseAppearance::Suggested);
    dialog.set_default_response(Some("create"));

    let state2 = state.clone();
    let list_box2 = list_box.clone();
    let toast2 = toast_overlay.clone();
    let _detail2 = detail_inner.clone();
    let stack2 = stack.clone();
    let ct2 = content_title.clone();
    let run2 = run_btn.clone();
    let preview2 = preview_btn.clone();
    let edit2 = edit_btn.clone();
    let del2 = delete_btn.clone();

    dialog.connect_response(None, move |_, response| {
        if response != "create" {
            return;
        }
        let name = builder.rule_name.text().trim().to_string();
        if name.is_empty() {
            toast(&toast2, "Rule name is required");
            return;
        }

        let rule_id = uuid::Uuid::new_v4().to_string()[..8].to_string();
        let raw = builder.build_rule_json(&rule_id, &name);
        let mut new_rule: RuleConfig = match serde_json::from_value(raw) {
            Ok(r) => r,
            Err(e) => {
                eprintln!("Rule scaffold error: {e}");
                return;
            }
        };

        let saved = {
            let s = state2.borrow_mut();
            s.config.save_rule(&mut new_rule)
        };
        if let Err(e) = saved {
            toast(&toast2, &format!("Could not save rule: {e}"));
            return;
        }

        load_rules(
            state2.clone(),
            &list_box2,
            &stack2,
            &ct2,
            &run2,
            &preview2,
            &edit2,
            &del2,
        );
        toast(&toast2, &format!("Created \"{name}\""));
    });

    dialog.present(Some(window));
}

#[allow(clippy::too_many_arguments)]
fn show_edit_rule_dialog(
    window: &adw::ApplicationWindow,
    state: S,
    list_box: &gtk4::ListBox,
    toast_overlay: &adw::ToastOverlay,
    detail_inner: &gtk4::Box,
    stack: &gtk4::Stack,
    content_title: &adw::WindowTitle,
    run_btn: &gtk4::Button,
    preview_btn: &gtk4::Button,
    edit_btn: &gtk4::Button,
    delete_btn: &gtk4::Button,
    rule: RuleConfig,
) {
    let dialog = adw::AlertDialog::builder()
        .heading("Configure Rule")
        .body("Update the saved rule from common file qualities and actions.")
        .build();

    let builder = RuleBuilderWidgets::for_rule(&rule);
    dialog.set_extra_child(Some(&builder.root));

    dialog.add_response("cancel", "Cancel");
    dialog.add_response("save", "Save");
    dialog.set_response_appearance("save", adw::ResponseAppearance::Suggested);
    dialog.set_default_response(Some("save"));

    let state2 = state.clone();
    let list_box2 = list_box.clone();
    let toast2 = toast_overlay.clone();
    let detail2 = detail_inner.clone();
    let stack2 = stack.clone();
    let ct2 = content_title.clone();
    let run2 = run_btn.clone();
    let preview2 = preview_btn.clone();
    let edit2 = edit_btn.clone();
    let del2 = delete_btn.clone();
    let rule_id = rule.id.clone();

    dialog.connect_response(None, move |_, response| {
        if response != "save" {
            return;
        }
        let name = builder.rule_name.text().trim().to_string();
        if name.is_empty() {
            toast(&toast2, "Rule name is required");
            return;
        }

        let raw = builder.build_rule_json(&rule_id, &name);
        let mut updated: RuleConfig = match serde_json::from_value(raw) {
            Ok(r) => r,
            Err(e) => {
                eprintln!("Rule update scaffold error: {e}");
                return;
            }
        };

        let saved = {
            let s = state2.borrow_mut();
            s.config.save_rule(&mut updated)
        };
        if let Err(e) = saved {
            toast(&toast2, &format!("Could not save rule: {e}"));
            return;
        }

        load_rules(
            state2.clone(),
            &list_box2,
            &stack2,
            &ct2,
            &run2,
            &preview2,
            &edit2,
            &del2,
        );

        let idx = {
            let s = state2.borrow();
            s.rules.iter().position(|r| r.id == rule_id)
        };
        if let Some(idx) = idx {
            {
                let mut s = state2.borrow_mut();
                s.selected_idx = Some(idx);
            }
            if let Some(rule) = state2.borrow().rules.get(idx) {
                load_detail(&detail2, rule);
                stack2.set_visible_child_name("detail");
                ct2.set_title(&rule.name);
                ct2.set_subtitle(&format!("Priority {}", rule.priority));
                run2.set_visible(true);
                preview2.set_visible(true);
                edit2.set_visible(true);
                del2.set_visible(true);
            }
        }
        toast(&toast2, &format!("Saved \"{name}\""));
    });

    dialog.present(Some(window));
}

struct RuleBuilderWidgets {
    root: gtk4::Box,
    rule_name: adw::EntryRow,
    description: adw::EntryRow,
    priority: gtk4::SpinButton,
    enabled: gtk4::Switch,
    folder_choice: adw::ComboRow,
    folder_custom: adw::EntryRow,
    recursive: gtk4::Switch,
    depth: gtk4::SpinButton,
    on_add: gtk4::CheckButton,
    on_modify: gtk4::CheckButton,
    match_mode: adw::ComboRow,
    condition_field: adw::ComboRow,
    condition_operator: adw::ComboRow,
    condition_value: adw::EntryRow,
    condition_unit: adw::ComboRow,
    action_type: adw::ComboRow,
    action_value: adw::EntryRow,
    conflict: adw::ComboRow,
    continue_matching: gtk4::Switch,
}

impl RuleBuilderWidgets {
    fn new() -> Self {
        let root = gtk4::Box::builder()
            .orientation(gtk4::Orientation::Vertical)
            .spacing(0)
            .width_request(560)
            .build();

        let basics = adw::PreferencesGroup::builder().title("Rule").build();
        let rule_name = adw::EntryRow::builder()
            .title("Name")
            .text("Old Items")
            .build();
        basics.add(&rule_name);
        let description = adw::EntryRow::builder().title("Description").build();
        basics.add(&description);
        let priority = gtk4::SpinButton::with_range(-100.0, 100.0, 1.0);
        priority.set_value(0.0);
        let priority_row = adw::ActionRow::builder()
            .title("Priority")
            .subtitle("Lower numbers run first")
            .build();
        priority_row.add_suffix(&priority);
        basics.add(&priority_row);
        let enabled = gtk4::Switch::builder()
            .active(true)
            .valign(gtk4::Align::Center)
            .build();
        let enabled_row = adw::ActionRow::builder().title("Enabled").build();
        enabled_row.add_suffix(&enabled);
        basics.add(&enabled_row);
        root.append(&basics);

        let folders = adw::PreferencesGroup::builder().title("In Folders").build();
        let folder_choice = combo_row(
            "Folder",
            &[
                "Downloads",
                "Desktop",
                "Documents",
                "Pictures",
                "Music",
                "Videos",
                "Custom",
            ],
            0,
        );
        folders.add(&folder_choice);
        let folder_custom = adw::EntryRow::builder()
            .title("Custom folder")
            .text("~/Downloads")
            .build();
        folder_custom.set_visible(false);
        folders.add(&folder_custom);
        let recursive = gtk4::Switch::builder()
            .active(false)
            .valign(gtk4::Align::Center)
            .build();
        let recursive_row = adw::ActionRow::builder()
            .title("Include subfolders")
            .subtitle("Safety depth still applies")
            .build();
        recursive_row.add_suffix(&recursive);
        folders.add(&recursive_row);
        let depth = gtk4::SpinButton::with_range(1.0, 25.0, 1.0);
        depth.set_value(1.0);
        let depth_row = adw::ActionRow::builder().title("Subfolder depth").build();
        depth_row.add_suffix(&depth);
        folders.add(&depth_row);
        root.append(&folders);

        let triggers = adw::PreferencesGroup::builder().title("When").build();
        let on_add = gtk4::CheckButton::builder()
            .label("Files are added")
            .active(true)
            .build();
        let on_modify = gtk4::CheckButton::builder().label("Files change").build();
        let trigger_box = gtk4::Box::builder()
            .orientation(gtk4::Orientation::Horizontal)
            .spacing(18)
            .margin_start(12)
            .margin_end(12)
            .margin_top(8)
            .margin_bottom(8)
            .build();
        trigger_box.append(&on_add);
        trigger_box.append(&on_modify);
        triggers.add(&trigger_box);
        root.append(&triggers);

        let conditions = adw::PreferencesGroup::builder().title("If").build();
        let match_mode = combo_row("Match", &["All", "Any", "None"], 0);
        conditions.add(&match_mode);
        let condition_field = combo_row(
            "Quality",
            &[
                "Any file",
                "Name",
                "Extension",
                "Kind",
                "Date modified",
                "Date created",
                "Date opened",
                "Size",
                "Contents",
                "Folder or file",
            ],
            4,
        );
        conditions.add(&condition_field);
        let condition_operator = combo_row(
            "Has quality",
            &[
                "is",
                "is not",
                "contains",
                "does not contain",
                "is in the last",
                "is not in the last",
                "is larger than",
                "is smaller than",
            ],
            5,
        );
        conditions.add(&condition_operator);
        let condition_value = adw::EntryRow::builder().title("Value").text("4").build();
        conditions.add(&condition_value);
        let condition_unit = combo_row(
            "Unit",
            &[
                "minutes", "hours", "days", "weeks", "months", "years", "KB", "MB", "GB",
            ],
            3,
        );
        conditions.add(&condition_unit);
        root.append(&conditions);

        let actions = adw::PreferencesGroup::builder().title("Then").build();
        let action_type = combo_row(
            "Action",
            &[
                "Sort into subfolder",
                "Move",
                "Copy",
                "Rename",
                "Trash",
                "Delete permanently",
                "Display notification",
                "Run shell script",
                "Log",
                "Open",
                "Ignore",
            ],
            0,
        );
        actions.add(&action_type);
        let action_value = adw::EntryRow::builder()
            .title("Destination / value")
            .text("~/Downloads/Old Items/{year}/{month_name}")
            .build();
        actions.add(&action_value);
        let conflict = combo_row("If destination exists", &["rename", "skip", "overwrite"], 0);
        actions.add(&conflict);
        let continue_matching = gtk4::Switch::builder()
            .active(false)
            .valign(gtk4::Align::Center)
            .build();
        let continue_row = adw::ActionRow::builder()
            .title("Continue matching rules")
            .build();
        continue_row.add_suffix(&continue_matching);
        actions.add(&continue_row);
        root.append(&actions);

        {
            let folder_custom2 = folder_custom.clone();
            folder_choice.connect_selected_notify(move |row| {
                folder_custom2.set_visible(row.selected() == 6);
            });
        }
        {
            let condition_operator2 = condition_operator.clone();
            let condition_value2 = condition_value.clone();
            let condition_unit2 = condition_unit.clone();
            condition_field.connect_selected_notify(move |row| {
                configure_condition_rows(
                    row.selected(),
                    &condition_operator2,
                    &condition_value2,
                    &condition_unit2,
                );
            });
        }
        {
            let action_value2 = action_value.clone();
            let conflict2 = conflict.clone();
            action_type.connect_selected_notify(move |row| {
                configure_action_rows(row.selected(), &action_value2, &conflict2);
            });
        }

        Self {
            root,
            rule_name,
            description,
            priority,
            enabled,
            folder_choice,
            folder_custom,
            recursive,
            depth,
            on_add,
            on_modify,
            match_mode,
            condition_field,
            condition_operator,
            condition_value,
            condition_unit,
            action_type,
            action_value,
            conflict,
            continue_matching,
        }
    }

    fn for_rule(rule: &RuleConfig) -> Self {
        let widgets = Self::new();
        widgets.load_rule(rule);
        widgets
    }

    fn load_rule(&self, rule: &RuleConfig) {
        self.rule_name.set_text(&rule.name);
        self.description.set_text(&rule.description);
        self.priority.set_value(rule.priority as f64);
        self.enabled.set_active(rule.enabled);
        self.on_add.set_active(rule.triggers.on_add);
        self.on_modify.set_active(rule.triggers.on_modify);
        self.continue_matching.set_active(rule.continue_matching);

        if let Some(folder) = rule.folders.first() {
            set_folder_choice(&self.folder_choice, &self.folder_custom, &folder.path);
            self.recursive.set_active(folder.recursive);
            self.depth.set_value(folder.depth.max(1) as f64);
        }

        let rule_json = serde_json::to_value(rule).unwrap_or_default();
        if let Some(mode) = rule_json["conditions"]["match"].as_str() {
            self.match_mode.set_selected(match mode {
                "any" => 1,
                "none" => 2,
                _ => 0,
            });
        }

        if let Some(condition) = rule_json["conditions"]["items"]
            .as_array()
            .and_then(|items| items.first())
        {
            load_condition_widgets(
                condition,
                &self.condition_field,
                &self.condition_operator,
                &self.condition_value,
                &self.condition_unit,
            );
        } else {
            configure_condition_rows(
                self.condition_field.selected(),
                &self.condition_operator,
                &self.condition_value,
                &self.condition_unit,
            );
        }

        if let Some(action) = rule_json["actions"]
            .as_array()
            .and_then(|items| items.first())
        {
            load_action_widgets(
                action,
                &self.action_type,
                &self.action_value,
                &self.conflict,
            );
        } else {
            configure_action_rows(
                self.action_type.selected(),
                &self.action_value,
                &self.conflict,
            );
        }
    }

    fn build_rule_json(&self, rule_id: &str, name: &str) -> Value {
        let condition = self.condition_json();
        let items = if condition.is_null() {
            vec![]
        } else {
            vec![condition]
        };

        serde_json::json!({
            "id": rule_id,
            "name": name,
            "enabled": self.enabled.is_active(),
            "priority": self.priority.value_as_int(),
            "description": self.description.text().trim().to_string(),
            "folders": [{
                "path": self.folder_path(),
                "recursive": self.recursive.is_active(),
                "depth": self.depth.value_as_int()
            }],
            "triggers": {
                "on_add": self.on_add.is_active(),
                "on_modify": self.on_modify.is_active(),
                "on_delete": false,
                "schedule": null
            },
            "conditions": {
                "type": "group",
                "match": selected_str(&self.match_mode).to_lowercase(),
                "items": items
            },
            "actions": self.action_json(),
            "continue_matching": self.continue_matching.is_active()
        })
    }

    fn folder_path(&self) -> String {
        match self.folder_choice.selected() {
            0 => "~/Downloads".to_string(),
            1 => "~/Desktop".to_string(),
            2 => "~/Documents".to_string(),
            3 => "~/Pictures".to_string(),
            4 => "~/Music".to_string(),
            5 => "~/Videos".to_string(),
            _ => {
                let custom = self.folder_custom.text().trim().to_string();
                if custom.is_empty() {
                    "~/Downloads".to_string()
                } else {
                    custom
                }
            }
        }
    }

    fn condition_json(&self) -> Value {
        let value = self.condition_value.text().trim().to_string();
        match self.condition_field.selected() {
            0 => Value::Null,
            1 => serde_json::json!({
                "type": "name",
                "operator": string_operator(self.condition_operator.selected()),
                "value": value_or_default(&value, "*"),
                "case_sensitive": false
            }),
            2 => serde_json::json!({
                "type": "extension",
                "operator": list_operator(self.condition_operator.selected()),
                "value": csv_values(&value_or_default(&value, "pdf"))
            }),
            3 => serde_json::json!({
                "type": "kind",
                "operator": list_operator(self.condition_operator.selected()),
                "value": csv_values(&value_or_default(&value, "document"))
            }),
            4..=6 => serde_json::json!({
                "type": "age",
                "operator": age_operator(self.condition_operator.selected()),
                "value": value.parse::<f64>().unwrap_or(4.0),
                "unit": time_unit(&selected_str(&self.condition_unit)),
                "date_type": match self.condition_field.selected() {
                    5 => "created",
                    6 => "accessed",
                    _ => "modified",
                }
            }),
            7 => serde_json::json!({
                "type": "size",
                "operator": size_operator(self.condition_operator.selected()),
                "value": value.parse::<f64>().unwrap_or(10.0),
                "unit": size_unit(&selected_str(&self.condition_unit))
            }),
            8 => serde_json::json!({
                "type": "content",
                "operator": text_operator(self.condition_operator.selected()),
                "value": value
            }),
            9 => serde_json::json!({
                "type": "is_directory",
                "value": matches!(value.to_lowercase().as_str(), "folder" | "directory" | "true" | "yes")
            }),
            _ => Value::Null,
        }
    }

    fn action_json(&self) -> Vec<Value> {
        let value = self.action_value.text().trim().to_string();
        let conflict = selected_str(&self.conflict);
        match self.action_type.selected() {
            0 | 1 => vec![serde_json::json!({
                "type": "move",
                "destination": value_or_default(&value, "~/Organized/{kind}/{year}"),
                "on_conflict": conflict,
                "create_parents": true
            })],
            2 => vec![serde_json::json!({
                "type": "copy",
                "destination": value_or_default(&value, "~/Organized/{kind}/{year}"),
                "on_conflict": conflict,
                "create_parents": true
            })],
            3 => vec![serde_json::json!({
                "type": "rename",
                "pattern": value_or_default(&value, "{stem}-sorted.{extension}"),
                "on_conflict": conflict
            })],
            4 => vec![serde_json::json!({"type": "trash"})],
            5 => vec![serde_json::json!({"type": "delete", "recursive": false})],
            6 => vec![serde_json::json!({
                "type": "notify",
                "title": "Doumi",
                "body": value_or_default(&value, "Matched {filename}")
            })],
            7 => vec![serde_json::json!({
                "type": "run_script",
                "command": value_or_default(&value, "~/bin/process-file.sh"),
                "args": ["{path}"],
                "interpreter": "bash"
            })],
            8 => vec![serde_json::json!({
                "type": "log",
                "message": value_or_default(&value, "Matched {filename}"),
                "destination": null
            })],
            9 => vec![serde_json::json!({"type": "open", "command": null})],
            _ => vec![serde_json::json!({
                "type": "log",
                "message": "Ignored {filename}",
                "destination": null
            })],
        }
    }
}

fn combo_row(title: &str, items: &[&str], selected: u32) -> adw::ComboRow {
    let model = gtk4::StringList::new(items);
    adw::ComboRow::builder()
        .title(title)
        .model(&model)
        .selected(selected)
        .build()
}

fn configure_condition_rows(
    field: u32,
    operator: &adw::ComboRow,
    value: &adw::EntryRow,
    unit: &adw::ComboRow,
) {
    unit.set_visible(matches!(field, 4..=7));
    value.set_visible(field != 0);
    match field {
        0 => value.set_text(""),
        1 => {
            operator.set_selected(2);
            value.set_title("Name pattern");
            value.set_text("invoice");
        }
        2 => {
            operator.set_selected(0);
            value.set_title("Extensions");
            value.set_text("pdf, docx");
        }
        3 => {
            operator.set_selected(0);
            value.set_title("Kinds");
            value.set_text("document");
        }
        4..=6 => {
            operator.set_selected(5);
            value.set_title("Time");
            value.set_text("4");
            unit.set_selected(3);
        }
        7 => {
            operator.set_selected(6);
            value.set_title("Size");
            value.set_text("10");
            unit.set_selected(7);
        }
        8 => {
            operator.set_selected(2);
            value.set_title("Text");
            value.set_text("");
        }
        9 => {
            operator.set_selected(0);
            value.set_title("folder or file");
            value.set_text("file");
        }
        _ => {}
    }
}

fn set_folder_choice(choice: &adw::ComboRow, custom: &adw::EntryRow, path: &str) {
    let selected = match path {
        "~/Downloads" => 0,
        "~/Desktop" => 1,
        "~/Documents" => 2,
        "~/Pictures" => 3,
        "~/Music" => 4,
        "~/Videos" => 5,
        _ => 6,
    };
    choice.set_selected(selected);
    custom.set_visible(selected == 6);
    if selected == 6 {
        custom.set_text(path);
    }
}

fn load_condition_widgets(
    condition: &Value,
    field: &adw::ComboRow,
    operator: &adw::ComboRow,
    value: &adw::EntryRow,
    unit: &adw::ComboRow,
) {
    match condition["type"].as_str().unwrap_or("") {
        "name" => {
            field.set_selected(1);
            configure_condition_rows(1, operator, value, unit);
            operator.set_selected(string_op_index(condition["operator"].as_str()));
            value.set_text(&value_as_entry_text(&condition["value"]));
        }
        "extension" => {
            field.set_selected(2);
            configure_condition_rows(2, operator, value, unit);
            operator.set_selected(list_op_index(condition["operator"].as_str()));
            value.set_text(&value_as_entry_text(&condition["value"]));
        }
        "kind" => {
            field.set_selected(3);
            configure_condition_rows(3, operator, value, unit);
            operator.set_selected(list_op_index(condition["operator"].as_str()));
            value.set_text(&value_as_entry_text(&condition["value"]));
        }
        "age" => {
            let field_idx = match condition["date_type"].as_str().unwrap_or("modified") {
                "created" => 5,
                "accessed" => 6,
                _ => 4,
            };
            field.set_selected(field_idx);
            configure_condition_rows(field_idx, operator, value, unit);
            operator.set_selected(age_op_index(condition["operator"].as_str()));
            value.set_text(&numeric_text(&condition["value"], "4"));
            set_unit_selection(unit, condition["unit"].as_str(), true);
        }
        "size" => {
            field.set_selected(7);
            configure_condition_rows(7, operator, value, unit);
            operator.set_selected(size_op_index(condition["operator"].as_str()));
            value.set_text(&numeric_text(&condition["value"], "10"));
            set_unit_selection(unit, condition["unit"].as_str(), false);
        }
        "content" | "contents" => {
            field.set_selected(8);
            configure_condition_rows(8, operator, value, unit);
            operator.set_selected(text_op_index(condition["operator"].as_str()));
            value.set_text(condition["value"].as_str().unwrap_or(""));
        }
        "is_directory" | "is_folder" => {
            field.set_selected(9);
            configure_condition_rows(9, operator, value, unit);
            value.set_text(if condition["value"].as_bool().unwrap_or(false) {
                "folder"
            } else {
                "file"
            });
        }
        _ => {
            field.set_selected(0);
            configure_condition_rows(0, operator, value, unit);
        }
    }
}

fn load_action_widgets(
    action: &Value,
    action_type: &adw::ComboRow,
    action_value: &adw::EntryRow,
    conflict: &adw::ComboRow,
) {
    match action["type"].as_str().unwrap_or("") {
        "move" => {
            action_type.set_selected(1);
            configure_action_rows(1, action_value, conflict);
            action_value.set_text(action["destination"].as_str().unwrap_or(""));
            set_conflict_selection(conflict, action["on_conflict"].as_str());
        }
        "copy" => {
            action_type.set_selected(2);
            configure_action_rows(2, action_value, conflict);
            action_value.set_text(action["destination"].as_str().unwrap_or(""));
            set_conflict_selection(conflict, action["on_conflict"].as_str());
        }
        "rename" => {
            action_type.set_selected(3);
            configure_action_rows(3, action_value, conflict);
            action_value.set_text(action["pattern"].as_str().unwrap_or(""));
            set_conflict_selection(conflict, action["on_conflict"].as_str());
        }
        "trash" => {
            action_type.set_selected(4);
            configure_action_rows(4, action_value, conflict);
        }
        "delete" => {
            action_type.set_selected(5);
            configure_action_rows(5, action_value, conflict);
        }
        "notify" | "notification" => {
            action_type.set_selected(6);
            configure_action_rows(6, action_value, conflict);
            action_value.set_text(action["body"].as_str().unwrap_or(""));
        }
        "run_script" | "script" => {
            action_type.set_selected(7);
            configure_action_rows(7, action_value, conflict);
            action_value.set_text(action["command"].as_str().unwrap_or(""));
        }
        "log" => {
            action_type.set_selected(8);
            configure_action_rows(8, action_value, conflict);
            action_value.set_text(action["message"].as_str().unwrap_or(""));
        }
        "open" => {
            action_type.set_selected(9);
            configure_action_rows(9, action_value, conflict);
        }
        _ => {
            action_type.set_selected(10);
            configure_action_rows(10, action_value, conflict);
        }
    }
}

fn configure_action_rows(action: u32, value: &adw::EntryRow, conflict: &adw::ComboRow) {
    value.set_visible(!matches!(action, 4 | 5 | 9 | 10));
    conflict.set_visible(matches!(action, 0..=3));
    match action {
        0 => {
            value.set_title("Subfolder template");
            value.set_text("~/Downloads/Old Items/{year}/{month_name}");
        }
        1 | 2 => {
            value.set_title("Destination");
            value.set_text("~/Organized/{kind}/{year}");
        }
        3 => {
            value.set_title("Name template");
            value.set_text("{stem}-sorted.{extension}");
        }
        6 => {
            value.set_title("Notification");
            value.set_text("Matched {filename}");
        }
        7 => {
            value.set_title("Shell script");
            value.set_text("~/bin/process-file.sh");
        }
        8 => {
            value.set_title("Log message");
            value.set_text("Matched {filename}");
        }
        _ => {}
    }
}

fn value_as_entry_text(value: &Value) -> String {
    if let Some(text) = value.as_str() {
        text.to_string()
    } else if let Some(items) = value.as_array() {
        items
            .iter()
            .filter_map(|item| item.as_str())
            .collect::<Vec<_>>()
            .join(", ")
    } else {
        String::new()
    }
}

fn numeric_text(value: &Value, default: &str) -> String {
    value
        .as_f64()
        .map(|v| {
            if v.fract().abs() < f64::EPSILON {
                format!("{}", v as i64)
            } else {
                v.to_string()
            }
        })
        .unwrap_or_else(|| default.to_string())
}

fn string_op_index(op: Option<&str>) -> u32 {
    match op.unwrap_or("") {
        "is_not" => 1,
        "contains" => 2,
        "not_contains" => 3,
        _ => 0,
    }
}

fn list_op_index(op: Option<&str>) -> u32 {
    match op.unwrap_or("") {
        "is_not" | "is_not_one_of" => 1,
        _ => 0,
    }
}

fn age_op_index(op: Option<&str>) -> u32 {
    match op.unwrap_or("") {
        "newer_than" => 4,
        _ => 5,
    }
}

fn size_op_index(op: Option<&str>) -> u32 {
    match op.unwrap_or("") {
        "less_than" => 7,
        _ => 6,
    }
}

fn text_op_index(op: Option<&str>) -> u32 {
    match op.unwrap_or("") {
        "not_contains" => 3,
        _ => 2,
    }
}

fn set_unit_selection(row: &adw::ComboRow, unit: Option<&str>, time: bool) {
    let idx = if time {
        match unit.unwrap_or("days") {
            "minutes" => 0,
            "hours" => 1,
            "weeks" => 3,
            "months" => 4,
            "years" => 5,
            _ => 2,
        }
    } else {
        match unit.unwrap_or("mb").to_lowercase().as_str() {
            "kb" => 6,
            "gb" => 8,
            _ => 7,
        }
    };
    row.set_selected(idx);
}

fn set_conflict_selection(row: &adw::ComboRow, policy: Option<&str>) {
    row.set_selected(match policy.unwrap_or("rename") {
        "skip" => 1,
        "overwrite" => 2,
        _ => 0,
    });
}

fn selected_str(row: &adw::ComboRow) -> String {
    row.selected_item()
        .and_then(|item| item.downcast::<gtk4::StringObject>().ok())
        .map(|obj| obj.string().to_string())
        .unwrap_or_default()
}

fn value_or_default(value: &str, default: &str) -> String {
    if value.trim().is_empty() {
        default.to_string()
    } else {
        value.trim().to_string()
    }
}

fn csv_values(value: &str) -> Vec<String> {
    value
        .split(',')
        .map(|v| v.trim().trim_start_matches('.').to_string())
        .filter(|v| !v.is_empty())
        .collect()
}

fn string_operator(selected: u32) -> &'static str {
    match selected {
        1 => "is_not",
        2 => "contains",
        3 => "not_contains",
        _ => "is",
    }
}

fn list_operator(selected: u32) -> &'static str {
    match selected {
        1 | 3 => "is_not_one_of",
        _ => "is_one_of",
    }
}

fn age_operator(selected: u32) -> &'static str {
    match selected {
        4 => "newer_than",
        _ => "older_than",
    }
}

fn size_operator(selected: u32) -> &'static str {
    match selected {
        7 => "less_than",
        _ => "greater_than",
    }
}

fn text_operator(selected: u32) -> &'static str {
    match selected {
        3 => "not_contains",
        _ => "contains",
    }
}

fn time_unit(unit: &str) -> &'static str {
    match unit.to_lowercase().as_str() {
        "minutes" => "minutes",
        "hours" => "hours",
        "weeks" => "weeks",
        "months" => "months",
        "years" => "years",
        _ => "days",
    }
}

fn size_unit(unit: &str) -> &'static str {
    match unit.to_lowercase().as_str() {
        "kb" => "kb",
        "gb" => "gb",
        _ => "mb",
    }
}

// ─── Daemon polling ───────────────────────────────────────────────────────────

fn start_daemon_poll(
    state: S,
    status_dot: &gtk4::Label,
    stack: &gtk4::Stack,
    dashboard_box: &gtk4::Box,
) {
    poll_once(state.clone(), status_dot, stack, dashboard_box);

    let state2 = state.clone();
    let dot = status_dot.clone();
    let stk = stack.clone();
    let db = dashboard_box.clone();

    glib::timeout_add_seconds_local(8, move || {
        poll_once(state2.clone(), &dot, &stk, &db);
        glib::ControlFlow::Continue
    });
}

fn poll_once(state: S, dot: &gtk4::Label, stack: &gtk4::Stack, dashboard_box: &gtk4::Box) {
    let socket = state.borrow().config.ipc_socket_path();
    let dot2 = dot.clone();
    let stk2 = stack.clone();
    let db2 = dashboard_box.clone();

    ipc_async(socket, serde_json::json!({"cmd": "status"}), move |resp| {
        if resp["ok"].as_bool().unwrap_or(false) {
            dot2.remove_css_class("status-offline");
            dot2.add_css_class("status-online");
            dot2.set_tooltip_text(Some("Daemon running"));
            if stk2.visible_child_name().as_deref() == Some("dashboard") {
                update_dashboard(&db2, &resp["data"]);
            }
        } else {
            dot2.remove_css_class("status-online");
            dot2.add_css_class("status-offline");
            dot2.set_tooltip_text(Some("Daemon offline — run: doumi daemon start"));
        }
    });
}

fn update_dashboard(dashboard_box: &gtk4::Box, data: &Value) {
    // Clear existing stats (keep the status page, replace if stats are shown)
    while let Some(child) = dashboard_box.first_child() {
        dashboard_box.remove(&child);
    }

    let scroll = gtk4::ScrolledWindow::builder()
        .hscrollbar_policy(gtk4::PolicyType::Never)
        .vexpand(true)
        .build();
    let clamp = adw::Clamp::builder()
        .maximum_size(700)
        .margin_top(24)
        .margin_bottom(24)
        .margin_start(16)
        .margin_end(16)
        .build();
    let inner = gtk4::Box::new(gtk4::Orientation::Vertical, 20);
    clamp.set_child(Some(&inner));
    scroll.set_child(Some(&clamp));
    dashboard_box.append(&scroll);

    // Status row
    let status_row = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Horizontal)
        .spacing(12)
        .halign(gtk4::Align::Center)
        .build();
    let dot = gtk4::Label::builder()
        .label("●")
        .css_classes(["status-dot", "status-online"])
        .build();
    let rules_n = data["rules"].as_u64().unwrap_or(0);
    let watches_n = data["watches"].as_u64().unwrap_or(0);
    let dry_run = data["dry_run"].as_bool().unwrap_or(false);
    let mut status_txt =
        format!("Daemon running  ·  {rules_n} rules  ·  {watches_n} folders watched");
    if dry_run {
        status_txt.push_str("  ·  DRY RUN");
    }
    let status_lbl = gtk4::Label::builder()
        .label(&status_txt)
        .css_classes(["body"])
        .build();
    status_row.append(&dot);
    status_row.append(&status_lbl);
    inner.append(&status_row);

    // Stats grid
    let stats = &data["stats"];
    let grid = gtk4::Grid::builder()
        .column_spacing(12)
        .row_spacing(12)
        .halign(gtk4::Align::Center)
        .build();

    let cards = [
        (
            "Total Events",
            stats["total_events"].as_u64().unwrap_or(0),
            "view-list-symbolic",
        ),
        (
            "Actions OK",
            stats["actions_ok"].as_u64().unwrap_or(0),
            "emblem-ok-symbolic",
        ),
        (
            "Actions Failed",
            stats["actions_failed"].as_u64().unwrap_or(0),
            "dialog-error-symbolic",
        ),
        (
            "Rules Active",
            data["rules"].as_u64().unwrap_or(0),
            "emblem-default-symbolic",
        ),
    ];
    for (i, (label, value, icon)) in cards.iter().enumerate() {
        let card = stat_card(label, &value.to_string(), icon);
        grid.attach(&card, (i % 2) as i32, (i / 2) as i32, 1, 1);
    }
    inner.append(&grid);
}

fn stat_card(label: &str, value: &str, icon_name: &str) -> gtk4::Box {
    let card = gtk4::Box::builder()
        .orientation(gtk4::Orientation::Vertical)
        .spacing(6)
        .css_classes(["card", "stat-card"])
        .width_request(180)
        .height_request(100)
        .halign(gtk4::Align::Fill)
        .valign(gtk4::Align::Fill)
        .build();
    set_pad(&card, 16);

    let icon = gtk4::Image::from_icon_name(icon_name);
    icon.set_pixel_size(20);
    icon.set_halign(gtk4::Align::Start);
    card.append(&icon);

    let val_lbl = gtk4::Label::builder()
        .label(value)
        .xalign(0.0)
        .css_classes(["title-1", "stat-number"])
        .build();
    card.append(&val_lbl);

    let lbl = gtk4::Label::builder()
        .label(label)
        .xalign(0.0)
        .css_classes(["caption", "stat-label"])
        .build();
    card.append(&lbl);
    card
}

// ─── Utilities ────────────────────────────────────────────────────────────────

fn toast(overlay: &adw::ToastOverlay, msg: &str) {
    overlay.add_toast(adw::Toast::builder().title(msg).timeout(3).build());
}

fn chip(label: &str, classes: &[&str]) -> gtk4::Label {
    let w = gtk4::Label::builder().label(label).build();
    for c in classes {
        w.add_css_class(c);
    }
    w
}

fn set_pad(widget: &impl gtk4::prelude::WidgetExt, px: i32) {
    widget.set_margin_start(px);
    widget.set_margin_end(px);
    widget.set_margin_top(px);
    widget.set_margin_bottom(px);
}

fn condition_icon(ctype: &str) -> &'static str {
    match ctype {
        "name" => "edit-find-symbolic",
        "extension" => "text-x-generic-symbolic",
        "size" => "drive-harddisk-symbolic",
        "age" => "alarm-symbolic",
        "mime_type" => "application-x-executable-symbolic",
        "kind" => "preferences-other-symbolic",
        "is_directory" | "is_folder" => "folder-symbolic",
        "content" | "contents" => "format-justify-left-symbolic",
        "permissions" => "system-lock-screen-symbolic",
        "script" => "utilities-terminal-symbolic",
        _ => "dialog-question-symbolic",
    }
}

fn action_icon(atype: &str) -> &'static str {
    match atype {
        "move" => "go-next-symbolic",
        "copy" => "edit-copy-symbolic",
        "delete" | "trash" => "user-trash-symbolic",
        "rename" => "document-edit-symbolic",
        "run_script" | "script" => "utilities-terminal-symbolic",
        "notify" | "notification" => "notifications-symbolic",
        "compress" | "archive" => "package-x-generic-symbolic",
        "tag" => "tag-symbolic",
        "log" => "format-justify-left-symbolic",
        "open" => "window-new-symbolic",
        "create_folder" | "mkdir" => "folder-new-symbolic",
        _ => "emblem-default-symbolic",
    }
}
