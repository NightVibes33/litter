use codex_models_manager::bundled_models_response;

#[test]
fn bundled_mobile_models_retain_code_mode_tool_capabilities() {
    let catalog = bundled_models_response().expect("valid bundled catalog");
    for slug in ["gpt-5.6-terra", "gpt-6.1-sol"] {
        let model = catalog.models.iter().find(|model| model.slug == slug)
            .unwrap_or_else(|| panic!("missing bundled model {slug}"));
        let value = serde_json::to_value(model).expect("serializable model metadata");
        assert_eq!(value["tool_mode"], "code_mode_only");
        assert_eq!(value["shell_type"], "shell_command");
        assert!(model.supports_parallel_tool_calls);
        assert!(model.supported_in_api);
        assert!(model.apply_patch_tool_type.is_some());
        assert_eq!(model.context_window, Some(272_000));
        assert!(model.supported_reasoning_levels.len() >= 6);
    }
}
