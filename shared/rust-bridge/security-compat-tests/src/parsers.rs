use serde::{Deserialize, Serialize};
use std::io::{Cursor, Write};

#[derive(Debug, PartialEq, Serialize, Deserialize)]
struct Metadata {
    name: String,
    enabled: bool,
    values: Vec<u32>,
}

#[test]
fn yaml_metadata_roundtrips_unicode_and_typed_values() {
    let original = Metadata {
        name: "Alley Cat 🐈".into(),
        enabled: true,
        values: vec![1, 7],
    };
    let encoded = serde_yaml::to_string(&original).unwrap();
    assert_eq!(
        serde_yaml::from_str::<Metadata>(&encoded).unwrap(),
        original
    );
    let value: serde_yaml::Value = serde_yaml::from_str(&encoded).unwrap();
    assert_eq!(value["name"].as_str(), Some("Alley Cat 🐈"));
    assert_eq!(value["enabled"].as_bool(), Some(true));
    assert!(value.as_mapping().is_some());
    assert!(serde_yaml::from_str::<Metadata>("name: [unterminated").is_err());
}

#[test]
fn yaml_frontmatter_value_resolves_anchors_before_scalar_matching() {
    let value =
        serde_yaml::from_str_value("name: &label 'Alley Cat'\ndescription: *label\n").unwrap();
    assert_eq!(value["description"].as_str(), Some("Alley Cat"));
    assert!(serde_yaml::from_str_value("loop: &loop [*loop]\n").is_err());
}

#[test]
fn toml_metadata_preserves_legacy_parser_entrypoint_and_errors() {
    let source = "name = 'Alley Cat'\nenabled = true\nvalues = [1, 7]\n";
    let parsed: Metadata = basic_toml::from_str(source).unwrap();
    assert_eq!(parsed.name, "Alley Cat");
    assert_eq!(parsed.values, [1, 7]);
    let invalid: Result<Metadata, basic_toml::Error> = basic_toml::from_str("name = [");
    assert!(invalid.is_err());
}

#[test]
fn fixed_zip_extracts_binary_data_and_rejects_parent_traversal() {
    let mut zip = zip::ZipWriter::new(Cursor::new(Vec::new()));
    let options = zip::write::SimpleFileOptions::default();
    zip.start_file("payload.bin", options).unwrap();
    let bytes: Vec<u8> = (0..=255).collect();
    zip.write_all(&bytes).unwrap();
    let archive = zip.finish().unwrap();
    let destination = tempfile::tempdir().unwrap();
    zip::ZipArchive::new(archive)
        .unwrap()
        .extract(destination.path())
        .unwrap();
    assert_eq!(
        std::fs::read(destination.path().join("payload.bin")).unwrap(),
        bytes
    );

    let mut zip = zip::ZipWriter::new(Cursor::new(Vec::new()));
    zip.start_file("../outside.txt", options).unwrap();
    zip.write_all(b"must not escape").unwrap();
    let mut archive = zip::ZipArchive::new(zip.finish().unwrap()).unwrap();
    assert!(archive.by_index(0).unwrap().enclosed_name().is_none());
    assert!(archive.extract(destination.path()).is_err());
}
