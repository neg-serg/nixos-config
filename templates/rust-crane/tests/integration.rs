use app::parse_user;

#[test]
fn integration_parses_minimal_user() {
    let u = parse_user("{\"id\": 1, \"name\": \"alice\"}").unwrap();
    assert_eq!(u.id, 1);
    assert_eq!(u.name, "alice");
}

